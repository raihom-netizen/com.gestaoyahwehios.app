import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

bool _isFirestoreTransient(Object e) {
  if (e is FirebaseException) {
    const codes = {
      'unavailable',
      'deadline-exceeded',
      'resource-exhausted',
      'aborted',
      'internal',
      'unknown',
    };
    return codes.contains(e.code);
  }
  if (FirestoreWebGuard.isInternalAssertionError(e)) return true;
  final s = e.toString().toLowerCase();
  return s.contains('unavailable') ||
      s.contains('deadline-exceeded') ||
      s.contains('network_error') ||
      s.contains('failed to fetch');
}

/// Repete operações Firestore em falhas transitórias (padrão Controle Total).
Future<T> runFirestoreWithRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 350),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e, st) {
      final retry = _isFirestoreTransient(e) && attempt < maxAttempts - 1;
      if (!retry) {
        Error.throwWithStackTrace(e, st);
      }
      await Future<void>.delayed(initialDelay * (1 << attempt));
    }
  }
  throw StateError('firestore_retry: exhausted attempts');
}
