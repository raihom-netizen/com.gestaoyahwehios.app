import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/panel_finance_accounts_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';

/// Financeiro em tempo real — invalida cache local e observa `_panel_cache/finance_accounts`.
abstract final class ChurchFinanceRealtimeService {
  ChurchFinanceRealtimeService._();

  static Future<void> onFinanceMutation(String tenantId) async {
    await TenantStaleWhileRevalidate.invalidateModule(
      tenantId: tenantId,
      module: TenantModuleKeys.financeiro,
    );
    await ChurchFinanceLoadService.invalidate(tenantId);
    mutationEpoch.value++;
  }

  /// Incrementa quando há lançamento — painel/gráficos escutam para refrescar sem F5.
  static final ValueNotifier<int> mutationEpoch = ValueNotifier<int>(0);

  /// Resumo mensal directo do servidor (após novo lançamento).
  static Future<PanelFinanceSnapshot> fetchFinanceSummaryFromServer(
    String tenantId,
  ) =>
      PanelFinanceSnapshotService.readOnceFromServer(tenantId);

  /// Leitura fresca após gravar lançamento (sem Hive stale).
  static Future<QuerySnapshot<Map<String, dynamic>>> fetchFinanceFresh(
    String tenantId, {
    int limit = YahwehPerformanceV4.financeChartsSampleLimit,
  }) async {
    final result = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: tenantId,
      limit: limit,
      forceRefresh: true,
      forceServer: true,
    );
    return result.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> fetchContasFresh(
    String tenantId,
  ) async {
    final result = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tenantId,
      forceRefresh: true,
      forceServer: true,
    );
    return result.snapshot;
  }

  /// Cache-first — RAM → Hive → Firestore `igrejas/{id}/finance`.
  static Future<QuerySnapshot<Map<String, dynamic>>> fetchFinanceCached(
    String tenantId, {
    int limit = YahwehPerformanceV4.financeChartsSampleLimit,
  }) async {
    final result = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: tenantId,
      limit: limit,
    );
    return result.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> fetchContasCached(
    String tenantId,
  ) async {
    final result = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tenantId,
    );
    return result.snapshot;
  }

  static Stream<PanelFinanceAccountsSnapshot> watchAccountBalances(
    String tenantId,
  ) =>
      PanelFinanceAccountsSnapshotService.watch(tenantId);
}
