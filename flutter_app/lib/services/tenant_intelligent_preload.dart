import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_panel_module_prefetch_service.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_statistics_snapshot_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Pré-carregamento — dashboard imediato + **todos** os módulos em background.
abstract final class TenantIntelligentPreload {
  TenantIntelligentPreload._();

  static bool _dashboardRunning = false;

  /// Após Dashboard visível — contadores + prefetch completo (Hive + Firestore cache).
  static void scheduleAfterDashboard(String tenantIdRaw) {
    final tid = ChurchRepository.churchId(tenantIdRaw.trim());
    if (tid.isEmpty) return;
    unawaited(_runDashboardOnly(tid));
    ChurchPanelModulePrefetchService.scheduleFullPrefetch(tid);
    unawaited(
      ChurchTenantOfflineWarmupService.instance.scheduleWarmupAfterLogin(tid),
    );
  }

  /// Ao abrir um módulo do menu — garante aquecimento daquele módulo.
  static void scheduleModuleForShellIndex(String tenantIdRaw, int shellIndex) {
    final tid = ChurchRepository.churchId(tenantIdRaw.trim());
    if (tid.isEmpty) return;
    final module = _moduleForShellIndex(shellIndex);
    if (module != null) {
      ChurchPanelModulePrefetchService.scheduleModule(tid, module);
    }
    unawaited(_warmShellModuleLegacy(tid, shellIndex));
  }

  static String? _moduleForShellIndex(int shellIndex) {
    switch (shellIndex) {
      case ChurchShellIndices.membros:
        return TenantModuleKeys.membros;
      case ChurchShellIndices.muralAvisos:
        return TenantModuleKeys.avisos;
      case ChurchShellIndices.muralEventos:
        return TenantModuleKeys.eventos;
      case ChurchShellIndices.chatIgreja:
        return null;
      case ChurchShellIndices.financeiro:
        return TenantModuleKeys.financeiro;
      case ChurchShellIndices.patrimonio:
        return TenantModuleKeys.patrimonio;
      case ChurchShellIndices.escalaGeral:
      case ChurchShellIndices.minhaEscala:
        return TenantModuleKeys.escalas;
      default:
        return null;
    }
  }

  static Future<void> _runDashboardOnly(String tenantId) async {
    if (_dashboardRunning) return;
    _dashboardRunning = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      await PanelDashboardSnapshotService.readOnce(tenantId);
      await PanelStatisticsSnapshotService.readOnce(tenantId);
      await ChurchTenantDashboardDocService.readOnce(tenantId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('Preload[dashboard] $e\n$st');
    } finally {
      _dashboardRunning = false;
    }
  }

  /// Compat — reaquece Firestore cache do módulo aberto (delega ao prefetch).
  static Future<void> _warmShellModuleLegacy(String tenantId, int shellIndex) async {
    final module = _moduleForShellIndex(shellIndex);
    if (module == null) return;
    ChurchPanelModulePrefetchService.scheduleModule(tenantId, module);
  }
}
