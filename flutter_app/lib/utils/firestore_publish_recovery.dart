import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Erro típico do Firestore Web (SDK 11.x) — não é falha da rede do utilizador.
bool isFirestoreInternalAssertion(Object error) {
  return FirestoreWebGuard.isInternalAssertionError(error);
}

/// Prepara sessão antes de gravar — **sem** `terminate()` no 1.º attempt.
Future<void> prepareFirestorePublishAttempt({
  int attempt = 0,
  bool allowReconnect = false,
  bool criticalWrite = false,
  Object? lastError,
}) async {
  if (attempt > 0) {
    await Future<void>.delayed(
      Duration(milliseconds: 280 + attempt * 420),
    );
  }
  if (kIsWeb) {
    try {
      if (attempt == 0) {
        await FirestoreWebGuard.prepareForPublishWrite();
      } else {
        final hard = lastError != null &&
            (FirestoreWebGuard.isClientTerminated(lastError) ||
                isFirestoreInternalAssertion(lastError));
        await FirestoreWebGuard.recoverFirestoreWebSession(
          allowHardReconnect: hard,
        );
      }
    } catch (_) {}
  }
  if (allowReconnect) {
    try {
      await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
    } catch (_) {}
  }
}

/// Publicação / escrita Firestore — prep leve + recovery só após falha (1 retry web).
Future<T> runFirestorePublishWithRecovery<T>(
  Future<T> Function() fn, {
  int maxAttempts = 2,
  bool criticalWrite = false,
}) async {
  if (kIsWeb) {
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    return FirestoreWebGuard.runWithWebRecovery(
      fn,
      maxAttempts: maxAttempts.clamp(2, 4),
    );
  }
  return fn();
}
