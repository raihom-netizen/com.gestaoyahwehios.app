import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/panel_public_site_snapshot_service.dart';

/// Lê caches gerados pelas Cloud Functions (`_performance_cache`).
///
/// Reduz consultas pesadas no site público e no painel (aniversariantes).
abstract final class ChurchPerformanceCacheService {
  ChurchPerformanceCacheService._();
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static DocumentReference<Map<String, dynamic>> _ref(
    String tenantId,
    String docId,
  ) {
    return         ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_performance_cache')
        .doc(docId);
  }

  /// Feed público pré-montado (`generatePublicFeedCache` — a cada 10 min).
  static Future<List<Map<String, dynamic>>> readPublicFeedOnce(
    String tenantId,
  ) async {
    try {
      final panel = await PanelPublicSiteSnapshotService.readOnce(tenantId);
      if (panel.feedData.isNotEmpty) return panel.feedData;
    } catch (_) {}
    try {
      final snap = await _ref(tenantId, 'public_feed').get();
      final data = snap.data()?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Logo + lista de URLs para pré-carregamento (site público).
  static Future<({String? churchLogoUrl, List<String> prefetchUrls})>
      readPublicFeedMediaMeta(String tenantId) async {
    const empty = (churchLogoUrl: null as String?, prefetchUrls: <String>[]);
    try {
      final panel = await PanelPublicSiteSnapshotService.readOnce(tenantId);
      if (panel.hasData) {
        return (
          churchLogoUrl: panel.churchLogoUrl,
          prefetchUrls: List<String>.from(panel.prefetchUrls),
        );
      }
    } catch (_) {}
    try {
      final snap = await _ref(tenantId, 'public_feed').get();
      final raw = snap.data();
      if (raw == null) return empty;
      final logo = (raw['churchLogoUrl'] ?? '').toString().trim();
      final urls = <String>[];
      final list = raw['prefetchUrls'];
      if (list is List) {
        for (final e in list) {
          final s = (e ?? '').toString().trim();
          if (s.startsWith('http')) urls.add(s);
        }
      }
      return (
        churchLogoUrl: logo.startsWith('http') ? logo : null,
        prefetchUrls: List<String>.from(urls),
      );
    } catch (_) {
      return empty;
    }
  }

  /// Aniversariantes do mês (`generateBirthdayCache` — diário).
  static Future<List<Map<String, dynamic>>> readBirthdaysOnce(
    String tenantId,
  ) async {
    try {
      final snap = await _ref(tenantId, 'birthdays').get();
      final data = snap.data()?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Stream<List<Map<String, dynamic>>> watchPublicFeed(String tenantId) {
    return PanelPublicSiteSnapshotService.watch(tenantId).asyncMap((panel) async {
      if (panel.feedData.isNotEmpty) return panel.feedData;
      try {
        final snap = await _ref(tenantId, 'public_feed').get();
        final data = snap.data()?['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
      return const <Map<String, dynamic>>[];
    });
  }

  static const Duration _publicFeedStaleAfter = Duration(seconds: 90);

  static bool _isFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt.toDate()) < _publicFeedStaleAfter;
  }

  /// Força atualização do cache público no backend (site/painel).
  static Future<void> warmPublicFeedCacheFromCallable(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final callable = _functions.httpsCallable(
        'warmChurchPublicFeedCache',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'tenantId': tid,
      });
    } catch (_) {
      // Não bloquear o fluxo principal de publicação por falha de warmup.
    }
  }

  /// Chama callable só quando o cache público está ausente/velho.
  static Future<void> warmPublicFeedCacheFromCallableIfStale(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final panel = await PanelPublicSiteSnapshotService.readOnce(tid);
      if (panel.updatedAt != null && _isFresh(panel.updatedAt)) return;
    } catch (_) {}
    try {
      final doc = await _ref(tid, 'public_feed').get();
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp && _isFresh(u)) return;
    } catch (_) {}
    await warmPublicFeedCacheFromCallable(tid);
  }
}
