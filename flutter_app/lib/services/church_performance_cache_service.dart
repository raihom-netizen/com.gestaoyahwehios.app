import 'package:cloud_firestore/cloud_firestore.dart';

/// Lê caches gerados pelas Cloud Functions (`_performance_cache`).
///
/// Reduz consultas pesadas no site público e no painel (aniversariantes).
abstract final class ChurchPerformanceCacheService {
  ChurchPerformanceCacheService._();

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
}
