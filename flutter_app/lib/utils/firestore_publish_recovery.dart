import 'dart:async';

import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Erro típico do Firestore Web (SDK 11.x) com muitas operações / rede instável.
bool isFirestoreInternalAssertion(Object error) {
  return error.toString().contains('INTERNAL ASSERTION');
}

/// Prepara sessão antes de gravar aviso/evento — evita `reconnect` no 1.º retry (não derruba o painel).
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
  if (allowReconnect) {
    try {
      await FirebaseBootstrapService.reconnect(requireAuthSession: true);
    } catch (_) {}
  }
}

/// Publicação / escrita Firestore com retries (token → delay → reconnect só no fim).
Future<T> runFirestorePublishWithRecovery<T>(
  Future<T> Function() fn, {
  int maxAttempts = 4,
}) async {
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
