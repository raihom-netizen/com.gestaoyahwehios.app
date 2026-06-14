import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Resultado da carga agenda — `igrejas/{churchId}/agenda`.
class ChurchAgendaLoadResult {
  const ChurchAgendaLoadResult({
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

/// Carga canónica — Firestore `igrejas/{id}/agenda`.
abstract final class ChurchAgendaLoadService {
  ChurchAgendaLoadService._();

  static const int plainFallbackLimit = 500;

  static const int _plainFallbackLimit = plainFallbackLimit;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String cacheKeyAll(String churchId, int limit) =>
      '${churchId.trim()}_agenda_all_$limit';

  static String cacheKey(String churchId, Timestamp start, Timestamp end) =>
      '${churchId.trim()}_agenda_${start.seconds}_${end.seconds}';

  /// Extrai timestamp canónico — suporta campos legados (`data`, `date`, strings BR).
  static Timestamp? docStartTimestamp(Map<String, dynamic> data) =>
      AgendaFirestoreFields.parseTimestamp(data);

  /// Pré-visualização síncrona — lista completa ou intervalo filtrado.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekAnyRam(
    String seedTenantId, {
    Timestamp? start,
    Timestamp? end,
  }) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;

    final allKey = cacheKeyAll(churchId, _plainFallbackLimit);
    final allHit = _peekRamEntry(allKey);
    if (allHit != null) {
      if (start != null && end != null) {
        final filtered = _filterByRange(allHit, start, end);
        return filtered.isNotEmpty ? filtered : allHit;
      }
      return allHit;
    }

    if (start != null && end != null) {
      final ranged = peekRam(churchId, start: start, end: end);
      if (ranged != null) return ranged;
    }

    final prefix = '${churchId.trim()}_agenda_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    DateTime? bestAt;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (bestAt == null || e.value.at.isAfter(bestAt)) {
        best = e.value.docs;
        bestAt = e.value.at;
      }
    }
    if (best == null) return null;
    if (start != null && end != null) {
      final filtered = _filterByRange(best, start, end);
      return filtered.isNotEmpty ? filtered : best;
    }
    return best;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    required Timestamp start,
    required Timestamp end,
  }) {
    final key = cacheKey(_resolve(seedTenantId), start, end);
    return _peekRamEntry(key);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRamEntry(
    String key,
  ) {
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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterByRange(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Timestamp start,
    Timestamp end,
  ) {
    final startDate = start.toDate();
    final endDate = end.toDate();
    return docs.where((d) {
      final ts = docStartTimestamp(d.data());
      if (ts == null) return false;
      final dt = ts.toDate();
      return !dt.isBefore(startDate) && !dt.isAfter(endDate);
    }).toList();
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByStartTime(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort(AgendaFirestoreFields.compareDateAsc);
    return sorted;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filterActiveDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .where((d) => ChurchModuleFirestoreListRead.isActiveRecord(d.data()))
          .toList(growable: false);

  /// Lista completa da agenda — cache-first; filtro por mês na UI.
  static Future<ChurchAgendaLoadResult> loadAll({
    required String seedTenantId,
    int limit = _plainFallbackLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchAgendaLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'agenda',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/agenda';
    final ramKey = cacheKeyAll(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRamEntry(ramKey);
      if (ramHit != null) {
        unawaited(_refreshAllInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: limit,
        ));
        return ChurchAgendaLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram_all',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _sortByStartTime(mem.docs);
        _putRam(ramKey, docs);
        return ChurchAgendaLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem_all',
          collectionPath: path,
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          TenantModuleKeys.agenda,
        ).timeout(const Duration(seconds: 4));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(
            churchId,
            TenantModuleKeys.agenda,
          );
          final docs = _sortByStartTime(
            TenantModuleHiveCache.toQueryDocuments(hive),
          );
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramKey, docs);
            unawaited(_refreshAllInBackground(
              churchId: churchId,
              ramKey: ramKey,
              limit: limit,
            ));
            return ChurchAgendaLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive_all',
              collectionPath: path,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestoreAll(
        churchId: churchId,
        cacheKey: ramKey,
        limit: limit,
        forceServer: forceServer,
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchAgendaLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server_all' : 'firestore_all',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'agenda',
        moduleLabel: 'Agenda',
        limit: limit,
        cacheKey: '${ramKey}_direct',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      final docs = _sortByStartTime(snap.docs);
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchAgendaLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_list_all',
        collectionPath: path,
      );
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.agenda.listCacheFirst(
        churchIdHint: churchId,
        limit: limit,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        final docs = _sortByStartTime(repo.items);
        _putRam(ramKey, docs);
        return ChurchAgendaLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchAgendaLoadResult(
        churchId: churchId,
        docs: _sortByStartTime(mem.docs),
        readSource: 'fallback_mem_all',
        collectionPath: path,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = _peekRamEntry(ramKey);
    if (ramFallback != null) {
      return ChurchAgendaLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback_all',
        collectionPath: path,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchAgendaLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: _humanizeError(lastError),
    );
  }

  static Future<ChurchAgendaLoadResult> loadByStartTimeRange({
    required String seedTenantId,
    required Timestamp start,
    required Timestamp end,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final all = await loadAll(
      seedTenantId: seedTenantId,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    final filtered = _sortByStartTime(_filterByRange(all.docs, start, end));
    final churchId = all.churchId;
    final path = all.collectionPath;
    if (filtered.isNotEmpty) {
      _putRam(cacheKey(churchId, start, end), filtered);
    }
    return ChurchAgendaLoadResult(
      churchId: churchId,
      docs: filtered,
      readSource: filtered.isEmpty && all.docs.isNotEmpty
          ? '${all.readSource}_filtered_empty'
          : all.readSource,
      collectionPath: path,
      softError: filtered.isEmpty ? all.softError : null,
    );
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar agenda. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  static Future<void> _refreshAllInBackground({
    required String churchId,
    required String ramKey,
    required int limit,
  }) async {
    try {
      final docs = await _loadFirestoreAll(
        churchId: churchId,
        cacheKey: ramKey,
        limit: limit,
        forceServer: false,
      );
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.agenda,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreAll({
    required String churchId,
    required String cacheKey,
    required int limit,
    required bool forceServer,
  }) async {
    final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.agenda(churchId),
      cacheKey: cacheKey,
      limit: limit,
      forceServer: forceServer,
      orderByField: 'startTime',
      orderDescending: false,
      sortDocs: _sortByStartTime,
    );
    return docs;
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.agenda);
  }
}
