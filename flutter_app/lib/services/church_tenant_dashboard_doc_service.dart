import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_write_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Contadores leves do painel — `dashboard_stats/summary` ou `dashboard/home`.
///
/// A Home pode ler **só** estes docs (rápido) e deixar `_panel_cache` para detalhe.
class ChurchTenantDashboardCounters {
  const ChurchTenantDashboardCounters({
    this.members = 0,
    this.avisos = 0,
    this.eventos = 0,
    this.updatedAt,
  });

  final int members;
  final int avisos;
  final int eventos;
  final DateTime? updatedAt;

  factory ChurchTenantDashboardCounters.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const ChurchTenantDashboardCounters();
    }
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final ts = raw['updatedAt'];
    return ChurchTenantDashboardCounters(
      members: n(raw['members']),
      avisos: n(raw['avisos']),
      eventos: n(raw['eventos']),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

abstract final class ChurchTenantDashboardDocService {
  ChurchTenantDashboardDocService._();

  static const String docId = 'home';
  static const String statsDocId = 'summary';

  static DocumentReference<Map<String, dynamic>> ref(String tenantId) {
    return firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('dashboard')
        .doc(docId);
  }

  /// `igrejas/{tenantId}/dashboard_stats/summary` — fonte principal (1 documento).
  static DocumentReference<Map<String, dynamic>> statsRef(String tenantId) {
    return firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('dashboard_stats')
        .doc(statsDocId);
  }

  /// Alias spec CT: `church_dashboard_stats/summary` (mesmo payload que [statsRef]).
  static DocumentReference<Map<String, dynamic>> churchDashboardStatsRef(
    String tenantId,
  ) =>
      firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId.trim())
          .collection('church_dashboard_stats')
          .doc(statsDocId);

  static Future<ChurchTenantDashboardCounters?> _readCountersDoc(
    DocumentReference<Map<String, dynamic>> docRef,
    String cacheKey,
  ) async {
    try {
      final cached = await docRef.get(
        const GetOptions(source: Source.cache),
      );
      final fromCache = ChurchTenantDashboardCounters.fromMap(cached.data());
      if (fromCache.members > 0 ||
          fromCache.avisos > 0 ||
          fromCache.eventos > 0) {
        return fromCache;
      }
    } catch (_) {}
    try {
      final snap = await FirestoreReadResilience.getDocument(
        docRef,
        cacheKey: cacheKey,
      );
      final data = snap.data();
      if (data != null && data.isNotEmpty) {
        return ChurchTenantDashboardCounters.fromMap(data);
      }
    } catch (e, st) {
      ChurchTenantWriteLog.firestoreSetFail(
        docRef.path,
        e,
        stack: st,
        module: 'dashboard_read',
      );
    }
    return null;
  }

  /// Cache primeiro, servidor depois (stale-while-revalidate).
  static Future<ChurchTenantDashboardCounters> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const ChurchTenantDashboardCounters();
    await ensureFirebaseCore(requireAuth: false);

    final stats = await _readCountersDoc(statsRef(tid), '${tid}_dashboard_stats');
    if (stats != null) return stats;

    final churchStats = await _readCountersDoc(
      churchDashboardStatsRef(tid),
      '${tid}_church_dashboard_stats',
    );
    if (churchStats != null) return churchStats;

    final home = await _readCountersDoc(ref(tid), '${tid}_dashboard_home');
    if (home != null) return home;

    final panel = await PanelDashboardSnapshotService.readOnce(tid);
    return ChurchTenantDashboardCounters(
      members: panel.membersTotalCount,
      avisos: panel.homeAvisos.length,
      eventos: panel.recentEventos.length + panel.upcomingEventos.length,
    );
  }

  static Future<void> mergeCounters(
    String tenantId, {
    int? membersDelta,
    int? avisosDelta,
    int? eventosDelta,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final patch = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (membersDelta != null) {
      patch['members'] = FieldValue.increment(membersDelta);
    }
    if (avisosDelta != null) {
      patch['avisos'] = FieldValue.increment(avisosDelta);
    }
    if (eventosDelta != null) {
      patch['eventos'] = FieldValue.increment(eventosDelta);
    }
    for (final docRef in [statsRef(tid), ref(tid)]) {
      final path = docRef.path;
      ChurchTenantWriteLog.firestoreUpdateStart(path, module: 'dashboard');
      try {
        await docRef.set(patch, SetOptions(merge: true));
        ChurchTenantWriteLog.firestoreUpdateOk(path, module: 'dashboard');
      } catch (e, st) {
        ChurchTenantWriteLog.firestoreUpdateFail(path, e, stack: st, module: 'dashboard');
      }
    }
  }
}

