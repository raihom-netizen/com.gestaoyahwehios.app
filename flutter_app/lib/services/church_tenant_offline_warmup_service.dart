import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_firestore_collection_migration_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
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

  Future<void> _runWarmup(String tenantIdRaw, {bool light = false}) async {
    if (_warmupRunning) return;
    _warmupRunning = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
      await FirestoreWebGuard.ensurePanelReadReady();

      String tenantId = tenantIdRaw;
      try {
        final uid = firebaseDefaultAuth.currentUser?.uid;
        final r = await TenantResolverService.resolveOperationalChurchDocId(
          tenantIdRaw,
          userUid: uid,
        );
        if (r.trim().isNotEmpty) tenantId = r.trim();
      } catch (_) {}

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

      final membrosLimit = light ? 24 : 80;
      final avisosLimit = light ? 20 : 50;
      final eventosLimit = light ? 20 : 60;

      final tasks = <Future<void>>[
        safe('igreja_doc', () => ChurchTenantResilientReads.churchDocument(tenantId)),
        safe('panel_cache', () => ChurchTenantResilientReads.panelCacheSummary(tenantId)),
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
          safe('members_legacy', () async {
            await FirebaseFirestore.instance
                .collection('igrejas')
                .doc(tenantId)
                .collection('members')
                .limit(120)
                .get();
          }),
        ]);
      }

      await Future.wait(tasks);
    } finally {
      _warmupRunning = false;
    }
  }
}
