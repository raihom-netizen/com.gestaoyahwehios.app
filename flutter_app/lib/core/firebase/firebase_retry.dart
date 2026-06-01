import 'dart:async' show unawaited;

import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Retry com backoff linear (2s, 4s) — uploads, Firestore e Functions.
Future<T> firebaseRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  String? reason,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (e, st) {
      attempt++;
      if (attempt >= maxAttempts) {
        unawaited(
          CrashlyticsService.record(
            e,
            st,
            reason: reason ?? 'firebase_retry_exhausted',
          ),
        );
        rethrow;
      }
      if (isFirestoreInternalAssertion(e) ||
          FirestoreReadResilience.isTransient(e)) {
        await prepareFirestorePublishAttempt(
          attempt: attempt,
          allowReconnect: attempt >= maxAttempts - 1,
        );
      } else {
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
          force: attempt > 1,
        );
      }
    }
  }
}
