import 'dart:async';
import 'dart:convert';

import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/admin_user_search.dart';

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
    this.membrosTotal = 0,
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
  /// Soma de `membros` / `_panel_cache/members_directory` — cadastro real nas igrejas.
  final int membrosTotal;
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

  /// KPI «Usuários» — preferir membros cadastrados quando disponível.
  int get usuariosExibicao =>
      membrosTotal > usuarios ? membrosTotal : usuarios;

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
      membrosTotal: i(j['membrosTotal']),
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
        'membrosTotal': membrosTotal,
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
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static MasterDashboardSummary? _memSummary;
  static DateTime? _memSummaryAt;
  static const Duration _memTtl = Duration(minutes: 8);

  /// KPIs em RAM — instantâneo ao abrir qualquer tela master (sem await).
  static MasterDashboardSummary? peekMemory() => _memSummary;

  static void _storeMem(MasterDashboardSummary s) {
    _memSummary = s;
    _memSummaryAt = DateTime.now();
  }

  static bool _memFresh() {
    if (_memSummary == null || _memSummaryAt == null) return false;
    return DateTime.now().difference(_memSummaryAt!) < _memTtl;
  }

  static DocumentReference<Map<String, dynamic>> get _firestoreRef =>
      firebaseDefaultFirestore
          .collection('config')
          .doc('master_dashboard_summary');

  static Future<MasterDashboardSummary?> readFirestore({
    Source source = Source.serverAndCache,
  }) async {
    try {
      final snap = await _firestoreRef.get(GetOptions(source: source));
      final data = snap.data();
      if (data == null || data.isEmpty) return null;
      final out = MasterDashboardSummary.fromJson(data);
      _storeMem(out);
      return out;
    } catch (_) {
      return null;
    }
  }

  static Stream<MasterDashboardSummary> watchFirestore() {
    return _firestoreRef.watchSafe().map((snap) {
      final data = snap.data();
      if (data == null || data.isEmpty) {
        return const MasterDashboardSummary();
      }
      final out = MasterDashboardSummary.fromJson(data);
      _storeMem(out);
      return out;
    });
  }

  /// Prefs locais — aceita cache stale (SWR / arranque instantâneo).
  static Future<MasterDashboardSummary?> readAnyLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final s = MasterDashboardSummary.fromJson(
        Map<String, dynamic>.from(j),
      );
      _storeMem(s);
      return s;
    } catch (_) {
      return null;
    }
  }

  static Future<MasterDashboardSummary?> readLocalPrefs() async {
    final s = await readAnyLocal();
    if (s == null) return null;
    return s.isFresh ? s : null;
  }

  static Future<void> writeLocal(MasterDashboardSummary s) async {
    _storeMem(s);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static MasterDashboardSummary _alignChurchCount(MasterDashboardSummary summary) {
    final churchCount = MasterChurchesListService.peekCount();
    if (churchCount > 0 && summary.igrejas != churchCount) {
      return MasterDashboardSummary(
        igrejas: churchCount,
        usuarios: summary.usuarios,
        membrosTotal: summary.membrosTotal,
        receita: summary.receita,
        alertas: summary.alertas,
        licencasAtivas: summary.licencasAtivas,
        vencimentos7d: summary.vencimentos7d,
        vencimentos30d: summary.vencimentos30d,
        blockedCount: summary.blockedCount,
        freeCount: summary.freeCount,
        suggestionsPending: summary.suggestionsPending,
        panelCacheStaleCount: summary.panelCacheStaleCount,
        receitaPix: summary.receitaPix,
        receitaCartao: summary.receitaCartao,
        cachedAtMs: summary.cachedAtMs,
        cacheUpdatedAt: summary.cacheUpdatedAt,
        igrejasPorMes: summary.igrejasPorMes,
        usuariosPorMes: summary.usuariosPorMes,
        receitaPorMes: summary.receitaPorMes,
        actionQueue: summary.actionQueue,
        expiringChurches: summary.expiringChurches,
      );
    }
    return summary;
  }

  /// RAM → prefs (stale ok) → Firestore cache → null. Sem rede.
  static Future<MasterDashboardSummary?> readCachedInstant() async {
    if (_memFresh() && _memSummary != null) {
      return _alignChurchCount(_memSummary!);
    }
    final local = await readAnyLocal();
    if (local != null) return _alignChurchCount(local);
    final fs = await readFirestore(source: Source.cache);
    if (fs != null) return _alignChurchCount(fs);
    return null;
  }

  /// Atualiza em background (callable → fallback cliente) sem bloquear UI.
  static void revalidateInBackground({
    void Function(MasterDashboardSummary summary)? onUpdated,
  }) {
    unawaited(() async {
      try {
        final fresh = await warmFromCallable(force: true);
        onUpdated?.call(fresh);
      } catch (_) {
        try {
          final fb = await refreshClientFallback(force: true);
          onUpdated?.call(fb);
        } catch (_) {}
      }
    }());
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
        options: HttpsCallableOptions(timeout: const Duration(seconds: 28)),
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

  /// Leitura rápida: cache instantâneo → Firestore fresco → callable → scan cliente.
  /// Alinha contagem de igrejas com [MasterChurchesListService] (badge vs KPI).
  static Future<MasterDashboardSummary> refresh({bool force = false}) async {
    // Offline: só disco/RAM — sync silenciosa quando voltar a rede.
    if (!force && !AppConnectivityService.instance.isOnline) {
      final instant = await readCachedInstant();
      if (instant != null) return _alignChurchCount(instant);
      return const MasterDashboardSummary();
    }

    if (!force) {
      if (_memFresh() && _memSummary != null) {
        return _alignChurchCount(_memSummary!);
      }
      final instant = await readCachedInstant();
      if (instant != null && (instant.isFresh || instant.igrejas > 0)) {
        if (!instant.isFresh) {
          revalidateInBackground();
        }
        return instant;
      }
    }

    MasterDashboardSummary summary;
    if (!force) {
      final fs = await readFirestore();
      if (fs != null && fs.isFresh) {
        await writeLocal(fs);
        summary = fs;
      } else {
        final local = await readLocalPrefs();
        if (local != null) {
          summary = local;
          revalidateInBackground();
        } else {
          summary = await warmFromCallable(force: force);
        }
      }
    } else {
      summary = await warmFromCallable(force: force);
    }
    summary = _alignChurchCount(summary);
    await writeLocal(summary);
    return summary;
  }

  /// Fallback quando callable indisponível (scan leve no cliente).
  static Future<MasterDashboardSummary> refreshClientFallback({
    bool force = false,
  }) async {
    if (!force) {
      final c = await readLocalPrefs();
      if (c != null) return c;
    }

    final db = firebaseDefaultFirestore;
    var igrejas = 0;
    var usuarios = 0;
    var membrosTotal = 0;
    var alertas = 0;
    var licencasAtivas = 0;
    var venc7 = 0;
    var receita = 0.0;

    try {
      final igCount = await db.collection('igrejas').count().get();
      final userCount =
          await adminUsersWithEmailQuery(db.collection('users')).count().get();
      final alertSnap = await db
          .collection('alertas')
          .limit(YahwehPerformanceV4.masterCacheAlertsLimit)
          .get();
      final paySnap = await db
          .collection('pagamentos')
          .where('status', whereIn: ['approved', 'paid', 'accredited'])
          .limit(YahwehPerformanceV4.masterCachePaymentsLimit)
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

      final igSnap = await db
          .collection('igrejas')
          .limit(YahwehPerformanceV4.masterCacheChurchesScanLimit)
          .get();
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

        try {
          final dirSnap = await doc.reference
              .collection('_panel_cache')
              .doc('members_directory')
              .get(const GetOptions(source: Source.server));
          final dirData = dirSnap.data();
          final tc = dirData?['totalCount'] ??
              (dirData?['summary'] is Map
                  ? (dirData!['summary'] as Map)['totalCount']
                  : null);
          if (tc is num && tc > 0) {
            membrosTotal += tc.toInt();
          } else {
            final mc = await doc.reference.collection('membros').count().get();
            membrosTotal += mc.count ?? 0;
          }
        } catch (_) {
          try {
            final mc = await doc.reference.collection('membros').count().get();
            membrosTotal += mc.count ?? 0;
          } catch (_) {}
        }
      }
    } catch (_) {}

    final out = MasterDashboardSummary(
      igrejas: igrejas,
      usuarios: usuarios,
      membrosTotal: membrosTotal,
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

