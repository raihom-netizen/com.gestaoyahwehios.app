import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';
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
    if (firebaseDefaultAuth.currentUser == null) return;

    if (_lastTenant != tid) {
      _lastTenant = tid;
      _done = false;
    }
    if (_done) return;

    unawaited(_run(context, tid));
  }

  static Future<void> _run(BuildContext context, String tenantIdRaw) async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
    } catch (_) {
      return;
    }
    var tenantId = tenantIdRaw;
    try {
      final r = await TenantResolverService
          .resolveEffectiveTenantIdPreferringUserBinding(
        tenantIdRaw,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      );
      if (r.trim().isNotEmpty) tenantId = r.trim();
    } catch (_) {}

    // 1) Cache Firestore local primeiro (líderes/membros/avisos aparecem já).
    final panel = await PanelDashboardSnapshotService.readOnce(tenantId);
    final membersDir = await MembersDirectorySnapshotService.readOnce(tenantId);
    if (!context.mounted) return;

    unawaited(
      ChurchGalleryPhotoWarmup.warmBytesForPanel(
        tenantId: tenantId,
        panel: panel,
      ),
    );
    if (membersDir.hasEntries && context.mounted) {
      ChurchGalleryPhotoWarmup.scheduleMembersDirectory(
        context: context,
        tenantId: tenantId,
        directory: membersDir,
        maxMembers: 120,
      );
    }

    final prefetch = await PanelMediaPrefetchService.readOnce(tenantId);
    unawaited(
      ChurchGalleryPhotoWarmup.warmBytesFromMediaPrefetch(tenantId, prefetch),
    );

    // Callable em background — não bloqueia fotos do painel/chat.
    unawaited(PanelDashboardSnapshotService.warmFromCallableIfStale(tenantId));
    unawaited(_warmPerformanceCaches(tenantId));
    if (context.mounted) {
      ChurchGalleryPhotoWarmup.schedulePanelHome(
        context: context,
        tenantId: tenantId,
        panel: panel,
        force: true,
      );
    }

    final urls = <String>[];
    for (final m in panel.birthdaysToday.take(16)) {
      final u = ProgressiveMediaResolver.memberListUrl(m.toMemberDataMap());
      if (u.isNotEmpty) urls.add(u);
    }
    for (final a in panel.homeAvisos.take(8)) {
      final u = a.coverPhotoUrl ?? '';
      if (u.isNotEmpty) urls.add(u);
    }
    await YahwehMediaPreloadService.preloadForScreen(
      context,
      urls,
      maxItems: 28,
    );
    _done = true;
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
