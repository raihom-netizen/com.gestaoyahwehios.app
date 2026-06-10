import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
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

  /// Recuperação **suave** (Controle Total): token + rede — **sem** `terminate`/`clearPersistence`.
  static Future<void> recoverFirestoreWebSession({bool allowHardReconnect = false}) async {
    if (EcoFireFlow.passThroughFirestore) return;
    if (!kIsWeb) return;
    if (WebPanelStability.isSessionExpired) return;
    await stabilizeAfterWebSignIn();
    if (allowHardReconnect) {
      try {
        await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: true);
        applyWebFirestoreSettings();
      } catch (_) {}
    }
    try {
      await firebaseDefaultFirestore.disableNetwork();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await firebaseDefaultFirestore.enableNetwork();
    } catch (e) {
      if (isClientTerminated(e) && allowHardReconnect) {
        await _reconnectFirestoreAfterTerminated();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  /// Painel igreja (web/mobile) — leitura rápida sem desligar a rede.
  static Future<void> ensurePanelReadReady() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    await ensureWebDatabaseConnected(refreshAuth: false);
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
    final attempts = kIsWeb ? (maxAttempts > 2 ? 2 : maxAttempts) : maxAttempts;
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
            await ensureMasterPanelReady();
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

  /// Antes de publicar/gravar doc crítico — reduz INTERNAL ASSERTION (SDK 11.x + listeners do painel).
  static Future<void> prepareForCriticalWrite() async {
    if (!kIsWeb) return;
    applyWebFirestoreSettings();
    if (EcoFireFlow.passThroughFirestore) {
      await ensureWebDatabaseConnected(refreshAuth: false);
      return;
    }
    await recoverFirestoreWebSession(allowHardReconnect: true);
    await ensureWebDatabaseConnected(refreshAuth: true);
    // Segundo ciclo rede — alinha WatchChangeAggregator após dezenas de listeners no IndexedStack.
    try {
      await firebaseDefaultFirestore.disableNetwork();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 200));
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

  /// Recuperação progressiva após falha no envio do chat.
  static Future<void> recoverForChatWrite({required int attempt}) async {
    if (!kIsWeb) return;
    if (attempt >= 3) {
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
          await recoverForChatWrite(attempt: attempt);
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
