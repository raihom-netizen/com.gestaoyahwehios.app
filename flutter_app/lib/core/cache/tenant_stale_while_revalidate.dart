import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Stale-while-revalidate — mostra Hive / cache Firestore instantaneamente, atualiza em background.
abstract final class TenantStaleWhileRevalidate {
  TenantStaleWhileRevalidate._();

  static void _traceReadSource({
    required String tenantId,
    required String module,
    required String readSource,
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    ChurchOperationalFirestoreTrace.record(
      origin: 'TenantSWR:$module',
      firestorePath: 'igrejas/$tid/*',
      churchId: tid,
      readSource: readSource,
    );
  }

  static Duration _networkAttemptTimeout(int attempt) {
    return ChurchPanelReadTimeouts.attempt + Duration(seconds: attempt * 4);
  }

  static Future<void> _persistSnapshot(
    String tenantId,
    String module,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    if (snap.docs.isEmpty) {
      await TenantModuleHiveCache.clearModule(tid, module);
      return;
    }
    await TenantModuleHiveCache.saveFromQuerySnapshot(tid, module, snap);
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
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? hiveDocs;
    if (tid.isNotEmpty) {
      final cachedRows = await TenantModuleHiveCache.readDocs(tid, module);
      if (cachedRows.isNotEmpty) {
        hiveDocs = TenantModuleHiveCache.toQueryDocuments(cachedRows);
      }
    }

    final memKey = firestoreCacheKey?.trim() ?? '';
    QuerySnapshot<Map<String, dynamic>>? memSnap;
    if (memKey.isNotEmpty) {
      memSnap = FirestoreReadResilience.peekLastGoodQuery(memKey);
    }

    // Web: prioriza produção (server-first) e usa cache apenas como fallback.
    if (kIsWeb && !WebPanelStability.isSessionExpired) {
      try {
        final fresh = await networkFetch().timeout(ChurchPanelReadTimeouts.attempt);
        await _persistSnapshot(tid, module, fresh);
        _traceReadSource(
          tenantId: tid,
          module: module,
          readSource: 'server_first',
        );
        return fresh;
      } catch (_) {}
      if (hiveDocs != null && hiveDocs.isNotEmpty) {
        if (refreshInBackground) {
          unawaited(_refresh(tid, module, networkFetch));
        }
        _traceReadSource(
          tenantId: tid,
          module: module,
          readSource: 'hive_fallback',
        );
        return MergedFirestoreQuerySnapshot(hiveDocs);
      }
      if (memSnap != null && memSnap.docs.isNotEmpty) {
        if (refreshInBackground) {
          unawaited(_refresh(tid, module, networkFetch));
        }
        _traceReadSource(
          tenantId: tid,
          module: module,
          readSource: 'memory_fallback',
        );
        return memSnap;
      }
    }

    // Mobile: mantém cache-first instantâneo.
    if (hiveDocs != null && hiveDocs.isNotEmpty) {
      if (refreshInBackground) {
        unawaited(_refresh(tid, module, networkFetch));
      }
      _traceReadSource(
        tenantId: tid,
        module: module,
        readSource: 'hive_cache',
      );
      return MergedFirestoreQuerySnapshot(hiveDocs);
    }

    if (memSnap != null && memSnap.docs.isNotEmpty) {
      if (refreshInBackground) {
        unawaited(_refresh(tid, module, networkFetch));
      }
      _traceReadSource(
        tenantId: tid,
        module: module,
        readSource: 'memory_cache',
      );
      return memSnap;
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
        await _persistSnapshot(tid, module, snap);
        _traceReadSource(
          tenantId: tid,
          module: module,
          readSource: attempt == 0 ? 'server' : 'server_retry_$attempt',
        );
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
            _traceReadSource(
              tenantId: tid,
              module: module,
              readSource: 'memory_fallback_after_error',
            );
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
      await _persistSnapshot(tenantId, module, snap);
      _traceReadSource(
        tenantId: tenantId,
        module: module,
        readSource: 'background_refresh',
      );
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
      await _persistSnapshot(tid, module, snap);
      _traceReadSource(
        tenantId: tid,
        module: module,
        readSource: 'fresh_network',
      );
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
      await _persistSnapshot(tenantId, module, snap);
      _traceReadSource(
        tenantId: tenantId,
        module: module,
        readSource: 'warm_network',
      );
    } catch (_) {}
  }
}
