import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/crashlytics_benign_errors.dart';

/// Registo de erros não fatais (publicação, upload, rede).
abstract final class CrashlyticsService {
  CrashlyticsService._();

  static bool get _enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Evita inflar Crashlytics com sessão expirada, stream duplicado ou bootstrap recuperável.
  static bool shouldReport(Object error, {bool? fatal}) {
    if (fatal == true && !CrashlyticsBenignErrors.isBenign(error)) return true;
    if (CrashlyticsBenignErrors.isBenign(error)) return false;
    return true;
  }

  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool? fatal,
  }) async {
    if (!_enabled) return;
    if (!shouldReport(error, fatal: fatal)) return;
    final reportFatal = fatal ?? false;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack ?? StackTrace.current,
        fatal: reportFatal,
        reason: reason,
      );
    } catch (_) {}
  }
}
