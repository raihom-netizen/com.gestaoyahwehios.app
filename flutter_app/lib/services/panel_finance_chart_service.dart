import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';

/// Dados prontos para gráficos do painel — cache mensal ou lançamentos ao vivo.
class PanelFinanceChartData {
  const PanelFinanceChartData({
    required this.netByBucket,
    required this.entradasByBucket,
    required this.saidasByBucket,
    required this.totalEntradas,
    required this.totalSaidas,
    this.fromLiveDocs = false,
  });

  final List<double> netByBucket;
  final List<double> entradasByBucket;
  final List<double> saidasByBucket;
  final double totalEntradas;
  final double totalSaidas;
  final bool fromLiveDocs;

  double get saldo => totalEntradas - totalSaidas;
  bool get hasValues =>
      totalEntradas.abs() > 0.01 ||
      totalSaidas.abs() > 0.01 ||
      netByBucket.any((v) => v.abs() > 0.01);
}

abstract final class PanelFinanceChartService {
  PanelFinanceChartService._();

  static bool isDespesa(Map<String, dynamic> data) {
    final t = (data['tipo'] ?? data['type'] ?? '').toString().toLowerCase();
    return t.contains('saida') ||
        t.contains('despesa') ||
        t.contains('saída') ||
        t == 'saida';
  }

  static bool isEntrada(Map<String, dynamic> data) {
    if (isDespesa(data)) return false;
    final t = (data['tipo'] ?? data['type'] ?? '').toString().toLowerCase();
    return t.contains('entrada') ||
        t.contains('receita') ||
        t == 'income' ||
        t == 'receita';
  }

  static DateTime? docDate(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['date'] ?? data['data'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      if (sec != null) {
        return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
      }
    }
    return null;
  }

  static double valorAbs(Map<String, dynamic> data) {
    final valor = data['amount'] ?? data['valor'] ?? data['value'] ?? 0;
    final v = valor is num
        ? valor.toDouble()
        : double.tryParse(valor.toString()) ?? 0;
    return v.abs();
  }

  static int? bucketIndexForDate(
    DateTime dt,
    List<DateTime> bucketStarts, {
    required bool monthlyMode,
  }) {
    if (monthlyMode) {
      for (var i = 0; i < bucketStarts.length; i++) {
        final s = bucketStarts[i];
        final e = DateTime(s.year, s.month + 1, 0, 23, 59, 59, 999);
        if (!dt.isBefore(s) && !dt.isAfter(e)) return i;
      }
      return null;
    }
    final day = DateTime(dt.year, dt.month, dt.day);
    for (var i = 0; i < bucketStarts.length; i++) {
      final s = bucketStarts[i];
      if (day == DateTime(s.year, s.month, s.day)) return i;
    }
    return null;
  }

  static PanelFinanceChartData fromSnapshot({
    required PanelFinanceSnapshot snapshot,
    required List<DateTime> bucketStarts,
    required bool monthlyMode,
  }) {
    final n = bucketStarts.length;
    final net = PanelFinanceSnapshotService.netFlowByBuckets(
      snapshot: snapshot,
      bucketStarts: bucketStarts,
      monthlyMode: monthlyMode,
    );
    final ent = List<double>.filled(n, 0);
    final sai = List<double>.filled(n, 0);
    if (monthlyMode) {
      for (var i = 0; i < bucketStarts.length; i++) {
        final mk = PanelFinanceSnapshotService.monthKey(bucketStarts[i]);
        final m = snapshot.months[mk] ?? const PanelFinanceMonthTotals();
        ent[i] = m.entradas;
        sai[i] = m.saidas;
      }
    }
    final te = ent.fold<double>(0, (a, b) => a + b);
    final ts = sai.fold<double>(0, (a, b) => a + b);
    return PanelFinanceChartData(
      netByBucket: net,
      entradasByBucket: ent,
      saidasByBucket: sai,
      totalEntradas: te,
      totalSaidas: ts,
    );
  }

  static PanelFinanceChartData fromFinanceDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required List<DateTime> bucketStarts,
    required bool monthlyMode,
    DateTimeRange? clipRange,
  }) {
    final n = bucketStarts.length;
    final ent = List<double>.filled(n, 0);
    final sai = List<double>.filled(n, 0);

    bool inRange(DateTime dt) {
      if (clipRange == null) return true;
      final d = DateTime(dt.year, dt.month, dt.day);
      final s = DateTime(
        clipRange.start.year,
        clipRange.start.month,
        clipRange.start.day,
      );
      final e = DateTime(
        clipRange.end.year,
        clipRange.end.month,
        clipRange.end.day,
        23,
        59,
        59,
        999,
      );
      return !d.isBefore(s) && !d.isAfter(e);
    }

    for (final doc in docs) {
      final data = doc.data();
      final dt = docDate(data);
      if (dt == null || !inRange(dt)) continue;
      final idx = bucketIndexForDate(
        dt,
        bucketStarts,
        monthlyMode: monthlyMode,
      );
      if (idx == null) continue;
      final v = valorAbs(data);
      if (isDespesa(data)) {
        sai[idx] += v;
      } else if (isEntrada(data)) {
        ent[idx] += v;
      }
    }

    final net = List<double>.generate(n, (i) => ent[i] - sai[i]);
    return PanelFinanceChartData(
      netByBucket: net,
      entradasByBucket: ent,
      saidasByBucket: sai,
      totalEntradas: ent.fold<double>(0, (a, b) => a + b),
      totalSaidas: sai.fold<double>(0, (a, b) => a + b),
      fromLiveDocs: true,
    );
  }

  /// Cache `_panel_cache/finance_summary` → se vazio ou modo diário, lançamentos recentes.
  static Future<PanelFinanceChartData> load({
    required String tenantId,
    required List<DateTime> bucketStarts,
    required bool monthlyMode,
    PanelFinanceSnapshot? cachedSnapshot,
    DateTimeRange? clipRange,
  }) async {
    final snap = cachedSnapshot ??
        await PanelFinanceSnapshotService.readOnce(tenantId);

    if (snap.hasData && monthlyMode) {
      final fromCache = fromSnapshot(
        snapshot: snap,
        bucketStarts: bucketStarts,
        monthlyMode: true,
      );
      if (fromCache.hasValues) return fromCache;
    }

    try {
      final qs = await ChurchFinanceRealtimeService.fetchFinanceFresh(
        tenantId,
        limit: 400,
      );
      return fromFinanceDocs(
        docs: qs.docs,
        bucketStarts: bucketStarts,
        monthlyMode: monthlyMode,
        clipRange: clipRange,
      );
    } catch (_) {
      if (snap.hasData) {
        return fromSnapshot(
          snapshot: snap,
          bucketStarts: bucketStarts,
          monthlyMode: monthlyMode,
        );
      }
      final n = bucketStarts.length;
      return PanelFinanceChartData(
        netByBucket: List<double>.filled(n, 0),
        entradasByBucket: List<double>.filled(n, 0),
        saidasByBucket: List<double>.filled(n, 0),
        totalEntradas: 0,
        totalSaidas: 0,
      );
    }
  }
}
