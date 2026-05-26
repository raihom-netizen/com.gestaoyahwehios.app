import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// KPIs pré-calculados no servidor — `igrejas/{tenant}/_performance_cache/dashboard_current`.
///
/// Atualizado pela Cloud Function do painel (sem contar membros no cliente).
class ChurchDashboardCurrent {
  const ChurchDashboardCurrent({
    this.totalMembers = 0,
    this.birthdaysToday = 0,
    this.totalUpcomingEvents = 0,
    this.pendingMembers = 0,
    this.newVisitors = 0,
    this.openPrayerRequests = 0,
    this.updatedAt,
  });

  final int totalMembers;
  final int birthdaysToday;
  final int totalUpcomingEvents;
  final int pendingMembers;
  final int newVisitors;
  final int openPrayerRequests;
  final Timestamp? updatedAt;

  factory ChurchDashboardCurrent.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const ChurchDashboardCurrent();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    Timestamp? ts;
    final u = raw['updatedAt'];
    if (u is Timestamp) ts = u;
    return ChurchDashboardCurrent(
      totalMembers: n(raw['totalMembers']),
      birthdaysToday: n(raw['birthdaysToday']),
      totalUpcomingEvents: n(raw['totalUpcomingEvents']),
      pendingMembers: n(raw['pendingMembers']),
      newVisitors: n(raw['newVisitors']),
      openPrayerRequests: n(raw['openPrayerRequests']),
      updatedAt: ts,
    );
  }
}

abstract final class ChurchDashboardCurrentService {
  ChurchDashboardCurrentService._();

  static DocumentReference<Map<String, dynamic>> ref(String tenantId) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('_performance_cache')
        .doc('dashboard_current');
  }

  static Future<ChurchDashboardCurrent> readOnce(String tenantId) async {
    try {
      final snap = await ref(tenantId).get();
      return ChurchDashboardCurrent.fromMap(snap.data());
    } catch (_) {
      return const ChurchDashboardCurrent();
    }
  }

  static Stream<ChurchDashboardCurrent> watch(String tenantId) {
    return FirestoreStreamUtils.resilientDocument(ref(tenantId).snapshots())
        .map((s) => ChurchDashboardCurrent.fromMap(s.data()));
  }
}
