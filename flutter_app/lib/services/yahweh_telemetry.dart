import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crashlytics + breadcrumbs (upload, rede, ecrãs lentos).
abstract final class YahwehTelemetry {
  YahwehTelemetry._();

  static bool get _crashlytics =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void log(String message) {
    if (_crashlytics) {
      FirebaseCrashlytics.instance.log(message);
    } else if (kDebugMode) {
      debugPrint('Telemetry: $message');
    }
  }

  static void logScreenLoad({required String screen, required int loadMs}) {
    log('screen=$screen loadMs=$loadMs');
  }

  static Future<void> recordUploadFailure(
    Object error,
    StackTrace? stack, {
    required String context,
    bool fatal = false,
  }) async {
    log('upload_fail context=$context error=$error');
    if (!_crashlytics) return;
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack ?? StackTrace.current,
      fatal: fatal,
      reason: 'upload:$context',
    );
  }

  static Future<void> recordNonFatal(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {
    if (!_crashlytics) return;
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack ?? StackTrace.current,
      fatal: false,
      reason: reason,
    );
  }
}
