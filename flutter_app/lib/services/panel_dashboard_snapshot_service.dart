import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firestore_stream_utils.dart';

/// Membro leve no cache do painel (`_panel_cache/dashboard_summary`).
class PanelHomeMemberLite {
  const PanelHomeMemberLite({
    required this.memberDocId,
    required this.displayName,
    this.photoUrl,
    this.fotoUrlCacheRevision = 0,
    this.authUid,
    this.cpfDigits,
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
  });

  bool get hasBirthdayData =>
      birthdaysToday.isNotEmpty ||
      birthdaysWeek.isNotEmpty ||
      birthdaysMonth.isNotEmpty;

  bool get hasHomeLeaders => homeLeaders.isNotEmpty;

  bool get hasHomeCorpo => homeCorpoAdmin.isNotEmpty;

  bool get hasHomeAvisos => homeAvisos.isNotEmpty;

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
    );
  }
}

class PanelDashboardSnapshotService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('_panel_cache')
        .doc('dashboard_summary');
  }

  static Stream<PanelDashboardSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const PanelDashboardSnapshot());
    }
    return FirestoreStreamUtils.resilientDocument(cacheRef(tid).snapshots()).map(
      (snap) => PanelDashboardSnapshot.fromMap(snap.data()),
    );
  }

  /// Leitura única (1 doc) — pintura instantânea antes dos streams pesados.
  static Future<PanelDashboardSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelDashboardSnapshot();
    try {
      final snap = await cacheRef(tid).get();
      return PanelDashboardSnapshot.fromMap(snap.data());
    } catch (_) {
      return const PanelDashboardSnapshot();
    }
  }

  static const Duration _staleAfter = Duration(minutes: 6);

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
    try {
      final doc = await cacheRef(tid).get();
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp && _isFresh(u)) {
        return PanelDashboardSnapshot.fromMap(doc.data());
      }
    } catch (_) {}
    return warmFromCallable();
  }

  /// Aquece o cache no servidor se estiver ausente ou velho.
  static Future<PanelDashboardSnapshot> warmFromCallable() async {
    try {
      final callable = _functions.httpsCallable(
        'getChurchPanelSnapshot',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final res = await callable.call<Map<String, dynamic>>({});
      final data = res.data;
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
