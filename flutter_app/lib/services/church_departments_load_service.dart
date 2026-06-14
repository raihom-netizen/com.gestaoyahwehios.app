import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de `igrejas/{churchId}/departamentos`.
class ChurchDepartmentsLoadResult {
  const ChurchDepartmentsLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica Departamentos — `igrejas/{churchId}/departamentos` (plain-first Web).
abstract final class ChurchDepartmentsLoadService {
  ChurchDepartmentsLoadService._();

  static const int kLimit = 120;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String cacheKey(String churchId) =>
      '${churchId.trim()}_departamentos_$kLimit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String churchId,
  ) {
    final key = churchId.trim();
    if (key.isEmpty) return null;
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void putRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = churchId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsFromHive(
    List<Map<String, dynamic>> rows,
  ) {
    return TenantModuleHiveCache.toQueryDocuments(rows);
  }

  static int _sortByDisplayName(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) =>
      churchDepartmentNameFromDoc(a)
          .toLowerCase()
          .compareTo(churchDepartmentNameFromDoc(b).toLowerCase());

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreFull(
    String churchId, {
    bool forceServer = false,
  }) async {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return const [];

    final key = cacheKey(id);

    final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.departamentos(id),
      cacheKey: key,
      limit: kLimit,
      forceServer: forceServer,
      sortDocs: (list) {
        final sorted =
            List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(list)
              ..sort(_sortByDisplayName);
        return sorted;
      },
    );
    return docs;
  }

  static Future<ChurchDepartmentsLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchDepartmentsLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    if (!forceRefresh && !forceServer) {
      final ram = peekRam(churchId);
      if (ram != null && ram.isNotEmpty) {
        unawaited(_refreshInBackground(churchId));
        return ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: ram,
          readSource: 'ram',
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey(churchId));
      if (mem != null && mem.docs.isNotEmpty) {
        putRam(churchId, mem.docs);
        unawaited(_refreshInBackground(churchId));
        return ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: mem.docs,
          readSource: 'firestore_mem',
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          TenantModuleKeys.departamentos,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(
            churchId,
            TenantModuleKeys.departamentos,
          );
          final docs = _docsFromHive(hive);
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            putRam(churchId, docs);
            unawaited(_refreshInBackground(churchId));
            return ChurchDepartmentsLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestoreFull(
        churchId,
        forceServer: forceServer,
      );
      if (docs.isNotEmpty) {
        putRam(churchId, docs);
        return ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: forceServer ? 'server' : 'firestore_full',
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'departamentos',
        moduleLabel: 'Departamentos',
        limit: kLimit,
        cacheKey: cacheKey(churchId),
      );
      if (snap.docs.isNotEmpty) {
        putRam(churchId, snap.docs);
        return ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: snap.docs,
          readSource: 'direct_list',
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.departamentos.listCacheFirst(
        churchIdHint: churchId,
        limit: kLimit,
        firestoreCacheKey: cacheKey(churchId),
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          repo.items,
        )..sort(_sortByDisplayName);
        if (docs.isNotEmpty) putRam(churchId, docs);
        return ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey(churchId));
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchDepartmentsLoadResult(
        churchId: churchId,
        docs: mem.docs,
        readSource: 'fallback_mem',
        softError: lastError?.toString(),
      );
    }

    return ChurchDepartmentsLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar departamentos.'
          : lastError?.toString(),
    );
  }

  static Future<void> _refreshInBackground(String churchId) async {
    try {
      final docs = await _loadFirestoreFull(churchId);
      if (docs.isEmpty) return;
      putRam(churchId, docs);
      await persistAfterLoad(
        ChurchDepartmentsLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'background_refresh',
        ),
      );
    } catch (_) {}
  }

  static Future<void> persistAfterLoad(ChurchDepartmentsLoadResult result) async {
    if (result.docs.isEmpty) return;
    putRam(result.churchId, result.docs);
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        result.churchId,
        TenantModuleKeys.departamentos,
        result.snapshot,
      );
    } catch (_) {}
  }

  static void invalidateRam(String churchId) {
    final id = churchId.trim();
    if (id.isEmpty) return;
    _ram.remove(id);
  }
}
