import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';

/// Atualização síncrona dos contadores denormalizados do painel (`dashboard_stats/summary`).
///
/// Evita `count()` em coleções grandes — o dashboard lê um único documento.
abstract final class DashboardStatsCounterService {
  DashboardStatsCounterService._();

  static Future<void> onMemberCreated(String tenantId) =>
      _applyMemberDelta(tenantId, 1);

  static Future<void> onMemberDeleted(String tenantId) =>
      _applyMemberDelta(tenantId, -1);

  static Future<void> onAvisoPublished(String tenantId) =>
      ChurchTenantDashboardDocService.mergeCounters(tenantId, avisosDelta: 1);

  static Future<void> onEventoPublished(String tenantId) =>
      ChurchTenantDashboardDocService.mergeCounters(tenantId, eventosDelta: 1);

  static Future<void> _applyMemberDelta(String tenantId, int delta) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || delta == 0) return;
    await ChurchTenantDashboardDocService.mergeCounters(
      tid,
      membersDelta: delta,
    );
    final panelRef = PanelDashboardSnapshotService.cacheRef(tid);
    try {
      await panelRef.set(
        {
          'summary': {'membersTotalCount': FieldValue.increment(delta)},
          'membersTotalCount': FieldValue.increment(delta),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
