import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado — `igrejas/{churchId}/visitantes` (Web = Android = iOS).
class ChurchVisitantesLoadResult {
  const ChurchVisitantesLoadResult({
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

/// Carga canónica visitantes — path fixo `igrejas/{churchId}/visitantes`.
abstract final class ChurchVisitantesLoadService {
  ChurchVisitantesLoadService._();

  static const int kDefaultLimit = 400;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) =>
      ChurchPanelTenant.resolve(ChurchRepository.churchId(hint.trim()));

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_visitantes_$limit';

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
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static DateTime? _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _createdAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _createdAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  /// Lista visitantes — **nunca lança** (lista vazia = coleção ainda sem docs).
  static Future<ChurchVisitantesLoadResult> load({
    required String seedTenantId,
    int limit = kDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchVisitantesLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'visitantes',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/visitantes';
    final ramKey = cacheKey(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(seedTenantId, limit: limit);
      if (ramHit != null) {
        return ChurchVisitantesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _sortByCreatedAt(mem.docs);
        _putRam(ramKey, docs);
        return ChurchVisitantesLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.visitantes,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final docs = _sortByCreatedAt(
            TenantModuleHiveCache.toQueryDocuments(hive),
          );
          _putRam(ramKey, docs);
          return ChurchVisitantesLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'hive',
            collectionPath: path,
          );
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: limit,
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchVisitantesLoadResult(
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
        'visitantes',
        moduleLabel: 'Visitantes',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      final docs = _sortByCreatedAt(snap.docs);
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchVisitantesLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_list',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchVisitantesLoadResult(
        churchId: churchId,
        docs: _sortByCreatedAt(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: _formatSoftError(lastError),
      );
    }

    return ChurchVisitantesLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: _formatSoftError(lastError),
    );
  }

  static String? _formatSoftError(Object? error) {
    if (error == null) return null;
    if (error is TimeoutException) {
      return 'Tempo esgotado ao carregar visitantes.';
    }
    if (FirestoreWebGuard.isInternalAssertionError(error)) {
      return 'Firestore instável. Toque em Atualizar.';
    }
    final raw = error.toString();
    if (raw.length > 220) return '${raw.substring(0, 217)}…';
    return raw;
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.visitantes,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required String churchId,
    required String cacheKey,
    required bool forceServer,
    required int limit,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final col = ChurchUiCollections.visitantes(churchId);
    final ordered = col.orderBy('createdAt', descending: true).limit(limit);

    if (!forceServer) {
      try {
        final cacheSnap = await ordered
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 4));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByCreatedAt(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        return await FirestoreReadResilience.getQuery(
          ordered,
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        final plain = await FirestoreReadResilience.getQuery(
          col.limit(limit),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        return MergedFirestoreQuerySnapshot(_sortByCreatedAt(plain.docs));
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

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.visitantes,
    );
  }
}
