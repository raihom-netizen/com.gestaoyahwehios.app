import 'package:gestao_yahweh/core/system_health/production_module_traces.dart';
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

  static Future<T> traceDashboard<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.dashboard, fn);

  static Future<T> traceChat<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.chat, fn);

  static Future<T> traceAvisos<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.avisos, fn);

  static Future<T> traceEventos<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.eventos, fn);

  static Future<T> tracePatrimonio<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.patrimonio, fn);

  static Future<T> traceFinanceiro<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.financeiro, fn);

  static Future<T> traceUpload<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.upload, fn);

  static Future<T> traceSyncFlush<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.syncFlush, fn);

  static Future<T> traceLogin<T>(Future<T> Function() fn) =>
      traceAsync(ProductionModuleTraces.login, fn);

  static Future<void> recordFirestoreError(Object error, StackTrace? stack) =>
      recordError(error, stack, reason: 'firestore_error');

  static Future<void> recordStorageError(Object error, StackTrace? stack) =>
      recordError(error, stack, reason: 'storage_error');

  static Future<void> recordUploadError(Object error, StackTrace? stack) =>
      recordError(error, stack, reason: 'upload_error');

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
