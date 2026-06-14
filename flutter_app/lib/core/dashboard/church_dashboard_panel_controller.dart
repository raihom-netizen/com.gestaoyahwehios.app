import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_birthday_query_service.dart';
import 'package:gestao_yahweh/services/church_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/church_dashboard_current_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';

/// Facade única do Painel Inicial — **proibido** `FirebaseFirestore.instance` aqui.
///
/// Equivalente arquitectural ao «DashboardController» genérico, mas alinhado ao Gestão YAHWEH:
/// - 1 read `_panel_cache/dashboard_summary` (aniversariantes, líderes, avisos leves)
/// - 1 read `_dashboard_cache/main` (KPIs agregados)
/// - queries indexadas `birthMonth`/`birthDay` via [ChurchBirthdayQueryService]
/// - avisos/eventos painel: one-shot limit 10/32 (sem N snapshots live)
abstract final class ChurchDashboardPanelController {
  ChurchDashboardPanelController._();

  static String churchId(String shellHint) => ChurchRepository.churchId(shellHint);

  /// Cache local primeiro — pintura instantânea Web/Android/iOS.
  static Future<PanelDashboardSnapshot> readPanelSummary(String churchIdHint) =>
      PanelDashboardSnapshotService.readOnce(churchIdHint);

  static Stream<PanelDashboardSnapshot> watchPanelSummary(String churchIdHint) =>
      PanelDashboardSnapshotService.watch(churchIdHint);

  static Future<ChurchDashboardCacheSnapshot?> readMainKpis(String churchIdHint) =>
      ChurchDashboardCacheService.load(churchIdHint: churchIdHint);

  static Stream<ChurchDashboardCacheSnapshot?> watchMainKpis(String churchIdHint) =>
      ChurchDashboardCacheService.watch(churchIdHint: churchIdHint);

  static Future<ChurchDashboardCurrent> readEngagementKpis(String churchIdHint) =>
      ChurchDashboardCurrentService.readOnce(churchIdHint);

  static Future<MembersDirectorySnapshot> readMembersDirectory(String churchIdHint) =>
      MembersDirectorySnapshotService.readOnce(churchIdHint);

  /// Aniversariantes — índice Firestore (nunca scan completo de `membros`).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      birthdaysToday(String churchIdHint) =>
          ChurchBirthdayQueryService.fetchTodayBirthdays(tenantId: churchIdHint);

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      birthdaysThisWeek(String churchIdHint) =>
          ChurchBirthdayQueryService.fetchWeekBirthdays(tenantId: churchIdHint);

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      birthdaysThisMonth(String churchIdHint) =>
          ChurchBirthdayQueryService.fetchCurrentMonthBirthdays(
            tenantId: churchIdHint,
          );

  /// Resumo financeiro — doc `_panel_cache/finance_summary` (pré-calculado).
  static Future<PanelFinanceSnapshot> readFinanceSummary(String churchIdHint) =>
      PanelFinanceSnapshotService.readOnceFromServer(churchIdHint);

  /// Avisos ativos no painel — one-shot, limit baixo.
  static Future<QuerySnapshot<Map<String, dynamic>>> avisosPainel(
    String churchIdHint, {
    int limit = 10,
  }) =>
      ChurchTenantResilientReads.avisosFeed(churchIdHint, limit: limit);
}
