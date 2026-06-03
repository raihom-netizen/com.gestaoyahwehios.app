import 'package:flutter/foundation.dart';

/// Últimos erros do sistema — Central de Saúde ADM (memória, sessão atual).
abstract final class SystemLastErrorRegistry {
  SystemLastErrorRegistry._();

  static const int _maxEntries = 12;
  static final List<SystemLastErrorEntry> _entries = [];

  static List<SystemLastErrorEntry> get recent =>
      List<SystemLastErrorEntry>.unmodifiable(_entries);

  static SystemLastErrorEntry? get latest =>
      _entries.isEmpty ? null : _entries.first;

  static void record({
    required String module,
    required Object error,
    StackTrace? stackTrace,
    String? context,
  }) {
    final entry = SystemLastErrorEntry(
      module: module.trim().isEmpty ? 'SYSTEM' : module.trim(),
      message: error.toString(),
      context: context,
      at: DateTime.now(),
      stackTrace: stackTrace?.toString(),
    );
    _entries.insert(0, entry);
    while (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('SYSTEM_ERROR [${entry.module}] ${entry.message}');
    }
  }
}

class SystemLastErrorEntry {
  const SystemLastErrorEntry({
    required this.module,
    required this.message,
    required this.at,
    this.context,
    this.stackTrace,
  });

  final String module;
  final String message;
  final String? context;
  final DateTime at;
  final String? stackTrace;
}
