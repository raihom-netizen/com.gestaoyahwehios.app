import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';

import 'firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_repository.dart';

/// Membro leve no cache do painel (`_panel_cache/dashboard_summary`).
class PanelHomeMemberLite {
  const PanelHomeMemberLite({
    required this.memberDocId,
    required this.displayName,
    this.photoUrl,
    this.fotoUrlCacheRevision = 0,
    this.authUid,
    this.cpfDigits,
    this.telefone,
    this.birthMonth,
    this.birthDay,
    this.deptNames = const [],
    this.corpoRoles = const [],
  });

  final String memberDocId;
  final String displayName;
  final String? photoUrl;
  final int fotoUrlCacheRevision;
  final String? authUid;
  final String? cpfDigits;
  final String? telefone;
  final int? birthMonth;
  final int? birthDay;
  final List<String> deptNames;
  final List<String> corpoRoles;

  factory PanelHomeMemberLite.fromMap(Map<String, dynamic> raw) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }

    final photo = (raw['photoUrl'] ?? '').toString().trim();
    return PanelHomeMemberLite(
      memberDocId: (raw['memberDocId'] ?? '').toString(),
      displayName: (raw['displayName'] ?? 'Membro').toString(),
      photoUrl: photo.isEmpty ? null : photo,
      fotoUrlCacheRevision: n(raw['fotoUrlCacheRevision']),
      authUid: (raw['authUid'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['authUid'] ?? '').toString(),
      cpfDigits: (raw['cpfDigits'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['cpfDigits'] ?? '').toString(),
      telefone: (raw['telefone'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['telefone'] ?? '').toString(),
      birthMonth: raw['birthMonth'] == null ? null : n(raw['birthMonth']),
      birthDay: raw['birthDay'] == null ? null : n(raw['birthDay']),
      deptNames: strList(raw['deptNames']),
      corpoRoles: strList(raw['corpoRoles']),
    );
  }

  /// Mapa compatível com [FotoMembroWidget] / avatares do painel.
  Map<String, dynamic> toMemberDataMap() {
    return <String, dynamic>{
      if (authUid != null && authUid!.isNotEmpty) 'authUid': authUid,
      'NOME_COMPLETO': displayName,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'fotoUrl': photoUrl,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoMedium': photoUrl,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoThumb': photoUrl,
      if (fotoUrlCacheRevision > 0)
        'fotoUrlCacheRevision': fotoUrlCacheRevision,
      if (cpfDigits != null && cpfDigits!.isNotEmpty) 'CPF': cpfDigits,
      if (telefone != null && telefone!.isNotEmpty) 'TELEFONES': telefone,
    };
  }
}

/// Aviso leve com capa para o painel inicial.
class PanelHomeAvisoLite {
  const PanelHomeAvisoLite({
    required this.id,
    required this.title,
    this.coverPhotoUrl,
    this.textPreview = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final String? coverPhotoUrl;
  final String textPreview;
  final Timestamp? createdAt;

  factory PanelHomeAvisoLite.fromMap(Map<String, dynamic> raw) {
    Timestamp? ts;
    final c = raw['createdAt'];
    if (c is Timestamp) ts = c;
    final cover = (raw['coverPhotoUrl'] ?? '').toString().trim();
    return PanelHomeAvisoLite(
      id: (raw['id'] ?? '').toString(),
      title: (raw['title'] ?? 'Aviso').toString(),
      coverPhotoUrl: cover.isEmpty ? null : cover,
      textPreview: (raw['textPreview'] ?? '').toString(),
      createdAt: ts,
    );
  }
}

/// Resumo leve do painel (`igrejas/{tid}/_panel_cache/dashboard_summary`).
class PanelDashboardSnapshot {
  final int pendingMembersCount;
  final int newVisitorsCount;
  final int openPrayerRequestsCount;
  final int membersTotalCount;
  final List<Map<String, dynamic>> recentAvisos;
  final List<Map<String, dynamic>> recentEventos;
  final List<Map<String, dynamic>> upcomingEventos;
  final List<PanelHomeMemberLite> birthdaysToday;
  final List<PanelHomeMemberLite> birthdaysWeek;
  final List<PanelHomeMemberLite> birthdaysMonth;
  final List<PanelHomeMemberLite> homeLeaders;
  final List<PanelHomeMemberLite> homeCorpoAdmin;
  final List<PanelHomeAvisoLite> homeAvisos;
  final Timestamp? cacheUpdatedAt;

  const PanelDashboardSnapshot({
    this.pendingMembersCount = 0,
    this.newVisitorsCount = 0,
    this.openPrayerRequestsCount = 0,
    this.membersTotalCount = 0,
    this.recentAvisos = const [],
    this.recentEventos = const [],
    this.upcomingEventos = const [],
    this.birthdaysToday = const [],
    this.birthdaysWeek = const [],
    this.birthdaysMonth = const [],
    this.homeLeaders = const [],
    this.homeCorpoAdmin = const [],
    this.homeAvisos = const [],
    this.cacheUpdatedAt,
  });

  bool get hasBirthdayData =>
      birthdaysToday.isNotEmpty ||
      birthdaysWeek.isNotEmpty ||
      birthdaysMonth.isNotEmpty;

  bool get hasHomeLeaders => homeLeaders.isNotEmpty;

  bool get hasHomeCorpo => homeCorpoAdmin.isNotEmpty;

  bool get hasHomeAvisos => homeAvisos.isNotEmpty;

  /// Cache `_panel_cache` recente o suficiente para pintar o painel sem streams de membros.
  bool get isFreshForInstantPanel {
    final ts = cacheUpdatedAt;
    if (ts == null) return false;
    if (DateTime.now().difference(ts.toDate()) >
        PanelDashboardSnapshotService.panelCacheFreshMaxAge) {
      return false;
    }
    return membersTotalCount > 0 ||
        hasBirthdayData ||
        hasHomeLeaders ||
        hasHomeCorpo ||
        hasHomeAvisos;
  }

  factory PanelDashboardSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const PanelDashboardSnapshot();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<Map<String, dynamic>> list(dynamic v) {
      if (v is! List) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    List<PanelHomeMemberLite> members(dynamic v) {
      return list(v).map(PanelHomeMemberLite.fromMap).toList();
    }

    return PanelDashboardSnapshot(
      pendingMembersCount: n(raw['pendingMembersCount']),
      newVisitorsCount: n(raw['newVisitorsCount']),
      openPrayerRequestsCount: n(raw['openPrayerRequestsCount']),
      membersTotalCount: n(raw['membersTotalCount']),
      recentAvisos: list(raw['recentAvisos']),
      recentEventos: list(raw['recentEventos']),
      upcomingEventos: list(raw['upcomingEventos']),
      birthdaysToday: members(raw['birthdaysToday']),
      birthdaysWeek: members(raw['birthdaysWeek']),
      birthdaysMonth: members(raw['birthdaysMonth']),
      homeLeaders: members(raw['homeLeaders']),
      homeCorpoAdmin: members(raw['homeCorpoAdmin']),
      homeAvisos: list(raw['recentAvisos'])
          .map(PanelHomeAvisoLite.fromMap)
          .toList(),
      cacheUpdatedAt: raw['updatedAt'] is Timestamp
          ? raw['updatedAt'] as Timestamp
          : null,
    );
  }
}

class PanelDashboardSnapshotService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Um único `igrejas/{churchId}` — Web = Android = iOS (sem cluster slug/alias).
  static Future<List<String>> clusterDocIdsForPanel(String seed) async {
    final id = ChurchRepository.churchId(seed);
    if (id.isEmpty) return const [];
    return [id];
  }

  static int _snapshotRichnessScore(PanelDashboardSnapshot s) {
    return s.membersTotalCount +
        s.homeLeaders.length * 8 +
        s.homeCorpoAdmin.length * 8 +
        s.homeAvisos.length * 3 +
        s.birthdaysToday.length * 2;
  }

  static Future<PanelDashboardSnapshot> _readBestPanelCache(
    List<String> clusterIds,
  ) async {
    var best = const PanelDashboardSnapshot();
    var bestScore = -1;
    for (final id in clusterIds) {
      for (final docRef in [cacheRef(id), cacheRefAlias(id)]) {
        for (final src in [Source.cache, Source.serverAndCache]) {
          try {
            final snap = await docRef.get(GetOptions(source: src));
            final parsed = _fromCacheDoc(snap);
            final sc = _snapshotRichnessScore(parsed);
            if (sc > bestScore) {
              bestScore = sc;
              best = parsed;
            }
          } catch (_) {}
        }
      }
    }
    return best;
  }

  static Future<String> _moduleReadTenantId(String seed) async {
    final id = ChurchRepository.churchId(seed);
    return id.isNotEmpty ? id : seed.trim();
  }

  /// Doc onde o servidor grava `_panel_cache` — sempre `igrejas/{churchId}` da sessão.
  static String _panelCacheWriteTenantId(String seed) {
    final id = ChurchRepository.churchId(seed);
    return id.isNotEmpty ? id : seed.trim();
  }

  /// Cache pré-processado — 1 leitura para todo o Dashboard.
  /// Canónico CF: `dashboard_summary`; alias spec: `dashboard`.
  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_panel_cache')
        .doc('dashboard_summary');
  }

  static DocumentReference<Map<String, dynamic>> cacheRefAlias(
    String tenantId,
  ) {
    return ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_panel_cache')
        .doc('dashboard');
  }

  /// Alias opcional se existir no tenant (`igrejas/{id}/dashboard_stats/summary`).
  static DocumentReference<Map<String, dynamic>>? dashboardStatsRef(
    String tenantId,
  ) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    return         ChurchOperationalPaths.churchDoc(tid)
        .collection('dashboard_stats')
        .doc('summary');
  }

  static Stream<PanelDashboardSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const PanelDashboardSnapshot());
    }
    return Stream.fromFuture(_moduleReadTenantId(tid)).asyncExpand(
      (readId) => FirestoreStreamUtils.documentWatchBootstrap(
        cacheRef(_panelCacheWriteTenantId(readId)),
      ).map(
        (snap) {
          final data = snap.data();
          if (data == null) return const PanelDashboardSnapshot();
          final summary = data['summary'];
          final base = summary is Map
              ? Map<String, dynamic>.from(summary)
              : Map<String, dynamic>.from(data);
          if (data['updatedAt'] is Timestamp) {
            base['updatedAt'] = data['updatedAt'];
          }
          return PanelDashboardSnapshot.fromMap(base);
        },
      ),
    );
  }

  static PanelDashboardSnapshot _fromCacheDoc(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data();
    if (data == null) return const PanelDashboardSnapshot();
    final summary = data['summary'];
    final base = summary is Map
        ? Map<String, dynamic>.from(summary)
        : Map<String, dynamic>.from(data);
    if (data['updatedAt'] is Timestamp) {
      base['updatedAt'] = data['updatedAt'];
    }
    return PanelDashboardSnapshot.fromMap(base);
  }

  /// Leitura única — cache local primeiro (padrão Controle Total), depois servidor.
  static Future<PanelDashboardSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelDashboardSnapshot();
    YahwehFlowLog.dashboardStart();
    final cluster = await clusterDocIdsForPanel(tid);
    final readId = await _moduleReadTenantId(tid);

    final statsRef = dashboardStatsRef(readId);
    if (statsRef != null) {
      try {
        final statsSnap = await statsRef.get(
          const GetOptions(source: Source.cache),
        );
        if (statsSnap.exists && statsSnap.data() != null) {
          YahwehFlowLog.dashboardSuccess();
          return PanelDashboardSnapshot.fromMap(statsSnap.data());
        }
      } catch (_) {}
      try {
        final statsSnap = await statsRef.get();
        if (statsSnap.exists && statsSnap.data() != null) {
          YahwehFlowLog.dashboardSuccess();
          return PanelDashboardSnapshot.fromMap(statsSnap.data());
        }
      } catch (_) {}
    }

    final fromCluster = await _readBestPanelCache(
      cluster.isNotEmpty ? cluster : [readId],
    );
    if (fromCluster.isFreshForInstantPanel) {
      YahwehFlowLog.dashboardSuccess();
      return fromCluster;
    }

    try {
      final warmed = await warmFromCallableIfStale(readId);
      if (_snapshotRichnessScore(warmed) >= _snapshotRichnessScore(fromCluster)) {
        YahwehFlowLog.dashboardSuccess();
        return warmed;
      }
      if (_snapshotRichnessScore(fromCluster) > 0) {
        YahwehFlowLog.dashboardSuccess();
        return fromCluster;
      }
      YahwehFlowLog.dashboardSuccess();
      return warmed;
    } catch (_) {
      if (_snapshotRichnessScore(fromCluster) > 0) return fromCluster;
      return const PanelDashboardSnapshot();
    }
  }

  static const Duration _staleAfter = Duration(minutes: 6);

  /// Idade máxima do snapshot para adiar queries pesadas de `membros` no painel.
  static const Duration panelCacheFreshMaxAge = _staleAfter;

  static bool _isFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt.toDate()) < _staleAfter;
  }

  /// Aquece o cache no servidor só se ausente ou com mais de [_staleAfter].
  static Future<PanelDashboardSnapshot> warmFromCallableIfStale(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelDashboardSnapshot();
    final readId = await _moduleReadTenantId(tid);
    try {
      final doc = await cacheRef(_panelCacheWriteTenantId(readId)).get();
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp && _isFresh(u)) {
        return _fromCacheDoc(doc);
      }
    } catch (_) {}
    return warmFromCallable(tenantId: readId);
  }

  /// Aquece o cache no servidor se estiver ausente ou velho.
  static Future<PanelDashboardSnapshot> warmFromCallable({
    String? tenantId,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'getChurchPanelSnapshot',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final payload = <String, dynamic>{};
      final tid = (tenantId ?? '').trim();
      if (tid.isNotEmpty) payload['tenantId'] = tid;
      final res = await callable.call<Map<String, dynamic>>(payload);
      final data = res.data;
      final mp = data['mediaPrefetch'];
      if (mp is Map) {
        final tid = (data['tenantId'] ?? '').toString().trim();
        if (tid.isNotEmpty) {
          unawaited(
            PanelMediaPrefetchService.applyToUrlCaches(
              tid,
              raw: Map<String, dynamic>.from(mp),
            ),
          );
        }
      }
      final summary = data['summary'];
      if (summary is Map) {
        return PanelDashboardSnapshot.fromMap(
          Map<String, dynamic>.from(summary),
        );
      }
    } catch (_) {}
    return const PanelDashboardSnapshot();
  }
}
