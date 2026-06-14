import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
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

  static const int kDefaultLimit = 120;

  /// Doc de kit — não é visitante; excluir de listagens e cache RAM.
  static const String kSchemaDocId = '_schema';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterVisitorDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.where((d) => d.id != kSchemaDocId).toList(growable: false);

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) =>
      ChurchRepository.churchId(hint.trim());

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
    final filtered = _filterVisitorDocs(docs);
    if (filtered.isEmpty) return;
    _ram[key] = (docs: List.from(filtered), at: DateTime.now());
  }

  static void putRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final id = _resolve(churchId);
    if (id.isEmpty) return;
    _putRam(cacheKey(id, kDefaultLimit), docs);
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
      if (ramHit != null && ramHit.isNotEmpty) {
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: limit,
        ));
        return ChurchVisitantesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByCreatedAt(_filterVisitorDocs(mem.docs));
        _putRam(ramKey, docs);
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: limit,
        ));
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
        ).timeout(const Duration(seconds: 2));
        final docs = _sortByCreatedAt(
          _filterVisitorDocs(TenantModuleHiveCache.toQueryDocuments(hive)),
        );
        if (docs.isNotEmpty) {
          _putRam(ramKey, docs);
          unawaited(_refreshInBackground(
            churchId: churchId,
            ramKey: ramKey,
            limit: limit,
          ));
          return ChurchVisitantesLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'hive',
            collectionPath: path,
          );
        }
      } catch (_) {}

      try {
        final cacheSnap = await ChurchUiCollections.visitantes(churchId)
            .limit(limit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        final docs = _sortByCreatedAt(_filterVisitorDocs(cacheSnap.docs));
        if (docs.isNotEmpty) {
          _putRam(ramKey, docs);
          unawaited(_refreshInBackground(
            churchId: churchId,
            ramKey: ramKey,
            limit: limit,
          ));
          return ChurchVisitantesLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'firestore_cache',
            collectionPath: path,
          );
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = _filterVisitorDocs(await _loadFirestore(
        churchId: churchId,
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: limit,
      ));
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
      }
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
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      final docs = _sortByCreatedAt(_filterVisitorDocs(snap.docs));
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
      }
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
        docs: _sortByCreatedAt(_filterVisitorDocs(mem.docs)),
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
    final filtered = _filterVisitorDocs(docs);
    if (filtered.isEmpty) return;
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.visitantes,
        MergedFirestoreQuerySnapshot(filtered),
      );
    } catch (_) {}
  }

  static Future<void> persistAfterLoad(ChurchVisitantesLoadResult result) async {
    if (result.churchId.isEmpty || result.docs.isEmpty) return;
    putRam(result.churchId, result.docs);
    await _persistHive(result.churchId, result.docs);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required String churchId,
    required String cacheKey,
    required bool forceServer,
    required int limit,
  }) async {
    final raw = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.visitantes(churchId),
      cacheKey: cacheKey,
      limit: limit,
      forceServer: forceServer,
      orderByField: 'createdAt',
      orderDescending: true,
      sortDocs: _sortByCreatedAt,
    );
    return _filterVisitorDocs(raw);
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required String ramKey,
    required int limit,
  }) async {
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        cacheKey: ramKey,
        forceServer: false,
        limit: limit,
      );
      if (docs.isEmpty) return;
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static void removeFromRam(String seedTenantId, Iterable<String> docIds) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    final ids = docIds.toSet();
    for (final key in _ram.keys.toList()) {
      if (!key.startsWith('${churchId}_visitantes_')) continue;
      final hit = _ram[key];
      if (hit == null) continue;
      _ram[key] = (
        docs: hit.docs.where((d) => !ids.contains(d.id)).toList(),
        at: DateTime.now(),
      );
    }
  }

  /// Gravação rápida — OptimisticFirestoreWrite (sem `ensurePanelReadReady` duplo).
  static Future<String> saveVisitor({
    required String churchId,
    required Map<String, dynamic> payload,
    String? existingDocId,
  }) async {
    final cid = _resolve(churchId);
    if (cid.isEmpty) throw StateError('Igreja não identificada.');

    final col = ChurchUiCollections.visitantes(cid);
    final data = ChurchTenantFields.stamp(cid, payload);

    if (existingDocId != null && existingDocId.trim().isNotEmpty) {
      final id = existingDocId.trim();
      await OptimisticFirestoreWrite.update(
        ref: col.doc(id),
        data: data,
        module: OfflineModules.visitantes,
        tenantId: cid,
      );
      return id;
    }

    final docRef = col.doc();
    final create = Map<String, dynamic>.from(data)
      ..putIfAbsent('status', () => 'Novo')
      ..putIfAbsent('followupCount', () => 0)
      ..['createdAt'] = FieldValue.serverTimestamp();

    await OptimisticFirestoreWrite.set(
      ref: docRef,
      data: create,
      module: OfflineModules.visitantes,
      tenantId: cid,
    );
    return docRef.id;
  }

  /// Exclui um ou vários visitantes num único batch (chunks de 450).
  static Future<int> deleteVisitors({
    required String seedTenantId,
    required Iterable<String> docIds,
  }) async {
    final churchId = _resolve(seedTenantId);
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty && id != '_schema')
        .toSet()
        .toList();
    if (ids.isEmpty || churchId.isEmpty) return 0;

    const chunkSize = 450;
    final col = ChurchUiCollections.visitantes(churchId);

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final slice = ids.sublist(i, end);
      final batch = ChurchRepository.batch();
      for (final id in slice) {
        batch.delete(col.doc(id));
      }
      await runFirestorePublishWithRecovery(
        () => batch.commit(),
        maxAttempts: kIsWeb ? 3 : 2,
      );
    }

    removeFromRam(churchId, ids);
    unawaited(invalidate(seedTenantId));
    return ids.length;
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

  /// Garante `igrejas/{churchId}/visitantes/_schema` — coleção visível no console + kit novas igrejas.
  static Future<void> ensureProvisioned(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;

    final schemaRef = ChurchUiCollections.visitantes(churchId).doc('_schema');
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final existing = await FirestoreWebGuard.runWithWebRecovery(
        () => schemaRef.get(),
        maxAttempts: 3,
      ).timeout(const Duration(seconds: 12));
      if (existing.exists) return;

      await FirestoreWebGuard.runWithWebRecovery(
        () => schemaRef.set(
          ChurchTenantFields.stamp(churchId, {
            'schemaVersion': 1,
            'firestorePath': 'igrejas/$churchId/visitantes',
            'isWelcomeKit': true,
            'provisionedAt': FieldValue.serverTimestamp(),
            'followupsSubcollection': 'followups',
          }),
          SetOptions(merge: true),
        ),
        maxAttempts: 4,
      );
    } catch (_) {}
  }
}
