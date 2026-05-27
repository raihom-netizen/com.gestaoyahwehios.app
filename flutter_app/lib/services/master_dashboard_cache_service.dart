import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Item da fila de ações do Command Center.
class MasterActionItem {
  const MasterActionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.menuItem,
    this.tenantId,
  });

  final String id;
  final String title;
  final String subtitle;
  final int count;
  final String menuItem;
  final String? tenantId;

  AdminMenuItem? get adminMenuItem {
    for (final v in AdminMenuItem.values) {
      if (v.name == menuItem) return v;
    }
    return null;
  }

  factory MasterActionItem.fromMap(Map<String, dynamic> m) {
    return MasterActionItem(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      subtitle: (m['subtitle'] ?? '').toString(),
      count: m['count'] is num ? (m['count'] as num).toInt() : 0,
      menuItem: (m['menuItem'] ?? '').toString(),
      tenantId: (m['tenantId'] ?? '').toString().trim().isEmpty
          ? null
          : (m['tenantId'] ?? '').toString(),
    );
  }
}

/// Resumo do Painel Master (`config/master_dashboard_summary` + cache local).
class MasterDashboardSummary {
  const MasterDashboardSummary({
    this.igrejas = 0,
    this.usuarios = 0,
    this.receita = 0,
    this.alertas = 0,
    this.licencasAtivas = 0,
    this.vencimentos7d = 0,
    this.vencimentos30d = 0,
    this.blockedCount = 0,
    this.freeCount = 0,
    this.suggestionsPending = 0,
    this.panelCacheStaleCount = 0,
    this.receitaPix = 0,
    this.receitaCartao = 0,
    this.cachedAtMs = 0,
    this.cacheUpdatedAt,
    this.igrejasPorMes = const [],
    this.usuariosPorMes = const [],
    this.receitaPorMes = const [],
    this.actionQueue = const [],
    this.expiringChurches = const [],
  });

  final int igrejas;
  final int usuarios;
  final double receita;
  final int alertas;
  final int licencasAtivas;
  final int vencimentos7d;
  final int vencimentos30d;
  final int blockedCount;
  final int freeCount;
  final int suggestionsPending;
  final int panelCacheStaleCount;
  final double receitaPix;
  final double receitaCartao;
  final int cachedAtMs;
  final Timestamp? cacheUpdatedAt;
  final List<Map<String, dynamic>> igrejasPorMes;
  final List<Map<String, dynamic>> usuariosPorMes;
  final List<Map<String, dynamic>> receitaPorMes;
  final List<MasterActionItem> actionQueue;
  final List<Map<String, dynamic>> expiringChurches;

  bool get isFresh {
    if (cacheUpdatedAt != null) {
      return DateTime.now().difference(cacheUpdatedAt!.toDate()) <
          const Duration(minutes: 15);
    }
    if (cachedAtMs <= 0) return false;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    return age < const Duration(minutes: 15).inMilliseconds;
  }

  bool get hasChartData =>
      igrejasPorMes.isNotEmpty || usuariosPorMes.isNotEmpty;

  bool get hasActionQueue => actionQueue.isNotEmpty;

  factory MasterDashboardSummary.fromJson(Map<String, dynamic> j) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<Map<String, dynamic>> list(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    Timestamp? ts;
    final u = j['updatedAt'];
    if (u is Timestamp) ts = u;

    return MasterDashboardSummary(
      igrejas: i(j['igrejas']),
      usuarios: i(j['usuarios']),
      receita: n(j['receita']),
      alertas: i(j['alertas']),
      licencasAtivas: i(j['licencasAtivas']),
      vencimentos7d: i(j['vencimentos7d']),
      vencimentos30d: i(j['vencimentos30d']),
      blockedCount: i(j['blockedCount']),
      freeCount: i(j['freeCount']),
      suggestionsPending: i(j['suggestionsPending']),
      panelCacheStaleCount: i(j['panelCacheStaleCount']),
      receitaPix: n(j['receitaPix']),
      receitaCartao: n(j['receitaCartao']),
      cachedAtMs: ts != null
          ? ts.millisecondsSinceEpoch
          : i(j['cachedAtMs']),
      cacheUpdatedAt: ts,
      igrejasPorMes: list(j['igrejasPorMes']),
      usuariosPorMes: list(j['usuariosPorMes']),
      receitaPorMes: list(j['receitaPorMes']),
      actionQueue: list(j['actionQueue'])
          .map(MasterActionItem.fromMap)
          .toList(),
      expiringChurches: list(j['expiringChurches']),
    );
  }

  Map<String, dynamic> toJson() => {
        'igrejas': igrejas,
        'usuarios': usuarios,
        'receita': receita,
        'alertas': alertas,
        'licencasAtivas': licencasAtivas,
        'vencimentos7d': vencimentos7d,
        'vencimentos30d': vencimentos30d,
        'blockedCount': blockedCount,
        'freeCount': freeCount,
        'suggestionsPending': suggestionsPending,
        'panelCacheStaleCount': panelCacheStaleCount,
        'receitaPix': receitaPix,
        'receitaCartao': receitaCartao,
        'cachedAtMs': cachedAtMs,
        if (cacheUpdatedAt != null) 'updatedAt': cacheUpdatedAt,
        'igrejasPorMes': igrejasPorMes,
        'usuariosPorMes': usuariosPorMes,
        'receitaPorMes': receitaPorMes,
        'actionQueue': actionQueue
            .map((a) => {
                  'id': a.id,
                  'title': a.title,
                  'subtitle': a.subtitle,
                  'count': a.count,
                  'menuItem': a.menuItem,
                  if (a.tenantId != null) 'tenantId': a.tenantId,
                })
            .toList(),
        'expiringChurches': expiringChurches,
      };
}

abstract final class MasterDashboardCacheService {
  MasterDashboardCacheService._();

  static const _prefsKey = 'master_dashboard_summary_v2';
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static DocumentReference<Map<String, dynamic>> get _firestoreRef =>
      FirebaseFirestore.instance
          .collection('config')
          .doc('master_dashboard_summary');

  static Future<MasterDashboardSummary?> readFirestore() async {
    try {
      final snap = await _firestoreRef.get();
      final data = snap.data();
      if (data == null || data.isEmpty) return null;
      return MasterDashboardSummary.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Stream<MasterDashboardSummary> watchFirestore() {
    return _firestoreRef.snapshots().map((snap) {
      final data = snap.data();
      if (data == null || data.isEmpty) {
        return const MasterDashboardSummary();
      }
      return MasterDashboardSummary.fromJson(data);
    });
  }

  static Future<MasterDashboardSummary?> readLocalPrefs() async {
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

  static Future<void> writeLocal(MasterDashboardSummary s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static Future<MasterDashboardSummary> warmFromCallable({
    bool force = false,
  }) async {
    if (!force) {
      final local = await readLocalPrefs();
      if (local != null) return local;
      final fs = await readFirestore();
      if (fs != null && fs.isFresh) {
        await writeLocal(fs);
        return fs;
      }
    }
    try {
      final callable = _functions.httpsCallable(
        'getMasterDashboardSnapshot',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final res = await callable.call<Map<String, dynamic>>({});
      final data = res.data;
      final summary = data['summary'];
      if (summary is Map) {
        final out = MasterDashboardSummary.fromJson(
          Map<String, dynamic>.from(summary),
        );
        await writeLocal(out);
        return out;
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('getMasterDashboardSnapshot: $e');
      }
    }
    return refreshClientFallback(force: true);
  }

  /// Atualiza cache do painel de uma igreja (callable master).
  static Future<void> warmChurchPanel(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    await _functions.httpsCallable(
      'warmChurchPanelFromMaster',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    ).call({'tenantId': tid});
  }

  /// Leitura rápida: Firestore → prefs → callable → scan cliente.
  static Future<MasterDashboardSummary> refresh({bool force = false}) async {
    if (!force) {
      final fs = await readFirestore();
      if (fs != null && fs.isFresh) {
        await writeLocal(fs);
        return fs;
      }
      final local = await readLocalPrefs();
      if (local != null) return local;
    }
    return warmFromCallable(force: force);
  }

  /// Fallback quando callable indisponível (scan leve no cliente).
  static Future<MasterDashboardSummary> refreshClientFallback({
    bool force = false,
  }) async {
    if (!force) {
      final c = await readLocalPrefs();
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
      final alertSnap = await db.collection('alertas').limit(200).get();
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
    await writeLocal(out);
    return out;
  }
}
