import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de `igrejas/{churchId}/cargos`.
class ChurchCargosLoadResult {
  const ChurchCargosLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collectionPath,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collectionPath;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica Cargos — `igrejas/{churchId}/cargos` (plain-first Web).
abstract final class ChurchCargosLoadService {
  ChurchCargosLoadService._();

  static const int kLimit = YahwehPerformanceV4.defaultPageSize;
  static const int kFullLimit = 120;

  static const List<String> _legacySubcollections = ['roles'];

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String cacheKey(String churchId) =>
      '${churchId.trim()}_cargos_$kLimit';

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

  static String _cargoSortKey(Map<String, dynamic> data) =>
      (data['name'] ?? data['nome'] ?? '').toString().trim().toLowerCase();

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final oa = (da['order'] as num?)?.toInt() ?? 999;
      final ob = (db['order'] as num?)?.toInt() ?? 999;
      if (oa != ob) return oa.compareTo(ob);
      final ha = (da['hierarchyLevel'] as num?)?.toInt() ?? 999;
      final hb = (db['hierarchyLevel'] as num?)?.toInt() ?? 999;
      if (ha != hb) return ha.compareTo(hb);
      return _cargoSortKey(da).compareTo(_cargoSortKey(db));
    });
    return sorted;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRamAny(
    String seedTenantId,
  ) {
    final churchId = ChurchRepository.churchId(seedTenantId);
    if (churchId.isEmpty) return null;
    final hit = peekRam(churchId);
    if (hit != null && hit.isNotEmpty) return hit;
    final prefix = '${churchId.trim()}_cargos_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> primary,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> legacy,
  ) {
    if (legacy.isEmpty) return primary;
    if (primary.isEmpty) return legacy;
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in legacy) {
      byId[d.id] = d;
    }
    for (final d in primary) {
      byId[d.id] = d;
    }
    return byId.values.toList(growable: false);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreFull(
    String churchId, {
    bool forceServer = false,
    int limit = kFullLimit,
  }) async {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return const [];

    final key = cacheKey(id);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readCol(
      CollectionReference<Map<String, dynamic>> ref,
      String suffix,
    ) async {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      return ChurchModuleFirestoreListRead.queryPlainFirst(
        reference: ref,
        cacheKey: '${key}_$suffix',
        limit: limit,
        forceServer: forceServer,
        orderByField: 'order',
        orderDescending: false,
        sortDocs: _sortDocs,
      );
    }

    var docs = await readCol(ChurchUiCollections.cargos(id), 'primary');
    if (docs.isEmpty) {
      for (final sub in _legacySubcollections) {
        final legacyRef = ChurchUiCollections.churchDoc(id).collection(sub);
        if (legacyRef.path == ChurchUiCollections.cargos(id).path) continue;
        final legacy = await readCol(legacyRef, 'legacy_$sub');
        docs = _sortDocs(_mergeDocs(docs, legacy));
        if (docs.isNotEmpty) break;
      }
    }
    return docs;
  }

  static Future<ChurchCargosLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchCargosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'cargos',
        softError: 'Igreja não identificada.',
      );
    }

    final path = FirebasePaths.cargos(churchId);

    if (!forceRefresh && !forceServer) {
      final ram = peekRam(churchId);
      if (ram != null && ram.isNotEmpty) {
        unawaited(_refreshInBackground(churchId));
        return ChurchCargosLoadResult(
          churchId: churchId,
          docs: ram,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey(churchId));
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortDocs(mem.docs);
        putRam(churchId, docs);
        unawaited(_refreshInBackground(churchId));
        return ChurchCargosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.cargos,
        ).timeout(const Duration(seconds: 2));
        final docs = _sortDocs(TenantModuleHiveCache.toQueryDocuments(hive));
        if (docs.isNotEmpty) {
          putRam(churchId, docs);
          unawaited(_refreshInBackground(churchId));
          return ChurchCargosLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'hive',
            collectionPath: path,
          );
        }
      } catch (_) {}

      try {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
        }
        final cacheSnap = await ChurchUiCollections.cargos(churchId)
            .limit(kLimit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheSnap.docs.isNotEmpty) {
          final docs = _sortDocs(cacheSnap.docs);
          putRam(churchId, docs);
          unawaited(_refreshInBackground(churchId));
          return ChurchCargosLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'firestore_cache',
            collectionPath: path,
          );
        }
      } catch (_) {}
    }

    Object? lastError;
    final queryLimit =
        forceServer || forceRefresh ? kFullLimit : kLimit;
    try {
      final docs = await _loadFirestoreFull(
        churchId,
        forceServer: forceServer,
        limit: queryLimit,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (docs.isNotEmpty) {
        putRam(churchId, docs);
        unawaited(persistAfterLoad(
          ChurchCargosLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: forceServer ? 'server' : 'firestore_full',
            collectionPath: path,
          ),
        ));
      }
      if (!forceRefresh && !forceServer && queryLimit == kLimit) {
        unawaited(_refreshInBackground(churchId));
      }
      return ChurchCargosLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'cargos',
        moduleLabel: 'Cargos',
        limit: kLimit,
        cacheKey: cacheKey(churchId),
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      if (snap.docs.isNotEmpty) {
        final docs = _sortDocs(snap.docs);
        putRam(churchId, docs);
        unawaited(persistAfterLoad(
          ChurchCargosLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'direct_list',
            collectionPath: path,
          ),
        ));
        return ChurchCargosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.cargos.listCacheFirst(
        churchIdHint: churchId,
        limit: kLimit,
        firestoreCacheKey: cacheKey(churchId),
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        final docs = _sortDocs(repo.items);
        if (docs.isNotEmpty) putRam(churchId, docs);
        return ChurchCargosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey(churchId));
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchCargosLoadResult(
        churchId: churchId,
        docs: _sortDocs(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchCargosLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar cargos.'
          : lastError?.toString(),
    );
  }

  static Future<void> _refreshInBackground(String churchId) async {
    try {
      final docs = await _loadFirestoreFull(
        churchId,
        limit: kFullLimit,
      );
      if (docs.isEmpty) return;
      putRam(churchId, docs);
      await persistAfterLoad(
        ChurchCargosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'background_refresh',
          collectionPath: FirebasePaths.cargos(churchId),
        ),
      );
    } catch (_) {}
  }

  static Future<void> persistAfterLoad(ChurchCargosLoadResult result) async {
    if (result.docs.isEmpty) return;
    putRam(result.churchId, result.docs);
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        result.churchId,
        TenantModuleKeys.cargos,
        result.snapshot,
      );
    } catch (_) {}
  }

  static void invalidateRam(String churchId) {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return;
    _ram.remove(cacheKey(id));
    _ram.removeWhere((k, _) => k.startsWith('${id.trim()}_cargos_'));
  }

  static Future<void> _prepareWrite() async {
    if (!kIsWeb) return;
    await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
  }

  static String _tenantFromRef(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length >= 2 && parts[0] == 'igrejas') return parts[1];
    return '';
  }

  static Future<void> refreshRamFromCache(String churchId) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    if (cid.isEmpty) return;
    try {
      final snap = await ChurchUiCollections.cargos(cid)
          .limit(kLimit)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));
      if (snap.docs.isEmpty) return;
      putRam(cid, _sortDocs(snap.docs));
    } catch (_) {}
  }

  /// Gravação optimista — `igrejas/{churchId}/cargos/{docId}` (igual Visitantes).
  static Future<void> createCargo({
    required String churchId,
    required String docId,
    required Map<String, dynamic> payload,
  }) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    if (cid.isEmpty) throw StateError('Igreja não identificada.');
    final id = docId.trim();
    if (id.isEmpty) throw StateError('Chave do cargo inválida.');
    final ref = ChurchUiCollections.cargos(cid).doc(id);
    await _prepareWrite();
    try {
      final existing = await ref
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (existing.exists) {
        throw StateError('Já existe um cargo com a chave «$id».');
      }
    } on StateError {
      rethrow;
    } on TimeoutException {
      // Rede lenta — gravação optimista segue; servidor rejeita duplicata se existir.
    } catch (_) {}
    await OptimisticFirestoreWrite.set(
      ref: ref,
      data: payload,
      module: OfflineModules.cargos,
      tenantId: cid,
    );
    invalidateRam(cid);
    unawaited(refreshRamFromCache(cid));
  }

  static Future<void> updateCargo({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> payload,
  }) async {
    final cid = _tenantFromRef(ref);
    await _prepareWrite();
    await OptimisticFirestoreWrite.update(
      ref: ref,
      data: payload,
      module: OfflineModules.cargos,
      tenantId: cid.isNotEmpty ? cid : null,
    );
    if (cid.isNotEmpty) {
      invalidateRam(cid);
      unawaited(refreshRamFromCache(cid));
    }
  }

  static Future<void> deleteCargo(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final cid = _tenantFromRef(ref);
    await _prepareWrite();
    await OptimisticFirestoreWrite.delete(
      ref: ref,
      module: OfflineModules.cargos,
      tenantId: cid.isNotEmpty ? cid : null,
    );
    if (cid.isNotEmpty) invalidateRam(cid);
  }
}
