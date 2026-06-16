import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_firestore_collection_migration_service.dart';
import 'package:gestao_yahweh/services/church_panel_module_prefetch_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Pré-carrega leituras frequentes no **cache do Firestore** (mobile/web)
/// após o login — painel, mural, membros, finanças, etc. (padrão Controle Total).
class ChurchTenantOfflineWarmupService {
  ChurchTenantOfflineWarmupService._();
  static final ChurchTenantOfflineWarmupService instance =
      ChurchTenantOfflineWarmupService._();

  String? _sessionTenant;
  bool _warmupDoneThisSession = false;
  bool _heavyWarmupScheduled = false;
  bool _warmupRunning = false;
  final StreamController<bool> _warmupCtrl =
      StreamController<bool>.broadcast();

  bool get isWarmupRunning => _warmupRunning;

  Stream<bool> get warmupRunningStream => _warmupCtrl.stream;

  void resetForNewSession() {
    _sessionTenant = null;
    _warmupDoneThisSession = false;
  }

  /// Ao voltar à app (web/mobile), reaquece coleções críticas sem bloquear UI.
  void scheduleLightRefreshOnResume(String tenantIdRaw) {
    final tid = tenantIdRaw.trim();
    if (tid.isEmpty) return;
    if (!AppConnectivityService.instance.isOnline) return;
    if (firebaseDefaultAuth.currentUser == null) return;
    unawaited(_runWarmup(tid, light: true));
  }

  Future<void> scheduleWarmupAfterLogin(String tenantIdRaw) async {
    final tidIn = tenantIdRaw.trim();
    if (tidIn.isEmpty) return;
    if (!AppConnectivityService.instance.isOnline) return;
    if (firebaseDefaultAuth.currentUser == null) return;

    if (_sessionTenant != tidIn) {
      _sessionTenant = tidIn;
      _warmupDoneThisSession = false;
    }
    if (_warmupDoneThisSession) return;

    _warmupDoneThisSession = true;
    // Web: só leituras leves — heavy dispara INTERNAL ASSERTION + milhares de 404 Storage.
    if (kIsWeb) {
      unawaited(_runWarmup(tidIn, light: true));
      return;
    }
    // 1.º frame: só leituras leves (painel rápido).
    unawaited(_runWarmup(tidIn, light: true));
    if (!_heavyWarmupScheduled) {
      _heavyWarmupScheduled = true;
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (_sessionTenant != tidIn) return;
        unawaited(_runWarmup(tidIn, light: false));
      });
    }
  }

  void _setWarmupRunning(bool running) {
    if (_warmupRunning == running) return;
    _warmupRunning = running;
    if (!_warmupCtrl.isClosed) _warmupCtrl.add(running);
  }

  Future<void> _runWarmup(String tenantIdRaw, {bool light = false}) async {
    if (_warmupRunning) return;
    _setWarmupRunning(true);
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      await FirestoreWebGuard.ensurePanelReadReady();

      final tenantId = ChurchPanelTenant.resolve(tenantIdRaw);
      if (tenantId.isEmpty) return;

      Future<void> safe(String label, Future<void> Function() fn) async {
        try {
          await fn();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('OfflineWarmup[$label] $e\n$st');
          }
        }
      }

      unawaited(
        ChurchFirestoreCollectionMigrationService.ensureTenantMigrated(tenantId),
      );

      final membrosLimit = kIsWeb ? (light ? 8 : 12) : (light ? 24 : 80);
      final avisosLimit = light ? 20 : 50;
      final eventosLimit = light ? 20 : 60;

      final tasks = <Future<void>>[
        safe('igreja_doc', () => ChurchTenantResilientReads.churchDocument(tenantId)),
        safe('panel_cache', () => ChurchTenantResilientReads.panelCacheSummary(tenantId)),
        safe(
          'panel_statistics',
          () => ChurchTenantResilientReads.panelStatisticsSummary(tenantId),
        ),
        safe(
          'panel_public_site',
          () => ChurchTenantResilientReads.panelPublicSiteCache(tenantId),
        ),
        safe(
          'membros',
          () => ChurchTenantResilientReads.membrosRecent(
            tenantId,
            limit: membrosLimit,
          ),
        ),
        safe(
          'avisos',
          () => ChurchTenantResilientReads.avisosFeed(
            tenantId,
            limit: avisosLimit,
          ),
        ),
        safe(
          'noticias',
          () => ChurchTenantResilientReads.noticiasByStartAt(
            tenantId,
            limit: eventosLimit,
          ),
        ),
        safe(
          'event_templates',
          () => ChurchTenantResilientReads.eventTemplates(tenantId),
        ),
      ];

      if (!light) {
        tasks.addAll([
          safe('departamentos', () => ChurchTenantResilientReads.departamentos(tenantId)),
          safe('visitantes', () => ChurchTenantResilientReads.visitantes(tenantId)),
          safe('pedidos_oracao', () => ChurchTenantResilientReads.pedidosOracao(tenantId)),
          safe('event_categories', () => ChurchTenantResilientReads.eventCategories(tenantId)),
          safe('finance', () => ChurchTenantResilientReads.financeRecent(tenantId)),
          safe('contas', () => ChurchTenantResilientReads.contas(tenantId)),
          safe('despesas_fixas', () => ChurchTenantResilientReads.despesasFixas(tenantId)),
          safe('patrimonio', () => ChurchTenantResilientReads.patrimonio(tenantId)),
          safe('fornecedores', () => ChurchTenantResilientReads.fornecedores(tenantId)),
          safe('cargos', () => ChurchTenantResilientReads.cargos(tenantId)),
          safe('escala_templates', () => ChurchTenantResilientReads.escalaTemplates(tenantId)),
          safe('escalas', () => ChurchTenantResilientReads.escalasRecent(tenantId)),
          safe('users_tenant', () async {
            await FirebaseFirestore.instance
                .collection('users')
                .where(Filter.or(
                  Filter('tenantId', isEqualTo: tenantId),
                  Filter('igrejaId', isEqualTo: tenantId),
                ))
                .limit(200)
                .get();
          }),
        ]);
      }

      if (kIsWeb) {
        for (final t in tasks) {
          await t;
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      } else {
        await Future.wait(tasks);
      }
      if (!light) {
        ChurchPanelModulePrefetchService.scheduleFullPrefetch(tenantId);
      }
    } finally {
      _setWarmupRunning(false);
    }
  }
}
