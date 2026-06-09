import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

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
    return         ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_performance_cache')
        .doc('dashboard_current');
  }

  /// Leitura cache-first sem aguardar bootstrap (pintura instantânea do painel).
  static Future<ChurchDashboardCurrent> readOnceFromLocalCache(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const ChurchDashboardCurrent();
    try {
      final cached = await ref(tid).get(
        const GetOptions(source: Source.cache),
      );
      return ChurchDashboardCurrent.fromMap(cached.data());
    } catch (_) {
      return const ChurchDashboardCurrent();
    }
  }

  static Future<ChurchDashboardCurrent> readOnce(String tenantId) async {
    final dashMain = await ChurchDashboardCacheService.load(churchIdHint: tenantId);
    if (dashMain != null && dashMain.hasData) {
      return ChurchDashboardCurrent(
        totalMembers: dashMain.totalMembros,
        newVisitors: dashMain.visitantes,
        updatedAt: dashMain.updatedAt != null
            ? Timestamp.fromDate(dashMain.updatedAt!)
            : null,
      );
    }
    await ensureFirebaseReadyForPanelRead();
    try {
      final cached = await ref(tenantId).get(
        const GetOptions(source: Source.cache),
      );
      final fromCache = ChurchDashboardCurrent.fromMap(cached.data());
      if (fromCache.updatedAt != null) return fromCache;
    } catch (_) {}
    try {
      final snap = await ref(tenantId).get();
      return ChurchDashboardCurrent.fromMap(snap.data());
    } catch (_) {
      return const ChurchDashboardCurrent();
    }
  }

  static Stream<ChurchDashboardCurrent> watch(String tenantId) {
    return ref(tenantId).watchSafe()
        .map((s) => ChurchDashboardCurrent.fromMap(s.data()));
  }
}
