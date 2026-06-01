import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_app_config.dart';

/// Blindagem Web (padrão Controle Total): `INTERNAL ASSERTION FAILED` /
/// `WatchChangeAggregator` com listeners `snapshots()` + cache IndexedDB.
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
        await user.getIdToken(true);
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

  /// Recupera estado corrompido do SDK JS (terminate + limpar persistência + long-polling).
  static Future<void> recoverFirestoreWebSession() async {
    if (!kIsWeb) return;
    try {
      await firebaseDefaultFirestore.disableNetwork();
    } catch (_) {}
    try {
      await firebaseDefaultFirestore.terminate();
    } catch (_) {}
    try {
      await firebaseDefaultFirestore.clearPersistence();
    } catch (_) {}
    applyWebFirestoreSettings();
    try {
      await firebaseDefaultFirestore.enableNetwork();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await stabilizeAfterWebSignIn();
  }

  /// Executa [fn]; em erro interno do Firestore Web, recupera e tenta de novo (1x).
  static Future<T> runWithWebRecovery<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      if (!kIsWeb || !isInternalAssertionError(e)) {
        Error.throwWithStackTrace(e, st);
      }
      debugPrint('FirestoreWebGuard: recuperando sessão Web após assert…');
      await recoverFirestoreWebSession();
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
