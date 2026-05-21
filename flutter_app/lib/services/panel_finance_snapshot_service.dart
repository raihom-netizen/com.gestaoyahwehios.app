import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_stream_utils.dart';

/// Resumo mensal em `igrejas/{tid}/_panel_cache/finance_summary` (Cloud Function).
class PanelFinanceMonthTotals {
  const PanelFinanceMonthTotals({
    this.entradas = 0,
    this.saidas = 0,
  });

  final double entradas;
  final double saidas;

  factory PanelFinanceMonthTotals.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const PanelFinanceMonthTotals();
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    return PanelFinanceMonthTotals(
      entradas: n(raw['entradas']),
      saidas: n(raw['saidas']),
    );
  }
}

class PanelFinanceSnapshot {
  final Map<String, PanelFinanceMonthTotals> months;
  final int basisDocCount;
  final Timestamp? updatedAt;

  const PanelFinanceSnapshot({
    this.months = const {},
    this.basisDocCount = 0,
    this.updatedAt,
  });

  bool get hasData => months.isNotEmpty;

  factory PanelFinanceSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const PanelFinanceSnapshot();
    final monthsRaw = raw['months'];
    final out = <String, PanelFinanceMonthTotals>{};
    if (monthsRaw is Map) {
      for (final e in monthsRaw.entries) {
        if (e.value is Map) {
          out[e.key.toString()] = PanelFinanceMonthTotals.fromMap(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    final bc = raw['basisDocCount'];
    return PanelFinanceSnapshot(
      months: out,
      basisDocCount: bc is num ? bc.toInt() : int.tryParse('$bc') ?? 0,
      updatedAt: raw['updatedAt'] is Timestamp ? raw['updatedAt'] as Timestamp : null,
    );
  }
}

class PanelFinanceSnapshotService {
  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('_panel_cache')
        .doc('finance_summary');
  }

  static Stream<PanelFinanceSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return Stream.value(const PanelFinanceSnapshot());
    return FirestoreStreamUtils.resilientQuery(cacheRef(tid).snapshots()).map(
      (s) => PanelFinanceSnapshot.fromMap(s.data()),
    );
  }

  static String monthKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  /// Fluxo líquido (entradas − saídas) por bucket do painel — só `finance_summary`.
  static List<double> netFlowByBuckets({
    required PanelFinanceSnapshot snapshot,
    required List<DateTime> bucketStarts,
    required bool monthlyMode,
  }) {
    final out = List<double>.filled(bucketStarts.length, 0);
    for (var i = 0; i < bucketStarts.length; i++) {
      final start = bucketStarts[i];
      final mk = monthKey(start);
      final m = snapshot.months[mk] ?? const PanelFinanceMonthTotals();
      final net = m.entradas - m.saidas;
      if (monthlyMode) {
        out[i] = net;
      } else {
        final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
        out[i] = daysInMonth > 0 ? net / daysInMonth : 0;
      }
    }
    return out;
  }

  /// Saídas por bucket — só cache mensal.
  static List<double> saidasByBuckets({
    required PanelFinanceSnapshot snapshot,
    required List<DateTime> bucketStarts,
    required bool monthlyMode,
  }) {
    final out = List<double>.filled(bucketStarts.length, 0);
    for (var i = 0; i < bucketStarts.length; i++) {
      final start = bucketStarts[i];
      final mk = monthKey(start);
      final m = snapshot.months[mk] ?? const PanelFinanceMonthTotals();
      if (monthlyMode) {
        out[i] = m.saidas;
      } else {
        final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
        out[i] = daysInMonth > 0 ? m.saidas / daysInMonth : 0;
      }
    }
    return out;
  }

  static Future<PanelFinanceSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelFinanceSnapshot();
    try {
      final snap = await cacheRef(tid).get();
      return PanelFinanceSnapshot.fromMap(snap.data());
    } catch (_) {
      return const PanelFinanceSnapshot();
    }
  }
}
