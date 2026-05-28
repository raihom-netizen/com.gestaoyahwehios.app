import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('_performance_cache')
        .doc(docId);
  }

  /// Feed público pré-montado (`generatePublicFeedCache` — a cada 10 min).
  static Future<List<Map<String, dynamic>>> readPublicFeedOnce(
    String tenantId,
  ) async {
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
    return _ref(tenantId, 'public_feed').snapshots().map((snap) {
      final data = snap.data()?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
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
      final doc = await _ref(tid, 'public_feed').get();
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp && _isFresh(u)) return;
    } catch (_) {}
    await warmPublicFeedCacheFromCallable(tid);
  }
}
