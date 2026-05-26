import 'package:firebase_performance/firebase_performance.dart';
import 'package:gestao_yahweh/services/analytics_service.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/performance_service.dart';
import 'package:gestao_yahweh/services/public_site_analytics.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';

/// Fachada — preferir [AnalyticsService], [PerformanceService], [CrashlyticsService].
abstract final class YahwehObservability {
  YahwehObservability._();

  static Future<void> ensureInitialized() async {
    await PublicSiteAnalytics.ensureInitialized();
    await AnalyticsService.ensureInitialized();
    await PerformanceService.ensureInitialized();
  }

  static Future<void> logScreenView({
    required String screenName,
    String? screenClass,
    String? tenantId,
  }) async {
    YahwehTelemetry.log('screen_view=$screenName');
    await AnalyticsService.logScreen(screenName);
    if (tenantId != null && tenantId.isNotEmpty) {
      await PublicSiteAnalytics.logEvent(
        'panel_screen_view',
        parameters: {'screen': screenName, 'tenant_id': tenantId},
      );
    }
  }

  static Future<void> logAction(
    String name, {
    Map<String, Object>? parameters,
  }) =>
      AnalyticsService.logEvent(name, parameters: parameters);

  static Future<T> traceAsync<T>(
    String traceName,
    Future<T> Function() fn,
  ) =>
      PerformanceService.track(traceName, fn);

  static HttpMetric? startHttpMetric(String url, HttpMethod method) {
    try {
      return FirebasePerformance.instance.newHttpMetric(url, method);
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) =>
      CrashlyticsService.record(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
}
