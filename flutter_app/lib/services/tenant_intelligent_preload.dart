import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';

/// Pré-carregamento inteligente — após login/dashboard, aquece Hive + Firestore cache.
abstract final class TenantIntelligentPreload {
  TenantIntelligentPreload._();

  static String? _lastTenant;
  static bool _running = false;

  /// Chamar após dashboard visível (não bloqueia UI).
  static void scheduleAfterDashboard(String tenantIdRaw) {
    final tid = tenantIdRaw.trim();
    if (tid.isEmpty) return;
    if (_lastTenant == tid && _running) return;
    _lastTenant = tid;
    unawaited(_run(tid));
    unawaited(
      ChurchTenantOfflineWarmupService.instance.scheduleWarmupAfterLogin(tid),
    );
  }

  static Future<void> _run(String tenantId) async {
    if (_running) return;
    _running = true;
    try {
      await FirebaseBootstrap.ensureInitialized();
      final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
      if (uid.isEmpty) return;

      Future<void> safe(String label, Future<void> Function() fn) async {
        try {
          await fn();
        } catch (e, st) {
          if (kDebugMode) debugPrint('Preload[$label] $e\n$st');
        }
      }

      await safe('dashboard', () async {
        await ChurchTenantDashboardDocService.readOnce(tenantId);
      });

      await safe('membros', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.membros,
          networkFetch: () =>
              ChurchTenantResilientReads.membrosRecent(tenantId, limit: 80),
        );
      });

      await safe('avisos', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.avisos,
          networkFetch: () =>
              ChurchTenantResilientReads.avisosFeed(tenantId, limit: 30),
        );
      });

      await safe('eventos', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.eventos,
          networkFetch: () =>
              ChurchTenantResilientReads.noticiasByStartAt(tenantId, limit: 30),
        );
      });

      await safe('agenda', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.agenda,
          networkFetch: () =>
              ChurchTenantResilientReads.eventTemplates(tenantId),
        );
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.agenda,
          networkFetch: () =>
              ChurchTenantResilientReads.escalasRecent(tenantId, limit: 40),
        );
      });

      await safe('chat', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.chat,
          networkFetch: () async {
            return firebaseDefaultFirestore
                .collection('igrejas')
                .doc(tenantId)
                .collection('chats')
                .where('participantUids', arrayContains: uid)
                .orderBy('lastMessageAt', descending: true)
                .limit(30)
                .get();
          },
        );
      });

      await safe('patrimonio', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.patrimonio,
          networkFetch: () =>
              ChurchTenantResilientReads.patrimonio(tenantId, limit: 80),
        );
      });

      await safe('financeiro', () async {
        await TenantStaleWhileRevalidate.warmModule(
          tenantId: tenantId,
          module: TenantModuleKeys.financeiro,
          networkFetch: () =>
              ChurchTenantResilientReads.financeRecent(tenantId, limit: 80),
        );
      });
    } finally {
      _running = false;
    }
  }
}
