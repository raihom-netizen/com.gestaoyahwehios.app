import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics — mede uso de telas e eventos (não acelera o app; revela gargalos de UX).
abstract final class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

  static Future<void> ensureInitialized() async {
    try {
      await analytics.setAnalyticsCollectionEnabled(true);
    } catch (_) {}
  }

  /// Nome curto e estável (ex.: `dashboard`, `chat`, `avisos`).
  static Future<void> logScreen(String screen) async {
    final name = screen.trim();
    if (name.isEmpty) return;
    try {
      await analytics.logScreenView(
        screenName: name.length > 100 ? name.substring(0, 100) : name,
      );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('AnalyticsService.logScreen falhou: $screen');
      }
    }
  }

  static Future<void> logUpload(String type) async {
    try {
      await analytics.logEvent(
        name: 'upload',
        parameters: {'type': type.length > 40 ? type.substring(0, 40) : type},
      );
    } catch (_) {}
  }

  static Future<void> logMessage() async {
    try {
      await analytics.logEvent(name: 'message_sent');
    } catch (_) {}
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final safe = name.trim();
    if (safe.isEmpty) return;
    try {
      await analytics.logEvent(
        name: safe.length > 40 ? safe.substring(0, 40) : safe,
        parameters: parameters,
      );
    } catch (_) {}
  }
}
