import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Registro runtime de consultas Firestore — relatório de performance (sem UI).
class FirebaseQueryAuditEntry {
  const FirebaseQueryAuditEntry({
    required this.module,
    required this.path,
    required this.kind,
    required this.durationMs,
    required this.docCount,
    this.limit,
    this.error,
  });

  final String module;
  final String path;
  final String kind; // get | list | count | watch
  final int durationMs;
  final int docCount;
  final int? limit;
  final String? error;

  int get estimatedBytes => docCount * 2048;
}

/// Auditoria em memória — exportável via [toReportTable] / Saúde do Sistema.
abstract final class FirebaseQueryAudit {
  FirebaseQueryAudit._();

  static const int _maxEntries = 400;
  static final List<FirebaseQueryAuditEntry> _entries = [];

  static void record({
    required String module,
    required String path,
    required String kind,
    required int durationMs,
    int docCount = 0,
    int? limit,
    String? error,
  }) {
    if (path.contains('unlimited_scan')) {
      debugPrint('PERF_AUDIT WARN: scan sem limite — $module $path');
    }
    _entries.add(
      FirebaseQueryAuditEntry(
        module: module,
        path: path,
        kind: kind,
        durationMs: durationMs,
        docCount: docCount,
        limit: limit,
        error: error,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  static List<FirebaseQueryAuditEntry> snapshot() =>
      List.unmodifiable(_entries);

  static Map<String, FirebaseQueryModuleStats> aggregateByModule() {
    final map = <String, FirebaseQueryModuleStats>{};
    for (final e in _entries) {
      final s = map.putIfAbsent(e.module, () => FirebaseQueryModuleStats());
      s.queries++;
      s.totalMs += e.durationMs;
      s.totalDocs += e.docCount;
      s.totalBytes += e.estimatedBytes;
      if (e.error != null) s.errors++;
      if (e.limit == null && e.kind == 'list' && e.docCount > 50) {
        s.unlimitedScans++;
      }
    }
    return map;
  }

  static String toReportTable() {
    final platform = kIsWeb ? 'WEB' : 'MOBILE';
    final agg = aggregateByModule();
    final b = StringBuffer()
      ..writeln('=== FIRESTORE QUERY AUDIT — $platform ===')
      ..writeln('')
      ..writeln('| Módulo | Consultas | ms médio | Docs | ~KB | Scans s/ limite | Erros |');
    final sorted = agg.entries.toList()
      ..sort((a, b) => b.value.totalMs.compareTo(a.value.totalMs));
    for (final e in sorted) {
      final s = e.value;
      final avg = s.queries > 0 ? (s.totalMs / s.queries).round() : 0;
      final kb = (s.totalBytes / 1024).round();
      b.writeln(
        '| ${e.key} | ${s.queries} | ${avg}ms | ${s.totalDocs} | $kb | ${s.unlimitedScans} | ${s.errors} |',
      );
    }
    b.writeln('');
    b.writeln('TOTAL entradas: ${_entries.length}');
    return b.toString().trimRight();
  }

  static void clear() => _entries.clear();
}

class FirebaseQueryModuleStats {
  int queries = 0;
  int totalMs = 0;
  int totalDocs = 0;
  int totalBytes = 0;
  int unlimitedScans = 0;
  int errors = 0;
}
