import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, preloadNetworkImages, sanitizeImageUrl;

/// Cache `_performance_cache/public_feed` — logo + URLs de mídia já resolvidas no servidor.
abstract final class PublicSiteMediaPrefetchService {
  PublicSiteMediaPrefetchService._();

  static const Duration _staleAfter = Duration(minutes: 12);

  static Future<Map<String, dynamic>?> readPrefetchMeta(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    try {
      final op = await ChurchOperationalPaths.resolveCached(tid.trim());
      final snap = await           ChurchOperationalPaths.churchDoc(op)
          .collection('_performance_cache')
          .doc('public_feed')
          .get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  static bool _isStale(Timestamp? updatedAt) {
    if (updatedAt == null) return true;
    return DateTime.now().difference(updatedAt.toDate()) > _staleAfter;
  }

  /// Sementeia logo no cache RAM e pré-carrega imagens (web/iOS/Android).
  static Future<void> applyAndPreload(
    BuildContext context,
    String tenantId, {
    Map<String, dynamic>? tenantData,
    Map<String, dynamic>? meta,
    List<Map<String, dynamic>>? feedRows,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;

    final data = meta ?? await readPrefetchMeta(tid);
    if (data == null) return;

    final logo = (data['churchLogoUrl'] ?? '').toString().trim();
    if (logo.startsWith('http')) {
      FirebaseStorageService.seedChurchLogoDownloadUrl(
        tid,
        logo,
        tenantData: tenantData,
      );
    }

    final urls = <String>[];
    final seen = <String>{};

    void add(String? raw) {
      final s = sanitizeImageUrl((raw ?? '').toString());
      if (!isValidImageUrl(s) || seen.contains(s)) return;
      seen.add(s);
      urls.add(s);
    }

    final prefetch = data['prefetchUrls'];
    if (prefetch is List) {
      for (final e in prefetch) {
        add(e?.toString());
      }
    }

    final rows = feedRows ??
        (data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : const <Map<String, dynamic>>[]);

    for (final row in rows.take(12)) {
      add((row['feedCoverUrl'] ?? '').toString());
      final photos = row['photoUrls'];
      if (photos is List) {
        for (final p in photos.take(4)) {
          add(p?.toString());
        }
      }
      add((row['videoThumbUrl'] ?? '').toString());
    }

    if (!context.mounted || urls.isEmpty) return;
    await preloadNetworkImages(context, urls, maxItems: 40);
  }

  /// Callable para visitante anónimo (após [PublicSiteMediaAuth]).
  static Future<void> warmFromCallableIfStale(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final meta = await readPrefetchMeta(tid);
      final u = meta?['updatedAt'];
      if (u is Timestamp && !_isStale(u)) return;
    } catch (_) {}

    try {
      await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess();
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'warmPublicSiteFeedCache',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'tenantId': tid,
      });
    } catch (_) {
      await ChurchPerformanceCacheService.warmPublicFeedCacheFromCallableIfStale(
        tid,
      );
    }
  }

  /// Abertura do site: aquece servidor em background + pré-carrega quando há cache.
  static void scheduleOnPublicSiteOpen(
    BuildContext context,
    String tenantId, {
    Map<String, dynamic>? tenantData,
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    unawaited(warmFromCallableIfStale(tid));
    unawaited(() async {
      final meta = await readPrefetchMeta(tid);
      if (!context.mounted) return;
      await applyAndPreload(
        context,
        tid,
        tenantData: tenantData,
        meta: meta,
      );
    }());
  }
}
