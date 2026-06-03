import 'package:gestao_yahweh/core/system_health/production_module_traces.dart';

/// Métricas da sessão atual — exibidas em ADM > Diagnóstico (sem novo serviço remoto).
class SessionMetricEntry {
  const SessionMetricEntry({
    required this.label,
    required this.traceKey,
    required this.lastMs,
    required this.targetMs,
    required this.recordedAt,
  });

  final String label;
  final String traceKey;
  final int lastMs;
  final int targetMs;
  final DateTime recordedAt;

  bool get meetsTarget => lastMs <= targetMs;

  String get targetLabel => '${targetMs}ms';
}

abstract final class SessionPerformanceMetrics {
  SessionPerformanceMetrics._();

  static const _labels = <String, String>{
    ProductionModuleTraces.dashboard: 'Tempo Dashboard',
    'master_dashboard': 'Tempo Painel Master',
    ProductionModuleTraces.login: 'Tempo Login',
    ProductionModuleTraces.chat: 'Tempo Chat',
    ProductionModuleTraces.avisos: 'Tempo Avisos',
    ProductionModuleTraces.eventos: 'Tempo Eventos',
    ProductionModuleTraces.patrimonio: 'Tempo Patrimônio',
    ProductionModuleTraces.financeiro: 'Tempo Financeiro',
    ProductionModuleTraces.upload: 'Tempo Upload',
  };

  static const _targetsMs = <String, int>{
    ProductionModuleTraces.dashboard: 1000,
    'master_dashboard': 1000,
    ProductionModuleTraces.login: 3000,
    ProductionModuleTraces.chat: 1000,
    ProductionModuleTraces.avisos: 1000,
    ProductionModuleTraces.eventos: 1000,
    ProductionModuleTraces.patrimonio: 1500,
    ProductionModuleTraces.financeiro: 1500,
    ProductionModuleTraces.upload: 3000,
  };

  static final Map<String, SessionMetricEntry> _entries = {};

  static void record(String traceKey, int durationMs) {
    final key = traceKey.trim();
    if (key.isEmpty) return;
    _entries[key] = SessionMetricEntry(
      label: _labels[key] ?? key,
      traceKey: key,
      lastMs: durationMs,
      targetMs: _targetsMs[key] ?? 2000,
      recordedAt: DateTime.now(),
    );
  }

  static List<SessionMetricEntry> snapshot() {
    final keys = _labels.keys.toList();
    return keys
        .map((k) => _entries[k])
        .whereType<SessionMetricEntry>()
        .toList();
  }

  static List<SessionMetricEntry> snapshotWithPlaceholders() {
    return _labels.keys.map((k) {
      return _entries[k] ??
          SessionMetricEntry(
            label: _labels[k]!,
            traceKey: k,
            lastMs: -1,
            targetMs: _targetsMs[k] ?? 2000,
            recordedAt: DateTime.fromMillisecondsSinceEpoch(0),
          );
    }).toList();
  }

  static bool get allRecordedMeetTargets {
    final recorded = snapshot();
    if (recorded.isEmpty) return true;
    return recorded.every((e) => e.meetsTarget);
  }
}
