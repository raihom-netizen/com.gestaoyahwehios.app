import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
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

/// Carga canónica Cargos — directa `igrejas/{churchId}/cargos`.
abstract final class ChurchCargosLoadService {
  ChurchCargosLoadService._();

  static const int kLimit = 120;

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

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreFull(
    String churchId, {
    bool forceServer = false,
  }) async {
    final id = ChurchPanelTenant.resolve(churchId);
    if (id.isEmpty) return const [];

    final key = cacheKey(id);

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    if (!forceServer) {
      try {
        final cacheSnap = await ChurchUiCollections.cargos(id)
            .limit(kLimit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortDocs(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readPlain() =>
        FirestoreReadResilience.getQuery(
          ChurchUiCollections.cargos(id).limit(kLimit),
          cacheKey: key,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 24)
              : const Duration(seconds: 16),
        );

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        return await FirestoreReadResilience.getQuery(
          ChurchUiCollections.cargos(id).orderBy('name').limit(kLimit),
          cacheKey: '${key}_name',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 24)
              : const Duration(seconds: 16),
        );
      } catch (_) {
        return readPlain();
      }
    }

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(const Duration(seconds: 100))
        : await readServer().timeout(const Duration(seconds: 50));

    return _sortDocs(snap.docs);
  }

  static Future<ChurchCargosLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = ChurchPanelTenant.resolve(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchCargosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'cargos',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/cargos';

    if (!forceRefresh && !forceServer) {
      final ram = peekRam(churchId);
      if (ram != null && ram.isNotEmpty) {
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
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final docs = _sortDocs(TenantModuleHiveCache.toQueryDocuments(hive));
          if (docs.isNotEmpty) {
            putRam(churchId, docs);
            return ChurchCargosLoadResult(
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
      final docs = await _loadFirestoreFull(
        churchId,
        forceServer: forceServer,
      );
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
        return ChurchCargosLoadResult(
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
        'cargos',
        moduleLabel: 'Cargos',
        limit: kLimit,
        cacheKey: cacheKey(churchId),
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
}
