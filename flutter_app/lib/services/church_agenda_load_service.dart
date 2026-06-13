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

/// Carga canónica — Firestore `igrejas/{id}/agenda` por intervalo `startTime`.
abstract final class ChurchAgendaLoadService {
  ChurchAgendaLoadService._();

  static const int _plainFallbackLimit = 500;

  /// Pré-visualização síncrona — RAM por intervalo ou lista completa em cache.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekAnyRam(
    String seedTenantId, {
    Timestamp? start,
    Timestamp? end,
  }) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    if (start != null && end != null) {
      final ranged = peekRam(churchId, start: start, end: end);
      if (ranged != null && ranged.isNotEmpty) return ranged;
    }
    final prefix = '${churchId.trim()}_agenda_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    DateTime? bestAt;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (e.value.docs.isEmpty) continue;
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

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

  static String cacheKey(String churchId, Timestamp start, Timestamp end) =>
      '${churchId.trim()}_agenda_${start.seconds}_${end.seconds}';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    required Timestamp start,
    required Timestamp end,
  }) {
    final key = cacheKey(_resolve(seedTenantId), start, end);
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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterByRange(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Timestamp start,
    Timestamp end,
  ) {
    final startDate = start.toDate();
    final endDate = end.toDate();
    return docs.where((d) {
      final raw = d.data()['startTime'];
      if (raw is! Timestamp) return false;
      final dt = raw.toDate();
      return !dt.isBefore(startDate) && !dt.isAfter(endDate);
    }).toList();
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByStartTime(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = a.data()['startTime'];
      final tb = b.data()['startTime'];
      if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
      return 0;
    });
    return sorted;
  }

  static Future<ChurchAgendaLoadResult> loadByStartTimeRange({
    required String seedTenantId,
    required Timestamp start,
    required Timestamp end,
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
    final ramKey = cacheKey(churchId, start, end);

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId, start: start, end: end);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchAgendaLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByStartTime(mem.docs);
        _putRam(ramKey, docs);
        return ChurchAgendaLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.agenda,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final filtered = _sortByStartTime(
            _filterByRange(TenantModuleHiveCache.toQueryDocuments(hive), start, end),
          );
          if (filtered.isNotEmpty) {
            _putRam(ramKey, filtered);
            return ChurchAgendaLoadResult(
              churchId: churchId,
              docs: filtered,
              readSource: 'hive',
              collectionPath: path,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestoreRange(
        churchId: churchId,
        start: start,
        end: end,
        cacheKey: ramKey,
        forceServer: forceServer,
      );
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs));
        return ChurchAgendaLoadResult(
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
        'agenda',
        moduleLabel: 'Agenda',
        limit: _plainFallbackLimit,
        cacheKey: '${ramKey}_direct',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        final filtered = _sortByStartTime(_filterByRange(snap.docs, start, end));
        if (filtered.isNotEmpty) {
          _putRam(ramKey, filtered);
          unawaited(_persistHive(churchId, snap.docs));
          return ChurchAgendaLoadResult(
            churchId: churchId,
            docs: filtered,
            readSource: 'direct_list',
            collectionPath: path,
          );
        }
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchAgendaLoadResult(
        churchId: churchId,
        docs: _sortByStartTime(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchAgendaLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar agenda.'
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
        TenantModuleKeys.agenda,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestoreRange({
    required String churchId,
    required Timestamp start,
    required Timestamp end,
    required String cacheKey,
    required bool forceServer,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final col = ChurchUiCollections.agenda(churchId);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainLoad() async {
      final plain = await FirestoreReadResilience.getQuery(
        col.orderBy('startTime', descending: true).limit(_plainFallbackLimit),
        cacheKey: '${cacheKey}_plain_all',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      return _sortByStartTime(_filterByRange(plain.docs, start, end));
    }

    Query<Map<String, dynamic>> ranged() => col
        .where('startTime', isGreaterThanOrEqualTo: start)
        .where('startTime', isLessThanOrEqualTo: end);

    if (!forceServer) {
      try {
        final cacheSnap = await col
            .orderBy('startTime', descending: true)
            .limit(_plainFallbackLimit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          final filtered = _filterByRange(cacheSnap.docs, start, end);
          if (filtered.isNotEmpty) {
            return _sortByStartTime(filtered);
          }
        }
      } catch (_) {}
    }

    if (kIsWeb && !forceServer) {
      try {
        final filtered = await FirestoreWebGuard.runWithWebRecovery(
          plainLoad,
          maxAttempts: 4,
        ).timeout(ChurchPanelReadTimeouts.queryCap);
        if (filtered.isNotEmpty) return filtered;
      } catch (_) {}
    }

    if (!forceServer) {
      try {
        final cacheSnap = await ranged()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByStartTime(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        return await FirestoreReadResilience.getQuery(
          ranged(),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        return MergedFirestoreQuerySnapshot(await plainLoad());
      }
    }

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);

    final docs = _sortByStartTime(snap.docs);
    if (docs.isEmpty) {
      try {
        return await plainLoad();
      } catch (_) {}
    }
    return docs;
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(churchId, TenantModuleKeys.agenda);
  }
}
