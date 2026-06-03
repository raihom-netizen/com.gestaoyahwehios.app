import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/system_health/session_performance_metrics.dart';

/// Firebase Performance Monitoring — mede duração de operações (upload, consultas).
abstract final class PerformanceService {
  PerformanceService._();

  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    try {
      await FirebasePerformance.instance
          .setPerformanceCollectionEnabled(kReleaseMode);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<T> track<T>(
    String name,
    Future<T> Function() operation,
  ) async {
    final sw = Stopwatch()..start();
    try {
      if (!_ready) return await operation();
      Trace? trace;
      try {
        trace = FirebasePerformance.instance.newTrace(_safeTraceName(name));
        await trace.start();
        return await operation();
      } finally {
        try {
          await trace?.stop();
        } catch (_) {}
      }
    } finally {
      sw.stop();
      SessionPerformanceMetrics.record(name, sw.elapsedMilliseconds);
    }
  }

  static String _safeTraceName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (s.isEmpty) return 'operation';
    return s.length > 100 ? s.substring(0, 100) : s;
  }
}
