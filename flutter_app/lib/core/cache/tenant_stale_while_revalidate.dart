import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Stale-while-revalidate — mostra Hive instantaneamente, atualiza em background.
abstract final class TenantStaleWhileRevalidate {
  TenantStaleWhileRevalidate._();

  /// Retorna cache Hive imediato (se existir) e dispara [networkFetch] em background.
  static Future<QuerySnapshot<Map<String, dynamic>>> loadQuery({
    required String tenantId,
    required String module,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
    bool refreshInBackground = true,
  }) async {
    final tid = tenantId.trim();
    if (tid.isNotEmpty) {
      final cachedRows = await TenantModuleHiveCache.readDocs(tid, module);
      if (cachedRows.isNotEmpty) {
        final docs = TenantModuleHiveCache.toQueryDocuments(cachedRows);
        if (refreshInBackground) {
          unawaited(_refresh(tid, module, networkFetch));
        }
        return MergedFirestoreQuerySnapshot(docs);
      }
    }
    final snap = await networkFetch().timeout(
      const Duration(seconds: 20),
      onTimeout: () => const MergedFirestoreQuerySnapshot([]),
    );
    if (tid.isNotEmpty && snap.docs.isNotEmpty) {
      unawaited(TenantModuleHiveCache.saveFromQuerySnapshot(tid, module, snap));
    }
    return snap;
  }

  static Future<void> _refresh(
    String tenantId,
    String module,
    Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
  ) async {
    try {
      final snap = await networkFetch();
      if (snap.docs.isNotEmpty) {
        await TenantModuleHiveCache.saveFromQuerySnapshot(
          tenantId,
          module,
          snap,
        );
      }
    } catch (_) {}
  }

  /// Pré-aquece módulo (login / dashboard) — grava Hive sem bloquear UI.
  static Future<void> warmModule({
    required String tenantId,
    required String module,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
  }) async {
    try {
      final snap = await networkFetch();
      if (snap.docs.isNotEmpty) {
        await TenantModuleHiveCache.saveFromQuerySnapshot(
          tenantId,
          module,
          snap,
        );
      }
    } catch (_) {}
  }
}
