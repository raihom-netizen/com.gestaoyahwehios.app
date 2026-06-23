import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:gestao_yahweh/core/system_health/production_module_traces.dart';
import 'package:gestao_yahweh/core/system_health/session_performance_metrics.dart';
import 'package:gestao_yahweh/services/yahweh_observability.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// Medidor interno de tempo de ecrÃ£ (debug + amostra em `performanceLogs`).
abstract final class YahwehPerformanceMonitor {
  YahwehPerformanceMonitor._();

  static final Map<String, int> _startsMs = {};
  static bool _enabled = kDebugMode;

  static void setEnabled(bool value) => _enabled = value;

  static void markScreenStart(String screen) {
    _startsMs[screen] = DateTime.now().millisecondsSinceEpoch;
  }

  static Future<void> markScreenReady(
    String screen, {
    bool reportToFirestore = false,
  }) async {
    final start = _startsMs.remove(screen);
    if (start != null) {
      final loadMs = DateTime.now().millisecondsSinceEpoch - start;
      final traceKey = _traceKeyForScreen(screen);
      if (traceKey != null) {
        SessionPerformanceMetrics.record(traceKey, loadMs);
      }
      if (!_enabled) return;
      if (kDebugMode) {
        debugPrint('Perf[$screen] ${loadMs}ms');
      }
      YahwehTelemetry.logScreenLoad(screen: screen, loadMs: loadMs);
      if (reportToFirestore && loadMs > 800) {
        unawaited(_sampleLog(screen: screen, loadMs: loadMs));
      }
    }
  }

  /// ApÃ³s primeiro frame pintado.
  static void markScreenReadyAfterFirstFrame(
    String screen, {
    bool reportToFirestore = false,
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(markScreenReady(screen, reportToFirestore: reportToFirestore));
    });
  }

  static Future<T> traceAsync<T>(
    String label,
    Future<T> Function() fn,
  ) async {
    return YahwehObservability.traceAsync(label, () async {
      final sw = Stopwatch()..start();
      try {
        return await fn();
      } finally {
        sw.stop();
        if (_enabled && kDebugMode) {
          debugPrint('Perf[$label] ${sw.elapsedMilliseconds}ms');
        }
      }
    });
  }

  static Future<void> _sampleLog({
    required String screen,
    required int loadMs,
  }) async {
    try {
      final uid = firebaseDefaultAuth.currentUser?.uid;
      if (uid == null) return;
      await firebaseDefaultFirestore.collection('performanceLogs').add({
        'screen': screen,
        'loadTime': loadMs,
        'device': defaultTargetPlatform.name,
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static String? _traceKeyForScreen(String screen) {
    switch (screen) {
      case 'igreja_dashboard':
        return ProductionModuleTraces.dashboard;
      case 'master_dashboard':
        return 'master_dashboard';
      case 'church_shell':
        return ProductionModuleTraces.dashboard;
      default:
        return null;
    }
  }
}

