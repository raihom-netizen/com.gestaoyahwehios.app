import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/yahweh_incremental_sync.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';

/// Modo instantâneo (offline-first leve) — Hive + SharedPreferences + Firestore offline.
///
/// Fluxo: gravar local → UI imediata → sync em background → Firestore.
abstract final class YahwehOfflineInstant {
  YahwehOfflineInstant._();

  /// Buckets: `avisos`, `eventos`, `chat`, `membros`, `patrimonio`, `financeiro`, `agenda`.
  static Future<List<Map<String, dynamic>>> readFeedLocal(
    String tenantId,
    String bucket,
  ) async {
    final hive = await TenantModuleHiveCache.readDocs(tenantId, bucket);
    if (hive.isNotEmpty) {
      return hive
          .map((r) {
            final data = r['data'];
            if (data is Map) return Map<String, dynamic>.from(data);
            return Map<String, dynamic>.from(r);
          })
          .toList();
    }
    return YahwehLocalSnapshotStore.readJsonList(tenantId, bucket);
  }

  static Future<void> writeFeedLocal(
    String tenantId,
    String bucket,
    List<Map<String, dynamic>> items,
  ) =>
      YahwehLocalSnapshotStore.saveJsonList(tenantId, bucket, items);

  /// Após sync bem-sucedido, marca delta para próxima pull incremental.
  static Future<void> markBucketSynced(String tenantId, String bucket) =>
      YahwehIncrementalSync.markSyncedNow(tenantId, bucket);

  /// Publicação / envio: persiste rascunho local e corre rede depois.
  static Future<void> persistThenSync({
    required String tenantId,
    required String bucket,
    required List<Map<String, dynamic>> optimisticItems,
    required Future<void> Function() networkSync,
  }) async {
    await writeFeedLocal(tenantId, bucket, optimisticItems);
    unawaited(Future<void>(() async {
      try {
        await networkSync();
        await markBucketSynced(tenantId, bucket);
      } catch (_) {}
    }));
  }
}
