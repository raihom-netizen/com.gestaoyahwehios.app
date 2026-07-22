import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga fornecedores — `igrejas/{churchId}/fornecedores`.
class ChurchFornecedoresLoadResult {
  const ChurchFornecedoresLoadResult({
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

/// Carga canónica — Firestore `igrejas/{id}/fornecedores`.
///
/// **Regra:** lista vazia = sucesso. Cache RAM / Hive aceite mesmo com 0 documentos.
abstract final class ChurchFornecedoresLoadService {
  ChurchFornecedoresLoadService._();

  static const int kDefaultLimit = YahwehPerformanceV4.defaultPageSize;
  static const int kDefaultAllLimit = 800;
  static const int kDefaultCompromissosLimit = 120;

  static String compromissosCacheKey(String churchId, int limit) =>
      '${churchId.trim()}_fornecedor_compromissos_$limit';

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
      })> _ramCompromissos = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String resolveChurchId(String hint) => _resolve(hint);

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_fornecedores_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultLimit,
  }) =>
      _peekRam(_resolve(seedTenantId), limit);

  /// Qualquer entrada RAM deste tenant (warm com limites diferentes).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRamAny(
    String seedTenantId,
  ) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    for (final limit in [800, kDefaultLimit, 200, 80, 50]) {
      final hit = _peekRam(churchId, limit);
      if (hit != null && hit.isNotEmpty) return hit;
    }
    final prefix = '${churchId}_fornecedores_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  /// Dados de um fornecedor já carregados na lista (RAM/Hive) — evita re-fetch na edição.
  static Map<String, dynamic>? peekDocData(String seedTenantId, String docId) {
    final id = docId.trim();
    if (id.isEmpty) return null;
    final docs = peekRamAny(seedTenantId);
    if (docs == null) return null;
    for (final d in docs) {
      if (d.id == id) return Map<String, dynamic>.from(d.data());
    }
    return null;
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
    return TenantDeletedDocTombstones.filter(
      churchId,
      TenantModuleKeys.fornecedores,
      hit.docs,
      (d) => d.id,
    );
  }

  static void _putRam(
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Lista vazia não apaga RAM boa (evita sumiço ao voltar ao módulo).
    if (docs.isEmpty) {
      final hit = _ram[key];
      if (hit != null && hit.docs.isNotEmpty) return;
      return;
    }
    final churchId = key.split('_fornecedores_').first;
    final safe = TenantDeletedDocTombstones.filter(
      churchId,
      TenantModuleKeys.fornecedores,
      List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs),
      (d) => d.id,
    );
    if (safe.isEmpty) return;
    _ram[key] = (docs: safe, at: DateTime.now());
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByNome(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final na = (a.data()['nome'] ?? '').toString().trim().toLowerCase();
      final nb = (b.data()['nome'] ?? '').toString().trim().toLowerCase();
      return na.compareTo(nb);
    });
    return sorted;
  }

  static Future<ChurchFornecedoresLoadResult> load({
    required String seedTenantId,
    int limit = kDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _loadFornecedoresInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );

  static Future<ChurchFornecedoresLoadResult> loadAll({
    required String seedTenantId,
    int limit = kDefaultAllLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _loadFornecedoresInternal(
        seedTenantId: seedTenantId,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );

  static Future<ChurchFornecedoresLoadResult> loadCompromissos({
    required String seedTenantId,
    int limit = kDefaultCompromissosLimit,
    String? fornecedorIdFilter,
    bool descending = true,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchFornecedoresLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'fornecedor_compromissos',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/fornecedor_compromissos';
    final f = (fornecedorIdFilter ?? '').trim();
    final ramKey = '${compromissosCacheKey(churchId, limit)}_${f}_$descending';
    final capped =
        FirebasePerformanceLimits.capListLimit('fornecedor_compromissos', limit);

    if (forceRefresh || forceServer) {
      _ramCompromissos.removeWhere((k, _) => k.startsWith(churchId));
      FirestoreReadResilience.forgetKey(ramKey);
      await TenantModuleHiveCache.clearModule(
        churchId,
        TenantModuleKeys.fornecedorCompromissos,
      );
    }

    final ramHit = _ramCompromissos[ramKey];
    if (!forceRefresh &&
        !forceServer &&
        ramHit != null &&
        DateTime.now().difference(ramHit.at) <= _ramTtl &&
        ramHit.docs.isNotEmpty) {
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: ramHit.docs,
        readSource: 'ram_compromissos',
        collectionPath: path,
        fromCache: true,
      );
    }

    Object? lastError;
    try {
      final docs = await _loadCompromissosFirestore(
        churchId: churchId,
        limit: capped,
        fornecedorIdFilter: f,
        descending: descending,
        cacheKey: ramKey,
        forceServer: forceServer,
      );
      _ramCompromissos[ramKey] = (docs: List.from(docs), at: DateTime.now());
      unawaited(_persistCompromissosHive(churchId, docs));
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_compromissos',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'fornecedor_compromissos',
        moduleLabel: 'FornecedorCompromissos',
        limit: capped,
        cacheKey: '${ramKey}_direct',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      var docs = snap.docs;
      if (f.isNotEmpty) {
        docs = docs
            .where((d) => (d.data()['fornecedorId'] ?? '').toString().trim() == f)
            .toList(growable: false);
      }
      docs = _sortByVencimento(docs, descending: descending);
      if (docs.isNotEmpty) {
        _ramCompromissos[ramKey] = (docs: List.from(docs), at: DateTime.now());
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError = e;
    }

    final fallback = _ramCompromissos[ramKey]?.docs;
    if (fallback != null && fallback.isNotEmpty) {
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: fallback,
        readSource: 'ram_fallback',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchFornecedoresLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: _humanizeError(lastError),
    );
  }

  static Future<ChurchFornecedoresLoadResult> _loadFornecedoresInternal({
    required String seedTenantId,
    required int limit,
    required bool forceRefresh,
    required bool forceServer,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchFornecedoresLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'fornecedores',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/fornecedores';
    final ramKey = cacheKey(churchId, limit);
    final reference = ChurchUiCollections.fornecedores(churchId);
    final capped = FirebasePerformanceLimits.capListLimit('fornecedores', limit);

    if (forceRefresh || forceServer) {
      _ram.removeWhere((k, _) => k.startsWith(churchId));
      FirestoreReadResilience.forgetKey(ramKey);
      FirestoreReadResilience.forgetKey('${ramKey}_retry');
      await TenantModuleHiveCache.clearModule(
        churchId,
        TenantModuleKeys.fornecedores,
      );
    }

    if (!forceRefresh && !forceServer) {
      final anyRam = peekRamAny(churchId);
      if (anyRam != null && anyRam.isNotEmpty) {
        final docs = _sortByNome(anyRam);
        _putRam(ramKey, docs);
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
        ));
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'ram_any',
          collectionPath: path,
          fromCache: true,
        );
      }

      final ramHit = _peekRam(churchId, limit);
      if (ramHit != null) {
        if (ramHit.isEmpty) {
          _ram.remove(ramKey);
        } else {
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
        ));
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
        }
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _sortByNome(mem.docs);
        _putRam(ramKey, docs);
        return ChurchFornecedoresLoadResult(
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
          TenantModuleKeys.fornecedores,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(
            churchId,
            TenantModuleKeys.fornecedores,
          );
          final docs = _sortByNome(TenantModuleHiveCache.toQueryDocuments(hive));
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramKey, docs);
            unawaited(_refreshInBackground(
              churchId: churchId,
              ramKey: ramKey,
              limit: capped,
              reference: reference,
            ));
            return ChurchFornecedoresLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
          // Hive vazio/obsoleto — continua para Firestore.
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
      return ChurchFornecedoresLoadResult(
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
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_plain',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'fornecedores',
        moduleLabel: 'Fornecedores',
        limit: capped,
        cacheKey: '${ramKey}_direct',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      final docs = _sortByNome(snap.docs);
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final repo = await ChurchRepository.fornecedores.listCacheFirst(
        churchIdHint: churchId,
        limit: capped,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        var docs = _sortByNome(repo.items);
        _putRam(ramKey, docs);
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          fromCache: repo.error == null && docs.isNotEmpty,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError = e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: _sortByNome(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = peekRamAny(churchId) ?? _peekRam(churchId, limit);
    if (ramFallback != null) {
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchFornecedoresLoadResult(
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
      return 'Tempo esgotado ao carregar fornecedores. Verifique a conexão.';
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
      final hit = _ram[ramKey];
      if (docs.isEmpty && hit != null && hit.docs.isNotEmpty) {
        return;
      }
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      if (docs.isEmpty) {
        final existing = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.fornecedores,
        );
        if (existing.isNotEmpty) return;
      }
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.fornecedores,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByVencimento(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool descending = true,
  }) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = a.data()['dataVencimento'];
      final tb = b.data()['dataVencimento'];
      if (ta is Timestamp && tb is Timestamp) {
        return descending ? tb.compareTo(ta) : ta.compareTo(tb);
      }
      return 0;
    });
    return sorted;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadCompromissosFirestore({
    required String churchId,
    required int limit,
    required String fornecedorIdFilter,
    required bool descending,
    required String cacheKey,
    required bool forceServer,
  }) async {
    final col = ChurchUiCollections.fornecedorCompromissos(churchId);
    if (fornecedorIdFilter.isNotEmpty) {
      try {
        final snap = await ChurchModuleFirestoreListRead.queryPlainFirst(
          reference: col,
          cacheKey: '${cacheKey}_fn_plain',
          limit: 200,
          forceServer: forceServer,
          orderByField: 'dataVencimento',
          orderDescending: true,
          sortDocs: (docs) => _sortByVencimento(
            docs
                .where(
                  (d) =>
                      (d.data()['fornecedorId'] ?? '').toString().trim() ==
                      fornecedorIdFilter,
                )
                .toList(growable: false),
            descending: descending,
          ),
        );
        return snap.take(limit).toList(growable: false);
      } catch (_) {
        final plain = await col
            .where('fornecedorId', isEqualTo: fornecedorIdFilter)
            .limit(200)
            .get();
        return _sortByVencimento(plain.docs, descending: descending)
            .take(limit)
            .toList(growable: false);
      }
    }
    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: col,
      cacheKey: cacheKey,
      limit: limit,
      forceServer: forceServer,
      orderByField: 'dataVencimento',
      orderDescending: descending,
      sortDocs: (docs) => _sortByVencimento(docs, descending: descending),
    );
  }

  static Future<void> _persistCompromissosHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.fornecedorCompromissos,
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
        legacyFallbackSubcollections: const ['suppliers'],
        orderByField: 'nome',
        sortDocs: _sortByNome,
      );

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    _ramCompromissos.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.fornecedores,
    );
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.fornecedorCompromissos,
    );
  }
}
