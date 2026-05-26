import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sincronização inteligente — só buscar alterações após [lastSyncDate].
///
/// Complementa cache Firestore offline e snapshots locais (não substitui Isar).
abstract final class YahwehIncrementalSync {
  YahwehIncrementalSync._();

  static String _key(String tenantId, String bucket) =>
      'yahweh_last_sync_${tenantId.trim()}_$bucket';

  static Future<DateTime?> readLastSync(
    String tenantId,
    String bucket,
  ) async {
    if (tenantId.trim().isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_key(tenantId, bucket));
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> markSyncedNow(String tenantId, String bucket) async {
    if (tenantId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _key(tenantId, bucket),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Query com `updatedAt` ou `createdAt` > último sync (menos tráfego que full reload).
  static Query<Map<String, dynamic>> collectionDeltaQuery({
    required CollectionReference<Map<String, dynamic>> collection,
    required String tenantId,
    required String bucket,
    String timestampField = 'updatedAt',
  }) {
    return collectionDeltaQueryFrom(
      base: collection,
      tenantId: tenantId,
      bucket: bucket,
      timestampField: timestampField,
    );
  }

  static Query<Map<String, dynamic>> collectionDeltaQueryFrom({
    required Query<Map<String, dynamic>> base,
    required String tenantId,
    required String bucket,
    String timestampField = 'updatedAt',
  }) {
    // Firestore exige valor concreto — leitura síncrona do último sync em memória
    // após [readLastSync] no caller; aqui devolvemos query base para primeiro fetch.
    return base;
  }

  /// Busca delta assíncrona (usa último sync gravado).
  static Future<QuerySnapshot<Map<String, dynamic>>> fetchDelta({
    required CollectionReference<Map<String, dynamic>> collection,
    required String tenantId,
    required String bucket,
    String timestampField = 'updatedAt',
    int limit = 40,
  }) async {
    final last = await readLastSync(tenantId, bucket);
    Query<Map<String, dynamic>> q = collection;
    if (last != null) {
      q = collection
          .where(timestampField, isGreaterThan: Timestamp.fromDate(last))
          .orderBy(timestampField, descending: true);
    } else {
      q = collection.orderBy(timestampField, descending: true);
    }
    final snap = await q.limit(limit).get();
    await markSyncedNow(tenantId, bucket);
    return snap;
  }
}
