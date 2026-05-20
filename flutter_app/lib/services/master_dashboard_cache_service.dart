import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resumo leve do painel master (cache local 15 min — abertura rápida).
class MasterDashboardSummary {
  const MasterDashboardSummary({
    this.igrejas = 0,
    this.usuarios = 0,
    this.receita = 0,
    this.alertas = 0,
    this.licencasAtivas = 0,
    this.vencimentos7d = 0,
    this.cachedAtMs = 0,
  });

  final int igrejas;
  final int usuarios;
  final double receita;
  final int alertas;
  final int licencasAtivas;
  final int vencimentos7d;
  final int cachedAtMs;

  bool get isFresh {
    if (cachedAtMs <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    return age < const Duration(minutes: 15).inMilliseconds;
  }

  factory MasterDashboardSummary.fromJson(Map<String, dynamic> j) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return MasterDashboardSummary(
      igrejas: i(j['igrejas']),
      usuarios: i(j['usuarios']),
      receita: n(j['receita']),
      alertas: i(j['alertas']),
      licencasAtivas: i(j['licencasAtivas']),
      vencimentos7d: i(j['vencimentos7d']),
      cachedAtMs: i(j['cachedAtMs']),
    );
  }

  Map<String, dynamic> toJson() => {
        'igrejas': igrejas,
        'usuarios': usuarios,
        'receita': receita,
        'alertas': alertas,
        'licencasAtivas': licencasAtivas,
        'vencimentos7d': vencimentos7d,
        'cachedAtMs': cachedAtMs,
      };
}

class MasterDashboardCacheService {
  MasterDashboardCacheService._();
  static const _prefsKey = 'master_dashboard_summary_v1';

  static Future<MasterDashboardSummary?> readCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final s = MasterDashboardSummary.fromJson(
        Map<String, dynamic>.from(j),
      );
      return s.isFresh ? s : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(MasterDashboardSummary s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static Future<MasterDashboardSummary> refresh({bool force = false}) async {
    if (!force) {
      final c = await readCached();
      if (c != null) return c;
    }

    final db = FirebaseFirestore.instance;
    var igrejas = 0;
    var usuarios = 0;
    var alertas = 0;
    var licencasAtivas = 0;
    var venc7 = 0;
    var receita = 0.0;

    try {
      final igCount = await db.collection('igrejas').count().get();
      final userCount = await db.collection('users').count().get();
      final alertSnap =
          await db.collection('alertas').limit(200).get();
      final paySnap = await db
          .collection('pagamentos')
          .where('status', whereIn: ['approved', 'paid', 'accredited'])
          .limit(400)
          .get();

      igrejas = igCount.count ?? 0;
      usuarios = userCount.count ?? 0;
      alertas = alertSnap.docs.where((d) {
        final lido = d.data()['lido'] == true || d.data()['read'] == true;
        return !lido;
      }).length;

      for (final d in paySnap.docs) {
        final amt = d.data()['amount'] ?? d.data()['valor'] ?? 0;
        receita += amt is num
            ? amt.toDouble()
            : double.tryParse('$amt') ?? 0;
      }

      final igSnap = await db.collection('igrejas').limit(300).get();
      final now = DateTime.now();
      final in7 = now.add(const Duration(days: 7));
      for (final doc in igSnap.docs) {
        final data = doc.data();
        final lic = data['license'];
        if (lic is Map && lic['active'] == true) licencasAtivas++;
        final dv = data['dataVencimento'] ?? data['vencimento'];
        DateTime? dt;
        if (dv is Timestamp) dt = dv.toDate();
        if (dt != null && !dt.isBefore(now) && !dt.isAfter(in7)) venc7++;
      }
    } catch (_) {}

    final out = MasterDashboardSummary(
      igrejas: igrejas,
      usuarios: usuarios,
      receita: receita,
      alertas: alertas,
      licencasAtivas: licencasAtivas,
      vencimentos7d: venc7,
      cachedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await write(out);
    return out;
  }
}
