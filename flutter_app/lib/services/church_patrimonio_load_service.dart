import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
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

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String resolveChurchId(String hint) => _resolve(hint);

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_patrimonio_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultListLimit,
  }) =>
      _peekRam(_resolve(seedTenantId), limit);

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

  static Future<ChurchPatrimonioLoadResult> _loadInternal({
    required String seedTenantId,
    required int limit,
    required bool forceRefresh,
    required bool forceServer,
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

    final path = 'igrejas/$churchId/patrimonio';
    final ramKey = cacheKey(churchId, limit);
    final reference = ChurchUiCollections.patrimonio(churchId);
    final capped = FirebasePerformanceLimits.capListLimit('patrimonio', limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(churchId, limit);
      if (ramHit != null) {
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
        ));
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _sortByNome(mem.docs);
        _putRam(ramKey, docs);
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
          TenantModuleKeys.patrimonio,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive =
              await TenantModuleHiveCache.readDocs(churchId, TenantModuleKeys.patrimonio);
          var docs = _sortByNome(TenantModuleHiveCache.toQueryDocuments(hive));
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramKey, docs);
            unawaited(_refreshInBackground(
              churchId: churchId,
              ramKey: ramKey,
              limit: capped,
              reference: reference,
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
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
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
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_plain',
        collectionPath: path,
      );
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.patrimonio.listCacheFirst(
        churchIdHint: churchId,
        limit: capped,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        var docs = repo.items;
        docs = _sortByNome(docs);
        _putRam(ramKey, docs);
        return ChurchPatrimonioLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          fromCache: repo.error == null && docs.isNotEmpty,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchPatrimonioLoadResult(
        churchId: churchId,
        docs: _sortByNome(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = _peekRam(churchId, limit);
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
  }) async {
    try {
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: ramKey,
        forceServer: false,
        limit: limit,
      );
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
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
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.patrimonio,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required CollectionReference<Map<String, dynamic>> reference,
    required String cacheKey,
    required bool forceServer,
    required int limit,
  }) =>
      ChurchModuleFirestoreListRead.queryPlainFirst(
        reference: reference,
        cacheKey: cacheKey,
        limit: limit,
        forceServer: forceServer,
        orderByField: 'nome',
        sortDocs: _sortByNome,
      );

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.patrimonio,
    );
  }
}
