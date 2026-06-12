import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
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

/// Carga canónica — Firestore `igrejas/{id}/fornecedores`.
abstract final class ChurchFornecedoresLoadService {
  ChurchFornecedoresLoadService._();

  static const int kDefaultLimit = YahwehPerformanceV4.defaultPageSize;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_fornecedores_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultLimit,
  }) {
    final key = cacheKey(_resolve(seedTenantId), limit);
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
    if (docs.isEmpty) return;
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
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

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId, limit: limit);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByNome(mem.docs);
        _putRam(ramKey, docs);
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.fornecedores,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final docs = _sortByNome(TenantModuleHiveCache.toQueryDocuments(hive));
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            return ChurchFornecedoresLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        reference: ChurchUiCollections.fornecedores(churchId),
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: limit,
      );
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchFornecedoresLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: forceServer ? 'server' : 'firestore_full',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'fornecedores',
        moduleLabel: 'Fornecedores',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        final docs = _sortByNome(snap.docs);
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
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchFornecedoresLoadResult(
        churchId: churchId,
        docs: _sortByNome(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchFornecedoresLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar fornecedores.'
          : lastError?.toString(),
    );
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.fornecedores,
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
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Query<Map<String, dynamic>> ordered(CollectionReference<Map<String, dynamic>> c) =>
        c.orderBy('nome').limit(limit);
    Query<Map<String, dynamic>> plain(CollectionReference<Map<String, dynamic>> c) =>
        c.limit(limit);

    if (!forceServer) {
      try {
        final cacheSnap = await ordered(reference)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByNome(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        return await FirestoreReadResilience.getQuery(
          ordered(reference),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        return FirestoreReadResilience.getQuery(
          plain(reference),
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

    return _sortByNome(snap.docs);
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.fornecedores,
    );
  }
}
