import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/yahweh_church_profile_engine.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';

/// Totais pré-calculados — nunca somar 2500 lançamentos no celular.
class ChurchFinanceAggregates {
  const ChurchFinanceAggregates({
    this.saldoAtual = 0,
    this.receitasMes = 0,
    this.despesasMes = 0,
    this.saldoAnterior = 0,
    this.mesReferencia = '',
    this.updatedAt,
  });

  final double saldoAtual;
  final double receitasMes;
  final double despesasMes;
  final double saldoAnterior;
  final String mesReferencia;
  final Timestamp? updatedAt;

  bool get hasData =>
      saldoAtual != 0 ||
      receitasMes != 0 ||
      despesasMes != 0 ||
      mesReferencia.isNotEmpty;

  factory ChurchFinanceAggregates.fromFinanceSummaryMap(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) return const ChurchFinanceAggregates();
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    return ChurchFinanceAggregates(
      saldoAtual: n(raw['saldoAtual'] ?? raw['saldo_atual']),
      receitasMes: n(raw['receitasMes'] ?? raw['receitas_mes']),
      despesasMes: n(raw['despesasMes'] ?? raw['despesas_mes']),
      saldoAnterior: n(raw['saldoAnterior'] ?? raw['saldo_anterior']),
      mesReferencia: (raw['mesReferencia'] ?? raw['mes_referencia'] ?? '')
          .toString()
          .trim(),
      updatedAt:
          raw['updatedAt'] is Timestamp ? raw['updatedAt'] as Timestamp : null,
    );
  }

  /// Fallback quando CF ainda não gravou campos agregados — usa `months` do cache.
  factory ChurchFinanceAggregates.fromSnapshot(PanelFinanceSnapshot snapshot) {
    if (!snapshot.hasData) return const ChurchFinanceAggregates();
    final now = DateTime.now();
    final mk = PanelFinanceSnapshotService.monthKey(now);
    final cur = snapshot.months[mk] ?? const PanelFinanceMonthTotals();
    var saldoAcum = 0.0;
    var saldoAntesMes = 0.0;
    for (final e in snapshot.months.entries) {
      final net = e.value.entradas - e.value.saidas;
      saldoAcum += net;
      if (e.key.compareTo(mk) < 0) saldoAntesMes += net;
    }
    return ChurchFinanceAggregates(
      saldoAtual: saldoAcum,
      receitasMes: cur.entradas,
      despesasMes: cur.saidas,
      saldoAnterior: saldoAntesMes,
      mesReferencia: mk,
      updatedAt: snapshot.updatedAt,
    );
  }
}

/// Leitura de `igrejas/{id}/_panel_cache/finance_summary` (campos agregados + months).
abstract final class ChurchFinanceAggregatesService {
  ChurchFinanceAggregatesService._();

  static Future<ChurchFinanceAggregates> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const ChurchFinanceAggregates();
    final snap = await PanelFinanceSnapshotService.readOnce(tid);
    final direct = ChurchFinanceAggregates.fromFinanceSummaryMap(
      await _rawSummaryMap(tid),
    );
    if (direct.hasData &&
        (direct.receitasMes != 0 ||
            direct.despesasMes != 0 ||
            direct.saldoAtual != 0)) {
      return direct;
    }
    return ChurchFinanceAggregates.fromSnapshot(snap);
  }

  static Stream<ChurchFinanceAggregates> watch(String tenantId) async* {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      yield const ChurchFinanceAggregates();
      return;
    }
    yield await readOnce(tid);
    await for (final snap in PanelFinanceSnapshotService.watch(tid)) {
      final raw = await _rawSummaryMap(tid);
      final direct = ChurchFinanceAggregates.fromFinanceSummaryMap(raw);
      if (direct.hasData &&
          (direct.receitasMes != 0 ||
              direct.despesasMes != 0 ||
              direct.saldoAtual != 0)) {
        yield direct;
      } else {
        yield ChurchFinanceAggregates.fromSnapshot(snap);
      }
    }
  }

  static Future<Map<String, dynamic>?> _rawSummaryMap(String tenantId) async {
    try {
      final doc = await ChurchOperationalPaths.churchDoc(tenantId)
          .collection('_panel_cache')
          .doc('finance_summary')
          .get();
      final panel = doc.data();
      if (panel != null && panel.isNotEmpty) return panel;
    } catch (_) {}

    try {
      final root = await ChurchOperationalPaths.churchDoc(tenantId).get();
      final rootData = root.data();
      if (rootData == null || rootData.isEmpty) return null;
      final fin = rootData['financeAggregates'];
      if (fin is Map && fin.isNotEmpty) {
        return Map<String, dynamic>.from(fin);
      }
      return ChurchRootAggregatesParser.flattenRootAggregates(rootData);
    } catch (_) {
      return null;
    }
  }
}
