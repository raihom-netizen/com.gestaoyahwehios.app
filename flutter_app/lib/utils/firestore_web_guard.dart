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

  static bool isInternalAssertionError(Object e) {
    final msg = e.toString();
    return msg.contains('INTERNAL ASSERTION') ||
        msg.contains('Unexpected state') ||
        msg.contains('WatchChangeAggregator') ||
        msg.contains('PersistentListenStream') ||
        msg.contains('__PRIVATE__TargetState');
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
    try {
      await firebaseDefaultFirestore.disableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 48));
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

  /// Recuperação Web — **sem** `terminate()` (mata o singleton e quebra Eventos/Avisos/Patrimônio).
  static Future<void> recoverFirestoreWebSession({bool allowHardReconnect = false}) async {
    if (EcoFireFlow.passThroughFirestore) return;
    if (!kIsWeb) return;
    if (WebPanelStability.isSessionExpired) return;

    if (allowHardReconnect) {
      await _reconnectFirestoreAfterTerminated();
      applyWebFirestoreSettings();
    }

    await stabilizeAfterWebSignIn();
    if (allowHardReconnect) {
      try {
        await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
        applyWebFirestoreSettings();
      } catch (_) {}
    }
    try {
      await firebaseDefaultFirestore.disableNetwork();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await firebaseDefaultFirestore.enableNetwork();
    } catch (e) {
      if (isClientTerminated(e)) {
        await _reconnectFirestoreAfterTerminated();
        applyWebFirestoreSettings();
        try {
          await firebaseDefaultFirestore.enableNetwork();
        } catch (_) {}
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
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

  /// Painel igreja (web/mobile) — leitura rápida sem desligar a rede.
  static Future<void> ensurePanelReadReady() async {
    if (!kIsWeb) return;
    try {
      applyWebFirestoreSettings();
      await ensureWebDatabaseConnected(refreshAuth: false).timeout(
        ChurchPanelReadTimeouts.readReadyCap,
      );
    } catch (_) {}
  }

  /// Painel Master web — sessão estável antes de qualquer leitura/gravação.
  static Future<void> ensureMasterPanelReady() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    await ensureWebDatabaseConnected(refreshAuth: true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        await user.getIdToken(true);
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
            Duration(milliseconds: 100 + attempt * 160),
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
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
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
