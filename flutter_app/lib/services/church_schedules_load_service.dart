import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/escala_firestore_fields.dart';
import 'package:gestao_yahweh/core/escala_member_payload.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de subcoleções de escalas.
class ChurchSchedulesLoadResult {
  const ChurchSchedulesLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collection,
    required this.firestorePath,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collection;
  final String firestorePath;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica — `igrejas/{churchId}/escalas` e `escala_templates`.
abstract final class ChurchSchedulesLoadService {
  ChurchSchedulesLoadService._();

  static const int kEscalasDefaultLimit = 200;
  static const int kEscalasPanelActiveLimit = 30;
  static const int kTemplatesDefaultLimit = 120;
  static const String kTemplatesHiveModule = ChurchDataPaths.escalaTemplates;

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

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ramMemberEscalas = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _path(String churchId, String sub) =>
      churchId.isEmpty ? '' : ChurchDataPaths.subcollection(churchId, sub);

  static int _capLimit(String sub, int requested) =>
      FirebasePerformanceLimits.capListLimit(sub, requested);

  static String cacheKeyEscalas(String churchId, int limit) =>
      '${churchId.trim()}_escalas_$limit';

  static String cacheKeyTemplates(String churchId, int limit) =>
      '${churchId.trim()}_escala_templates_$limit';

  static String cacheKeyMemberEscalas(String churchId, String cpf, int limit) =>
      '${churchId.trim()}_escalas_member_${cpf.trim()}_$limit';

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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekMemberEscalasRam(
    String churchId,
    String cpfDigits, {
    int limit = kEscalasDefaultLimit,
  }) =>
      _peekRam(
        _ramMemberEscalas,
        cacheKeyMemberEscalas(churchId, cpfDigits, limit),
      );

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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filterByMemberCpfs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String cpfDigits,
  ) =>
      filterByMember(
        docs,
        cpfDigits: cpfDigits,
      );

  /// Filtra escalas do membro — `memberUids` (preferido) ou `escalados` / `memberCpfs` legado.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filterByMember(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String cpfDigits = '',
    String uid = '',
  }) {
    final cpf = EscalaMemberPayload.normCpf(cpfDigits);
    final authUid = uid.trim();
    if (cpf.length != 11 && authUid.isEmpty) return const [];
    return docs.where((d) {
      return EscalaMemberPayload.docContainsMember(
        data: d.data(),
        cpfDigits: cpf,
        uid: authUid,
      );
    }).toList();
  }

  /// Escalas geradas — lista completa (gestor / Escala Geral).
  static Future<ChurchSchedulesLoadResult> loadEscalas({
    required String seedTenantId,
    int limit = kEscalasDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
    bool activeOnly = false,
  }) =>
      _load(
        seedTenantId: seedTenantId,
        collection: ChurchDataPaths.escalas,
        hiveModule: TenantModuleKeys.escalas,
        cacheKeyFn: cacheKeyEscalas,
        ramMap: _ramEscalas,
        limit: limit,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
        orderedQuery: (col, capped) => activeOnly
            ? col.where('active', isEqualTo: true).limit(capped)
            : col.limit(capped),
        plainQuery: (col, capped) => activeOnly
            ? col.where('active', isEqualTo: true).limit(capped)
            : col.limit(capped),
        sortDocs: _sortEscalasByDateDesc,
      );

  /// Escalas do membro — índice `memberCpfs` + `date` (Minha Escala).
  static Future<ChurchSchedulesLoadResult> loadEscalasForMember({
    required String seedTenantId,
    required String cpfDigits,
    String memberUid = '',
    int limit = kEscalasDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final cpf = cpfDigits.replaceAll(RegExp(r'[^0-9]'), '');
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty || cpf.length != 11) {
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'invalid_input',
        collection: ChurchDataPaths.escalas,
        firestorePath: _path(churchId, ChurchDataPaths.escalas),
        softError: cpf.length != 11
            ? 'CPF não identificado para filtrar escalas.'
            : 'Igreja não identificada.',
      );
    }

    final capped = _capLimit(ChurchDataPaths.escalas, limit);
    final ramKey = cacheKeyMemberEscalas(churchId, cpf, capped);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(_ramMemberEscalas, ramKey);
      if (ramHit != null) {
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram_member',
          collection: ChurchDataPaths.escalas,
          firestorePath: _path(churchId, ChurchDataPaths.escalas),
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = filterByMember(mem.docs, cpfDigits: cpf, uid: memberUid);
        _putRam(_ramMemberEscalas, ramKey, docs);
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem_member',
          collection: ChurchDataPaths.escalas,
          firestorePath: _path(churchId, ChurchDataPaths.escalas),
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          TenantModuleKeys.escalas,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(
            churchId,
            TenantModuleKeys.escalas,
          );
          final all = TenantModuleHiveCache.toQueryDocuments(hive);
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(all)) {
            final docs = filterByMember(all, cpfDigits: cpf, uid: memberUid);
            _putRam(_ramMemberEscalas, ramKey, docs);
            unawaited(_refreshMemberEscalasInBackground(
              churchId: churchId,
              cpf: cpf,
              memberUid: memberUid,
              limit: capped,
              ramKey: ramKey,
            ));
            return ChurchSchedulesLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive_member',
              collection: ChurchDataPaths.escalas,
              firestorePath: _path(churchId, ChurchDataPaths.escalas),
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final all = await loadEscalas(
        seedTenantId: churchId,
        limit: capped,
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );
      final docs = filterByMember(all.docs, cpfDigits: cpf, uid: memberUid);
      _putRam(_ramMemberEscalas, ramKey, docs);
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: all.readSource.startsWith('ram')
            ? 'member_filter_${all.readSource}'
            : 'member_filter_firestore',
        collection: ChurchDataPaths.escalas,
        firestorePath: _path(churchId, ChurchDataPaths.escalas),
        softError: docs.isEmpty ? all.softError : null,
      );
    } catch (e) {
      lastError = e;
    }

    final ramFallback = _peekRam(_ramMemberEscalas, ramKey);
    if (ramFallback != null) {
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_member_fallback',
        collection: ChurchDataPaths.escalas,
        firestorePath: _path(churchId, ChurchDataPaths.escalas),
        softError: _humanizeError(lastError),
      );
    }

    final fallback = await loadEscalas(
      seedTenantId: churchId,
      limit: limit,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    final filtered = filterByMember(fallback.docs, cpfDigits: cpf, uid: memberUid);
    _putRam(_ramMemberEscalas, ramKey, filtered);
    return ChurchSchedulesLoadResult(
      churchId: churchId,
      docs: filtered,
      readSource: 'fallback_filter',
      collection: ChurchDataPaths.escalas,
      firestorePath: _path(churchId, ChurchDataPaths.escalas),
      softError: filtered.isEmpty ? _humanizeError(lastError) : null,
    );
  }

  static Future<void> _refreshMemberEscalasInBackground({
    required String churchId,
    required String cpf,
    required int limit,
    required String ramKey,
    String memberUid = '',
  }) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final col = ChurchUiCollections.escalas(churchId);
      final uid = memberUid.trim();
      Query<Map<String, dynamic>> query;
      if (uid.isNotEmpty) {
        query = col
            .where('memberUids', arrayContains: uid)
            .where('active', isEqualTo: true)
            .limit(limit);
      } else {
        query = col
            .where('memberCpfs', arrayContains: cpf)
            .where('active', isEqualTo: true)
            .limit(limit);
      }
      final snap = await FirestoreReadResilience.getQuery(
        query,
        cacheKey: ramKey,
        maxAttempts: kIsWeb ? 4 : 2,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        snap.docs,
      )..sort(EscalaFirestoreFields.compareDateAsc);
      _putRam(_ramMemberEscalas, ramKey, docs);
    } catch (_) {
      try {
        final col = ChurchUiCollections.escalas(churchId);
        final snap = await FirestoreReadResilience.getQuery(
          col.where('memberCpfs', arrayContains: cpf).limit(limit),
          cacheKey: '${ramKey}_legacy',
          maxAttempts: kIsWeb ? 4 : 2,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          snap.docs,
        )..sort(EscalaFirestoreFields.compareDateAsc);
        _putRam(_ramMemberEscalas, ramKey, docs);
      } catch (_) {}
    }
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar escalas. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  /// Modelos — `igrejas/{churchId}/escala_templates`.
  ///
  /// Lista vazia = sucesso (não bloqueia UI). Hidratação via `templateId` nas
  /// escalas só em background ou quando a leitura principal falhou.
  static Future<ChurchSchedulesLoadResult> loadTemplates({
    required String seedTenantId,
    int limit = kTemplatesDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final primary = await _load(
      seedTenantId: seedTenantId,
      collection: ChurchDataPaths.escalaTemplates,
      hiveModule: kTemplatesHiveModule,
      cacheKeyFn: cacheKeyTemplates,
      ramMap: _ramTemplates,
      limit: limit,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
      orderedQuery: (col, capped) => col.orderBy('title').limit(capped),
      plainQuery: (col, capped) => col.limit(capped),
      sortDocs: _sortTemplatesByTitle,
    );
    if (primary.docs.isNotEmpty) return primary;

    if (primary.softError == null) {
      unawaited(
        _hydrateTemplatesFromEscalas(
          seedTenantId: seedTenantId,
          limit: limit,
          forceRefresh: false,
        ),
      );
      return primary;
    }

    final hydrated = await _hydrateTemplatesFromEscalas(
      seedTenantId: seedTenantId,
      limit: limit,
      forceRefresh: false,
    );
    if (hydrated.docs.isEmpty) return primary;
    return hydrated;
  }

  /// Recupera modelos referenciados por `templateId` nas escalas geradas.
  static Future<ChurchSchedulesLoadResult> _hydrateTemplatesFromEscalas({
    required String seedTenantId,
    int limit = kTemplatesDefaultLimit,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return ChurchSchedulesLoadResult(
        churchId: '',
        docs: const [],
        readSource: 'empty_id',
        collection: ChurchDataPaths.escalaTemplates,
        firestorePath: '',
      );
    }

    final escalas = await loadEscalas(
      seedTenantId: churchId,
      limit: _capLimit(ChurchDataPaths.escalas, 120),
      forceRefresh: forceRefresh,
    );
    final ids = <String>{};
    for (final d in escalas.docs) {
      final tid = (d.data()['templateId'] ?? '').toString().trim();
      if (tid.isNotEmpty) ids.add(tid);
      if (ids.length >= limit) break;
    }
    if (ids.isEmpty) {
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'no_template_ids',
        collection: ChurchDataPaths.escalaTemplates,
        firestorePath: _path(churchId, ChurchDataPaths.escalaTemplates),
      );
    }

    final col = ChurchUiCollections.escalaTemplates(churchId);
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final idList = ids.take(limit).toList();
    for (var i = 0; i < idList.length; i += 10) {
      final end = (i + 10 > idList.length) ? idList.length : i + 10;
      final chunk = idList.sublist(i, end);
      try {
        final snap = await col
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        docs.addAll(snap.docs);
      } catch (_) {}
    }
    docs.sort(_sortTemplatesByTitle);
    if (docs.isNotEmpty) {
      final key = cacheKeyTemplates(churchId, limit);
      _putRam(_ramTemplates, key, docs);
    }
    return ChurchSchedulesLoadResult(
      churchId: churchId,
      docs: docs,
      readSource: 'hydrate_from_escalas',
      collection: ChurchDataPaths.escalaTemplates,
      firestorePath: _path(churchId, ChurchDataPaths.escalaTemplates),
    );
  }

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
      int capped,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
      int capped,
    ) plainQuery,
    required int Function(
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) sortDocs,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    final path = _path(churchId, collection);
    if (churchId.isEmpty) {
      return ChurchSchedulesLoadResult(
        churchId: '',
        docs: const [],
        readSource: 'empty_id',
        collection: collection,
        firestorePath: path,
        softError: 'Igreja não identificada.',
      );
    }

    final capped = _capLimit(collection, limit);
    final ramKey = cacheKeyFn(churchId, capped);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramMap, ramKey);
      if (ramHit != null) {
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collection: collection,
          firestorePath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        _putRam(ramMap, ramKey, mem.docs);
        return ChurchSchedulesLoadResult(
          churchId: churchId,
          docs: mem.docs,
          readSource: 'firestore_mem',
          collection: collection,
          firestorePath: path,
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          hiveModule,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(churchId, hiveModule);
          final docs = TenantModuleHiveCache.toQueryDocuments(hive);
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramMap, ramKey, docs);
            unawaited(
              _loadFirestore(
                churchId: churchId,
                collection: collection,
                cacheKey: ramKey,
                limit: capped,
                forceServer: false,
                orderedQuery: orderedQuery,
                plainQuery: plainQuery,
                sortDocs: sortDocs,
              ).then((fresh) => _putRam(ramMap, ramKey, fresh)).catchError((_) {}),
            );
            return ChurchSchedulesLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collection: collection,
              firestorePath: path,
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
        limit: capped,
        forceServer: forceServer,
        orderedQuery: orderedQuery,
        plainQuery: plainQuery,
        sortDocs: sortDocs,
      );
      _putRam(ramMap, ramKey, docs);
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collection: collection,
        firestorePath: path,
      );
    } catch (e) {
      lastError = e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchSchedulesLoadResult(
        churchId: churchId,
        docs: mem.docs,
        readSource: 'fallback_mem',
        collection: collection,
        firestorePath: path,
        softError: _humanizeError(lastError),
      );
    }

    if (collection == ChurchDataPaths.escalas) {
      try {
        final repo = await ChurchRepository.escalas.listCacheFirst(
          churchIdHint: churchId,
          limit: capped,
          firestoreCacheKey: ramKey,
        );
        if (repo.items.isNotEmpty || repo.error == null) {
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            repo.items,
          )..sort(sortDocs);
          _putRam(ramMap, ramKey, docs);
          return ChurchSchedulesLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'repository_cache_first',
            collection: collection,
            firestorePath: path,
            softError: repo.error,
          );
        }
      } catch (e) {
        lastError ??= e;
      }
    }

    return ChurchSchedulesLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collection: collection,
      firestorePath: path,
      softError: _humanizeError(lastError),
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
      int capped,
    ) orderedQuery,
    required Query<Map<String, dynamic>> Function(
      CollectionReference<Map<String, dynamic>> col,
      int capped,
    ) plainQuery,
    required int Function(
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) sortDocs,
  }) async {
    final reference = _collectionRef(churchId, collection);
    final orderField = collection == ChurchDataPaths.escalas ? 'date' : null;

    final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: reference,
      cacheKey: cacheKey,
      limit: limit,
      forceServer: forceServer,
      orderByField: orderField,
      orderDescending: collection == ChurchDataPaths.escalas,
      sortDocs: (list) {
        final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(list)
          ..sort(sortDocs);
        return sorted;
      },
    );
    return docs;
  }

  static CollectionReference<Map<String, dynamic>> _collectionRef(
    String churchId,
    String collection,
  ) {
    switch (collection) {
      case ChurchDataPaths.escalas:
        return ChurchUiCollections.escalas(churchId);
      case ChurchDataPaths.escalaTemplates:
        return ChurchUiCollections.escalaTemplates(churchId);
      default:
        return ChurchUiCollections.ref(collection, churchIdHint: churchId);
    }
  }

  static int _sortEscalasByDateDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) =>
      EscalaFirestoreFields.compareDateDesc(a, b);

  static int _sortTemplatesByTitle(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) =>
      (a.data()['title'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b.data()['title'] ?? '').toString().toLowerCase());

  static Future<void> persistEscalas(ChurchSchedulesLoadResult result) async {
    if (result.docs.isEmpty || result.collection != ChurchDataPaths.escalas) {
      return;
    }
    final key = cacheKeyEscalas(
      result.churchId,
      result.docs.length.clamp(1, kEscalasDefaultLimit),
    );
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
    if (result.docs.isEmpty ||
        result.collection != ChurchDataPaths.escalaTemplates) {
      return;
    }
    final key = cacheKeyTemplates(
      result.churchId,
      result.docs.length.clamp(1, kTemplatesDefaultLimit),
    );
    _putRam(_ramTemplates, key, result.docs);
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        result.churchId,
        kTemplatesHiveModule,
        result.snapshot,
      );
    } catch (_) {}
  }

  static void invalidateRam(String churchId) {
    final id = churchId.trim();
    if (id.isEmpty) return;
    _ramEscalas.removeWhere((k, _) => k.startsWith(id));
    _ramTemplates.removeWhere((k, _) => k.startsWith(id));
    _ramMemberEscalas.removeWhere((k, _) => k.startsWith(id));
  }
}
