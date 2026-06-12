import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/services/church_donation_load_service.dart';
import 'package:gestao_yahweh/services/church_schedules_load_service.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Pré-carrega **todos** os módulos do painel após login/dashboard — cache Hive + Firestore.
///
/// Antes: só 3 módulos em background e timeouts de 10–16s na web (listas vazias).
abstract final class ChurchPanelModulePrefetchService {
  ChurchPanelModulePrefetchService._();

  static String? _sessionChurchId;
  static bool _fullRunning = false;
  static final Set<String> _warmedKeys = {};

  static void resetForAccountSwitch() {
    _sessionChurchId = null;
    _fullRunning = false;
    _warmedKeys.clear();
  }

  /// Dispara prefetch completo (não bloqueia UI).
  static void scheduleFullPrefetch(String seedTenantId, {bool force = false}) {
    final churchId = ChurchPanelTenant.resolve(seedTenantId.trim());
    if (churchId.isEmpty) return;
    if (!force &&
        _sessionChurchId == churchId &&
        _fullRunning) {
      return;
    }
    _sessionChurchId = churchId;
    unawaited(_runFullPrefetch(churchId, force: force));
  }

  /// Um módulo ao abrir no menu — idempotente por sessão.
  static void scheduleModule(String seedTenantId, String moduleKey) {
    final churchId = ChurchPanelTenant.resolve(seedTenantId.trim());
    if (churchId.isEmpty || moduleKey.trim().isEmpty) return;
    unawaited(_warmModule(churchId, moduleKey.trim()));
  }

  static Future<void> _runFullPrefetch(String churchId, {bool force = false}) async {
    if (_fullRunning && !force) return;
    _fullRunning = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }

      // Doc raiz + doação (paths especiais) em paralelo leve.
      unawaited(
        ChurchCadastroLoadService.load(seedTenantId: churchId).then(
          (_) {},
          onError: (_, __) {},
        ),
      );
      unawaited(
        ChurchDonationLoadService.load(seedTenantId: churchId).then(
          (_) {},
          onError: (_, __) {},
        ),
      );

      for (final module in TenantModuleKeys.preloadOrder) {
        if (module == TenantModuleKeys.dashboard ||
            module == TenantModuleKeys.masterPanel) {
          continue;
        }
        await _warmModule(churchId, module);
        await Future<void>.delayed(const Duration(milliseconds: 45));
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('PanelModulePrefetch[full] $e\n$st');
      }
    } finally {
      _fullRunning = false;
    }
  }

  static Future<void> _warmModule(String churchId, String module) async {
    final key = '${churchId.trim()}#$module';
    if (_warmedKeys.contains(key)) return;

    final fetch = _networkFetch(churchId, module);
    if (fetch == null) return;

    try {
      if (module == TenantModuleKeys.departamentos) {
        final result = await ChurchDepartmentsLoadService.load(
          seedTenantId: churchId,
          forceRefresh: false,
        ).timeout(ChurchPanelReadTimeouts.prefetchCap);
        if (result.docs.isNotEmpty) {
          await ChurchDepartmentsLoadService.persistAfterLoad(result);
          _warmedKeys.add(key);
        }
        return;
      }

      await TenantStaleWhileRevalidate.warmModule(
        tenantId: churchId,
        module: module,
        networkFetch: fetch,
      ).timeout(ChurchPanelReadTimeouts.prefetchCap);
      _warmedKeys.add(key);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('PanelModulePrefetch[$module] $e\n$st');
      }
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> Function()? _networkFetch(
    String churchId,
    String module,
  ) {
    final limit = YahwehPerformanceV4.defaultPageSize;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    switch (module) {
      case TenantModuleKeys.membros:
        return () => ChurchTenantResilientReads.membrosRecent(
              churchId,
              limit: limit,
            );
      case TenantModuleKeys.departamentos:
        return () => ChurchTenantResilientReads.departamentos(churchId);
      case TenantModuleKeys.eventos:
        return () => ChurchTenantResilientReads.noticiasByStartAt(
              churchId,
              limit: limit,
            );
      case TenantModuleKeys.avisos:
        return () => ChurchTenantResilientReads.avisosFeed(
              churchId,
              limit: limit,
            );
      case TenantModuleKeys.chat:
        if (uid == null || uid.isEmpty) return null;
        return () => ChurchUiCollections.chats(churchId)
            .where('participantUids', arrayContains: uid)
            .orderBy('lastMessageAt', descending: true)
            .limit(YahwehPerformanceV4.chatThreadsListLimit)
            .get();
      case TenantModuleKeys.patrimonio:
        return () => ChurchTenantResilientReads.patrimonio(
              churchId,
              limit: limit,
            );
      case TenantModuleKeys.financeiro:
        return () => ChurchTenantResilientReads.financeRecent(
              churchId,
              limit: limit,
            );
      case TenantModuleKeys.escalas:
        return () async {
          final r = await ChurchSchedulesLoadService.loadEscalas(
            seedTenantId: churchId,
            limit: limit,
          );
          return r.snapshot;
        };
      case TenantModuleKeys.agenda:
        return () => ChurchTenantResilientReads.eventTemplates(churchId);
      case TenantModuleKeys.visitantes:
        return () => ChurchTenantResilientReads.visitantes(churchId);
      case TenantModuleKeys.cargos:
        return () => ChurchTenantResilientReads.cargos(churchId);
      case TenantModuleKeys.fornecedores:
        return () => ChurchTenantResilientReads.fornecedores(
              churchId,
              limit: limit,
            );
      default:
        return null;
    }
  }
}
