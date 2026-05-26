import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Registo de erros não fatais (publicação, upload, rede).
abstract final class CrashlyticsService {
  CrashlyticsService._();

  static bool get _enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_enabled) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack ?? StackTrace.current,
        fatal: fatal,
        reason: reason,
      );
    } catch (_) {}
  }
}
