import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_statistics_snapshot_service.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Pré-carregamento — **lazy**: só Dashboard no login; módulos ao abrir.
abstract final class TenantIntelligentPreload {
  TenantIntelligentPreload._();

  static String? _lastTenant;
  static bool _dashboardRunning = false;
  static final Set<String> _warmedModules = {};

  /// Após Dashboard visível — **1–2 leituras** (`_panel_cache` + contadores).
  static void scheduleAfterDashboard(String tenantIdRaw) {
    final tid = tenantIdRaw.trim();
    if (tid.isEmpty) return;
    _lastTenant = tid;
    unawaited(_runDashboardOnly(tid));
    unawaited(_warmCoreModulesSilently(tid));
  }

  /// Membros, Eventos e Avisos — cache Hive em background (usuário não percebe).
  static Future<void> _warmCoreModulesSilently(String tenantId) async {
    final limit = YahwehPerformanceV4.defaultPageSize;
    final specs = <(String, Future<QuerySnapshot<Map<String, dynamic>>> Function())>[
      (
        TenantModuleKeys.membros,
        () => ChurchTenantResilientReads.membrosRecent(tenantId, limit: limit),
      ),
      (
        TenantModuleKeys.eventos,
        () => ChurchTenantResilientReads.noticiasByStartAt(tenantId, limit: limit),
      ),
      (
        TenantModuleKeys.avisos,
        () => ChurchTenantResilientReads.avisosFeed(tenantId, limit: limit),
      ),
    ];
    for (final spec in specs) {
      try {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: spec.$1,
          networkFetch: spec.$2,
        );
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Ao abrir um módulo do menu — aquece só esse módulo (lazy).
  static void scheduleModuleForShellIndex(String tenantIdRaw, int shellIndex) {
    final tid = tenantIdRaw.trim();
    if (tid.isEmpty) return;
    final key = '$tid#$shellIndex';
    if (_warmedModules.contains(key)) return;
    _warmedModules.add(key);
    unawaited(_warmShellModule(tid, shellIndex));
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

  static Future<void> _warmShellModule(String tenantId, int shellIndex) async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
      final limit = YahwehPerformanceV4.defaultPageSize;

      Future<void> safe(String label, Future<void> Function() fn) async {
        try {
          await fn();
        } catch (e, st) {
          if (kDebugMode) debugPrint('Preload[$label] $e\n$st');
        }
      }

      switch (shellIndex) {
        case ChurchShellIndices.membros:
          await safe('membros', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.membros,
              networkFetch: () =>
                  ChurchTenantResilientReads.membrosRecent(tenantId, limit: limit),
            );
          });
          break;
        case ChurchShellIndices.muralAvisos:
          await safe('avisos', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.avisos,
              networkFetch: () =>
                  ChurchTenantResilientReads.avisosFeed(tenantId, limit: limit),
            );
          });
          break;
        case ChurchShellIndices.muralEventos:
          await safe('eventos', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.eventos,
              networkFetch: () => ChurchTenantResilientReads.noticiasByStartAt(
                tenantId,
                limit: limit,
              ),
            );
          });
          break;
        case ChurchShellIndices.chatIgreja:
          if (uid.isEmpty) break;
          await safe('chat', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.chat,
              networkFetch: () async {
                final op =
                    await ChurchOperationalPaths.resolveCached(tenantId);
                return ChurchOperationalPaths.churchDoc(op)
                    .collection('chats')
                    .where('participantUids', arrayContains: uid)
                    .orderBy('lastMessageAt', descending: true)
                    .limit(YahwehPerformanceV4.chatThreadsListLimit)
                    .get();
              },
            );
          });
          break;
        case ChurchShellIndices.financeiro:
          await safe('financeiro', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.financeiro,
              networkFetch: () =>
                  ChurchTenantResilientReads.financeRecent(tenantId, limit: limit),
            );
          });
          break;
        case ChurchShellIndices.patrimonio:
          await safe('patrimonio', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.patrimonio,
              networkFetch: () =>
                  ChurchTenantResilientReads.patrimonio(tenantId, limit: limit),
            );
          });
          break;
        case ChurchShellIndices.escalaGeral:
        case ChurchShellIndices.minhaEscala:
          await safe('escalas', () async {
            await TenantStaleWhileRevalidate.warmModule(
              tenantId: tenantId,
              module: TenantModuleKeys.escalas,
              networkFetch: () =>
                  ChurchTenantResilientReads.escalasRecent(tenantId, limit: limit),
            );
          });
          break;
        default:
          break;
      }
    } finally {
      unawaited(
        ChurchTenantOfflineWarmupService.instance.scheduleWarmupAfterLogin(
          tenantId,
        ),
      );
    }
  }
}
