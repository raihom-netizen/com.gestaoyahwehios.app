import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_church_profile_engine.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_statistics_snapshot_service.dart';

/// Contadores agregados — evita `collection('membros').get().length`.
///
/// Fontes (ordem):
/// 1. Campos no doc raiz `igrejas/{churchId}` (`membersCount`, …)
/// 2. `_panel_cache/statistics_summary`
/// 3. `_panel_cache/dashboard_summary`
/// 4. `dashboard_stats/summary` (via [ChurchTenantDashboardDocService])
class ChurchAggregatedCounters {
  const ChurchAggregatedCounters({
    this.membersCount = 0,
    this.activeMembersCount = 0,
    this.eventsCount = 0,
    this.avisosCount = 0,
    this.departmentsCount = 0,
    this.source = 'empty',
    this.updatedAt,
  });

  final int membersCount;
  final int activeMembersCount;
  final int eventsCount;
  final int avisosCount;
  final int departmentsCount;
  final String source;
  final DateTime? updatedAt;

  bool get hasAnyCounter =>
      membersCount > 0 ||
      activeMembersCount > 0 ||
      eventsCount > 0 ||
      avisosCount > 0 ||
      departmentsCount > 0;

  Map<String, dynamic> toJson() => {
        'membersCount': membersCount,
        'activeMembersCount': activeMembersCount,
        'eventsCount': eventsCount,
        'avisosCount': avisosCount,
        'departmentsCount': departmentsCount,
        'source': source,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

abstract final class ChurchAggregatedCountersService {
  ChurchAggregatedCountersService._();

  static const Duration kReadTimeout = Duration(seconds: 15);

  static int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  /// Uma leitura do doc raiz + fallback panel cache.
  static Future<ChurchAggregatedCounters> read(String churchId) async {
    final id = churchId.trim();
    if (id.isEmpty) return const ChurchAggregatedCounters();

    try {
      final snap = await ChurchOperationalPaths.churchDoc(id)
          .get(const GetOptions(source: Source.cache))
          .timeout(kReadTimeout);
      final fromRoot = _fromChurchRoot(snap.data());
      if (fromRoot.hasAnyCounter) return fromRoot;
    } catch (_) {}

    try {
      final snap = await ChurchOperationalPaths.churchDoc(id)
          .get()
          .timeout(kReadTimeout);
      final fromRoot = _fromChurchRoot(snap.data());
      if (fromRoot.hasAnyCounter) return fromRoot;
    } catch (_) {}

    try {
      final stats = await PanelStatisticsSnapshotService.readOnce(id)
          .timeout(kReadTimeout);
      if (stats.hasData) {
        return ChurchAggregatedCounters(
          membersCount: stats.membersTotalCount,
          activeMembersCount: stats.activeMembersCount,
          eventsCount: stats.eventosTotal,
          avisosCount: stats.avisosCount,
          departmentsCount: stats.departmentsCount,
          source: '_panel_cache/statistics_summary',
          updatedAt: stats.updatedAt?.toDate(),
        );
      }
    } catch (_) {}

    try {
      final panel = await PanelDashboardSnapshotService.readOnce(id)
          .timeout(kReadTimeout);
      return ChurchAggregatedCounters(
        membersCount: panel.membersTotalCount,
        eventsCount:
            panel.recentEventos.length + panel.upcomingEventos.length,
        avisosCount: panel.homeAvisos.length,
        source: '_panel_cache/dashboard_summary',
        updatedAt: panel.cacheUpdatedAt?.toDate(),
      );
    } catch (_) {}

    return const ChurchAggregatedCounters();
  }

  static ChurchAggregatedCounters _fromChurchRoot(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const ChurchAggregatedCounters();
    }
    final flat = ChurchRootAggregatesParser.flattenRootAggregates(raw);
    final ts = flat['countersUpdatedAt'] ?? flat['updatedAt'] ?? raw['updatedAt'];
    DateTime? at;
    if (ts is Timestamp) at = ts.toDate();

    final members = _n(
      flat['membersCount'] ??
          flat['membersTotalCount'] ??
          flat['members'] ??
          flat['totalMembros'],
    );
    final active = _n(
      flat['activeMembersCount'] ??
          flat['activeMembers'] ??
          flat['ativos'] ??
          members,
    );
    final events = _n(flat['eventsCount'] ?? flat['eventos']);
    final avisos = _n(flat['avisosCount'] ?? flat['avisos']);
    final departments = _n(
      flat['departmentsCount'] ?? flat['departamentos'],
    );

    if (members <= 0 &&
        active <= 0 &&
        events <= 0 &&
        avisos <= 0 &&
        departments <= 0) {
      return const ChurchAggregatedCounters();
    }

    return ChurchAggregatedCounters(
      membersCount: members > 0 ? members : active,
      activeMembersCount: active > 0 ? active : members,
      eventsCount: events,
      avisosCount: avisos,
      departmentsCount: departments,
      source: 'igrejas_root',
      updatedAt: at,
    );
  }

  /// Incremento atómico no doc raiz (cliente — CF também deve manter).
  static Future<void> increment({
    required String churchId,
    int membersDelta = 0,
    int eventsDelta = 0,
    int avisosDelta = 0,
    int departmentsDelta = 0,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) return;
    final patch = <String, dynamic>{
      'countersUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (membersDelta != 0) {
      patch['membersCount'] = FieldValue.increment(membersDelta);
    }
    if (eventsDelta != 0) {
      patch['eventsCount'] = FieldValue.increment(eventsDelta);
    }
    if (avisosDelta != 0) {
      patch['avisosCount'] = FieldValue.increment(avisosDelta);
    }
    if (departmentsDelta != 0) {
      patch['departmentsCount'] = FieldValue.increment(departmentsDelta);
    }
    await ChurchOperationalPaths.churchDoc(id).set(patch, SetOptions(merge: true));
  }
}
