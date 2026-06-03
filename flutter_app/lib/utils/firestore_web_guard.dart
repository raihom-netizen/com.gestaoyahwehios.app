import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firestore_app_config.dart';

/// Blindagem Web (padrão Controle Total): **nunca** `terminate()` em retry automático
/// (mata o singleton → `failed-precondition: client has already been terminated` em Doação,
/// Patrimônio, Cartão membro, Mural, etc.).
class FirestoreWebGuard {
  FirestoreWebGuard._();

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
    if (!kIsWeb) return;
    await stabilizeAfterWebSignIn();
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

  /// Executa [fn]; em assert interno ou cliente terminado, recupera **suave** e tenta 1x.
  static Future<T> runWithWebRecovery<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      final recoverable = kIsWeb &&
          (isInternalAssertionError(e) || isClientTerminated(e));
      if (!recoverable) {
        Error.throwWithStackTrace(e, st);
      }
      debugPrint('FirestoreWebGuard: recuperação suave Web…');
      await recoverFirestoreWebSession(
        allowHardReconnect: isClientTerminated(e),
      );
      return await fn();
    }
  }

  static Future<T> runWebGoogleSignInFlow<T>(Future<T> Function() fn) async {
    if (!kIsWeb) return fn();
    await prepareBeforeWebSignIn();
    try {
      return await runWithWebRecovery(fn);
    } finally {
      try {
        await firebaseDefaultFirestore.enableNetwork();
      } catch (_) {}
    }
  }
}
