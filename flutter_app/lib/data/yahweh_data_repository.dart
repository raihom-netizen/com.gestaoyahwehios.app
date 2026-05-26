import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:gestao_yahweh/core/firestore_cursor_pagination.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/church_public_feed_service.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_warmup_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';

/// Camada **Repository** — UI não deve falar com Firestore direto em fluxos novos.
///
/// Ordem de leitura (site público / painel):
/// 1. [YahwehLocalSnapshotStore] (disco, instantâneo)
/// 2. [ChurchPerformanceCacheService] (CF `_performance_cache`)
/// 3. Firestore paginado / streams
abstract final class YahwehDataRepository {
  YahwehDataRepository._();
}

/// Feed do site público e mural.
abstract final class YahwehPublicFeedRepository {
  YahwehPublicFeedRepository._();

  static const int pageSize = YahwehPerformanceV4.publicFeedPageSize;

  /// Abertura instantânea: disco → opcional refresh CF em background.
  static Future<List<Map<String, dynamic>>> readInstantFeed(
    String tenantId, {
    bool refreshServerCacheInBackground = true,
  }) async {
    final local = await YahwehLocalSnapshotStore.readJsonList(
      tenantId,
      'public_feed',
    );
    if (local.isNotEmpty) return local;
    final server = await ChurchPerformanceCacheService.readPublicFeedOnce(
      tenantId,
    );
    if (server.isNotEmpty) {
      unawaited(
        YahwehLocalSnapshotStore.saveJsonList(
          tenantId,
          'public_feed',
          server,
        ),
      );
      return server;
    }
    if (refreshServerCacheInBackground) {
      unawaited(_refreshServerFeed(tenantId));
    }
    return const [];
  }

  static Future<void> _refreshServerFeed(String tenantId) async {
    final server = await ChurchPerformanceCacheService.readPublicFeedOnce(
      tenantId,
    );
    if (server.isEmpty) return;
    await YahwehLocalSnapshotStore.saveJsonList(
      tenantId,
      'public_feed',
      server,
    );
  }

  static Stream<List<Map<String, dynamic>>> watchServerFeed(String tenantId) =>
      ChurchPerformanceCacheService.watchPublicFeed(tenantId);

  static Future<FirestoreCursorPage<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchAvisosPage({
    required String tenantId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) =>
      ChurchPublicFeedService.fetchAvisosPage(
        tenantId: tenantId,
        startAfter: startAfter,
      );

  static Future<FirestoreCursorPage<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchUpcomingEventosPage({
    required String tenantId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) =>
      ChurchPublicFeedService.fetchUpcomingEventosPage(
        tenantId: tenantId,
        startAfter: startAfter,
      );
}

/// Painel ADM — KPIs e pré-carregamento paralelo.
abstract final class YahwehPanelRepository {
  YahwehPanelRepository._();

  static Future<PanelDashboardSnapshot> readDashboardOnce(String tenantId) =>
      PanelDashboardSnapshotService.readOnce(tenantId);

  static Future<List<Map<String, dynamic>>> readBirthdaysInstant(
    String tenantId,
  ) async {
    final local = await YahwehLocalSnapshotStore.readJsonList(
      tenantId,
      'birthdays',
    );
    if (local.isNotEmpty) return local;
    return ChurchPerformanceCacheService.readBirthdaysOnce(tenantId);
  }

  /// Equivalente a `Future.wait([dashboard, events, birthdays, posts])` no shell.
  static void scheduleShellWarmup(BuildContext context, String tenantId) {
    ChurchTenantDashboardWarmupService.scheduleAfterShellOpen(
      context,
      tenantId,
    );
  }
}
