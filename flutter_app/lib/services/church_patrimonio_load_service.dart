import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga património — `igrejas/{churchId}/patrimonio`.
class ChurchPatrimonioLoadResult {
  const ChurchPatrimonioLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collectionPath,
    this.softError,
    this.fromCache = false,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collectionPath;
  final String? softError;
  final bool fromCache;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
  bool get hasHardError => softError != null && softError!.trim().isNotEmpty;
}

/// Carga canónica — Firestore `igrejas/{id}/patrimonio`.
///
/// **Regra:** lista vazia = sucesso (igreja sem bens). Cache RAM / Hive aceite mesmo com 0 docs.
abstract final class ChurchPatrimonioLoadService {
  ChurchPatrimonioLoadService._();

  static const int kDefaultListLimit = 20;
  static const int kDefaultAllLimit = 800;
  static const int kDefaultInventarioHistoricoLimit = 120;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};
  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramInventarioHistorico = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String resolveChurchId(String hint) => _resolve(hint);

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_patrimonio_$limit';

  static String inventarioHistoricoCacheKey(String churchId, int limit) =>
      '${churchId.trim()}_patrimonio_inventario_historico_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultListLimit,
  }) =>
      _peekRam(_resolve(seedTenantId), limit);

  /// Qualquer entrada RAM deste tenant (warm loadAll alimenta chaves diferentes de limit 20).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRamAny(
    String seedTenantId,
  ) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    for (final limit in [
      kDefaultAllLimit,
      kDefaultListLimit,
      200,
      80,
      50,
    ]) {
      final hit = _peekRam(churchId, limit);
      if (hit != null && hit.isNotEmpty) return hit;
    }
    final prefix = '${churchId}_patrimonio_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRam(
    String churchId,
    int limit,
  ) {
    if (churchId.isEmpty) return null;
    final key = cacheKey(churchId, limit);
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void _putRam(
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  /// Injeta bem na RAM após save otimista (lista instantânea antes do Firestore).
  static void seedOptimisticDoc({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> data,
  }) {
    final churchId = _resolve(seedTenantId);
    final id = itemId.trim();
    if (churchId.isEmpty || id.isEmpty) return;

    final path = 'igrejas/$churchId/patrimonio/$id';
    final docs = TenantModuleHiveCache.toQueryDocuments([
      {
        'path': path,
        'id': id,
        'data': Map<String, dynamic>.from(data),
      },
    ]);
    if (docs.isEmpty) return;

    final sorted = _sortByNome(_mergeDocIntoList(peekRamAny(churchId), docs.first));
    for (final limit in [
      kDefaultAllLimit,
      kDefaultListLimit,
      200,
      80,
      50,
    ]) {
      _putRam(cacheKey(churchId, limit), sorted);
    }
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDocIntoList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? existing,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var replaced = false;
    for (final d in existing ?? const []) {
      if (d.id == doc.id) {
        out.add(doc);
        replaced = true;
      } else {
        out.add(d);
      }
    }
    if (!replaced) out.add(doc);
    return out;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByNome(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) => (a.data()['nome'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
    return sorted;
  }

  static Future<ChurchPatrimonioLoadResult> load({
    required String seedTenantId,
    int limit = kDefaultListLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _loadInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );

  static Future<ChurchPatrimonioLoadResult> loadAll({
    required String seedTenantId,
    int limit = kDefaultAllLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _loadInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );

  static Future<ChurchPatrimonioLoadResult> loadInventarioHistorico({
    required String seedTenantId,
    int limit = kDefaultInventarioHistoricoLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _loadCollectionInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'patrimonio_inventario_historico',
        collectionPathBuilder: (id) =>
            'igrejas/$id/patrimonio_inventario_historico',
        referenceBuilder: (id) => ChurchUiCollections.patrimonioInventarioHistorico(id),
        cacheKeyBuilder: inventarioHistoricoCacheKey,
        ramMap: _ramInventarioHistorico,
        hiveModule: TenantModuleKeys.patrimonioInventarioHistorico,
        queryOrderBy: 'finalizadoEm',
        sortDocs: _sortByCreatedAtDesc,
      );

  static Future<ChurchPatrimonioLoadResult> _loadInternal({
    required String seedTenantId,
    required int limit,
    required bool forceRefresh,
    required bool forceServer,
  }) =>
      _loadCollectionInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'patrimonio',
        collectionPathBuilder: (id) => 'igrejas/$id/patrimonio',
        referenceBuilder: (id) => ChurchUiCollections.patrimonio(id),
        cacheKeyBuilder: cacheKey,
        ramMap: _ram,
        hiveModule: TenantModuleKeys.patrimonio,
        queryOrderBy: 'nome',
        sortDocs: _sortByNome,
      );

  static Future<ChurchPatrimonioLoadResult> _loadCollectionInternal({
    required String seedTenantId,
    required int limit,
    required bool forceRefresh,
    required bool forceServer,
    required String collectionLabel,
    required String Function(String churchId) collectionPathBuilder,
    required CollectionReference<Map<String, dynamic>> Function(String churchId)
        referenceBuilder,
    required String Function(String churchId, int limit) cacheKeyBuilder,
    required Map<
        String,
        ({
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
          DateTime at,
        })> ramMap,
    required String hiveModule,
    required String queryOrderBy,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) sortDocs,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchPatrimonioLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'patrimonio',
        softError: 'Igreja não identificada.',
      );
    }

    final path = collectionPathBuilder(churchId);
    final ramKey = cacheKeyBuilder(churchId, limit);
    final reference = referenceBuilder(churchId);
    final capped = FirebasePerformanceLimits.capListLimit(collectionLabel, limit);

    if (forceRefresh || forceServer) {
      final prefix = '${churchId}_${collectionLabel}_';
      ramMap.removeWhere((k, _) => k.startsWith(prefix));
      FirestoreReadResilience.forgetKey(ramKey);
      FirestoreReadResilience.forgetKey('${ramKey}_retry');
      if (collectionLabel == 'patrimonio') {
        await TenantModuleHiveCache.clearModule(
          churchId,
          TenantModuleKeys.patrimonio,
        );
      } else if (collectionLabel == 'patrimonio_inventario_historico') {
        await TenantModuleHiveCache.clearModule(
          churchId,
          TenantModuleKeys.patrimonioInventarioHistorico,
        );
      }
    }

    if (!forceRefresh && !forceServer) {
      final anyRam = _peekAnyRam(
        churchId: churchId,
        collectionLabel: collectionLabel,
        ramMap: ramMap,
      );
      if (anyRam != null && anyRam.isNotEmpty) {
        final docs = sortDocs(anyRam);
        _putRamInMap(ramMap, ramKey, docs);
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
          ramMap: ramMap,
          hiveModule: hiveModule,
          collectionLabel: collectionLabel,
          queryOrderBy: queryOrderBy,
          sortDocs: sortDocs,
        ));
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'ram_any',
          collectionPath: path,
          fromCache: true,
        );
      }

      final ramHit = _peekRamInMap(ramMap, cacheKeyBuilder(churchId, limit));
      if (ramHit != null && ramHit.isNotEmpty) {
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
          ramMap: ramMap,
          hiveModule: hiveModule,
          collectionLabel: collectionLabel,
          queryOrderBy: queryOrderBy,
          sortDocs: sortDocs,
        ));
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      } else if (ramHit != null && ramHit.isEmpty) {
        ramMap.remove(ramKey);
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = sortDocs(mem.docs);
        _putRamInMap(ramMap, ramKey, docs);
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
          fromCache: true,
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          hiveModule,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(churchId, hiveModule);
          var docs = sortDocs(TenantModuleHiveCache.toQueryDocuments(hive));
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRamInMap(ramMap, ramKey, docs);
            unawaited(_refreshInBackground(
              churchId: churchId,
              ramKey: ramKey,
              limit: capped,
              reference: reference,
              ramMap: ramMap,
              hiveModule: hiveModule,
              collectionLabel: collectionLabel,
              queryOrderBy: queryOrderBy,
              sortDocs: sortDocs,
            ));
            return ChurchPatrimonioLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: capped,
        collectionLabel: collectionLabel,
        queryOrderBy: queryOrderBy,
        sortDocs: sortDocs,
      );
      _putRamInMap(ramMap, ramKey, docs);
      unawaited(_persistHive(churchId, docs, hiveModule: hiveModule));
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: '${ramKey}_retry',
        forceServer: true,
        limit: capped,
        collectionLabel: collectionLabel,
        queryOrderBy: queryOrderBy,
        sortDocs: sortDocs,
      );
      _putRamInMap(ramMap, ramKey, docs);
      unawaited(_persistHive(churchId, docs, hiveModule: hiveModule));
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_plain',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final directDocs = await _loadDirectSubcollection(
        churchId: churchId,
        subcollection: collectionLabel,
        limit: capped,
        cacheKey: '${ramKey}_direct',
        sortDocs: sortDocs,
      );
      if (directDocs.isNotEmpty) {
        _putRamInMap(ramMap, ramKey, directDocs);
        unawaited(_persistHive(churchId, directDocs, hiveModule: hiveModule));
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: directDocs,
          readSource: 'direct_list',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      if (collectionLabel == 'patrimonio') {
        final repo = await ChurchRepository.patrimonio.listCacheFirst(
          churchIdHint: churchId,
          limit: capped,
          firestoreCacheKey: ramKey,
        );
        if (repo.items.isNotEmpty || repo.error == null) {
          var docs = repo.items;
          docs = sortDocs(docs);
          _putRamInMap(ramMap, ramKey, docs);
          return ChurchPatrimonioLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'repository_cache_first',
            collectionPath: path,
            fromCache: repo.error == null && docs.isNotEmpty,
            softError: repo.error,
          );
        }
      }
    } catch (e) {
      lastError = e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: sortDocs(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = _peekAnyRam(
          churchId: churchId,
          collectionLabel: collectionLabel,
          ramMap: ramMap,
        ) ??
        _peekRamInMap(ramMap, cacheKeyBuilder(churchId, limit));
    if (ramFallback != null) {
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchPatrimonioLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: _humanizeError(lastError),
    );
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar patrimônio. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required String ramKey,
    required int limit,
    required CollectionReference<Map<String, dynamic>> reference,
    required Map<
        String,
        ({
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
          DateTime at,
        })> ramMap,
    required String hiveModule,
    required String collectionLabel,
    required String queryOrderBy,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) sortDocs,
  }) async {
    try {
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: ramKey,
        forceServer: false,
        limit: limit,
        collectionLabel: collectionLabel,
        queryOrderBy: queryOrderBy,
        sortDocs: sortDocs,
      );
      _putRamInMap(ramMap, ramKey, docs);
      await _persistHive(churchId, docs, hiveModule: hiveModule);
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadPage({
    required String seedTenantId,
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return const [];

    Future<QuerySnapshot<Map<String, dynamic>>> read() async {
      final cacheKey =
          '${churchId}_patrimonio_page_${startAfter?.id ?? '0'}_$limit';
      Future<QuerySnapshot<Map<String, dynamic>>> plainRead() =>
          FirestoreReadResilience.getQuery(
            ChurchUiCollections.patrimonio(churchId).limit(limit),
            cacheKey: '${cacheKey}_plain',
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );

      if (kIsWeb) {
        final plain = await plainRead();
        if (plain.docs.isNotEmpty) {
          return MergedFirestoreQuerySnapshot(_sortByNome(plain.docs));
        }
      }

      var q = ChurchUiCollections.patrimonio(churchId)
          .orderBy('nome')
          .limit(limit);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      try {
        return await FirestoreReadResilience.getQuery(
          q,
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        final plain = await plainRead();
        return MergedFirestoreQuerySnapshot(_sortByNome(plain.docs));
      }
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        read,
        maxAttempts: 4,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      return snap.docs;
    }

    final snap = await read().timeout(ChurchPanelReadTimeouts.warmCap);
    return snap.docs;
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    {required String hiveModule}
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        hiveModule,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadDirectSubcollection({
    required String churchId,
    required String subcollection,
    required int limit,
    required String cacheKey,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) sortDocs,
  }) async {
    final snap = await IgrejaDirectFirestoreReads.listSubcollection(
      churchId,
      subcollection,
      moduleLabel: 'Patrimônio/$subcollection',
      limit: limit,
      cacheKey: cacheKey,
    ).timeout(ChurchPanelReadTimeouts.queryCap);
    return sortDocs(snap.docs);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required CollectionReference<Map<String, dynamic>> reference,
    required String cacheKey,
    required bool forceServer,
    required int limit,
    required String collectionLabel,
    required String queryOrderBy,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) sortDocs,
  }) =>
      ChurchModuleFirestoreListRead.queryPlainFirst(
        reference: reference,
        cacheKey: cacheKey,
        limit: limit,
        forceServer: forceServer,
        legacyFallbackSubcollections: const ['assets'],
        orderByField: queryOrderBy,
        sortDocs: sortDocs,
      );

  static void _putRamInMap(
    Map<String, ({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, DateTime at})>
        map,
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    map[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRamInMap(
    Map<String, ({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, DateTime at})>
        map,
    String key,
  ) {
    final hit = map[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      map.remove(key);
      return null;
    }
    return hit.docs;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekAnyRam({
    required String churchId,
    required String collectionLabel,
    required Map<String, ({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, DateTime at})>
        ramMap,
  }) {
    if (churchId.isEmpty) return null;
    final prefix = '${churchId}_${collectionLabel}_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in ramMap.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedAtDesc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    DateTime readDate(Map<String, dynamic> data) {
      final raw = data['finalizadoEm'] ??
          data['createdAt'] ??
          data['timestamp'] ??
          data['date'];
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    sorted.sort((a, b) => readDate(b.data()).compareTo(readDate(a.data())));
    return sorted;
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    _ramInventarioHistorico.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.patrimonio,
    );
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.patrimonioInventarioHistorico,
    );
  }
}
