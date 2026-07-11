import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/auth_gate_member_active.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado — membros pendentes `igrejas/{churchId}/membros`.
class ChurchAprovacoesPendentesResult {
  const ChurchAprovacoesPendentesResult({
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
  bool get hasHardError => softError != null && softError!.trim().isNotEmpty;
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

/// Carga canónica — Aprovações rápidas (`igrejas/{churchId}/membros`).
///
/// **Regra:** lista vazia de pendentes = sucesso (não erro de rede).
/// Cache Hive / RAM / memória Firestore sempre aceite, mesmo com 0 pendentes.
abstract final class ChurchAprovacoesLoadService {
  ChurchAprovacoesLoadService._();

  static const int kMembrosScanLimit = 800;
  static const int kPendentesQueryLimit = 120;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _pendentesRam = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) =>
      ChurchPanelTenant.forFirestore(hint.trim());

  /// Path canónico — `igrejas/{churchId}/membros` (filtro `status=pendente`).
  static String firestoreMembrosPath(String seedTenantId) {
    final id = _resolve(seedTenantId);
    return id.isEmpty ? '' : 'igrejas/$id/membros';
  }

  static String pendentesCacheKey(String churchId) =>
      '${churchId.trim()}_membros_pendente_v3';

  static String historicoCacheKey(String churchId, DateTime start, DateTime end) =>
      '${churchId.trim()}_aprov_hist_${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}';

  static String _statusNorm(Map<String, dynamic> data) =>
      (data['status'] ?? data['STATUS'] ?? '').toString().trim().toLowerCase();

  static bool isPendente(Map<String, dynamic> data) =>
      authGateMemberDocIsPending(data);

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

  static bool hasPendentesRam(String seedTenantId) {
    final key = _resolve(seedTenantId);
    if (key.isEmpty) return false;
    final hit = _pendentesRam[key];
    if (hit == null) return false;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _pendentesRam.remove(key);
      return false;
    }
    return true;
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

  static ChurchAprovacoesPendentesResult _ok({
    required String churchId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    required String readSource,
    bool fromCache = false,
    String? softError,
  }) {
    final docs = _sortByNome(_filterPendentes(allDocs));
    _putPendentesRam(churchId, docs);
    return ChurchAprovacoesPendentesResult(
      churchId: churchId,
      docs: docs,
      readSource: readSource,
      fromCache: fromCache,
      softError: softError,
    );
  }

  /// Instantâneo RAM / memória / módulo Membros — abertura sem skeleton quando possível.
  static ChurchAprovacoesPendentesResult? peekInstant(String seedTenantId) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    final ram = peekPendentesRam(churchId);
    if (ram != null) {
      return ChurchAprovacoesPendentesResult(
        churchId: churchId,
        docs: ram,
        readSource: 'ram',
        fromCache: true,
      );
    }
    final mem = FirestoreReadResilience.peekLastGoodQuery(
      pendentesCacheKey(churchId),
    );
    if (mem != null) {
      return _ok(
        churchId: churchId,
        allDocs: mem.docs,
        readSource: 'firestore_mem',
        fromCache: true,
      );
    }
    final membrosRam = ChurchMembersLoadService.peekRamAny(churchId);
    if (membrosRam != null) {
      return _ok(
        churchId: churchId,
        allDocs: membrosRam,
        readSource: 'membros_ram',
        fromCache: true,
      );
    }
    return null;
  }

  /// Aquecimento silencioso (dashboard / troca de aba) — não bloqueia UI.
  static Future<void> warmPendentes(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    try {
      await loadPendentes(seedTenantId: churchId, forceRefresh: false);
    } catch (_) {}
  }

  /// Só caches locais — retorna mesmo com 0 pendentes (sucesso).
  static Future<ChurchAprovacoesPendentesResult?> tryLocalCachesOnly(
    String seedTenantId,
  ) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    return _tryLocalCaches(churchId);
  }

  /// Cache local (RAM → Hive → mem Firestore) — **0 pendentes também é válido**.
  static Future<ChurchAprovacoesPendentesResult?> _tryLocalCaches(
    String churchId,
  ) async {
    final ram = peekPendentesRam(churchId);
    if (ram != null) {
      return ChurchAprovacoesPendentesResult(
        churchId: churchId,
        docs: ram,
        readSource: 'ram',
        fromCache: true,
      );
    }

    final memKey = pendentesCacheKey(churchId);
    final mem = FirestoreReadResilience.peekLastGoodQuery(memKey);
    if (mem != null) {
      return _ok(
        churchId: churchId,
        allDocs: mem.docs,
        readSource: 'firestore_mem',
        fromCache: true,
      );
    }

    final membrosRam = ChurchMembersLoadService.peekRamAny(churchId);
    if (membrosRam != null) {
      return _ok(
        churchId: churchId,
        allDocs: membrosRam,
        readSource: 'membros_ram',
        fromCache: true,
      );
    }

    try {
      final hive = await TenantModuleHiveCache.readDocs(
        churchId,
        TenantModuleKeys.membros,
      ).timeout(const Duration(seconds: 2));
      if (hive.isNotEmpty) {
        return _ok(
          churchId: churchId,
          allDocs: TenantModuleHiveCache.toQueryDocuments(hive),
          readSource: 'hive',
          fromCache: true,
        );
      }
    } catch (_) {}

    try {
      final cacheSnap = await ChurchUiCollections.membros(churchId)
          .limit(kMembrosScanLimit)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheSnap.docs.isNotEmpty) {
        return _ok(
          churchId: churchId,
          allDocs: cacheSnap.docs,
          readSource: 'firestore_cache',
          fromCache: true,
        );
      }
    } catch (_) {}

    return null;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchMembrosScan(String churchId, String cacheKey) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final result = await ChurchRepository.listCacheFirst(
      module: ChurchRepository.membros,
      churchIdHint: churchId,
      limit: kMembrosScanLimit,
      firestoreCacheKey: cacheKey,
    );

    if (result.items.isNotEmpty) return result.items;
    if (result.error == null) return result.items;

    final col = ChurchUiCollections.membros(churchId);
    Future<QuerySnapshot<Map<String, dynamic>>> readPlain() =>
        FirestoreReadResilience.getQuery(
          col.limit(kMembrosScanLimit),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readPlain,
            maxAttempts: 4,
          ).timeout(const Duration(seconds: 14))
        : await readPlain().timeout(ChurchPanelReadTimeouts.warmCap);

    return snap.docs;
  }

  /// Pendentes — query indexada em `igrejas/{churchId}/membros` + varredura fallback.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchPendentesNetwork(String churchId, String cacheKey) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final col = ChurchUiCollections.membros(churchId);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var queriesSucceeded = 0;

    Future<void> mergeQuery(
      Query<Map<String, dynamic>> q,
      String subKey,
    ) async {
      Future<QuerySnapshot<Map<String, dynamic>>> read() =>
          FirestoreReadResilience.getQuery(
            q,
            cacheKey: '${cacheKey}_$subKey',
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );
      try {
        final snap = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                read,
                maxAttempts: 4,
              ).timeout(const Duration(seconds: 14))
            : await read().timeout(ChurchPanelReadTimeouts.queryCap);
        queriesSucceeded++;
        for (final d in snap.docs) {
          byId[d.id] = d;
        }
      } catch (_) {}
    }

    // Paralelo — antes eram 3 round-trips sequenciais (+ scan 800 se vazio).
    await Future.wait([
      mergeQuery(
        col.where('status', isEqualTo: 'pendente').limit(kPendentesQueryLimit),
        'status_lc',
      ),
      mergeQuery(
        col.where('STATUS', isEqualTo: 'pendente').limit(kPendentesQueryLimit),
        'status_uc',
      ),
      mergeQuery(
        col
            .where('PUBLIC_SIGNUP', isEqualTo: true)
            .limit(kPendentesQueryLimit),
        'public_signup',
      ),
    ]);

    final fromQueries =
        byId.values.where((d) => isPendente(d.data())).toList();

    // Lista vazia após queries OK = sucesso (não varrer 800 membros).
    if (queriesSucceeded > 0) return fromQueries;

    // Cache local antes do scan pesado (800 docs).
    try {
      final cacheSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => col
            .limit(kMembrosScanLimit)
            .get(const GetOptions(source: Source.cache)),
        maxAttempts: 2,
      ).timeout(const Duration(seconds: 4));
      if (cacheSnap.docs.isNotEmpty) {
        return _filterPendentes(cacheSnap.docs);
      }
    } catch (_) {}

    try {
      final repo = await ChurchRepository.listCacheFirst(
        module: ChurchRepository.membros,
        churchIdHint: churchId,
        limit: kMembrosScanLimit,
        firestoreCacheKey: cacheKey,
      );
      if (repo.items.isNotEmpty) {
        return _filterPendentes(repo.items);
      }
    } catch (_) {}

    // Fallback legado — só se queries + cache falharam.
    final allDocs = await _fetchMembrosScan(churchId, cacheKey);
    return _filterPendentes(allDocs);
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

    final cacheKey = pendentesCacheKey(churchId);

    if (!forceRefresh) {
      final local = await _tryLocalCaches(churchId);
      if (local != null) {
        unawaited(_refreshPendentesInBackground(churchId, cacheKey));
        return local;
      }
    }

    Object? lastError;
    try {
      final allDocs = await _fetchPendentesNetwork(churchId, cacheKey).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      return _ok(
        churchId: churchId,
        allDocs: allDocs,
        readSource: 'network',
      );
    } catch (e) {
      lastError = e;
    }

    final fallback = await _tryLocalCaches(churchId);
    if (fallback != null) {
      return ChurchAprovacoesPendentesResult(
        churchId: churchId,
        docs: fallback.docs,
        readSource: '${fallback.readSource}_fallback',
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchAprovacoesPendentesResult(
      churchId: churchId,
      docs: const [],
      readSource: 'failed',
      softError: _humanizeError(lastError),
    );
  }

  static Future<void> _refreshPendentesInBackground(
    String churchId,
    String cacheKey,
  ) async {
    try {
      final allDocs = await _fetchPendentesNetwork(churchId, cacheKey).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      _ok(churchId: churchId, allDocs: allDocs, readSource: 'background');
    } catch (_) {}
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar. Verifique a conexão e tente novamente.';
    }
    final s = e.toString();
    if (s.contains('permission-denied')) {
      return 'Sem permissão para ver cadastros pendentes.';
    }
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
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
      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.membros,
        ).timeout(const Duration(seconds: 3));
        if (hive.isNotEmpty) {
          final hiveDocs = TenantModuleHiveCache.toQueryDocuments(hive);
          final approved = _filterHistorico(
            hiveDocs,
            status: 'ativo',
            tsField: 'aprovadoEm',
            start: start,
            end: end,
          );
          final rejected = _filterHistorico(
            hiveDocs,
            status: 'reprovado',
            tsField: 'reprovadoEm',
            start: start,
            end: end,
          );
          return ChurchAprovacoesHistoricoResult(
            churchId: churchId,
            approved: approved,
            rejected: rejected,
            readSource: 'hive',
            rangeStart: start,
            rangeEnd: end,
          );
        }
      } catch (_) {}

      final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey);
      if (mem != null) {
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

    Object? lastError;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = const [];

    try {
      allDocs = await _fetchMembrosScan(churchId, cacheKey)
          .timeout(ChurchPanelReadTimeouts.queryCap);
    } catch (e) {
      lastError = e;
    }

    if (allDocs.isEmpty) {
      return ChurchAprovacoesHistoricoResult(
        churchId: churchId,
        approved: const [],
        rejected: const [],
        readSource: 'empty',
        rangeStart: start,
        rangeEnd: end,
        softError: _humanizeError(lastError),
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

    if (approved.isEmpty && rejected.isEmpty && kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      final col = ChurchUiCollections.membros(churchId);
      final t0 = Timestamp.fromDate(start);
      final t1 = Timestamp.fromDate(end);
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
      readSource: 'network',
      rangeStart: start,
      rangeEnd: end,
      softError: lastError != null ? _humanizeError(lastError) : null,
    );
  }

  static void removePendentesFromRam(String seedTenantId, Iterable<String> docIds) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    final ids = docIds.toSet();
    final hit = _pendentesRam[churchId];
    if (hit == null) return;
    _pendentesRam[churchId] = (
      docs: hit.docs.where((d) => !ids.contains(d.id)).toList(),
      at: DateTime.now(),
    );
  }

  static Future<int> deleteMembros({
    required String seedTenantId,
    required Iterable<String> docIds,
  }) async {
    final churchId = _resolve(seedTenantId);
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || churchId.isEmpty) return 0;

    const chunkSize = 450;
    final col = ChurchUiCollections.membros(churchId);

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final slice = ids.sublist(i, end);
      await runFirestorePublishWithRecovery(
        () async {
          final batch = ChurchRepository.batch();
          for (final id in slice) {
            batch.delete(col.doc(id));
          }
          await batch.commit();
        },
        maxAttempts: kIsWeb ? 3 : 2,
      );
    }

    removePendentesFromRam(churchId, ids);
    await invalidate(seedTenantId);
    return ids.length;
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _pendentesRam.remove(churchId);
    try {
      await TenantModuleHiveCache.clearModule(
        churchId,
        TenantModuleKeys.membros,
      );
    } catch (_) {}
  }
}
