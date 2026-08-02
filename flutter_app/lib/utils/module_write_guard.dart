import 'package:flutter/foundation.dart' show kIsWeb;

import 'firestore_session_guard.dart';
import 'firestore_user_doc_id.dart';
import 'firestore_web_guard.dart';

/// Blindagem comum para gravações (Web + Android + iOS): sessão Auth alinhada
/// às regras do Firestore antes de `users/{uid}/…` e retry em erros transitórios.
class ModuleWriteGuard {
  ModuleWriteGuard._();

  static const String kSessionNotReadyMessage =
      'A sincronizar sessão… tente novamente em instantes.';

  /// Garante token/sessão prontos e retorna o uid do documento `users/{id}`.
  static Future<String> ensureReady(String shellUid) async {
    final passed = shellUid.trim();
    await FirestoreSessionGuard.ensureWriteSession();
    if (kIsWeb) {
      await FirestoreWebGuard.stabilizeAfterWebSignIn();
    }

    var uid = firestoreUserDocIdForModuleReads(passed);
    if (uid.isNotEmpty) return uid;

    await FirestoreSessionGuard.waitForCurrentUser(
      timeout: const Duration(seconds: 4),
    );
    if (kIsWeb) {
      await FirestoreWebGuard.stabilizeAfterWebSignIn();
    }
    uid = firestoreUserDocIdForModuleReads(passed);
    return uid;
  }

  /// Executa [action] com uid resolvido e retry (permission / assert Web).
  static Future<T> run<T>(
    String shellUid,
    Future<T> Function(String userDocId) action,
  ) async {
    final uid = await ensureReady(shellUid);
    if (uid.isEmpty) {
      throw StateError(kSessionNotReadyMessage);
    }
    return FirestoreSessionGuard.runWithAuthRetry(() async {
      if (kIsWeb) {
        return FirestoreWebGuard.runWithWebRecovery(() => action(uid));
      }
      return action(uid);
    });
  }
}
