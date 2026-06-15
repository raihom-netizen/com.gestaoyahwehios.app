import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado — categorias `igrejas/{churchId}/event_categories`.
class ChurchEventCategoriesLoadResult {
  const ChurchEventCategoriesLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    this.softError,
    this.fromCache = false,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String? softError;
  final bool fromCache;

  bool get isEmpty => docs.isEmpty;
}

/// Carga cache-first — Novo Evento / Agenda / gestor de categorias.
abstract final class ChurchEventCategoriesLoadService {
  ChurchEventCategoriesLoadService._();

  static const Duration _ramTtl = Duration(minutes: 30);

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String cacheKey(String churchId) => '${churchId.trim()}_event_categories';

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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId,
  ) {
    final key = cacheKey(_resolve(seedTenantId));
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

  static void invalidate(String seedTenantId) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.remove(cacheKey(churchId));
    unawaited(
      TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.eventCategories),
    );
  }

  static Future<ChurchEventCategoriesLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchEventCategoriesLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    final ramKey = cacheKey(churchId);

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId);
      if (ramHit != null) {
        unawaited(_refreshInBackground(churchId: churchId, ramKey: ramKey));
        return ChurchEventCategoriesLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByNome(mem.docs);
        _putRam(ramKey, docs);
        unawaited(_refreshInBackground(churchId: churchId, ramKey: ramKey));
        return ChurchEventCategoriesLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          fromCache: true,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.eventCategories,
        ).timeout(const Duration(seconds: 2));
        if (hive.isNotEmpty) {
          final docs = _sortByNome(
            TenantModuleHiveCache.toQueryDocuments(hive),
          );
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            unawaited(_refreshInBackground(churchId: churchId, ramKey: ramKey));
            return ChurchEventCategoriesLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              fromCache: true,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadResilient(
        churchId: churchId,
        ramKey: ramKey,
        forceServer: forceServer,
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchEventCategoriesLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_plain',
      );
    } catch (e) {
      lastError = e;
    }

    final stale = peekRam(churchId);
    if (stale != null && stale.isNotEmpty) {
      return ChurchEventCategoriesLoadResult(
        churchId: churchId,
        docs: stale,
        readSource: 'ram_stale',
        fromCache: true,
        softError: lastError.toString(),
      );
    }

    return ChurchEventCategoriesLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'error',
      softError: lastError.toString(),
    );
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required String ramKey,
  }) async {
    try {
      final docs = await _loadResilient(
        churchId: churchId,
        ramKey: ramKey,
        forceServer: false,
      );
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadResilient({
    required String churchId,
    required String ramKey,
    required bool forceServer,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.eventCategories(churchId),
      cacheKey: ramKey,
      limit: 120,
      forceServer: forceServer,
      sortDocs: _sortByNome,
    );
  }

  static Future<void> _writeFast(Future<void> Function() write) async {
    await runFirestorePublishWithRecovery(
      write,
      maxAttempts: 2,
      criticalWrite: true,
    ).timeout(
      kIsWeb ? const Duration(seconds: 10) : const Duration(seconds: 15),
    );
  }

  static Future<void> refreshRamFromCache(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    try {
      final snap = await ChurchUiCollections.eventCategories(churchId)
          .limit(120)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (snap.docs.isEmpty) return;
      _putRam(cacheKey(churchId), _sortByNome(snap.docs));
    } catch (_) {}
  }

  static void removeFromRam(String seedTenantId, String docId) {
    final key = cacheKey(_resolve(seedTenantId));
    final hit = _ram[key];
    if (hit == null) return;
    _ram[key] = (
      docs: hit.docs.where((d) => d.id != docId).toList(),
      at: DateTime.now(),
    );
  }

  /// Cria categoria — escrita directa com timeout curto.
  static Future<String> saveCategory({
    required String seedTenantId,
    required String nome,
    required int colorValue,
  }) async {
    final churchId = _resolve(seedTenantId);
    final trimmed = nome.trim();
    if (churchId.isEmpty) throw StateError('Igreja não identificada.');
    if (trimmed.isEmpty) throw ArgumentError('Nome da categoria vazio.');

    final ref = ChurchUiCollections.eventCategories(churchId).doc();
    final payload = ChurchTenantFields.stamp(churchId, {
      'nome': trimmed,
      'cor': colorValue,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _writeFast(() => ref.set(payload));
    unawaited(refreshRamFromCache(churchId));
    unawaited(_persistHive(churchId, peekRam(churchId) ?? const []));
    return ref.id;
  }

  /// Remove categoria.
  static Future<void> deleteCategory({
    required String seedTenantId,
    required String docId,
  }) async {
    final churchId = _resolve(seedTenantId);
    final id = docId.trim();
    if (churchId.isEmpty || id.isEmpty) return;

    await _writeFast(
      () => ChurchUiCollections.eventCategories(churchId).doc(id).delete(),
    );
    removeFromRam(churchId, id);
    unawaited(refreshRamFromCache(churchId));
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.eventCategories,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }
}
