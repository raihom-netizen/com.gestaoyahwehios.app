import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Erro típico do Firestore Web (SDK 11.x) — não é falha da rede do utilizador.
bool isFirestoreInternalAssertion(Object error) {
  return FirestoreWebGuard.isInternalAssertionError(error);
}

/// Prepara sessão antes de gravar aviso/evento — evita `reconnect` no 1.º retry.
Future<void> prepareFirestorePublishAttempt({
  int attempt = 0,
  bool allowReconnect = false,
}) async {
  if (attempt > 0) {
    await Future<void>.delayed(
      Duration(milliseconds: 280 + attempt * 420),
    );
  }
  await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: attempt > 0);
  if (kIsWeb && attempt >= 1) {
    try {
      await FirestoreWebGuard.recoverFirestoreWebSession(
        allowHardReconnect: attempt >= 2,
      );
    } catch (_) {}
  }
  if (allowReconnect) {
    try {
      await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: true);
    } catch (_) {}
  }
}

/// Publicação / escrita Firestore com retries (Controle Total + recuperação Web).
Future<T> runFirestorePublishWithRecovery<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
}) async {
  Future<T> runAttempts() async {
    Object? last;
    StackTrace? lastSt;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await prepareFirestorePublishAttempt(
          attempt: attempt,
          allowReconnect: attempt >= maxAttempts - 1,
        );
        return await fn();
      } catch (e, st) {
        last = e;
        lastSt = st;
        final retryable = FirestoreReadResilience.isTransient(e) ||
            isFirestoreInternalAssertion(e);
        if (!retryable || attempt >= maxAttempts - 1) break;
      }
    }
    Error.throwWithStackTrace(last!, lastSt ?? StackTrace.current);
  }

  if (kIsWeb) {
    return FirestoreWebGuard.runWithWebRecovery(runAttempts);
  }
  return runAttempts();
}
