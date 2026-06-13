import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/church_tenant_list_limits.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/member_document_resolve.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_cargos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_pedidos_oracao_load_service.dart';
import 'package:gestao_yahweh/services/church_visitantes_load_service.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leituras Firestore do tenant (padrão Controle Total): cache → retry → último bom.
///
/// Usar em **todos** os módulos do painel em vez de `.get()` directo.
abstract final class ChurchTenantResilientReads {
  ChurchTenantResilientReads._();

  static String _key(String tenantId, String suffix) =>
      '${tenantId.trim()}_$suffix';

  static DocumentReference<Map<String, dynamic>> _church(String tenantId) =>
      ChurchRepository.churchDoc(tenantId);

  /// Doc canónico em `igrejas/{churchId}` — ID directo (sem resolver/alias no painel).
  static Future<String> _readTenantId(String tenantId, {String? userUid}) async {
    final bound = ChurchContext.currentChurchId?.trim() ?? '';
    if (bound.isNotEmpty) return bound;
    final hint = tenantId.trim();
    if (hint.isEmpty) return '';
    final panel = ChurchContextService.panelChurchId(hint);
    return panel.isNotEmpty ? panel : hint;
  }

  /// Regra 8 — permission-denied / rede: re-resolve tenant e refaz leitura.
  static Future<T> withTenantRecovery<T>({
    required String tenantId,
    required String module,
    required Future<T> Function(String operationalId) fetch,
    String? userUid,
    int maxAttempts = 3,
  }) async {
    final seed = tenantId.trim();
    Object? lastError;
    var operational = seed;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await preparePanelRead(refreshToken: attempt >= 1);
          operational = await operationalTenantId(seed, userUid: userUid);
        } else {
          operational = await operationalTenantId(seed, userUid: userUid);
        }
        return await fetch(operational);
      } catch (e, st) {
        lastError = e;
        final transient = FirestoreReadResilience.isTransient(e) ||
            (e is FirebaseException && e.code == 'permission-denied');
        if (!transient || attempt >= maxAttempts - 1) {
          unawaited(
            SystemLogService.recordTenantAccessDenied(
              module: module,
              tenantId: operational,
              error: e,
              stackTrace: st,
            ),
          );
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 280 + attempt * 320),
        );
      }
    }
    throw lastError ?? StateError('tenant_recovery_failed');
  }

  /// Token + Firestore pronto (leitura do painel, sem desligar rede).
  static Future<void> preparePanelRead({bool refreshToken = false}) async {
    await ensureFirebaseReadyForPanelRead().catchError((_) {});
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    if (refreshToken) {
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true)
          .timeout(const Duration(seconds: 6))
          .catchError((_) {});
    }
  }

  /// Doc operacional da igreja — path directo `igrejas/{churchId}` (sem resolver).
  static Future<String> operationalTenantId(
    String seed, {
    String? userUid,
  }) async {
    final direct = ChurchContextService.panelChurchId(seed);
    return direct.isNotEmpty ? direct : seed.trim();
  }

  /// Endereço / formulário — tenant operacional + cache, sem desligar rede.
  static Future<({
    String firestoreTenantId,
    Map<String, dynamic> tenantData,
  })> loadChurchAddressBundle(
    String tenantIdHint, {
    String? userUid,
  }) async {
    final loaded = await ChurchCadastroLoadService.load(
      seedTenantId: tenantIdHint,
    );
    if (loaded.data.isEmpty && loaded.softError != null) {
      throw ChurchRepositoryException(
        loaded.softError!,
        seedTenantId: tenantIdHint,
      );
    }
    return (
      firestoreTenantId: loaded.churchId,
      tenantData: loaded.data,
    );
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> churchDocument(
    String tenantId, {
    String? userUid,
  }) async {
    await preparePanelRead();
    final tid = await _readTenantId(tenantId, userUid: userUid);
    final path = 'igrejas/$tid';
    return ChurchModuleFirestoreAudit.traceQuery(
      module: 'Cadastro Igreja',
      churchId: tid,
      path: path,
      run: () => FirestoreReadResilience.getDocument(
        _church(tid),
        cacheKey: _key(tid, 'igreja_doc'),
      ),
    );
  }

  /// Iglesia + slug (mural, site público, formulários).
  static Future<({
    String firestoreTenantId,
    String churchSlug,
    Map<String, dynamic> tenantData,
  })> loadTenantBundle(
    String tenantIdHint, {
    String? userUid,
  }) async {
    try {
      await preparePanelRead();
    } catch (_) {
      final fallback = tenantIdHint.trim();
      return (
        firestoreTenantId: fallback,
        churchSlug: fallback,
        tenantData: <String, dynamic>{},
      );
    }
    final tid = ChurchRepository.churchId(tenantIdHint);
    final effective = tid.isNotEmpty ? tid : tenantIdHint.trim();
    final snap = await churchDocument(effective);
    final data = snap.data() ?? {};
    final slug = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
    final churchSlug = slug.isEmpty ? effective : slug;
    return (
      firestoreTenantId: effective,
      churchSlug: churchSlug,
      tenantData: data,
    );
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> avisosFeed(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) async {
    final r = await ChurchAvisosLoadService.loadFeed(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  static DateTime? _avisoCreatedAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static QuerySnapshot<Map<String, dynamic>> _sortAvisosSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final ta = _avisoCreatedAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _avisoCreatedAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  /// Sem [preparePanelRead] — cache-first; plain query se faltar índice/campo createdAt.
  static Future<QuerySnapshot<Map<String, dynamic>>> _avisosFeedQueryResilient(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection('avisos')
                .where('ativo', isEqualTo: true)
                .where('publicado', isEqualTo: true)
                .orderBy('createdAt', descending: true)
                .limit(limit),
            cacheKey: _key(tenantId, 'avisos_feed_pub_$limit'),
          );
        } catch (_) {
          try {
            return await FirestoreReadResilience.getQuery(
              church
                  .collection('avisos')
                  .orderBy('createdAt', descending: true)
                  .limit(limit),
              cacheKey: _key(tenantId, 'avisos_feed_$limit'),
            );
          } catch (_) {
            final plain = await FirestoreReadResilience.getQuery(
              church.collection('avisos').limit(limit),
              cacheKey: _key(tenantId, 'avisos_plain_$limit'),
            );
            return _sortAvisosSnapshot(plain);
          }
        }
      });

  static Future<QuerySnapshot<Map<String, dynamic>>> noticiasByStartAt(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) async {
    final r = await ChurchEventosLoadService.loadFeed(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  static DateTime? _noticiaStartAt(Map<String, dynamic> data) {
    final raw = data['startAt'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static QuerySnapshot<Map<String, dynamic>> _sortNoticiasByStartAtSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final ta = _noticiaStartAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _noticiaStartAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  static Future<QuerySnapshot<Map<String, dynamic>>>
      _noticiasByStartAtQueryResilient(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection('eventos')
                .where('ativo', isEqualTo: true)
                .where('publicado', isEqualTo: true)
                .orderBy('startAt', descending: true)
                .limit(limit),
            cacheKey: _key(tenantId, 'noticias_start_pub_$limit'),
          );
        } catch (_) {
          try {
            return await FirestoreReadResilience.getQuery(
              church
                  .collection('eventos')
                  .orderBy('startAt', descending: true)
                  .limit(limit),
              cacheKey: _key(tenantId, 'noticias_start_$limit'),
            );
          } catch (_) {
            final plain = await FirestoreReadResilience.getQuery(
              church.collection('eventos').limit(limit),
              cacheKey: _key(tenantId, 'noticias_plain_$limit'),
            );
            return _sortNoticiasByStartAtSnapshot(plain);
          }
        }
      });

  static Future<QuerySnapshot<Map<String, dynamic>>> eventCategories(
    String tenantIdHint, {
    String? userUid,
  }) async {
    await ensureFirebaseReadyForPanelRead().catchError((_) {});
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final tid = ChurchRepository.churchId(tenantIdHint);
    final effective = tid.isNotEmpty ? tid : tenantIdHint.trim();
    return _queryWithSiblingFallback(
      effective,
      (id) => FirestoreReadResilience.getQuery(
        _church(id).collection('event_categories'),
        cacheKey: _key(id, 'event_categories'),
        maxAttempts: 4,
        attemptTimeout: kIsWeb
            ? const Duration(seconds: 10)
            : const Duration(seconds: 18),
      ),
    );
  }

  /// Modelos de culto/evento fixo — doc operacional + irmãos; sem [preparePanelRead].
  static Future<QuerySnapshot<Map<String, dynamic>>> eventTemplates(
    String tenantId,
  ) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.agenda,
        firestoreCacheKey: _key(tenantId, 'event_templates_all'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) => FirestoreWebGuard.runWithWebRecovery(
            () => FirestoreReadResilience.getQuery(
              _church(tid).collection('event_templates'),
              cacheKey: _key(tid, 'event_templates_all'),
              maxAttempts: 4,
              attemptTimeout: kIsWeb
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 18),
            ),
          ),
        ),
      );

  /// Leitura directa `igrejas/{churchId}/…` — **sem** fallback para docs irmãos.
  static Future<QuerySnapshot<Map<String, dynamic>>> _queryWithSiblingFallback(
    String tenantId,
    Future<QuerySnapshot<Map<String, dynamic>>> Function(String tid) loadFor, {
    String? userUid,
    bool tenantAlreadyResolved = false,
  }) async {
    var primary = tenantId.trim();
    if (primary.isEmpty) return const MergedFirestoreQuerySnapshot([]);

    if (!tenantAlreadyResolved) {
      primary = await _readTenantId(primary, userUid: userUid);
    }
    if (primary.isEmpty) return const MergedFirestoreQuerySnapshot([]);

    return loadFor(primary);
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> pedidosOracao(
    String tenantId, {
    bool? respondidaFilter,
    int limit = 300,
  }) async {
    final r = await ChurchPedidosOracaoLoadService.load(
      seedTenantId: tenantId,
      respondidaFilter: respondidaFilter,
      limit: limit,
    );
    return r.snapshot;
  }

  static QuerySnapshot<Map<String, dynamic>> _sortPedidosOracaoSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final ta = _avisoCreatedAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _avisoCreatedAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> _pedidosOracaoQueryResilient(
    String tenantId, {
    bool? respondidaFilter,
    int limit = 300,
  }) {
    final col = _church(tenantId).collection('pedidosOracao');
    final suffix = respondidaFilter == true
        ? 'respondidas'
        : respondidaFilter == false
            ? 'pendentes'
            : 'all';
    return FirestoreWebGuard.runWithWebRecovery(() async {
      try {
        late final Query<Map<String, dynamic>> q;
        if (respondidaFilter == true) {
          q = col
              .where('respondida', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .limit(limit);
        } else if (respondidaFilter == false) {
          q = col
              .where('respondida', isEqualTo: false)
              .orderBy('createdAt', descending: true)
              .limit(limit);
        } else {
          q = col.orderBy('createdAt', descending: true).limit(limit);
        }
        return await FirestoreReadResilience.getQuery(
          q,
          cacheKey: _key(tenantId, 'pedidos_oracao_$suffix'),
        );
      } catch (_) {
        final plain = await FirestoreReadResilience.getQuery(
          col.limit(limit),
          cacheKey: _key(tenantId, 'pedidos_oracao_plain_$suffix'),
        );
        if (respondidaFilter == null) {
          return _sortPedidosOracaoSnapshot(plain);
        }
        final filtered = plain.docs.where((d) {
          final r = d.data()['respondida'];
          return respondidaFilter ? r == true : r == false;
        }).toList();
        return _sortPedidosOracaoSnapshot(MergedFirestoreQuerySnapshot(filtered));
      }
    });
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> pedidosOracaoResilient(
    String tenantId, {
    bool? respondidaFilter,
    int limit = 300,
  }) =>
      pedidosOracao(
        tenantId,
        respondidaFilter: respondidaFilter,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> visitantes(
    String tenantId, {
    int limit = 400,
  }) async {
    final r = await ChurchVisitantesLoadService.load(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> membrosRecent(
    String tenantId, {
    int limit = 220,
  }) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.membros,
        firestoreCacheKey: _key(tenantId, 'membros_updated_$limit'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) async {
            final church = _church(tid);
            try {
              return await FirestoreReadResilience.getQuery(
                church
                    .collection('membros')
                    .orderBy('updatedAt', descending: true)
                    .limit(limit),
                cacheKey: _key(tid, 'membros_updated_$limit'),
              );
            } catch (_) {
              return FirestoreReadResilience.getQuery(
                church.collection('membros').limit(limit),
                cacheKey: _key(tid, 'membros_plain_$limit'),
              );
            }
          },
        ),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> departamentos(
    String tenantId, {
    int limit = 120,
    String? userUid,
  }) async {
    YahwehFlowLog.start('departamentos');
    try {
      final uid = userUid ?? FirebaseAuth.instance.currentUser?.uid;
      final tid = await _readTenantId(tenantId, userUid: uid);
      final path = 'igrejas/$tid/departamentos';
      Future<QuerySnapshot<Map<String, dynamic>>> fetch() =>
          ChurchModuleFirestoreAudit.traceQuery(
            module: 'Departamentos',
            churchId: tid,
            path: path,
            run: () => FirestoreWebGuard.runWithWebRecovery(
              () => FirestoreReadResilience.getQuery(
                _church(tid).collection('departamentos').limit(limit),
                cacheKey: _key(tid, 'departamentos_$limit'),
              ),
            ),
          );
      final query = TenantStaleWhileRevalidate.loadQuery(
        tenantId: tid,
        module: TenantModuleKeys.departamentos,
        firestoreCacheKey: _key(tid, 'departamentos_$limit'),
        networkFetch: fetch,
      );
      final result = await query.timeout(ChurchPanelReadTimeouts.queryCap);
      YahwehFlowLog.success('departamentos');
      return result;
    } catch (e, st) {
      YahwehFlowLog.error('departamentos', e, st);
      rethrow;
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> funcoesControle(
    String tenantId, {
    int limit = 80,
    String? userUid,
  }) async {
    final uid = userUid ?? FirebaseAuth.instance.currentUser?.uid;
    final tid = await _readTenantId(tenantId, userUid: uid);
    return TenantStaleWhileRevalidate.loadQuery(
      tenantId: tid,
      module: 'funcoes_controle',
      firestoreCacheKey: _key(tid, 'funcoes_controle_$limit'),
      networkFetch: () => _queryWithSiblingFallback(
        tid,
        (id) => FirestoreReadResilience.getQuery(
          _church(id).collection('funcoesControle').orderBy('order').limit(limit),
          cacheKey: _key(id, 'funcoes_controle_$limit'),
        ),
        userUid: uid,
        tenantAlreadyResolved: true,
      ),
    );
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> cargos(
    String tenantId, {
    int limit = 120,
    String? userUid,
  }) async {
    final r = await ChurchCargosLoadService.load(
      seedTenantId: tenantId,
    );
    return r.snapshot;
  }

  static String _cargoSortKey(Map<String, dynamic> data) =>
      (data['name'] ?? data['nome'] ?? '').toString().trim().toLowerCase();

  static QuerySnapshot<Map<String, dynamic>> _sortCargosSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final oa = (da['order'] as num?)?.toInt() ?? 999;
      final ob = (db['order'] as num?)?.toInt() ?? 999;
      if (oa != ob) return oa.compareTo(ob);
      final ha = (da['hierarchyLevel'] as num?)?.toInt() ?? 999;
      final hb = (db['hierarchyLevel'] as num?)?.toInt() ?? 999;
      if (ha != hb) return ha.compareTo(hb);
      return _cargoSortKey(da).compareTo(_cargoSortKey(db));
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  /// Sem [preparePanelRead] — cache-first; plain query se faltar índice/campo name.
  static Future<QuerySnapshot<Map<String, dynamic>>> _cargosQueryResilient(
    String tenantId, {
    int limit = 120,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church.collection('cargos').orderBy('name').limit(limit),
            cacheKey: _key(tenantId, 'cargos_$limit'),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection('cargos').limit(limit),
            cacheKey: _key(tenantId, 'cargos_plain_$limit'),
          );
          return _sortCargosSnapshot(plain);
        }
      });

  static DateTime? _financeCreatedAt(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  static QuerySnapshot<Map<String, dynamic>> _sortFinanceSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final ta = _financeCreatedAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _financeCreatedAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  /// Plain query se faltar índice/campo createdAt — crítico no Web.
  static Future<QuerySnapshot<Map<String, dynamic>>> _financeQueryResilient(
    String tenantId, {
    required int limit,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection('finance')
                .orderBy('createdAt', descending: true)
                .limit(limit),
            cacheKey: _key(tenantId, 'finance_$limit'),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection('finance').limit(limit),
            cacheKey: _key(tenantId, 'finance_plain_$limit'),
          );
          return _sortFinanceSnapshot(plain);
        }
      });

  static Future<QuerySnapshot<Map<String, dynamic>>> financeRecent(
    String tenantId, {
    int limit = 250,
  }) =>
      ChurchFinanceRealtimeService.fetchFinanceCached(
        tenantId,
        limit: limit,
      );

  /// Rede directa — após mutação financeira (sem Hive stale).
  static Future<QuerySnapshot<Map<String, dynamic>>> financeRecentNetwork(
    String tenantId, {
    int limit = 250,
  }) async {
    final result = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: tenantId,
      limit: limit,
      forceRefresh: true,
      forceServer: true,
    );
    return result.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> contasNetwork(
    String tenantId, {
    int limit = 80,
  }) =>
      _queryWithSiblingFallback(
        tenantId,
        (tid) => _orderedQuery(
          tid,
          'contas',
          'nome',
          descending: false,
          limit: limit,
          cacheSuffix: 'contas_$limit',
        ),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> patrimonio(
    String tenantId, {
    int limit = YahwehPerformanceV4.patrimonioListPageSize,
  }) async {
    final r = await ChurchPatrimonioLoadService.load(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> patrimonioPage(
    String tenantId, {
    int limit = YahwehPerformanceV4.patrimonioListPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final docs = await ChurchPatrimonioLoadService.loadPage(
      seedTenantId: tenantId,
      limit: limit,
      startAfter: startAfter,
    );
    return MergedFirestoreQuerySnapshot(docs);
  }

  /// Coleção completa (dashboard, inventário/conferência) — cache → rede com retry.
  static Future<QuerySnapshot<Map<String, dynamic>>> patrimonioAll(
    String tenantId, {
    int limit = 800,
  }) async {
    final r = await ChurchPatrimonioLoadService.loadAll(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  /// Um bem ao abrir formulário / retomar sessão — cache → rede com retry.
  static Future<DocumentSnapshot<Map<String, dynamic>>> patrimonioItem(
    String tenantId,
    String itemDocId,
  ) async {
    final id = itemDocId.trim();
    if (id.isEmpty) {
      return FirestoreReadResilience.getDocument(
        _church(tenantId).collection('patrimonio').doc('_empty_'),
        cacheKey: _key(tenantId, 'patrimonio_item_empty'),
      );
    }
    Future<DocumentSnapshot<Map<String, dynamic>>> loadFor(String tid) =>
        FirestoreReadResilience.getDocument(
          _church(tid).collection('patrimonio').doc(id),
          cacheKey: _key(tid, 'patrimonio_item_$id'),
        );
    final primary = await _readTenantId(tenantId);
    return loadFor(primary);
  }

  /// Categorias extras (`config/patrimonio`) — cache → rede com retry.
  static Future<DocumentSnapshot<Map<String, dynamic>>> patrimonioConfig(
    String tenantId,
  ) async {
    Future<DocumentSnapshot<Map<String, dynamic>>> loadFor(String tid) =>
        FirestoreReadResilience.getDocument(
          _church(tid).collection('config').doc('patrimonio'),
          cacheKey: _key(tid, 'patrimonio_config'),
        );
    final primary = await _readTenantId(tenantId);
    return loadFor(primary);
  }

  /// Doc em `igrejas/{tid}/config/{docId}` — directo (MP, payment_receiving).
  static Future<DocumentSnapshot<Map<String, dynamic>>> configDoc(
    String tenantId,
    String docId,
  ) async {
    Future<DocumentSnapshot<Map<String, dynamic>>> loadFor(String tid) =>
        FirestoreReadResilience.getDocument(
          _church(tid).collection('config').doc(docId),
          cacheKey: _key(tid, 'config_${docId.trim()}'),
        );
    final primary = await _readTenantId(tenantId);
    return loadFor(primary);
  }

  /// Contas tesouraria — directo `igrejas/{churchId}/contas`.
  static Future<QuerySnapshot<Map<String, dynamic>>> _contasQueryResilient(
    String tenantId, {
    int limit = 80,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church.collection('contas').orderBy('nome').limit(limit),
            cacheKey: _key(tenantId, 'contas_resilient_$limit'),
            maxAttempts: 4,
            attemptTimeout: kIsWeb
                ? const Duration(seconds: 12)
                : const Duration(seconds: 18),
          );
        } catch (_) {
          return FirestoreReadResilience.getQuery(
            church.collection('contas').limit(limit),
            cacheKey: _key(tenantId, 'contas_resilient_plain_$limit'),
            maxAttempts: 3,
            attemptTimeout: kIsWeb
                ? const Duration(seconds: 10)
                : const Duration(seconds: 15),
          );
        }
      });

  static bool _isMercadoPagoContaData(Map<String, dynamic> data) {
    if (data['ativo'] == false) return false;
    final cod = (data['bancoCodigo'] ?? '').toString().trim();
    if (cod == '323') return true;
    final bn = (data['bancoNome'] ?? '').toString().toLowerCase();
    if (bn.contains('mercado pago')) return true;
    if ((data['seedPreset'] ?? '').toString() == 'tesouraria_mercado_pago') {
      return true;
    }
    final nome = (data['nome'] ?? '').toString().toLowerCase();
    return nome.contains('mercado pago');
  }

  /// Contas MP — directo `igrejas/{churchId}/contas`.
  static Future<QuerySnapshot<Map<String, dynamic>>> _contasMercadoPagoWithSiblingFallback(
    String tenantId, {
    int limit = 80,
  }) async {
    final primary = await _readTenantId(tenantId);
    if (primary.isEmpty) return const MergedFirestoreQuerySnapshot([]);

    try {
      final snap = await _contasQueryResilient(primary, limit: limit);
      final hit = snap.docs
          .where((d) => _isMercadoPagoContaData(d.data()))
          .toList();
      if (hit.isNotEmpty) return MergedFirestoreQuerySnapshot(hit);
    } catch (_) {}
    return const MergedFirestoreQuerySnapshot([]);
  }

  /// Doação — só contas Mercado Pago (323), com fallback em docs irmãos do cluster.
  static Future<QuerySnapshot<Map<String, dynamic>>> contasDonation(
    String tenantId, {
    int limit = 80,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MergedFirestoreQuerySnapshot([]);

    final memKey = _key(tid, 'contas_mp_donation_$limit');
    final mem = FirestoreReadResilience.peekLastGoodQuery(memKey);
    if (mem != null && mem.docs.isNotEmpty) {
      unawaited(_contasMercadoPagoWithSiblingFallback(tid, limit: limit).then((snap) {
        if (snap.docs.isNotEmpty) {
          FirestoreReadResilience.forgetKey(memKey);
        }
      }).catchError((_) {}));
      return mem;
    }

    final hive = await TenantModuleHiveCache.readDocs(tid, TenantModuleKeys.financeiro);
    if (hive.isNotEmpty) {
      final mpHive = TenantModuleHiveCache.toQueryDocuments(hive)
          .where((d) => _isMercadoPagoContaData(d.data()))
          .toList();
      if (mpHive.isNotEmpty) {
        unawaited(_contasMercadoPagoWithSiblingFallback(tid, limit: limit).catchError((_) {}));
        return MergedFirestoreQuerySnapshot(mpHive);
      }
    }

    try {
      final snap = await _contasMercadoPagoWithSiblingFallback(tid, limit: limit);
      if (snap.docs.isNotEmpty) {
        unawaited(
          TenantModuleHiveCache.saveFromQuerySnapshot(
            tid,
            TenantModuleKeys.financeiro,
            snap,
          ),
        );
      }
      return snap;
    } catch (e) {
      final fallback = FirestoreReadResilience.peekLastGoodQuery(memKey);
      if (fallback != null && fallback.docs.isNotEmpty) return fallback;
      rethrow;
    }
  }

  /// Membro vinculado ao login — tenant + irmãos.
  static Future<({String docId, String nome})?> memberByAuthUid(
    String tenantId,
    String authUid,
  ) async {
    final uid = authUid.trim();
    if (uid.isEmpty) return null;
    Future<({String docId, String nome})?> loadFor(String tid) async {
      final q = await FirestoreReadResilience.getQuery(
        _church(tid)
            .collection('membros')
            .where('authUid', isEqualTo: uid)
            .limit(1),
        cacheKey: _key(tid, 'membro_auth_$uid'),
        maxAttempts: 3,
        attemptTimeout: kIsWeb
            ? const Duration(seconds: 10)
            : const Duration(seconds: 15),
      );
      if (q.docs.isEmpty) return null;
      final doc = q.docs.first;
      final data = doc.data();
      final nome = (data['NOME_COMPLETO'] ??
              data['NOME'] ??
              data['nome'] ??
              '')
          .toString()
          .trim();
      return (docId: doc.id, nome: nome);
    }

    final primary = await _readTenantId(tenantId);
    if (primary.isEmpty) return null;
    try {
      return await loadFor(primary);
    } catch (_) {
      return null;
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> contas(
    String tenantId, {
    int limit = 80,
  }) async {
    final result = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tenantId,
      limit: limit,
    );
    return result.snapshot;
  }

  /// Despesas mensais recorrentes — doc operacional + irmãos (ex.: `brasilparacristo_sistema`).
  static Future<QuerySnapshot<Map<String, dynamic>>> despesasFixas(
    String tenantId, {
    int limit = 200,
  }) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.financeiro,
        firestoreCacheKey: _key(tenantId, 'despesas_fixas_$limit'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) => _orderedQuery(
            tid,
            'despesas_fixas',
            'descricao',
            descending: false,
            limit: limit,
            cacheSuffix: 'despesas_fixas_$limit',
          ),
        ),
      );

  /// Receitas fixas / recorrentes — doc operacional + irmãos.
  static Future<QuerySnapshot<Map<String, dynamic>>> receitasRecorrentes(
    String tenantId, {
    int limit = YahwehPerformanceV4.defaultPageSize * 5,
  }) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.financeiro,
        firestoreCacheKey: _key(tenantId, 'receitas_recorrentes_$limit'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) => FirestoreReadResilience.getQuery(
            _church(tid)
                .collection('receitas_recorrentes')
                .limit(limit),
            cacheKey: _key(tid, 'receitas_recorrentes_$limit'),
          ),
        ),
      );

  static QuerySnapshot<Map<String, dynamic>> _sortFornecedoresSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      final na = (a.data()['nome'] ?? '').toString().trim().toLowerCase();
      final nb = (b.data()['nome'] ?? '').toString().trim().toLowerCase();
      return na.compareTo(nb);
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> _fornecedoresQueryResilient(
    String tenantId, {
    required int limit,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church.collection('fornecedores').orderBy('nome').limit(limit),
            cacheKey: _key(tenantId, 'fornecedores_$limit'),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection('fornecedores').limit(limit),
            cacheKey: _key(tenantId, 'fornecedores_plain_$limit'),
          );
          return _sortFornecedoresSnapshot(plain);
        }
      });

  static Future<QuerySnapshot<Map<String, dynamic>>> fornecedores(
    String tenantId, {
    int limit = YahwehPerformanceV4.defaultPageSize,
  }) async {
    final r = await ChurchFornecedoresLoadService.load(
      seedTenantId: tenantId,
      limit: limit,
    );
    return r.snapshot;
  }

  /// Rede directa — diagnóstico / refresh pós-mutação.
  static Future<QuerySnapshot<Map<String, dynamic>>> fornecedoresNetwork(
    String tenantId, {
    int limit = YahwehPerformanceV4.defaultPageSize,
  }) async {
    final r = await ChurchFornecedoresLoadService.load(
      seedTenantId: tenantId,
      limit: limit,
      forceRefresh: true,
    );
    return r.snapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> escalaTemplates(
    String tenantId, {
    int limit = 120,
  }) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.agenda,
        firestoreCacheKey: _key(tenantId, 'escala_templates_$limit'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) => _escalaTemplatesQueryResilient(tid, limit: limit),
        ),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> escalasRecent(
    String tenantId, {
    int limit = 120,
  }) =>
      TenantStaleWhileRevalidate.loadQuery(
        tenantId: tenantId,
        module: TenantModuleKeys.agenda,
        firestoreCacheKey: _key(tenantId, 'escalas_$limit'),
        networkFetch: () => _queryWithSiblingFallback(
          tenantId,
          (tid) => _escalasRecentQueryResilient(tid, limit: limit),
        ),
      );

  static String _escalaTemplateSortKey(Map<String, dynamic> data) =>
      (data['title'] ?? data['nome'] ?? '').toString().trim().toLowerCase();

  static QuerySnapshot<Map<String, dynamic>> _sortEscalaTemplatesSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort(
      (a, b) => _escalaTemplateSortKey(a.data())
          .compareTo(_escalaTemplateSortKey(b.data())),
    );
    return MergedFirestoreQuerySnapshot(sorted);
  }

  static QuerySnapshot<Map<String, dynamic>> _sortEscalasByDateSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool descending,
  }) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snap.docs);
    sorted.sort((a, b) {
      Timestamp? ta;
      Timestamp? tb;
      try {
        ta = a.data()['date'] as Timestamp?;
      } catch (_) {}
      try {
        tb = b.data()['date'] as Timestamp?;
      } catch (_) {}
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      final c = ta.compareTo(tb);
      return descending ? -c : c;
    });
    return MergedFirestoreQuerySnapshot(sorted);
  }

  /// Sem [preparePanelRead] — cache-first; plain query se faltar índice.
  static Future<QuerySnapshot<Map<String, dynamic>>> _escalaTemplatesQueryResilient(
    String tenantId, {
    int limit = 120,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection('escala_templates')
                .orderBy('title')
                .limit(limit),
            cacheKey: _key(tenantId, 'escala_templates_$limit'),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection('escala_templates').limit(limit),
            cacheKey: _key(tenantId, 'escala_templates_plain_$limit'),
          );
          return _sortEscalaTemplatesSnapshot(plain);
        }
      });

  static Future<QuerySnapshot<Map<String, dynamic>>> _escalasRecentQueryResilient(
    String tenantId, {
    int limit = 120,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church.collection('escalas').orderBy('date', descending: true).limit(limit),
            cacheKey: _key(tenantId, 'escalas_$limit'),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection('escalas').limit(limit),
            cacheKey: _key(tenantId, 'escalas_plain_$limit'),
          );
          return _sortEscalasByDateSnapshot(plain, descending: true);
        }
      });

  static Future<DocumentSnapshot<Map<String, dynamic>>> panelCacheSummary(
    String tenantId,
  ) =>
      FirestoreReadResilience.getDocument(
        _church(tenantId).collection('_panel_cache').doc('dashboard_summary'),
        cacheKey: _key(tenantId, 'panel_cache_summary'),
      );

  static Future<DocumentSnapshot<Map<String, dynamic>>> panelStatisticsSummary(
    String tenantId,
  ) =>
      FirestoreReadResilience.getDocument(
        _church(tenantId).collection('_panel_cache').doc('statistics_summary'),
        cacheKey: _key(tenantId, 'panel_cache_statistics'),
      );

  static Future<DocumentSnapshot<Map<String, dynamic>>> panelPublicSiteCache(
    String tenantId,
  ) =>
      FirestoreReadResilience.getDocument(
        _church(tenantId).collection('_panel_cache').doc('public_site'),
        cacheKey: _key(tenantId, 'panel_cache_public_site'),
      );

  /// Stream do painel / feeds — cache-first + live só fora da web.
  static Stream<QuerySnapshot<Map<String, dynamic>>> querySnapshotsResilient(
    Query<Map<String, dynamic>> query,
  ) =>
      FirestoreStreamUtils.queryWatchBootstrap(query);

  static Future<QuerySnapshot<Map<String, dynamic>>> _orderedQuery(
    String tenantId,
    String subcollection,
    String orderField, {
    required bool descending,
    required int limit,
    required String cacheSuffix,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection(subcollection)
                .orderBy(orderField, descending: descending)
                .limit(limit),
            cacheKey: _key(tenantId, cacheSuffix),
          );
        } catch (_) {
          return await FirestoreReadResilience.getQuery(
            church.collection(subcollection).limit(limit),
            cacheKey: _key(tenantId, '${cacheSuffix}_plain'),
          );
        }
      });

  static String _rangeCacheSuffix(Timestamp start, Timestamp end) =>
      '${start.seconds}_${end.seconds}';

  static Future<QuerySnapshot<Map<String, dynamic>>> _rangeQueryResilient({
    required String tenantId,
    required String collection,
    required String dateField,
    required Timestamp start,
    required Timestamp end,
    required String cacheSuffix,
    int plainLimit = 500,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(() async {
        final church = _church(tenantId);
        try {
          return await FirestoreReadResilience.getQuery(
            church
                .collection(collection)
                .where(dateField, isGreaterThanOrEqualTo: start)
                .where(dateField, isLessThanOrEqualTo: end),
            cacheKey: _key(tenantId, cacheSuffix),
            maxAttempts: kIsWeb ? 2 : 3,
            attemptTimeout: kIsWeb
                ? const Duration(seconds: 10)
                : const Duration(seconds: 16),
          );
        } catch (_) {
          final plain = await FirestoreReadResilience.getQuery(
            church.collection(collection).limit(plainLimit),
            cacheKey: _key(tenantId, '${cacheSuffix}_plain'),
          );
          final startDate = start.toDate();
          final endDate = end.toDate();
          final filtered = plain.docs.where((d) {
            final raw = d.data()[dateField];
            if (raw is! Timestamp) return false;
            final dt = raw.toDate();
            return !dt.isBefore(startDate) && !dt.isAfter(endDate);
          }).toList();
          return MergedFirestoreQuerySnapshot(filtered);
        }
      });

  /// Cultos no intervalo — doc operacional + irmãos.
  static Future<QuerySnapshot<Map<String, dynamic>>> cultosByDateRange(
    String tenantId, {
    required Timestamp start,
    required Timestamp end,
  }) =>
      _queryWithSiblingFallback(
        tenantId,
        (tid) => _rangeQueryResilient(
          tenantId: tid,
          collection: 'cultos',
          dateField: 'data',
          start: start,
          end: end,
          cacheSuffix: 'cultos_${_rangeCacheSuffix(start, end)}',
        ),
      );

  /// Eventos/mural por `dataEvento` no intervalo.
  static Future<QuerySnapshot<Map<String, dynamic>>> eventosByDataEventoRange(
    String tenantId, {
    required Timestamp start,
    required Timestamp end,
  }) =>
      _queryWithSiblingFallback(
        tenantId,
        (tid) => _rangeQueryResilient(
          tenantId: tid,
          collection: 'eventos',
          dateField: 'dataEvento',
          start: start,
          end: end,
          cacheSuffix: 'eventos_dataEvento_${_rangeCacheSuffix(start, end)}',
        ),
      );

  /// Posts `type: evento` com `startAt` no intervalo.
  static Future<QuerySnapshot<Map<String, dynamic>>> muralEventosByStartAtRange(
    String tenantId, {
    required Timestamp start,
    required Timestamp end,
  }) =>
      _queryWithSiblingFallback(
        tenantId,
        (tid) => FirestoreWebGuard.runWithWebRecovery(() async {
          final church = _church(tid);
          final suffix = 'mural_startAt_${_rangeCacheSuffix(start, end)}';
          try {
            return await FirestoreReadResilience.getQuery(
              church
                  .collection('eventos')
                  .where('type', isEqualTo: 'evento')
                  .where('startAt', isGreaterThanOrEqualTo: start)
                  .where('startAt', isLessThanOrEqualTo: end),
              cacheKey: _key(tid, suffix),
              maxAttempts: kIsWeb ? 2 : 3,
              attemptTimeout: kIsWeb
                  ? const Duration(seconds: 10)
                  : const Duration(seconds: 16),
            );
          } catch (_) {
            final plain = await FirestoreReadResilience.getQuery(
              church.collection('eventos').limit(400),
              cacheKey: _key(tid, '${suffix}_plain'),
            );
            final startDate = start.toDate();
            final endDate = end.toDate();
            final filtered = plain.docs.where((d) {
              final m = d.data();
              if ((m['type'] ?? '').toString() != 'evento') return false;
              final raw = m['startAt'];
              if (raw is! Timestamp) return false;
              final dt = raw.toDate();
              return !dt.isBefore(startDate) && !dt.isAfter(endDate);
            }).toList();
            return MergedFirestoreQuerySnapshot(filtered);
          }
        }),
      );

  /// Escalas no intervalo.
  static Future<QuerySnapshot<Map<String, dynamic>>> escalasByDateRange(
    String tenantId, {
    required Timestamp start,
    required Timestamp end,
  }) =>
      _queryWithSiblingFallback(
        tenantId,
        (tid) => _rangeQueryResilient(
          tenantId: tid,
          collection: 'escalas',
          dateField: 'date',
          start: start,
          end: end,
          cacheSuffix: 'escalas_${_rangeCacheSuffix(start, end)}',
        ),
      );

  /// Itens da coleção `agenda` no intervalo.
  static Future<QuerySnapshot<Map<String, dynamic>>> agendaByStartTimeRange(
    String tenantId, {
    required Timestamp start,
    required Timestamp end,
  }) async {
    final r = await ChurchAgendaLoadService.loadByStartTimeRange(
      seedTenantId: tenantId,
      start: start,
      end: end,
    );
    return r.snapshot;
  }

  /// Membro por id/CPF/código — doc operacional + irmãos (carteirinha, certificados).
  static Future<DocumentSnapshot<Map<String, dynamic>>?> membroByHint(
    String tenantId,
    String hint, {
    String? cpfDigits,
    String? userUid,
  }) async {
    await preparePanelRead();
    final h = hint.trim();
    if (h.isEmpty) return null;
    final seed = tenantId.trim();
    if (seed.isEmpty) return null;
    final primary = await _readTenantId(seed, userUid: userUid);
    if (primary.isEmpty) return null;

    Future<DocumentSnapshot<Map<String, dynamic>>?> tryTenant(String tid) =>
        MemberDocumentResolve.findByHint(
          MemberDocumentResolve.membrosCol(firebaseDefaultFirestore, tid),
          h,
          cpfDigits: cpfDigits,
        );

    try {
      final snap = await tryTenant(primary);
      if (snap != null && snap.exists) return snap;
    } catch (_) {}

    final siblings = TenantResolverService.orderedSiblingsForReadFallback(
      primary,
      await TenantResolverService.getAllRelatedIgrejaDocIds(primary),
    );
    for (final sid in siblings) {
      try {
        final snap = await tryTenant(sid);
        if (snap != null && snap.exists) {
          TenantResolverService.rememberModuleReadTenantId(
            seed,
            sid,
            userUid: userUid,
          );
          return snap;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Carteirinha / perfil do membro logado — directo `igrejas/{churchId}/membros`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> resolveSelfMember(
    String tenantId, {
    String? memberId,
    String? cpfDigits,
    String? authUid,
    String? email,
  }) async {
    await preparePanelRead();
    final cpf = (cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    final cpfArg = cpf.length >= 11 ? cpf : null;
    final tried = <String>{};

    Future<DocumentSnapshot<Map<String, dynamic>>?> tryHint(String raw) async {
      final h = raw.trim();
      if (h.isEmpty || tried.contains(h)) return null;
      tried.add(h);
      return membroByHint(tenantId, h, cpfDigits: cpfArg);
    }

    for (final raw in [
      memberId,
      cpfArg,
      authUid,
      email,
      email?.toLowerCase(),
    ]) {
      if (raw == null) continue;
      final snap = await tryHint(raw);
      if (snap != null && snap.exists) return snap;
    }
    return null;
  }
}
