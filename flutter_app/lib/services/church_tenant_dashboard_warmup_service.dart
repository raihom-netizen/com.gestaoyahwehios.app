import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';
import 'package:gestao_yahweh/services/yahweh_media_preload_service.dart';
import 'package:gestao_yahweh/core/progressive_media_resolver.dart';

/// Pré-carrega painel em paralelo (avisos, eventos, aniversariantes, cache servidor).
///
/// Chamado uma vez ao abrir [IgrejaCleanShell] — troca de abas fica instantânea.
abstract final class ChurchTenantDashboardWarmupService {
  ChurchTenantDashboardWarmupService._();

  static String? _lastTenant;
  static bool _done = false;

  static void resetSession() {
    _lastTenant = null;
    _done = false;
  }

  static Future<void> scheduleAfterShellOpen(
    BuildContext context,
    String tenantIdRaw,
  ) async {
    final tid = tenantIdRaw.trim();
    if (tid.isEmpty) return;
    if (!AppConnectivityService.instance.isOnline) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    if (_lastTenant != tid) {
      _lastTenant = tid;
      _done = false;
    }
    if (_done) return;
    _done = true;

    unawaited(_run(context, tid));
  }

  static Future<void> _run(BuildContext context, String tenantIdRaw) async {
    var tenantId = tenantIdRaw;
    try {
      final r = await TenantResolverService
          .resolveEffectiveTenantIdPreferringUserBinding(
        tenantIdRaw,
        userUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (r.trim().isNotEmpty) tenantId = r.trim();
    } catch (_) {}

    // Prioridade: 1) KPIs dashboard  2) caches leves  3) imagens (após texto)
    await PanelDashboardSnapshotService.warmFromCallableIfStale(tenantId);
    await _warmPerformanceCaches(tenantId);

    if (!context.mounted) return;

    final panel = await PanelDashboardSnapshotService.readOnce(tenantId);
    if (!context.mounted) return;
    final urls = <String>[];
    for (final m in panel.birthdaysToday.take(12)) {
      final u = ProgressiveMediaResolver.memberListUrl(m.toMemberDataMap());
      if (u.isNotEmpty) urls.add(u);
    }
    for (final a in panel.homeAvisos.take(6)) {
      final u = a.coverPhotoUrl ?? '';
      if (u.isNotEmpty) urls.add(u);
    }
    await YahwehMediaPreloadService.preloadForScreen(context, urls);
  }

  static Future<void> _warmPerformanceCaches(String tenantId) async {
    final feed = await ChurchPerformanceCacheService.readPublicFeedOnce(tenantId);
    final birthdays =
        await ChurchPerformanceCacheService.readBirthdaysOnce(tenantId);
    await MembersDirectorySnapshotService.warmFromCallableIfStale(tenantId);
    final membersDir =
        await MembersDirectorySnapshotService.readOnce(tenantId);
    final memberMaps = membersDir.entries
        .map((e) => <String, dynamic>{
              'memberDocId': e.memberDocId,
              'displayName': e.displayName,
              if (e.photoUrl != null) 'photoUrl': e.photoUrl,
              if (e.cpfDigits != null) 'cpfDigits': e.cpfDigits,
              if (e.email != null) 'email': e.email,
              if (e.telefone != null) 'telefone': e.telefone,
            })
        .toList();
    await Future.wait([
      YahwehLocalSnapshotStore.saveJsonList(tenantId, 'public_feed', feed),
      YahwehLocalSnapshotStore.saveJsonList(tenantId, 'birthdays', birthdays),
      if (memberMaps.isNotEmpty)
        YahwehLocalSnapshotStore.saveJsonList(
          tenantId,
          'membros_search',
          memberMaps,
        ),
    ]);
  }
}
