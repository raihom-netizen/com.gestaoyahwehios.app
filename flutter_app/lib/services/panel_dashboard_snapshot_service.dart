import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Resumo leve do painel (`igrejas/{tid}/_panel_cache/dashboard_summary`).
class PanelDashboardSnapshot {
  final int pendingMembersCount;
  final int newVisitorsCount;
  final int openPrayerRequestsCount;
  final int membersTotalCount;
  final List<Map<String, dynamic>> recentAvisos;
  final List<Map<String, dynamic>> recentEventos;
  final List<Map<String, dynamic>> upcomingEventos;

  const PanelDashboardSnapshot({
    this.pendingMembersCount = 0,
    this.newVisitorsCount = 0,
    this.openPrayerRequestsCount = 0,
    this.membersTotalCount = 0,
    this.recentAvisos = const [],
    this.recentEventos = const [],
    this.upcomingEventos = const [],
  });

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

    return PanelDashboardSnapshot(
      pendingMembersCount: n(raw['pendingMembersCount']),
      newVisitorsCount: n(raw['newVisitorsCount']),
      openPrayerRequestsCount: n(raw['openPrayerRequestsCount']),
      membersTotalCount: n(raw['membersTotalCount']),
      recentAvisos: list(raw['recentAvisos']),
      recentEventos: list(raw['recentEventos']),
      upcomingEventos: list(raw['upcomingEventos']),
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
    return cacheRef(tid).snapshots().map((snap) {
      return PanelDashboardSnapshot.fromMap(snap.data());
    });
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
