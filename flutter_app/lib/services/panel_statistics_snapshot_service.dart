import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Estatísticas agregadas — `igrejas/{tid}/_panel_cache/statistics_summary`.
class PanelStatisticsSnapshot {
  const PanelStatisticsSnapshot({
    this.membersTotalCount = 0,
    this.activeMembersCount = 0,
    this.pendingMembersCount = 0,
    this.newVisitorsCount = 0,
    this.openPrayerRequestsCount = 0,
    this.birthdaysTodayCount = 0,
    this.birthdaysWeekCount = 0,
    this.birthdaysMonthCount = 0,
    this.avisosCount = 0,
    this.eventsCount = 0,
    this.upcomingEventsCount = 0,
    this.departmentsCount = 0,
    this.updatedAt,
  });

  final int membersTotalCount;
  final int activeMembersCount;
  final int pendingMembersCount;
  final int newVisitorsCount;
  final int openPrayerRequestsCount;
  final int birthdaysTodayCount;
  final int birthdaysWeekCount;
  final int birthdaysMonthCount;
  final int avisosCount;
  final int eventsCount;
  final int upcomingEventsCount;
  final int departmentsCount;
  final Timestamp? updatedAt;

  int get eventosTotal => eventsCount + upcomingEventsCount;

  bool get hasData =>
      membersTotalCount > 0 ||
      avisosCount > 0 ||
      eventosTotal > 0 ||
      updatedAt != null;

  factory PanelStatisticsSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const PanelStatisticsSnapshot();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return PanelStatisticsSnapshot(
      membersTotalCount: n(
        raw['membersTotalCount'] ?? raw['members'] ?? raw['membros'],
      ),
      activeMembersCount: n(raw['activeMembersCount']),
      pendingMembersCount: n(raw['pendingMembersCount']),
      newVisitorsCount: n(raw['newVisitorsCount'] ?? raw['visitantes']),
      openPrayerRequestsCount: n(
        raw['openPrayerRequestsCount'] ?? raw['pedidosOracao'],
      ),
      birthdaysTodayCount: n(raw['birthdaysTodayCount']),
      birthdaysWeekCount: n(raw['birthdaysWeekCount']),
      birthdaysMonthCount: n(raw['birthdaysMonthCount']),
      avisosCount: n(raw['avisosCount'] ?? raw['avisos']),
      eventsCount: n(raw['eventsCount']),
      upcomingEventsCount: n(raw['upcomingEventsCount']),
      departmentsCount: n(raw['departmentsCount'] ?? raw['departamentos']),
      updatedAt:
          raw['updatedAt'] is Timestamp ? raw['updatedAt'] as Timestamp : null,
    );
  }
}

abstract final class PanelStatisticsSnapshotService {
  PanelStatisticsSnapshotService._();

  static DocumentReference<Map<String, dynamic>> ref(String tenantId) {
    return ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_panel_cache')
        .doc('statistics_summary');
  }

  static Future<PanelStatisticsSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelStatisticsSnapshot();
    try {
      final cached = await ref(tid).get(
        const GetOptions(source: Source.cache),
      );
      final fromCache = PanelStatisticsSnapshot.fromMap(cached.data());
      if (fromCache.hasData) return fromCache;
    } catch (_) {}
    try {
      final snap = await ref(tid).get();
      return PanelStatisticsSnapshot.fromMap(snap.data());
    } catch (_) {
      return const PanelStatisticsSnapshot();
    }
  }

  static Stream<PanelStatisticsSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const PanelStatisticsSnapshot());
    }
    return ref(tid).watchSafe().map(
          (snap) => PanelStatisticsSnapshot.fromMap(snap.data()),
        );
  }
}
