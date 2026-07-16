import 'dart:async' show Completer, TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/firestore_app_config.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';

/// Blindagem Web (padrão Controle Total): **nunca** `terminate()` em retry automático
/// (mata o singleton → `failed-precondition: client has already been terminated` em Doação,
/// Patrimônio, Cartão membro, Mural, etc.).
class FirestoreWebGuard {
  FirestoreWebGuard._();

  /// Web: evita dezenas de `snapshots()` paralelos (INTERNAL ASSERTION Firestore 11.x).
  static bool get disableLiveSnapshotsOnWeb => kIsWeb;

  /// Web: limita leituras Firestore em voo (alvos do watch stream) para evitar
  /// dezenas de alvos paralelos → `INTERNAL ASSERTION FAILED: Unexpected state`
  /// no `WatchChangeAggregator` (SDK JS 12.x). Semáforo justo (FIFO).
  static const int _maxWebConcurrentReads = 10;
  static int _webReadsInFlight = 0;
  static final List<Completer<void>> _webReadWaiters = <Completer<void>>[];

  /// Espera máx. na fila — evita starvation (módulos com queryCap 14s sem slot).
  static const Duration _webReadQueueWait = Duration(seconds: 6);

  static Future<T> webGetLimited<T>(Future<T> Function() fn) async {
    if (!kIsWeb) return fn();
    while (_webReadsInFlight >= _maxWebConcurrentReads) {
      final waiter = Completer<void>();
      _webReadWaiters.add(waiter);
      try {
        await waiter.future.timeout(_webReadQueueWait);
      } on TimeoutException {
        _webReadWaiters.remove(waiter);
        throw TimeoutException(
          'Tempo esgotado ao carregar dados do painel.',
        );
      }
    }
    _webReadsInFlight++;
    try {
      return await fn();
    } finally {
      _webReadsInFlight--;
      if (_webReadWaiters.isNotEmpty) {
        final next = _webReadWaiters.removeAt(0);
        if (!next.isCompleted) next.complete();
      }
    }
  }

  static bool isInternalAssertionError(Object e) {
    final msg = e.toString();
    return msg.contains('INTERNAL ASSERTION') ||
        msg.contains('Unexpected state') ||
        msg.contains('WatchChangeAggregator') ||
        msg.contains('PersistentListenStream') ||
        msg.contains('__PRIVATE__TargetState') ||
        isTargetIdConflict(e);
  }

  /// Firestore Web — alvo de escuta duplicado (ex.: Cartão membro + Membros em paralelo).
  static bool isTargetIdConflict(Object e) {
    final msg = e.toString();
    return msg.contains('Target ID already exists') ||
        msg.contains('already-exists');
  }

  /// Cliente Firestore morto após `terminate()` antigo ou corrida entre abas.
  static bool isClientTerminated(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('client has already been terminated')) return true;
    if (e is FirebaseException &&
        e.code == 'failed-precondition' &&
        msg.contains('terminated')) {
      return true;
    }
    return false;
  }

  static void applyWebFirestoreSettings() {
    if (!kIsWeb) return;
    configureFirestoreForOfflineAndSpeed();
  }

  static Future<void> prepareBeforeWebSignIn() async {
    if (!kIsWeb) return;
    await ensureWebDatabaseConnected(refreshAuth: false);
  }

  static Future<void> stabilizeAfterWebSignIn() async {
    if (!kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.getIdToken(false);
      } catch (_) {}
      try {
        await user.reload();
      } catch (_) {}
    }
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 140));
  }

  static Future<void>? _recoveryInFlight;

  /// Recuperação Web single-flight — nunca desliga a rede global do Firestore.
  static Future<void> recoverFirestoreWebSession({bool allowHardReconnect = false}) async {
    if (EcoFireFlow.passThroughFirestore) return;
    if (!kIsWeb) return;
    if (WebPanelStability.isSessionExpired) return;

    final active = _recoveryInFlight;
    if (active != null) return active;
    final recovery = () async {
      if (allowHardReconnect) {
        await _reconnectFirestoreAfterTerminated();
        try {
          await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
        } catch (_) {}
      }
      applyWebFirestoreSettings();
      await stabilizeAfterWebSignIn();
      await firebaseDefaultFirestore.enableNetwork();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }();
    _recoveryInFlight = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_recoveryInFlight, recovery)) _recoveryInFlight = null;
    }
  }

  /// Garante cliente Firestore utilizável na web — **nunca** chama `terminate()`.
  static Future<void> ensureFirestoreClientAlive() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    try {
      await firebaseDefaultFirestore.enableNetwork();
      return;
    } catch (e) {
      if (!isClientTerminated(e)) return;
    }
    await _reconnectFirestoreAfterTerminated();
    applyWebFirestoreSettings();
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
  }

  static Future<void>? _panelReadReadyOnce;
  static DateTime? _panelReadReadyAt;
  static const Duration _panelReadReadyTtl = Duration(seconds: 45);

  /// Painel igreja (web/mobile) — leitura rápida sem desligar a rede.
  /// Memoizado ~45s para não empilhar o mesmo gate em Agenda/Membros/Eventos.
  static Future<void> ensurePanelReadReady() async {
    if (!kIsWeb) return;
    final at = _panelReadReadyAt;
    if (at != null &&
        DateTime.now().difference(at) < _panelReadReadyTtl &&
        _panelReadReadyOnce != null) {
      return _panelReadReadyOnce!;
    }
    _panelReadReadyOnce = () async {
      applyWebFirestoreSettings();
      await ensureWebDatabaseConnected(refreshAuth: false).timeout(
        ChurchPanelReadTimeouts.readReadyCap,
      );
      _panelReadReadyAt = DateTime.now();
    }();
    _panelReadReadyOnce = _panelReadReadyOnce!.catchError((Object e, StackTrace st) {
      _panelReadReadyAt = null;
      _panelReadReadyOnce = null;
      Error.throwWithStackTrace(e, st);
    });
    return _panelReadReadyOnce!;
  }

  /// Painel Master web — sessão estável sem forçar refresh de token (igual painel igreja).
  static Future<void> ensureMasterPanelReady() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    await ensureWebDatabaseConnected(refreshAuth: false).timeout(
      ChurchPanelReadTimeouts.readReadyCap,
      onTimeout: () {},
    );
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        await user.getIdToken(false);
      }
    } catch (_) {}
  }

  /// Só quando o cliente já foi terminado — `reconnect` do bootstrap (sem `terminate` de novo).
  static Future<void> _reconnectFirestoreAfterTerminated() async {
    try {
      debugPrint('FirestoreWebGuard: reconnect após cliente terminado…');
      await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
      applyWebFirestoreSettings();
      try {
        await firebaseDefaultFirestore.enableNetwork();
      } catch (_) {}
    } catch (e) {
      debugPrint('FirestoreWebGuard: reconnect falhou: $e');
    }
  }

  /// Executa [fn]; em assert interno ou cliente terminado, recupera e re-tenta até [maxAttempts].
  static Future<T> runWithWebRecovery<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
  }) async {
    if (EcoFireFlow.passThroughFirestore) return fn();
    if (kIsWeb && WebPanelStability.isSessionExpired) {
      return fn();
    }
    final attempts = kIsWeb ? maxAttempts.clamp(2, 3) : maxAttempts;
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        if (attempt > 0) {
          debugPrint('FirestoreWebGuard: retry $attempt/$attempts…');
          final hard = lastError != null &&
              (isClientTerminated(lastError!) ||
                  isInternalAssertionError(lastError!));
          if (kIsWeb && attempt == 1 && !WebPanelStability.isSessionExpired) {
            await ensurePanelReadReady();
          }
          if (!WebPanelStability.isSessionExpired) {
            await recoverFirestoreWebSession(allowHardReconnect: hard);
          }
          await Future<void>.delayed(
            Duration(milliseconds: 40 + attempt * 80),
          );
        }
        return await fn();
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        final recoverable = kIsWeb &&
            !WebPanelStability.isSessionExpired &&
            (isInternalAssertionError(e) ||
                isClientTerminated(e) ||
                e is FirebaseException &&
                    (e.code == 'unavailable' ||
                        e.code == 'internal' ||
                        e.code == 'unknown'));
        if (!recoverable || attempt >= attempts - 1) {
          Error.throwWithStackTrace(e, st);
        }
        debugPrint('FirestoreWebGuard: recuperação suave Web…');
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('web_recovery_failed'),
      lastStack ?? StackTrace.current,
    );
  }

  static Future<T> runWebGoogleSignInFlow<T>(Future<T> Function() fn) async {
    if (!kIsWeb) return fn();
    await prepareBeforeWebSignIn();
    try {
      return await runWithWebRecovery(fn);
    } finally {
      await ensureWebDatabaseConnected(refreshAuth: true);
    }
  }

  /// Garante persistência + rede activa (web e mobile) — gravar e manter sessão no Firestore.
  static Future<void> ensureWebDatabaseConnected({bool refreshAuth = false}) async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    await firebaseDefaultFirestore.enableNetwork();
    if (refreshAuth) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        try {
          await user.getIdToken(false);
        } catch (_) {}
      }
    }
  }

  /// Arranque / resume web — conexão estável em qualquer domínio oficial.
  static Future<void> bindWebHostingDomainSession() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    await ensureWebDatabaseConnected(refreshAuth: true);
  }

  /// Preparação leve antes de gravar — **nunca** `terminate()` (Controle Total / WisdomApp).
  ///
  /// Recovery pesado só após falha em [runWithWebRecovery], [runFirestorePublishWithRecovery]
  /// ou [runChatWriteWithRecovery].
  static Future<void> prepareForPublishWrite() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    if (EcoFireFlow.passThroughFirestore) {
      await ensureWebDatabaseConnected(refreshAuth: false);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        await user.getIdToken(false);
      } catch (_) {}
    }
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
    await ensureFirestoreClientAlive();
  }

  /// Alias legado — mesma preparação leve (sem matar o cliente Firestore).
  static Future<void> prepareForCriticalWrite() async {
    await prepareForPublishWrite();
  }

  /// Chat (texto/mídia): **não** desliga a rede — listeners do thread ficam activos.
  static Future<void> prepareForChatWrite() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        await user.getIdToken(false);
      } catch (_) {}
    }
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
  }

  /// Recuperação após falha no envio do chat — hard reset só se cliente terminado.
  static Future<void> recoverForChatWrite({
    required int attempt,
    Object? lastError,
  }) async {
    if (!kIsWeb) return;
    final hard = lastError != null && isClientTerminated(lastError);
    if (hard) {
      await recoverFirestoreWebSession(allowHardReconnect: true);
      await ensureWebDatabaseConnected(refreshAuth: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return;
    }
    await prepareForChatWrite();
    await Future<void>.delayed(Duration(milliseconds: 70 + attempt * 90));
  }

  /// Gravação Firestore no chat — retry leve (estilo WhatsApp), rede só em falha grave.
  static Future<T> runChatWriteWithRecovery<T>(
    Future<T> Function() fn, {
    int maxAttempts = 5,
  }) async {
    if (EcoFireFlow.passThroughFirestore) {
      if (kIsWeb) await prepareForChatWrite();
      return fn();
    }
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt == 0) {
          await prepareForChatWrite();
        } else {
          debugPrint(
            'FirestoreWebGuard: chat write retry $attempt/$maxAttempts…',
          );
          await recoverForChatWrite(
            attempt: attempt,
            lastError: lastError,
          );
        }
        return await fn();
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        final recoverable = kIsWeb &&
            (isInternalAssertionError(e) ||
                isClientTerminated(e) ||
                e.toString().toLowerCase().contains('client is offline') ||
                e is FirebaseException &&
                    (e.code == 'unavailable' ||
                        e.code == 'internal' ||
                        e.code == 'unknown' ||
                        e.code == 'resource-exhausted'));
        if (!recoverable || attempt >= maxAttempts - 1) {
          Error.throwWithStackTrace(e, st);
        }
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('chat_write_failed'),
      lastStack ?? StackTrace.current,
    );
  }
}
