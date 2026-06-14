import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de avisos — `igrejas/{churchId}/avisos`.
class ChurchAvisosLoadResult {
  const ChurchAvisosLoadResult({
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

/// Carga canónica — Firestore `igrejas/{id}/avisos`; mídia em Storage `igrejas/{id}/avisos/…`.
abstract final class ChurchAvisosLoadService {
  ChurchAvisosLoadService._();

  static const int kDefaultFeedLimit = 20;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_avisos_feed_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultFeedLimit,
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

  static DateTime? _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta =
          _createdAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb =
          _createdAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  /// Feed principal — avisos publicados ordenados por `createdAt` desc.
  static Future<ChurchAvisosLoadResult> loadFeed({
    required String seedTenantId,
    int limit = kDefaultFeedLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchAvisosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'avisos',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/avisos';
    final ramKey = cacheKey(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId, limit: limit);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchAvisosLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByCreatedAt(mem.docs);
        _putRam(ramKey, docs);
        return ChurchAvisosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.avisos,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final docs =
              _sortByCreatedAt(TenantModuleHiveCache.toQueryDocuments(hive));
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            return ChurchAvisosLoadResult(
              churchId: churchId,
              docs: docs.length > limit ? docs.sublist(0, limit) : docs,
              readSource: 'hive',
              collectionPath: path,
            );
          }
        }
      } catch (_) {}
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
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchAvisosLoadResult(
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
        'avisos',
        moduleLabel: 'Avisos',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        final docs = _sortByCreatedAt(snap.docs);
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchAvisosLoadResult(
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
      return ChurchAvisosLoadResult(
        churchId: churchId,
        docs: _sortByCreatedAt(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchAvisosLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar avisos.'
          : lastError?.toString(),
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreFeed({
    required String churchId,
    required int limit,
    required String cacheKey,
    required bool forceServer,
  }) async {
    final col = ChurchUiCollections.avisos(churchId);

    Query<Map<String, dynamic>> published() => col
        .where('ativo', isEqualTo: true)
        .where('publicado', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    Query<Map<String, dynamic>> byCreated() =>
        col.orderBy('createdAt', descending: true).limit(limit);

    Query<Map<String, dynamic>> plain() => col.limit(limit);

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    if (!forceServer) {
      try {
        final cacheSnap = await published()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByCreatedAt(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        final plainSnap = await FirestoreReadResilience.getQuery(
          plain(),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        final filtered = ChurchModuleFirestoreListRead.filterPublishedFeedRecords(
          plainSnap.docs,
        );
        if (filtered.isNotEmpty) {
          return MergedFirestoreQuerySnapshot(_sortByCreatedAt(filtered));
        }
      } catch (_) {}

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
            byCreated(),
            cacheKey: cacheKey,
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );
        } catch (_) {
          return FirestoreReadResilience.getQuery(
            plain(),
            cacheKey: '${cacheKey}_plain_retry',
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );
        }
      }
    }

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);

    return _sortByCreatedAt(snap.docs);
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.avisos,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }
}
