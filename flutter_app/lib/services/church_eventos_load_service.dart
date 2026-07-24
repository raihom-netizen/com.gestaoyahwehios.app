import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/panel_feed_post_validator.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/core/church_panel_modules_removed.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de eventos — `igrejas/{churchId}/eventos`.
class ChurchEventosLoadResult {
  const ChurchEventosLoadResult({
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
}

/// Carga canónica — Firestore `igrejas/{id}/eventos`; mídia em Storage `igrejas/{id}/eventos/…`.
abstract final class ChurchEventosLoadService {
  ChurchEventosLoadService._();

  static const int kDefaultFeedLimit = PanelFeedPostValidator.kPanelFeedPageSize;
  static const int kGalleryLimit = 250;
  static const String _legacyEventsCollectionEn = 'events';

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_eventos_feed_$limit';

  static String galleryCacheKey(String churchId) =>
      '${churchId.trim()}_eventos_gallery_$kGalleryLimit';

  static Future<void> _ensureFirebaseForRead() async {
    await ensureFirebaseReadyForPanelRead();
  }

  /// Remove docs recém-excluídos (lápides) — nenhum cache pode ressuscitá-los.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _withoutDeleted(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      TenantDeletedDocTombstones.filter(
        churchId,
        TenantModuleKeys.eventos,
        docs,
        (d) => d.id,
      );

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultFeedLimit,
  }) {
    final churchId = _resolve(seedTenantId);
    final key = limit >= kGalleryLimit
        ? galleryCacheKey(churchId)
        : cacheKey(churchId, limit);
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return _withoutDeleted(churchId, hit.docs);
  }

  static void _putRam(
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return;
    // A chave começa sempre por `${churchId}_eventos_`.
    final churchId = key.split('_eventos_').first;
    _ram[key] = (
      docs: _withoutDeleted(churchId, List.from(docs)),
      at: DateTime.now(),
    );
  }

  static void putRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    int limit = kDefaultFeedLimit,
  }) {
    final id = _resolve(churchId);
    if (id.isEmpty || docs.isEmpty) return;
    final key = limit >= kGalleryLimit
        ? galleryCacheKey(id)
        : cacheKey(id, limit);
    _putRam(key, docs);
  }

  static DateTime? _startAt(Map<String, dynamic> data) {
    final raw = data['startAt'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByStartAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta =
          _startAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb =
          _startAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterRenderableFeed(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String churchId, {
    int? max,
  }) {
    final cap = max ?? kDefaultFeedLimit;
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      if (!PanelFeedPostValidator.isRenderableForPanelFeed(
        d.data(),
        docId: d.id,
        churchId: churchId,
      )) {
        continue;
      }
      out.add(d);
      if (out.length >= cap) break;
    }
    if (out.isNotEmpty) return out;
    // Fallback legado: quando o validador está mais rígido que os docs antigos,
    // mantém eventos sem `ativo/publicado=false` explícito para não esvaziar feed.
    return _filterPublishedLegacySafe(docs, max: cap);
  }

  static bool _isLegacyPublishedVisible(Map<String, dynamic> data) {
    if (data['ativo'] == false) return false;
    if (data['publicado'] == false) return false;
    return true;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterPublishedLegacySafe(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    int? max,
  }) {
    final cap = max ?? docs.length;
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      if (!_isLegacyPublishedVisible(d.data())) continue;
      out.add(d);
      if (out.length >= cap) break;
    }
    return out;
  }

  /// Feed principal — eventos publicados ordenados por `startAt` desc.
  static Future<ChurchEventosLoadResult> loadFeed({
    required String seedTenantId,
    int limit = kDefaultFeedLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    if (!kChurchEventosModuleEnabled) {
      final churchId = _resolve(seedTenantId);
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'eventos_module_removed',
        collectionPath:
            churchId.isEmpty ? 'eventos' : 'igrejas/$churchId/eventos',
      );
    }
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchEventosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'eventos',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/eventos';
    final ramKey = cacheKey(churchId, limit);

    // Cache-first: RAM/Hive antes do bootstrap Firebase (painel sem spinner).
    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId, limit: limit);
      if (ramHit != null) {
        unawaited(_refreshFeedInBackground(
          churchId: churchId,
          limit: limit,
          ramKey: ramKey,
        ));
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: ramHit.length > limit ? ramHit.sublist(0, limit) : ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _withoutDeleted(churchId, _sortByStartAt(mem.docs));
        _putRam(ramKey, docs);
        unawaited(_refreshFeedInBackground(
          churchId: churchId,
          limit: limit,
          ramKey: ramKey,
        ));
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: docs.length > limit ? docs.sublist(0, limit) : docs,
          readSource: 'firestore_mem',
          collectionPath: path,
          fromCache: true,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.eventos,
        ).timeout(const Duration(seconds: 2));
        if (hive.isNotEmpty) {
          final docs = _withoutDeleted(
            churchId,
            _sortByStartAt(TenantModuleHiveCache.toQueryDocuments(hive)),
          );
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            unawaited(_refreshFeedInBackground(
              churchId: churchId,
              limit: limit,
              ramKey: ramKey,
            ));
            return ChurchEventosLoadResult(
              churchId: churchId,
              docs: docs.length > limit ? docs.sublist(0, limit) : docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
        }
      } catch (e) {
        debugPrint('EVENTOS loadFeed hive cache failed: $e');
      }
    }

    try {
      await _ensureFirebaseForRead();
    } catch (e) {
      final ramFallback = peekRam(churchId, limit: limit);
      if (ramFallback != null) {
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: ramFallback.length > limit
              ? ramFallback.sublist(0, limit)
              : ramFallback,
          readSource: 'ram_firebase_not_ready',
          collectionPath: path,
          fromCache: true,
          softError: e.toString(),
        );
      }
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'firebase_not_ready',
        collectionPath: path,
        softError: e.toString(),
      );
    }

    if (!forceRefresh && !forceServer) {
      try {
        final cacheSnap = await ChurchUiCollections.eventos(churchId)
            .limit(limit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheSnap.docs.isNotEmpty) {
          final docs = _withoutDeleted(
            churchId,
            _sortByStartAt(cacheSnap.docs),
          );
          _putRam(ramKey, docs);
          unawaited(_refreshFeedInBackground(
            churchId: churchId,
            limit: limit,
            ramKey: ramKey,
          ));
          return ChurchEventosLoadResult(
            churchId: churchId,
            docs: docs.length > limit ? docs.sublist(0, limit) : docs,
            readSource: 'firestore_cache',
            collectionPath: path,
            fromCache: true,
          );
        }
      } catch (e) {
        debugPrint('EVENTOS loadFeed firestore cache failed: $e');
      }
    }

    Object? lastError;
    try {
      final docs = await _loadFirestoreFeed(
        churchId: churchId,
        limit: limit,
        cacheKey: ramKey,
        forceServer: forceServer,
      );
      if (docs.isNotEmpty) {
        var filtered = _filterRenderableFeed(docs, churchId, max: limit);
        if (filtered.isEmpty) {
          filtered = _filterPublishedLegacySafe(docs, max: limit);
        }
        filtered = _withoutDeleted(churchId, filtered);
        _putRam(ramKey, filtered);
        unawaited(_persistHive(churchId, filtered));
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: filtered,
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
        'eventos',
        moduleLabel: 'Eventos',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      if (snap.docs.isNotEmpty) {
        final docs = _withoutDeleted(
          churchId,
          _filterRenderableFeed(
            _sortByStartAt(snap.docs),
            churchId,
            max: limit,
          ),
        );
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchEventosLoadResult(
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
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: _withoutDeleted(churchId, _sortByStartAt(mem.docs)),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchEventosLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Demorou demais a carregar. Verifique a rede e toque em Tentar de novo.'
          : lastError?.toString(),
    );
  }

  /// Categorias de evento — `igrejas/{id}/event_categories`.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadEventCategories({
    required String seedTenantId,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return const [];

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((e) {
        debugPrint('EVENTOS categories ensurePanelReadReady failed: $e');
      });
    }

    final cacheKey = '${churchId}_event_categories';

    if (!kIsWeb) {
      try {
        final cacheSnap = await ChurchUiCollections.eventCategories(churchId)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheSnap.docs.isNotEmpty) {
          final list = cacheSnap.docs.toList()
            ..sort((a, b) => (a.data()['nome'] ?? '')
                .toString()
                .toLowerCase()
                .compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
          return list;
        }
      } catch (e) {
        debugPrint('EVENTOS categories cache read failed: $e');
      }
    }

    Future<QuerySnapshot<Map<String, dynamic>>> read() =>
        FirestoreReadResilience.getQuery(
          ChurchUiCollections.churchDoc(churchId).collection('event_categories'),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );

    QuerySnapshot<Map<String, dynamic>> snap;
    snap = await read().timeout(
      kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.warmCap,
    );

    final list = snap.docs.toList()
      ..sort((a, b) => (a.data()['nome'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
    return list;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreFeed({
    required String churchId,
    required int limit,
    required String cacheKey,
    required bool forceServer,
  }) async {
    final col = ChurchUiCollections.eventos(churchId);

    Query<Map<String, dynamic>> published() => col
        .where('ativo', isEqualTo: true)
        .where('publicado', isEqualTo: true)
        .orderBy('startAt', descending: true)
        .limit(limit);

    Query<Map<String, dynamic>> byStart() =>
        col.orderBy('startAt', descending: true).limit(limit);

    Query<Map<String, dynamic>> plain() => col.limit(limit);

    if (!forceServer) {
      try {
        final cacheSnap = await published()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByStartAt(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      // Preferir ordenação (startAt / publicado) — plain.limit sem orderBy
      // pode omitir o evento recém-criado quando a coleção tem muitos docs.
      try {
        return await FirestoreReadResilience.getQuery(
          published(),
          cacheKey: '${cacheKey}_pub',
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        try {
          return await FirestoreReadResilience.getQuery(
            byStart(),
            cacheKey: cacheKey,
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );
        } catch (e) {
          debugPrint('EVENTOS _loadFirestoreFeed ordered failed: $e');
        }
      }

      try {
        final plainSnap = await FirestoreReadResilience.getQuery(
          plain(),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        final strict =
            ChurchModuleFirestoreListRead.filterPublishedFeedRecords(
          plainSnap.docs,
        );
        final filtered = strict.isNotEmpty
            ? strict
            : _filterPublishedLegacySafe(plainSnap.docs, max: limit);
        if (filtered.isNotEmpty) {
          return MergedFirestoreQuerySnapshot(_sortByStartAt(filtered));
        }
      } catch (e) {
        debugPrint('EVENTOS _loadFirestoreFeed plain fallback failed: $e');
      }

      return FirestoreReadResilience.getQuery(
        plain(),
        cacheKey: '${cacheKey}_plain_retry',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
    }

    // Caminho direto — sem runWithWebRecovery (multiplicava timeouts / sync na Web).
    final snap = await readServer().timeout(
      kIsWeb
          ? const Duration(seconds: 12)
          : ChurchPanelReadTimeouts.warmCap,
    );

    final sorted = _sortByStartAt(snap.docs);
    if (sorted.isNotEmpty) return sorted;
    return _loadLegacyEventsEn(
      churchId: churchId,
      limit: limit,
      cacheKey: '${cacheKey}_legacy_en',
      forceServer: forceServer,
    );
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    try {
      // Nunca re-gravar no Hive um doc recém-excluído (lápide).
      final safeDocs = _withoutDeleted(churchId, docs);
      if (safeDocs.isEmpty) return;
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.eventos,
        MergedFirestoreQuerySnapshot(safeDocs),
      );
    } catch (_) {}
  }

  static Future<void> _refreshFeedInBackground({
    required String churchId,
    required int limit,
    required String ramKey,
  }) async {
    try {
      final docs = await _loadFirestoreFeed(
        churchId: churchId,
        // Painel: refresh no mesmo limite do feed — nunca 250 docs no hot path.
        limit: limit.clamp(1, 40),
        cacheKey: ramKey,
        forceServer: false,
      );
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        _putRam(galleryCacheKey(churchId), docs);
        unawaited(_persistHive(churchId, docs));
      }
    } catch (_) {}
  }

  /// Galeria — até [kGalleryLimit] eventos; query simples na web.
  static Future<ChurchEventosLoadResult> loadGallery({
    required String seedTenantId,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    if (!kChurchEventosModuleEnabled) {
      final churchId = _resolve(seedTenantId);
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'eventos_module_removed',
        collectionPath:
            churchId.isEmpty ? 'eventos' : 'igrejas/$churchId/eventos',
      );
    }
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchEventosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'eventos',
        softError: 'Igreja não identificada.',
      );
    }

    const limit = kGalleryLimit;
    final path = 'igrejas/$churchId/eventos';
    final ramKey = galleryCacheKey(churchId);

    try {
      await _ensureFirebaseForRead();
    } catch (e) {
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: const [],
        readSource: 'firebase_not_ready',
        collectionPath: path,
        softError: e.toString(),
      );
    }

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramKey);
      if (ramHit != null) {
        unawaited(_refreshGalleryInBackground(churchId: churchId, ramKey: ramKey));
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _withoutDeleted(churchId, _sortByStartAt(mem.docs));
        _putRam(ramKey, docs);
        return ChurchEventosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
          fromCache: true,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.eventos,
        ).timeout(const Duration(seconds: 2));
        if (hive.isNotEmpty) {
          final docs = _withoutDeleted(
            churchId,
            _sortByStartAt(TenantModuleHiveCache.toQueryDocuments(hive)),
          );
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            unawaited(_refreshGalleryInBackground(churchId: churchId, ramKey: ramKey));
            return ChurchEventosLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
        }
      } catch (_) {}

      try {
        final cacheSnap = await ChurchUiCollections.eventos(churchId)
            .limit(kGalleryLimit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheSnap.docs.isNotEmpty) {
          final docs = _withoutDeleted(
            churchId,
            _sortByStartAt(cacheSnap.docs),
          );
          _putRam(ramKey, docs);
          unawaited(_refreshGalleryInBackground(churchId: churchId, ramKey: ramKey));
          return ChurchEventosLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'firestore_cache',
            collectionPath: path,
            fromCache: true,
          );
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = _withoutDeleted(
        churchId,
        await _loadFirestoreGallery(
          churchId: churchId,
          cacheKey: ramKey,
          forceServer: forceServer,
        ),
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'eventos',
        moduleLabel: 'Eventos Galeria',
        limit: limit,
        cacheKey: '${ramKey}_direct',
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      final docs = _withoutDeleted(churchId, _sortByStartAt(snap.docs));
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_list',
        collectionPath: path,
      );
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchEventosLoadResult(
        churchId: churchId,
        docs: _withoutDeleted(churchId, _sortByStartAt(mem.docs)),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: lastError?.toString(),
      );
    }

    return ChurchEventosLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar galeria.'
          : lastError?.toString(),
    );
  }

  static Future<void> _refreshGalleryInBackground({
    required String churchId,
    required String ramKey,
  }) async {
    try {
      final docs = await _loadFirestoreGallery(
        churchId: churchId,
        cacheKey: ramKey,
        forceServer: false,
      );
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
      }
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreGallery({
    required String churchId,
    required String cacheKey,
    required bool forceServer,
  }) async {
    final col = ChurchUiCollections.eventos(churchId);
    const limit = kGalleryLimit;

    Query<Map<String, dynamic>> byStart() =>
        col.orderBy('startAt', descending: true).limit(limit);

    Query<Map<String, dynamic>> plain() => col.limit(limit);

    if (!forceServer) {
      try {
        final cacheSnap = await plain()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByStartAt(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainLoad() async {
      final plainSnap = await FirestoreReadResilience.getQuery(
        plain(),
        cacheKey: '${cacheKey}_plain',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      return _sortByStartAt(plainSnap.docs);
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readServer() async {
      try {
        final snap = await FirestoreReadResilience.getQuery(
          byStart(),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        return _sortByStartAt(snap.docs);
      } catch (_) {
        return plainLoad();
      }
    }

    if (kIsWeb) {
      try {
        final plain = await plainLoad().timeout(
          const Duration(seconds: 14),
        );
        if (plain.isNotEmpty) return plain;
      } catch (_) {}
    }

    final docs = await readServer().timeout(
      kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.warmCap,
    );

    if (docs.isEmpty) {
      try {
        return await plainLoad();
      } catch (_) {}
      return _loadLegacyEventsEn(
        churchId: churchId,
        limit: limit,
        cacheKey: '${cacheKey}_legacy_en',
        forceServer: forceServer,
      );
    }
    return docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadLegacyEventsEn({
    required String churchId,
    required int limit,
    required String cacheKey,
    required bool forceServer,
  }) async {
    final legacyCol =
        ChurchUiCollections.churchDoc(churchId).collection(_legacyEventsCollectionEn);
    Query<Map<String, dynamic>> plain() => legacyCol.limit(limit);
    Query<Map<String, dynamic>> byStart() =>
        legacyCol.orderBy('startAt', descending: true).limit(limit);

    if (!forceServer) {
      try {
        final cacheSnap = await plain()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 4));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByStartAt(cacheSnap.docs);
        }
      } catch (e) {
        debugPrint('EVENTOS legacy-events cache read failed: $e');
      }
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readServer() async {
      try {
        final snap = await FirestoreReadResilience.getQuery(
          byStart(),
          cacheKey: '${cacheKey}_start',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        if (snap.docs.isNotEmpty) return _sortByStartAt(snap.docs);
      } catch (e) {
        debugPrint('EVENTOS legacy-events orderBy(startAt) failed: $e');
      }
      final plainSnap = await FirestoreReadResilience.getQuery(
        plain(),
        cacheKey: '${cacheKey}_plain',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      return _sortByStartAt(plainSnap.docs);
    }

    return readServer().timeout(
      kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.warmCap,
    );
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRam(String key) {
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return _withoutDeleted(key.split('_eventos_').first, hit.docs);
  }

  /// Invalida TODAS as camadas: RAM + memória de resiliência + Hive.
  /// (Antes só limpava RAM — doc excluído voltava a partir do Hive.)
  static void invalidate(String seedTenantId) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith('${churchId.trim()}_eventos_'));
    for (final limit in [kDefaultFeedLimit, kGalleryLimit, 20, 30, 60, 80]) {
      FirestoreReadResilience.forgetKey(cacheKey(churchId, limit));
    }
    FirestoreReadResilience.forgetKey(galleryCacheKey(churchId));
    unawaited(
      TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.eventos),
    );
  }

  static void removeFromRam(String seedTenantId, Iterable<String> docIds) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    final ids = docIds.toSet();
    for (final key in _ram.keys.toList()) {
      if (!key.startsWith('${churchId.trim()}_eventos_')) continue;
      final hit = _ram[key];
      if (hit == null) continue;
      _ram[key] = (
        docs: hit.docs.where((d) => !ids.contains(d.id)).toList(),
        at: DateTime.now(),
      );
    }
  }

  static Future<void> persistAfterLoad(ChurchEventosLoadResult result) async {
    if (result.churchId.isEmpty || result.docs.isEmpty) return;
    putRam(
      result.churchId,
      result.docs,
      limit: result.docs.length >= kGalleryLimit
          ? kGalleryLimit
          : kDefaultFeedLimit,
    );
    await _persistHive(result.churchId, result.docs);
  }

  static Future<void> _deleteLegacyEventsMirror(
    String churchId,
    Iterable<String> docIds,
  ) async {
    try {
      final batch = ChurchRepository.batch();
      for (final id in docIds) {
        final tenant = firebaseDefaultFirestore
            .collection(ChurchDataPaths.rootCollection)
            .doc(churchId);
        batch.delete(
          tenant.collection(ChurchDataPaths.legacyEventosEn).doc(id),
        );
        batch.delete(
          tenant.collection(ChurchDataPaths.legacyEventosNoticias).doc(id),
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('EVENTOS legacy mirror delete: $e');
    }
  }

  /// Exclui um evento — Firestore + Storage (background) + cache RAM.
  static Future<void> deleteOne({
    required String churchIdHint,
    required String docId,
    Map<String, dynamic>? data,
  }) async {
    await deleteMany(
      churchIdHint: churchIdHint,
      docIds: [docId],
      dataById: data != null ? {docId: data} : const {},
    );
  }

  /// Exclusão em lote — Web: CF Admin SDK com fallback batch directo.
  static Future<int> deleteMany({
    required String churchIdHint,
    required Iterable<String> docIds,
    Map<String, Map<String, dynamic>> dataById = const {},
  }) async {
    final cid = _resolve(churchIdHint);
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cid.isEmpty || ids.isEmpty) return 0;

    // Lápide ANTES do delete — fecha corrida com refresh em background que
    // poderia re-gravar o doc antigo nas caches (RAM/Hive) e «ressuscitá-lo».
    TenantDeletedDocTombstones.mark(cid, TenantModuleKeys.eventos, ids);

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    final col = ChurchUiCollections.eventos(cid);
    const chunkSize = 450;

    for (var i = 0; i < ids.length; i += chunkSize) {
      final slice = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      await AdminFeedFirestoreBridge.deleteFeedPosts(
        churchId: cid,
        collection: 'eventos',
        docIds: slice,
        directDelete: () => FirestoreWebGuard.runWithWebRecovery(
          () async {
            final batch = ChurchRepository.batch();
            for (final id in slice) {
              batch.delete(col.doc(id));
            }
            await batch.commit();
          },
          maxAttempts: 4,
        ),
      );
      for (final id in slice) {
        ChurchCanonicalMediaDeleteService.scheduleFeedPostDeleted(
          tenantId: cid,
          postId: id,
          isEvento: true,
          data: dataById[id],
        );
      }
      unawaited(_deleteLegacyEventsMirror(cid, slice));
    }

    removeFromRam(cid, ids);
    invalidate(cid);
    return ids.length;
  }
}
