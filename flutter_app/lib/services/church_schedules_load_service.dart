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

/// Resultado da carga de subcoleções de escalas.
class ChurchSchedulesLoadResult {
  const ChurchSchedulesLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collection,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collection;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica — `igrejas/{churchId}/escalas` e `escala_templates`.
abstract final class ChurchSchedulesLoadService {
  ChurchSchedulesLoadService._();

  static const int kEscalasDefaultLimit = 500;
  static const int kTemplatesDefaultLimit = 120;
  static const String kTemplatesHiveModule = 'escala_templates';

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramEscalas = {};

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramTemplates = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String cacheKeyEscalas(String churchId, int limit) =>
      '${churchId.trim()}_escalas_$limit';

  static String cacheKeyTemplates(String churchId, int limit) =>
      '${churchId.trim()}_escala_templates_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekEscalasRam(
    String churchId, {
    int limit = kEscalasDefaultLimit,
  }) =>
      _peekRam(_ramEscalas, cacheKeyEscalas(churchId, limit));

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekTemplatesRam(
    String churchId, {
    int limit = kTemplatesDefaultLimit,
  }) =>
      _peekRam(_ramTemplates, cacheKeyTemplates(churchId, limit));

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

  static Future<ChurchSchedulesLoadResult> loadEscalas({
    required String seedTenantId,
    int limit = kEscalasDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        collection: 'escalas',
        hiveModule: TenantModuleKeys.escalas,
        cacheKeyFn: cacheKeyEscalas,
        ramMap: _ramEscalas,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        orderedQuery: (col) => col.orderBy('date', descending: true).limit(limit),
        plainQuery: (col) => col.limit(limit),
      );

  static Future<ChurchSchedulesLoadResult> loadTemplates({
    required String seedTenantId,
    int limit = kTemplatesDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        collection: 'escala_templates',
        hiveModule: kTemplatesHiveModule,
        cacheKeyFn: cacheKeyTemplates,
        ramMap: _ramTemplates,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        orderedQuery: (col) => col.orderBy('title').limit(limit),
        plainQuery: (col) => col.limit(limit),
      );

  static Future<ChurchSchedulesLoadResult> _load({
    required String seedTenantId,
    required String collection,
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
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) plainQuery,
  }) async {
    final churchId = ChurchPanelTenant.resolve(seedTenantId.trim());
    if (churchId.isEmpty) {
      return ChurchSchedulesLoadResult(
        churchId: '',
        docs: const [],
        readSource: 'empty_id',
        collection: collection,
        softError: 'Igreja não identificada.',
      );
    }

    final ramKey = cacheKeyFn(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramMap, ramKey);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collection: collection,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        _putRam(ramMap, ramKey, mem.docs);
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: mem.docs,
          readSource: 'firestore_mem',
          collection: collection,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(churchId, hiveModule);
        if (hive.isNotEmpty) {
          final docs = TenantModuleHiveCache.toQueryDocuments(hive);
          if (docs.isNotEmpty) {
            _putRam(ramMap, ramKey, docs);
            return ChurchSchedulesLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collection: collection,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        collection: collection,
        cacheKey: ramKey,
        limit: limit,
        forceServer: forceServer,
        orderedQuery: orderedQuery,
        plainQuery: plainQuery,
      );
      if (docs.isNotEmpty) {
        _putRam(ramMap, ramKey, docs);
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: forceServer ? 'server' : 'firestore_full',
          collection: collection,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        collection,
        moduleLabel: collection == 'escalas' ? 'Escalas' : 'Modelos escala',
        limit: limit,
        cacheKey: ramKey,
      );
      if (snap.docs.isNotEmpty) {
        _putRam(ramMap, ramKey, snap.docs);
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: snap.docs,
          readSource: 'direct_list',
          collection: collection,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: mem.docs,
        readSource: 'fallback_mem',
        collection: collection,
        softError: lastError?.toString(),
      );
    }

    return ChurchSchedulesLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collection: collection,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar escalas.'
          : lastError?.toString(),
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required String churchId,
    required String collection,
    required String cacheKey,
    required int limit,
    required bool forceServer,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
    ) plainQuery,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    CollectionReference<Map<String, dynamic>> col(String sub) {
      switch (sub) {
        case 'escalas':
          return ChurchUiCollections.escalas(churchId);
        case 'escala_templates':
          return ChurchUiCollections.churchDoc(churchId).collection(sub);
        default:
          return ChurchUiCollections.ref(sub, churchIdHint: churchId);
      }
    }

    final reference = col(collection);

    if (!forceServer) {
      try {
        final cacheSnap = await orderedQuery(reference)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) return cacheSnap.docs;
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
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

    return snap.docs;
  }

  static Future<void> persistEscalas(ChurchSchedulesLoadResult result) async {
    if (result.docs.isEmpty || result.collection != 'escalas') return;
    final key = cacheKeyEscalas(result.churchId, result.docs.length.clamp(1, kEscalasDefaultLimit));
    _putRam(_ramEscalas, key, result.docs);
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        result.churchId,
        TenantModuleKeys.escalas,
        result.snapshot,
      );
    } catch (_) {}
  }

  static Future<void> persistTemplates(ChurchSchedulesLoadResult result) async {
    if (result.docs.isEmpty || result.collection != 'escala_templates') return;
    final key = cacheKeyTemplates(result.churchId, result.docs.length.clamp(1, kTemplatesDefaultLimit));
    _putRam(_ramTemplates, key, result.docs);
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        result.churchId,
        kTemplatesHiveModule,
        result.snapshot,
      );
    } catch (_) {}
  }
}
