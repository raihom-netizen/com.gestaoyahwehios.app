import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Stale-while-revalidate — mostra Hive / cache Firestore instantaneamente, atualiza em background.
abstract final class TenantStaleWhileRevalidate {
  TenantStaleWhileRevalidate._();

  static Duration _networkAttemptTimeout(int attempt) {
    return ChurchPanelReadTimeouts.attempt + Duration(seconds: attempt * 4);
  }

  /// Retorna cache Hive imediato (se existir) e dispara [networkFetch] em background.
  static Future<QuerySnapshot<Map<String, dynamic>>> loadQuery({
    required String tenantId,
    required String module,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
    bool refreshInBackground = true,
    String? firestoreCacheKey,
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

    final memKey = firestoreCacheKey?.trim() ?? '';
    if (memKey.isNotEmpty) {
      final mem = FirestoreReadResilience.peekLastGoodQuery(memKey);
      if (mem != null && mem.docs.isNotEmpty) {
        if (refreshInBackground) {
          unawaited(_refresh(tid, module, networkFetch));
        }
        return mem;
      }
    }

    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (kIsWeb && attempt >= 2 && !WebPanelStability.isSessionExpired) {
          await FirestoreWebGuard.recoverFirestoreWebSession(
            allowHardReconnect: true,
          );
          await Future<void>.delayed(
            Duration(milliseconds: 120 + attempt * 180),
          );
        }
        final snap =
            await networkFetch().timeout(_networkAttemptTimeout(attempt));
        if (tid.isNotEmpty && snap.docs.isNotEmpty) {
          unawaited(
            TenantModuleHiveCache.saveFromQuerySnapshot(tid, module, snap),
          );
        }
        return snap;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (memKey.isNotEmpty) {
          final mem = FirestoreReadResilience.peekLastGoodQuery(memKey);
          if (mem != null && mem.docs.isNotEmpty) {
            if (refreshInBackground) {
              unawaited(_refresh(tid, module, networkFetch));
            }
            return mem;
          }
        }
        if (attempt >= 2) break;
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
    }
    return const MergedFirestoreQuerySnapshot([]);
  }

  static Future<void> _refresh(
    String tenantId,
    String module,
    Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
  ) async {
    try {
      if (kIsWeb) {
        await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: false)
            .timeout(const Duration(seconds: 6))
            .catchError((_) {});
      }
      final snap = await networkFetch().timeout(ChurchPanelReadTimeouts.warmCap);
      if (snap.docs.isNotEmpty) {
        await TenantModuleHiveCache.saveFromQuerySnapshot(
          tenantId,
          module,
          snap,
        );
      }
    } catch (_) {}
  }

  /// Após lançamento financeiro — força próxima leitura na rede (sem Hive obsoleto).
  static Future<void> invalidateModule({
    required String tenantId,
    required String module,
  }) async {
    await TenantModuleHiveCache.clearModule(tenantId, module);
  }

  /// Leitura direta na rede (sem Hive / memória stale) — uso após gravar lançamento.
  static Future<QuerySnapshot<Map<String, dynamic>>> loadQueryFresh({
    required String tenantId,
    required String module,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
  }) async {
    final tid = tenantId.trim();
    if (tid.isNotEmpty) {
      await TenantModuleHiveCache.clearModule(tid, module);
    }
    try {
      final snap = await networkFetch().timeout(ChurchPanelReadTimeouts.queryCap);
      if (tid.isNotEmpty && snap.docs.isNotEmpty) {
        await TenantModuleHiveCache.saveFromQuerySnapshot(tid, module, snap);
      }
      return snap;
    } catch (_) {
      return const MergedFirestoreQuerySnapshot([]);
    }
  }

  /// Pré-aquece módulo (login / dashboard) — grava Hive sem bloquear UI.
  static Future<void> warmModule({
    required String tenantId,
    required String module,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() networkFetch,
  }) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await networkFetch().timeout(ChurchPanelReadTimeouts.warmCap);
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
