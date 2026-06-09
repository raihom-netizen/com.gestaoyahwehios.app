import 'package:flutter/foundation.dart' show debugPrint;

/// Rastreio de leituras/gravações operacionais — diagnóstico Web/Android/iOS.
abstract final class ChurchOperationalFirestoreTrace {
  ChurchOperationalFirestoreTrace._();

  static final List<ChurchFirestoreTraceEntry> _recent = [];
  static const int _maxRecent = 48;

  static List<ChurchFirestoreTraceEntry> get recent =>
      List<ChurchFirestoreTraceEntry>.unmodifiable(_recent);

  static void record({
    required String origin,
    required String firestorePath,
    String? churchId,
    int? durationMs,
    String? error,
    bool usedTenantsCollection = false,
  }) {
    final entry = ChurchFirestoreTraceEntry(
      origin: origin.trim(),
      firestorePath: firestorePath.trim(),
      churchId: churchId?.trim(),
      durationMs: durationMs,
      error: error,
      usedTenantsCollection: usedTenantsCollection,
      at: DateTime.now(),
    );
    _recent.insert(0, entry);
    if (_recent.length > _maxRecent) {
      _recent.removeRange(_maxRecent, _recent.length);
    }
    if (usedTenantsCollection) {
      debugPrint(
        'TENANTS_BLOCKED origin=$origin path=$firestorePath — use igrejas/{churchId}',
      );
    }
  }

  static void clear() => _recent.clear();
}

class ChurchFirestoreTraceEntry {
  const ChurchFirestoreTraceEntry({
    required this.origin,
    required this.firestorePath,
    this.churchId,
    this.durationMs,
    this.error,
    this.usedTenantsCollection = false,
    required this.at,
  });

  final String origin;
  final String firestorePath;
  final String? churchId;
  final int? durationMs;
  final String? error;
  final bool usedTenantsCollection;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'origin': origin,
        'firestorePath': firestorePath,
        if (churchId != null) 'churchId': churchId,
        if (durationMs != null) 'durationMs': durationMs,
        if (error != null) 'error': error,
        'usedTenantsCollection': usedTenantsCollection,
        'at': at.toIso8601String(),
      };
}
