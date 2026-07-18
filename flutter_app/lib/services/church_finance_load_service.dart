import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

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
  static const String kHiveFinanceLogs = 'finance_logs';
  static const String kHiveFinanceMpNotifications = 'finance_mp_notifications';
  static const int kDefaultLancamentosLimit = 30;

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
  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramFinanceLogs = {};
  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramFinanceMpNotifications = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String cacheKeyLancamentos(String churchId, int limit) =>
      '${churchId.trim()}_finance_$limit';

  static String cacheKeyContas(String churchId) =>
      '${churchId.trim()}_finance_contas';
  static String cacheKeyFinanceLogs(String churchId, int limit) =>
      '${churchId.trim()}_finance_logs_$limit';
  static String cacheKeyFinanceMpNotifications(String churchId, int limit) =>
      '${churchId.trim()}_finance_mp_notifications_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekLancamentosRam(
    String seedTenantId, {
    int limit = kDefaultLancamentosLimit,
  }) =>
      _peekRam(_ramLancamentos, cacheKeyLancamentos(_resolve(seedTenantId), limit));

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekContasRam(
    String seedTenantId,
  ) =>
      _peekRam(_ramContas, cacheKeyContas(_resolve(seedTenantId)));

  /// Lançamentos já carregados (qualquer limite RAM) — seed instantâneo na UI.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekLancamentosRamAny(
    String seedTenantId,
  ) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    for (final limit in [800, 200, kDefaultLancamentosLimit, 400, 250, 80, 50]) {
      final hit = peekLancamentosRam(churchId, limit: limit);
      if (hit != null && hit.isNotEmpty) return hit;
    }
    final prefix = '${churchId}_finance_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in _ramLancamentos.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  static String resolveChurchId(String hint) => _resolve(hint);

  static String _resolve(String hint) =>
      ChurchPanelTenant.forFirestore(hint.trim());

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
    // Lista vazia não apaga RAM boa (evita sumiço ao voltar ao módulo).
    if (docs.isEmpty) {
      final hit = map[key];
      if (hit != null && hit.docs.isNotEmpty) return;
      return;
    }
    map[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static DateTime? _financeCreatedAt(Map<String, dynamic> data) =>
      financeLancamentoDate(data);

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
        queryLabel: 'finance',
        legacyFallbackSubcollection: 'financeiro',
      );

  /// Página seguinte — cursor Firestore (`startAfterDocument`), sem re-ler do início.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadLancamentosPage({
    required String seedTenantId,
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return const [];

    final capped =
        FirebasePerformanceLimits.capListLimit('finance', limit);
    final cacheKey =
        '${churchId}_finance_page_${startAfter?.id ?? '0'}_$capped';

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainRead(
      CollectionReference<Map<String, dynamic>> ref,
      String suffix,
    ) async {
      final snap = await FirestoreReadResilience.getQuery(
        ref.limit(capped),
        cacheKey: '${cacheKey}_${suffix}_plain',
      );
      var docs = snap.docs;
      if (startAfter != null) {
        final idx = docs.indexWhere((d) => d.id == startAfter.id);
        if (idx >= 0) {
          docs = docs.skip(idx + 1).take(capped).toList();
        }
      }
      return _sortFinanceDocs(docs);
    }

    try {
      var q = ChurchUiCollections.financeiro(churchId)
          .orderBy('createdAt', descending: true)
          .limit(capped);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      final snap = await FirestoreReadResilience.getQuery(
        q,
        cacheKey: cacheKey,
      );
      if (snap.docs.isNotEmpty) return snap.docs;
    } catch (_) {}

    try {
      final legacyRef =
          ChurchUiCollections.churchDoc(churchId).collection('financeiro');
      var q = legacyRef
          .orderBy('createdAt', descending: true)
          .limit(capped);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      final snap = await FirestoreReadResilience.getQuery(
        q,
        cacheKey: '${cacheKey}_legacy',
      );
      if (snap.docs.isNotEmpty) return snap.docs;
    } catch (_) {}

    final primaryPlain =
        await plainRead(ChurchUiCollections.financeiro(churchId), 'finance');
    final legacyPlain = await plainRead(
      ChurchUiCollections.churchDoc(churchId).collection('financeiro'),
      'financeiro',
    );
    return _mergeFinanceDocs(primaryPlain, legacyPlain, _sortFinanceDocs);
  }

  static Future<ChurchFinanceLoadResult> loadContas({
    required String seedTenantId,
    int limit = 80,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        hiveModule: kHiveContas,
        cacheKeyFn: (churchId, limit) => cacheKeyContas(churchId),
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
        queryLabel: 'contas',
      );

  static Future<ChurchFinanceLoadResult> loadFinanceLogs({
    required String seedTenantId,
    int limit = 120,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        hiveModule: kHiveFinanceLogs,
        cacheKeyFn: cacheKeyFinanceLogs,
        ramMap: _ramFinanceLogs,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'finance_logs',
        firestorePath: (id) => 'igrejas/$id/finance_logs',
        col: (id) => ChurchUiCollections.financeLogs(id),
        orderedQuery: (col, capped) =>
            col.orderBy('criadoEm', descending: true).limit(capped),
        plainQuery: (col, capped) => col.limit(capped),
        orderByField: 'criadoEm',
        orderDescending: true,
        queryLabel: 'finance_logs',
      );

  static Future<ChurchFinanceLoadResult> loadFinanceMpNotifications({
    required String seedTenantId,
    int limit = 120,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        hiveModule: kHiveFinanceMpNotifications,
        cacheKeyFn: cacheKeyFinanceMpNotifications,
        ramMap: _ramFinanceMpNotifications,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        collectionLabel: 'finance_mp_notifications',
        firestorePath: (id) => 'igrejas/$id/finance_mp_notifications',
        col: (id) => ChurchUiCollections.financeMpNotifications(id),
        orderedQuery: (col, capped) =>
            col.orderBy('createdAt', descending: true).limit(capped),
        plainQuery: (col, capped) => col.limit(capped),
        orderByField: 'createdAt',
        orderDescending: true,
        queryLabel: 'finance_mp_notifications',
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
    String queryLabel = 'finance',
    String? legacyFallbackSubcollection,
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
        queryLabel: queryLabel,
        legacyFallbackSubcollection: legacyFallbackSubcollection,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      final existingBeforeWrite = _peekRam(ramMap, ramKey);
      if (docs.isEmpty &&
          existingBeforeWrite != null &&
          existingBeforeWrite.isNotEmpty) {
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: existingBeforeWrite,
          readSource: 'ram_preserve_empty_network',
          collectionPath: firestorePath(churchId),
          fromCache: true,
          softError: 'Rede devolveu lista vazia — mantidos dados locais.',
        );
      }
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
        queryLabel: queryLabel,
        legacyFallbackSubcollection: legacyFallbackSubcollection,
      );
      final existingBeforeWrite = _peekRam(ramMap, ramKey);
      if (docs.isEmpty &&
          existingBeforeWrite != null &&
          existingBeforeWrite.isNotEmpty) {
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: existingBeforeWrite,
          readSource: 'ram_preserve_empty_retry',
          collectionPath: firestorePath(churchId),
          fromCache: true,
          softError: 'Rede devolveu lista vazia — mantidos dados locais.',
        );
      }
      _putRam(ramMap, ramKey, docs);
      unawaited(_persistHive(churchId, hiveModule, docs));
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_plain',
        collectionPath: firestorePath(churchId),
      );
    } catch (e) {
      lastError = e;
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
      lastError = e;
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
    String queryLabel = 'finance',
    String? legacyFallbackSubcollection,
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
        queryLabel: queryLabel,
        legacyFallbackSubcollection: legacyFallbackSubcollection,
      );
      final existing = _peekRam(ramMap, ramKey);
      if (docs.isEmpty &&
          existing != null &&
          existing.isNotEmpty) {
        return;
      }
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
      if (docs.isEmpty) {
        final existing = await TenantModuleHiveCache.readDocs(churchId, hiveModule);
        if (existing.isNotEmpty) return;
      }
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        hiveModule,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeFinanceDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> primary,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> legacy,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
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
    final merged = byId.values.toList(growable: false);
    return sortDocs != null ? sortDocs(merged) : merged;
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
    String queryLabel = 'finance',
    String? legacyFallbackSubcollection,
  }) async {
    final capped = FirebasePerformanceLimits.capListLimit(queryLabel, limit);
    final primary = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: reference,
      cacheKey: cacheKey,
      limit: capped,
      forceServer: forceServer,
      orderByField: orderByField,
      orderDescending: orderDescending,
      sortDocs: sortDocs,
    );

    final legacySub = (legacyFallbackSubcollection ?? '').trim();
    if (legacySub.isEmpty || primary.isNotEmpty) return primary;

    final legacyRef =
        ChurchUiCollections.churchDoc(churchId).collection(legacySub);
    if (legacyRef.path == reference.path) return primary;

    final legacy = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: legacyRef,
      cacheKey: '${cacheKey}_legacy_$legacySub',
      limit: capped,
      forceServer: forceServer,
      orderByField: 'createdAt',
      orderDescending: true,
      sortDocs: sortDocs,
    );
    return _mergeFinanceDocs(primary, legacy, sortDocs);
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ramLancamentos.removeWhere((k, _) => k.startsWith(churchId));
    _ramContas.remove(cacheKeyContas(churchId));
    _ramFinanceLogs.removeWhere((k, _) => k.startsWith('${churchId}_finance_logs_'));
    _ramFinanceMpNotifications.removeWhere(
      (k, _) => k.startsWith('${churchId}_finance_mp_notifications_'),
    );
    await TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.financeiro);
    await TenantModuleHiveCache.clearModule(churchId, ChurchDataPaths.financeiro);
    await TenantModuleHiveCache.clearModule(churchId, kHiveContas);
    await TenantModuleHiveCache.clearModule(churchId, kHiveFinanceLogs);
    await TenantModuleHiveCache.clearModule(churchId, kHiveFinanceMpNotifications);
  }
}
