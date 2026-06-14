import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga financeira — `igrejas/{churchId}/finance` e `contas`.
class ChurchFinanceLoadResult {
  const ChurchFinanceLoadResult({
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

/// Carga canónica — Firestore `igrejas/{id}/finance`, Storage comprovantes em `financeiro/YYYY_MM/`.
///
/// **Regra:** lista vazia = sucesso (igreja sem lançamentos). Cache RAM / Hive / memória
/// aceite mesmo com 0 documentos.
abstract final class ChurchFinanceLoadService {
  ChurchFinanceLoadService._();

  static const String kHiveContas = 'finance_contas';
  static const int kDefaultLancamentosLimit = 250;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramLancamentos = {};

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramContas = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String cacheKeyLancamentos(String churchId, int limit) =>
      '${churchId.trim()}_finance_$limit';

  static String cacheKeyContas(String churchId) =>
      '${churchId.trim()}_finance_contas';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekLancamentosRam(
    String seedTenantId, {
    int limit = kDefaultLancamentosLimit,
  }) =>
      _peekRam(_ramLancamentos, cacheKeyLancamentos(_resolve(seedTenantId), limit));

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekContasRam(
    String seedTenantId,
  ) =>
      _peekRam(_ramContas, cacheKeyContas(_resolve(seedTenantId)));

  static String resolveChurchId(String hint) => _resolve(hint);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRam(
    Map<String, ({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, DateTime at})> map,
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

  static void _putRam(
    Map<String, ({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, DateTime at})> map,
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    map[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static DateTime? _financeCreatedAt(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['date'] ?? data['data'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortFinanceDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _financeCreatedAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _financeCreatedAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  static Future<ChurchFinanceLoadResult> loadLancamentos({
    required String seedTenantId,
    int limit = kDefaultLancamentosLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        hiveModule: TenantModuleKeys.financeiro,
        cacheKeyFn: cacheKeyLancamentos,
        ramMap: _ramLancamentos,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'finance',
        firestorePath: (id) => 'igrejas/$id/finance',
        col: (id) => ChurchUiCollections.financeiro(id),
        orderedQuery: (col, capped) =>
            col.orderBy('createdAt', descending: true).limit(capped),
        plainQuery: (col, capped) => col.limit(capped),
        sortDocs: _sortFinanceDocs,
        orderByField: 'createdAt',
        orderDescending: true,
      );

  static Future<ChurchFinanceLoadResult> loadContas({
    required String seedTenantId,
    int limit = 80,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        hiveModule: kHiveContas,
        cacheKeyFn: (_, __) => cacheKeyContas(_resolve(seedTenantId)),
        ramMap: _ramContas,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'contas',
        firestorePath: (id) => 'igrejas/$id/contas',
        col: (id) => ChurchUiCollections.churchDoc(id).collection('contas'),
        orderedQuery: (col, capped) => col.orderBy('nome').limit(capped),
        plainQuery: (col, capped) => col.limit(capped),
        orderByField: 'nome',
        orderDescending: false,
      );

  static Future<ChurchFinanceLoadResult> _load({
    required String seedTenantId,
    required String hiveModule,
    required String Function(String churchId, int limit) cacheKeyFn,
    required Map<
        String,
        ({
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
          DateTime at,
        })> ramMap,
    required int limit,
    required bool forceRefresh,
    required bool forceServer,
    required String collectionLabel,
    required String Function(String churchId) firestorePath,
    required CollectionReference<Map<String, dynamic>> Function(String id) col,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> c,
      int capped,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> c,
      int capped,
    ) plainQuery,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
    String orderByField = 'createdAt',
    bool orderDescending = true,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return ChurchFinanceLoadResult(
        churchId: '',
        docs: const [],
        readSource: 'empty_id',
        collectionPath: collectionLabel,
        softError: 'Igreja não identificada.',
      );
    }

    final capped = FirebasePerformanceLimits.capListLimit(collectionLabel, limit);
    final ramKey = cacheKeyFn(churchId, capped);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramMap, ramKey);
      if (ramHit != null) {
        unawaited(_refreshInBackground(
          churchId: churchId,
          hiveModule: hiveModule,
          ramKey: ramKey,
          ramMap: ramMap,
          limit: capped,
          col: col,
          orderedQuery: orderedQuery,
          plainQuery: plainQuery,
          sortDocs: sortDocs,
          orderByField: orderByField,
          orderDescending: orderDescending,
        ));
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: firestorePath(churchId),
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = sortDocs != null ? sortDocs(mem.docs) : mem.docs;
        _putRam(ramMap, ramKey, docs);
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: firestorePath(churchId),
          fromCache: true,
        );
      }

      try {
        final hiveHit = await _readHiveSnapshot(
          churchId: churchId,
          hiveModule: hiveModule,
        );
        if (hiveHit != null) {
          var docs = hiveHit.docs;
          if (sortDocs != null) docs = sortDocs(docs);
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramMap, ramKey, docs);
            if (hiveHit.migratedFromLegacy) {
              unawaited(_persistHive(churchId, hiveModule, docs));
            }
            unawaited(_refreshInBackground(
              churchId: churchId,
              hiveModule: hiveModule,
              ramKey: ramKey,
              ramMap: ramMap,
              limit: capped,
              col: col,
              orderedQuery: orderedQuery,
              plainQuery: plainQuery,
              sortDocs: sortDocs,
              orderByField: orderByField,
              orderDescending: orderDescending,
            ));
            return ChurchFinanceLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: firestorePath(churchId),
              fromCache: true,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        reference: col(churchId),
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: capped,
        orderedQuery: (c) => orderedQuery(c, capped),
        plainQuery: (c) => plainQuery(c, capped),
        sortDocs: sortDocs,
        orderByField: orderByField,
        orderDescending: orderDescending,
      );
      _putRam(ramMap, ramKey, docs);
      unawaited(_persistHive(churchId, hiveModule, docs));
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: firestorePath(churchId),
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        reference: col(churchId),
        cacheKey: '${ramKey}_retry',
        forceServer: true,
        limit: capped,
        orderedQuery: (c) => plainQuery(c, capped),
        plainQuery: (c) => plainQuery(c, capped),
        sortDocs: sortDocs,
        orderByField: orderByField,
        orderDescending: orderDescending,
      );
      _putRam(ramMap, ramKey, docs);
      unawaited(_persistHive(churchId, hiveModule, docs));
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_plain',
        collectionPath: firestorePath(churchId),
      );
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.financeiro.listCacheFirst(
        churchIdHint: churchId,
        limit: capped,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        var docs = repo.items;
        if (sortDocs != null) docs = sortDocs(docs);
        _putRam(ramMap, ramKey, docs);
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: firestorePath(churchId),
          fromCache: repo.error == null && docs.isNotEmpty,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      var docs = mem.docs;
      if (sortDocs != null) docs = sortDocs(docs);
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'fallback_mem',
        collectionPath: firestorePath(churchId),
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = _peekRam(ramMap, ramKey);
    if (ramFallback != null) {
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback',
        collectionPath: firestorePath(churchId),
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchFinanceLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: firestorePath(churchId),
      softError: _humanizeError(lastError),
    );
  }

  static Future<
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        bool migratedFromLegacy,
      })?> _readHiveSnapshot({
    required String churchId,
    required String hiveModule,
  }) async {
    Future<
        ({
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
          bool migratedFromLegacy,
        })?> readModule(String module) async {
      final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
        churchId,
        module,
      ).timeout(const Duration(seconds: 3));
      if (updatedAt == null) return null;
      final hive = await TenantModuleHiveCache.readDocs(churchId, module);
      return (
        docs: TenantModuleHiveCache.toQueryDocuments(hive),
        migratedFromLegacy: false,
      );
    }

    final primary = await readModule(hiveModule);
    if (primary != null) return primary;

    if (hiveModule == TenantModuleKeys.financeiro) {
      final legacy = await readModule(ChurchDataPaths.financeiro);
      if (legacy != null) {
        return (
          docs: legacy.docs,
          migratedFromLegacy: true,
        );
      }
    }
    return null;
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar financeiro. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required String hiveModule,
    required String ramKey,
    required Map<
        String,
        ({
          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
          DateTime at,
        })> ramMap,
    required int limit,
    required CollectionReference<Map<String, dynamic>> Function(String id) col,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> c,
      int capped,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> c,
      int capped,
    ) plainQuery,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
    String orderByField = 'createdAt',
    bool orderDescending = true,
  }) async {
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        reference: col(churchId),
        cacheKey: ramKey,
        forceServer: false,
        limit: limit,
        orderedQuery: (c) => orderedQuery(c, limit),
        plainQuery: (c) => plainQuery(c, limit),
        sortDocs: sortDocs,
        orderByField: orderByField,
        orderDescending: orderDescending,
      );
      _putRam(ramMap, ramKey, docs);
      await _persistHive(churchId, hiveModule, docs);
    } catch (_) {}
  }

  static Future<void> _persistHive(
    String churchId,
    String hiveModule,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
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
      _loadFirestore({
    required String churchId,
    required CollectionReference<Map<String, dynamic>> reference,
    required String cacheKey,
    required bool forceServer,
    required int limit,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) plainQuery,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
    String orderByField = 'createdAt',
    bool orderDescending = true,
  }) async {
    final capped = FirebasePerformanceLimits.capListLimit('finance', limit);
    final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: reference,
      cacheKey: cacheKey,
      limit: capped,
      forceServer: forceServer,
      orderByField: orderByField,
      orderDescending: orderDescending,
      sortDocs: sortDocs,
    );
    if (docs.isNotEmpty) return docs;

    final legacyRef =
        ChurchUiCollections.churchDoc(churchId).collection('financeiro');
    if (legacyRef.path == reference.path) return docs;
    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: legacyRef,
      cacheKey: '${cacheKey}_legacy_financeiro',
      limit: capped,
      forceServer: forceServer,
      orderByField: 'createdAt',
      orderDescending: true,
      sortDocs: sortDocs,
    );
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ramLancamentos.removeWhere((k, _) => k.startsWith(churchId));
    _ramContas.remove(cacheKeyContas(churchId));
    await TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.financeiro);
    await TenantModuleHiveCache.clearModule(churchId, ChurchDataPaths.financeiro);
    await TenantModuleHiveCache.clearModule(churchId, kHiveContas);
  }
}
