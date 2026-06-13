import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
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

/// Carga canónica — Firestore `igrejas/{id}/finance`, Storage comprovantes em `financeiro/YYYY_MM/`.
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

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

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
    if (docs.isEmpty) return;
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
        orderedQuery: (col) =>
            col.orderBy('createdAt', descending: true).limit(limit),
        plainQuery: (col) => col.limit(limit),
        sortDocs: _sortFinanceDocs,
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
        orderedQuery: (col) => col.orderBy('nome').limit(limit),
        plainQuery: (col) => col.limit(limit),
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
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> c,
    ) plainQuery,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
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

    final ramKey = cacheKeyFn(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramMap, ramKey);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: firestorePath(churchId),
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = sortDocs != null ? sortDocs(mem.docs) : mem.docs;
        _putRam(ramMap, ramKey, docs);
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: firestorePath(churchId),
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(churchId, hiveModule)
            .timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          var docs = TenantModuleHiveCache.toQueryDocuments(hive);
          if (sortDocs != null) docs = sortDocs(docs);
          if (docs.isNotEmpty) {
            _putRam(ramMap, ramKey, docs);
            return ChurchFinanceLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: firestorePath(churchId),
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
        orderedQuery: orderedQuery,
        plainQuery: plainQuery,
        sortDocs: sortDocs,
      );
      if (docs.isNotEmpty) {
        _putRam(ramMap, ramKey, docs);
        unawaited(_persistHive(churchId, hiveModule, docs));
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: forceServer ? 'server' : 'firestore_full',
          collectionPath: firestorePath(churchId),
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        collectionLabel,
        moduleLabel: collectionLabel == 'finance' ? 'Financeiro' : 'Contas',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        var docs = snap.docs;
        if (sortDocs != null) docs = sortDocs(docs);
        _putRam(ramMap, ramKey, docs);
        unawaited(_persistHive(churchId, hiveModule, docs));
        return ChurchFinanceLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
          collectionPath: firestorePath(churchId),
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      var docs = mem.docs;
      if (sortDocs != null) docs = sortDocs(docs);
      return ChurchFinanceLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'fallback_mem',
        collectionPath: firestorePath(churchId),
        softError: lastError?.toString(),
      );
    }

    return ChurchFinanceLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: firestorePath(churchId),
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar $collectionLabel.'
          : lastError?.toString(),
    );
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
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) plainQuery,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>,
    )? sortDocs,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    if (!forceServer) {
      try {
        final cacheSnap = await orderedQuery(reference)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return sortDocs != null
              ? sortDocs(cacheSnap.docs)
              : cacheSnap.docs;
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      if (kIsWeb) {
        final plain = await FirestoreReadResilience.getQuery(
          plainQuery(reference),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: 4,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        if (plain.docs.isNotEmpty) return plain;
      }
      try {
        return await FirestoreReadResilience.getQuery(
          orderedQuery(reference),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        return FirestoreReadResilience.getQuery(
          plainQuery(reference),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      }
    }

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);

    final docs = snap.docs;
    return sortDocs != null ? sortDocs(docs) : docs;
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ramLancamentos.removeWhere((k, _) => k.startsWith(churchId));
    _ramContas.remove(cacheKeyContas(churchId));
    await TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.financeiro);
    await TenantModuleHiveCache.clearModule(churchId, kHiveContas);
  }
}
