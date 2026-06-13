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

/// Resultado — membros pendentes `igrejas/{churchId}/membros`.
class ChurchAprovacoesPendentesResult {
  const ChurchAprovacoesPendentesResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String? softError;

  bool get isEmpty => docs.isEmpty;
}

/// Histórico de aprovações / reprovações no período.
class ChurchAprovacoesHistoricoResult {
  const ChurchAprovacoesHistoricoResult({
    required this.churchId,
    required this.approved,
    required this.rejected,
    required this.readSource,
    required this.rangeStart,
    required this.rangeEnd,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> approved;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> rejected;
  final String readSource;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String? softError;
}

/// Carga canónica — Aprovações rápidas (membros pendentes + histórico).
abstract final class ChurchAprovacoesLoadService {
  ChurchAprovacoesLoadService._();

  static const int kPendentesLimit = 120;
  static const int kHistoricoPlainLimit = 500;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _pendentesRam = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

  static String pendentesCacheKey(String churchId) =>
      '${churchId.trim()}_membros_pendente_v2';

  static String historicoCacheKey(String churchId, DateTime start, DateTime end) =>
      '${churchId.trim()}_aprov_hist_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}';

  static String _statusNorm(Map<String, dynamic> data) =>
      (data['status'] ?? data['STATUS'] ?? '').toString().trim().toLowerCase();

  static bool isPendente(Map<String, dynamic> data) =>
      _statusNorm(data) == 'pendente';

  static DateTime? _tsField(Map<String, dynamic> data, String key) {
    final raw = data[key];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekPendentesRam(
    String seedTenantId,
  ) {
    final key = _resolve(seedTenantId);
    if (key.isEmpty) return null;
    final hit = _pendentesRam[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _pendentesRam.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void _putPendentesRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (churchId.isEmpty) return;
    _pendentesRam[churchId] = (docs: List.from(docs), at: DateTime.now());
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterPendentes(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.where((d) => isPendente(d.data())).toList();

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByNome(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    });
    return sorted;
  }

  static Future<ChurchAprovacoesPendentesResult> loadPendentes({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchAprovacoesPendentesResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    final ramKey = pendentesCacheKey(churchId);

    if (!forceRefresh) {
      final ram = peekPendentesRam(churchId);
      if (ram != null) {
        return ChurchAprovacoesPendentesResult(
          churchId: churchId,
          docs: ram,
          readSource: 'ram',
        );
      }
      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByNome(_filterPendentes(mem.docs));
        _putPendentesRam(churchId, docs);
        return ChurchAprovacoesPendentesResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
        );
      }
      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.membros,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          final docs = _sortByNome(
            _filterPendentes(TenantModuleHiveCache.toQueryDocuments(hive)),
          );
          if (docs.isNotEmpty) {
            _putPendentesRam(churchId, docs);
            return ChurchAprovacoesPendentesResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadPendentesFirestore(churchId, ramKey);
      _putPendentesRam(churchId, docs);
      return ChurchAprovacoesPendentesResult(
        churchId: churchId,
        docs: docs,
        readSource: 'firestore',
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'membros',
        moduleLabel: 'Aprovações',
        limit: kHistoricoPlainLimit,
        cacheKey: '${ramKey}_direct',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      final docs = _sortByNome(_filterPendentes(snap.docs));
      if (docs.isNotEmpty) {
        _putPendentesRam(churchId, docs);
        return ChurchAprovacoesPendentesResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchAprovacoesPendentesResult(
        churchId: churchId,
        docs: _sortByNome(_filterPendentes(mem.docs)),
        readSource: 'fallback_mem',
        softError: lastError?.toString(),
      );
    }

    return ChurchAprovacoesPendentesResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar pendentes.'
          : lastError?.toString(),
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadPendentesFirestore(String churchId, String cacheKey) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final col = ChurchUiCollections.membros(churchId);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainLoad() async {
      final plain = await FirestoreReadResilience.getQuery(
        col.limit(kHistoricoPlainLimit),
        cacheKey: '${cacheKey}_plain',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      return _sortByNome(_filterPendentes(plain.docs));
    }

    if (kIsWeb) {
      return FirestoreWebGuard.runWithWebRecovery(
        plainLoad,
        maxAttempts: 4,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
    }

    try {
      final snap = await FirestoreReadResilience.getQuery(
        col.where('status', isEqualTo: 'pendente').limit(kPendentesLimit),
        cacheKey: cacheKey,
        maxAttempts: 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      if (snap.docs.isNotEmpty) return _sortByNome(snap.docs);
    } catch (_) {}

    return plainLoad();
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterHistorico(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String status,
    required String tsField,
    required DateTime start,
    required DateTime end,
  }) {
    return docs.where((d) {
      final data = d.data();
      if (_statusNorm(data) != status) return false;
      final dt = _tsField(data, tsField);
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList()
      ..sort((a, b) {
        final ta = _tsField(a.data(), tsField) ?? DateTime(1970);
        final tb = _tsField(b.data(), tsField) ?? DateTime(1970);
        return tb.compareTo(ta);
      });
  }

  static Future<ChurchAprovacoesHistoricoResult> loadHistorico({
    required String seedTenantId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool forceRefresh = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    final start = rangeStart;
    final end = rangeEnd;
    if (churchId.isEmpty) {
      return ChurchAprovacoesHistoricoResult(
        churchId: '',
        approved: const [],
        rejected: const [],
        readSource: 'empty_id',
        rangeStart: start,
        rangeEnd: end,
        softError: 'Igreja não identificada.',
      );
    }

    final cacheKey = historicoCacheKey(churchId, start, end);
    if (!forceRefresh) {
      final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final approved = _filterHistorico(
          mem.docs,
          status: 'ativo',
          tsField: 'aprovadoEm',
          start: start,
          end: end,
        );
        final rejected = _filterHistorico(
          mem.docs,
          status: 'reprovado',
          tsField: 'reprovadoEm',
          start: start,
          end: end,
        );
        if (approved.isNotEmpty || rejected.isNotEmpty) {
          return ChurchAprovacoesHistoricoResult(
            churchId: churchId,
            approved: approved,
            rejected: rejected,
            readSource: 'firestore_mem',
            rangeStart: start,
            rangeEnd: end,
          );
        }
      }
    }

    Object? lastError;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = const [];

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final col = ChurchUiCollections.membros(churchId);
    final t0 = Timestamp.fromDate(start);
    final t1 = Timestamp.fromDate(end);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainAll() async {
      Future<QuerySnapshot<Map<String, dynamic>>> read() =>
          FirestoreReadResilience.getQuery(
            col.limit(kHistoricoPlainLimit),
            cacheKey: '${cacheKey}_plain',
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );

      final snap = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(read, maxAttempts: 4)
          : await read();
      return snap.docs;
    }

    try {
      allDocs = await plainAll().timeout(ChurchPanelReadTimeouts.queryCap);
    } catch (e) {
      lastError = e;
      try {
        final snap = await IgrejaDirectFirestoreReads.listSubcollection(
          churchId,
          'membros',
          moduleLabel: 'Aprovações histórico',
          limit: kHistoricoPlainLimit,
          cacheKey: '${cacheKey}_direct',
        ).timeout(ChurchPanelReadTimeouts.queryCap);
        allDocs = snap.docs;
      } catch (e2) {
        lastError ??= e2;
      }
    }

    if (allDocs.isEmpty) {
      return ChurchAprovacoesHistoricoResult(
        churchId: churchId,
        approved: const [],
        rejected: const [],
        readSource: 'empty',
        rangeStart: start,
        rangeEnd: end,
        softError: lastError?.toString(),
      );
    }

    var approved = _filterHistorico(
      allDocs,
      status: 'ativo',
      tsField: 'aprovadoEm',
      start: start,
      end: end,
    );
    var rejected = _filterHistorico(
      allDocs,
      status: 'reprovado',
      tsField: 'reprovadoEm',
      start: start,
      end: end,
    );

    if (approved.isEmpty && rejected.isEmpty) {
      try {
        final aSnap = await FirestoreWebGuard.runWithWebRecovery(
          () => col
              .where('status', isEqualTo: 'ativo')
              .where('aprovadoEm', isGreaterThanOrEqualTo: t0)
              .where('aprovadoEm', isLessThanOrEqualTo: t1)
              .orderBy('aprovadoEm', descending: true)
              .limit(400)
              .get(),
          maxAttempts: 3,
        );
        approved = aSnap.docs;
      } catch (_) {}

      try {
        final rSnap = await FirestoreWebGuard.runWithWebRecovery(
          () => col
              .where('status', isEqualTo: 'reprovado')
              .where('reprovadoEm', isGreaterThanOrEqualTo: t0)
              .where('reprovadoEm', isLessThanOrEqualTo: t1)
              .orderBy('reprovadoEm', descending: true)
              .limit(200)
              .get(),
          maxAttempts: 3,
        );
        rejected = rSnap.docs;
      } catch (_) {}
    }


    return ChurchAprovacoesHistoricoResult(
      churchId: churchId,
      approved: approved,
      rejected: rejected,
      readSource: 'firestore',
      rangeStart: start,
      rangeEnd: end,
      softError: lastError?.toString(),
    );
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _pendentesRam.remove(churchId);
  }
}
