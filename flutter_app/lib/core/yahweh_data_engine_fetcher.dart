import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';
import 'package:gestao_yahweh/core/dashboard/church_dashboard_panel_controller.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_central_engine_service.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_aprovacoes_load_service.dart';
import 'package:gestao_yahweh/services/church_cargos_load_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/church_pedidos_oracao_load_service.dart';
import 'package:gestao_yahweh/services/church_visitantes_load_service.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Motor **unificado de leitura** — delega a [ChurchRepository] / [ChurchFirestoreAccess].
///
/// **Proibido** neste ficheiro e nas telas:
/// - ID de igreja hardcoded (ex.: piloto BPC)
/// - `FirebaseFirestore.instance` directo
/// - Paths fora de `igrejas/{churchId}/…`
///
/// Uso canónico:
/// ```dart
/// final churchId = widget.tenantId;
/// final rows = await YahwehDataEngineFetcher.readModuleCacheFirst(
///   collectionName: 'membros',
///   churchIdHint: churchId,
/// );
/// ```
abstract final class YahwehDataEngineFetcher {
  YahwehDataEngineFetcher._();

  /// Sem fallback fixo de tenant — usar sempre o churchId da sessão.
  static const String pilotChurchIdHint = '';

  static String resolveChurchId([String? hint]) =>
      ChurchRepository.churchId(hint);

  static String firestoreRootPath([String? hint]) =>
      ChurchRepository.firestorePath(hint);

  /// Normaliza nomes legados/errados para subcoleção real em [ChurchDataPaths].
  static String normalizeCollection(String collectionName) {
    final key = collectionName.trim();
    if (key.isEmpty) return key;
    switch (key) {
      case 'finance':
      case 'financeiro':
        return ChurchDataPaths.financeiro;
      case 'pedidos_oracao':
      case 'pedidosOracao':
        return ChurchDataPaths.pedidosOracao;
      case 'visitantes':
        return 'visitantes';
      case 'certificados':
      case 'certificados_emitidos':
        return ChurchDataPaths.certificados;
      case 'transferencias':
      case 'cartas_historico':
        return ChurchDataPaths.transferencias;
      case 'chats':
      case 'chat':
        return ChurchDataPaths.chats;
      case 'noticias':
        return ChurchDataPaths.eventos;
      default:
        return key;
    }
  }

  static ChurchModuleRepositoryBase? _moduleForSubcollection(String sub) {
    return switch (sub) {
      ChurchDataPaths.membros => ChurchRepository.membros,
      ChurchDataPaths.departamentos => ChurchRepository.departamentos,
      ChurchDataPaths.cargos => ChurchRepository.cargos,
      ChurchDataPaths.eventos => ChurchRepository.eventos,
      ChurchDataPaths.avisos => ChurchRepository.avisos,
      ChurchDataPaths.patrimonio => ChurchRepository.patrimonio,
      ChurchDataPaths.financeiro => ChurchRepository.financeiro,
      ChurchDataPaths.fornecedores => ChurchRepository.fornecedores,
      ChurchDataPaths.escalas => ChurchRepository.escalas,
      ChurchDataPaths.agenda => ChurchRepository.agenda,
      ChurchDataPaths.lideres => ChurchRepository.lideres,
      ChurchDataPaths.administrativo => ChurchRepository.administrativo,
      ChurchDataPaths.doacoes => ChurchRepository.doacoes,
      ChurchDataPaths.mercadopago => ChurchRepository.mercadopago,
      ChurchDataPaths.pedidosOracao => ChurchRepository.pedidosOracao,
      ChurchDataPaths.transferencias => ChurchRepository.transferencias,
      ChurchDataPaths.certificados => ChurchRepository.certificados,
      ChurchDataPaths.cartoes => ChurchRepository.cartoes,
      ChurchDataPaths.chats => ChurchRepository.chat,
      _ => null,
    };
  }

  static List<Map<String, dynamic>> _docsToMaps(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            return data;
          })
          .toList(growable: false);

  /// Leitura **cache-first** — padrão obrigatório ao abrir módulo (Web/Android/iOS).
  static Future<List<Map<String, dynamic>>> readModuleCacheFirst({
    required String collectionName,
    required String churchIdHint,
    int limitCount = YahwehPerformanceV4.defaultPageSize,
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)?
        customFilters,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    final sub = normalizeCollection(collectionName);
    final capped =
        FirebasePerformanceLimits.capListLimit(sub, limitCount);

    if (sub == ChurchDataPaths.pedidosOracao && customFilters == null) {
      final result = await ChurchPedidosOracaoLoadService.load(
        seedTenantId: churchId,
        limit: capped,
      );
      return result.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList(growable: false);
    }

    if (sub == ChurchDataPaths.cargos && customFilters == null) {
      final result = await ChurchCargosLoadService.load(
        seedTenantId: churchId,
      );
      return _docsToMaps(result.docs);
    }

    if (sub == 'visitantes' && customFilters == null) {
      final result = await ChurchVisitantesLoadService.load(
        seedTenantId: churchId,
        limit: capped,
      );
      return _docsToMaps(result.docs);
    }

    if (sub == 'aprovacoes') {
      final result = await ChurchAprovacoesLoadService.loadPendentes(
        seedTenantId: churchId,
      );
      return result.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList(growable: false);
    }

    if (sub == ChurchDataPaths.fornecedores && customFilters == null) {
      final result = await ChurchFornecedoresLoadService.load(
        seedTenantId: churchId,
        limit: capped,
      );
      return _docsToMaps(result.docs);
    }

    if (sub == ChurchDataPaths.patrimonio && customFilters == null) {
      final result = await ChurchPatrimonioLoadService.load(
        seedTenantId: churchId,
        limit: capped,
      );
      return _docsToMaps(result.docs);
    }

    if (sub == ChurchDataPaths.financeiro && customFilters == null) {
      final result = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: churchId,
        limit: capped,
      );
      return _docsToMaps(result.docs);
    }

    final module = _moduleForSubcollection(sub);
    if (module != null && customFilters == null) {
      final result = await ChurchRepository.listCacheFirst(
        module: module,
        churchIdHint: churchId,
        limit: capped,
      );
      return _docsToMaps(result.items);
    }

    return _fetchOnce(
      churchId: churchId,
      subcollection: sub,
      limit: capped,
      customFilters: customFilters,
    );
  }

  /// Atalho canónico — `igrejas/{churchId}/fornecedores` via [ChurchFornecedoresLoadService].
  static Future<List<Map<String, dynamic>>> readFornecedoresCacheFirst({
    required String churchIdHint,
    int limitCount = YahwehPerformanceV4.defaultPageSize,
  }) =>
      readModuleCacheFirst(
        collectionName: ChurchDataPaths.fornecedores,
        churchIdHint: churchIdHint,
        limitCount: limitCount,
      );

  /// Atalho canónico — `igrejas/{churchId}/patrimonio`.
  static Future<List<Map<String, dynamic>>> readPatrimonioCacheFirst({
    required String churchIdHint,
    int limitCount = YahwehPerformanceV4.defaultPageSize,
  }) =>
      readModuleCacheFirst(
        collectionName: ChurchDataPaths.patrimonio,
        churchIdHint: churchIdHint,
        limitCount: limitCount,
      );

  /// Alias legado — **proibido** tenant fixo; usa [churchIdHint] via [ChurchRepository].
  ///
  /// Web: polling resiliente ([FirestoreWebGuard]); Mobile: `snapshots()` limitado.
  /// Filtro `ativo` aplicado **no cliente** quando [filterActiveOnly] (campo boolean real).
  static Stream<List<Map<String, dynamic>>> fetchCollection({
    required String targetModule,
    required String churchIdHint,
    int limitCount = YahwehPerformanceV4.defaultPageSize,
    bool filterActiveOnly = false,
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)?
        filterPipeline,
  }) async* {
    await for (final rows in watchModuleData(
      collectionName: targetModule,
      churchIdHint: churchIdHint,
      limitCount: limitCount,
      customFilters: filterPipeline,
    )) {
      if (!filterActiveOnly) {
        yield rows;
        continue;
      }
      yield rows
          .where(ChurchModuleFirestoreListRead.isActiveRecord)
          .toList(growable: false);
    }
  }

  /// Stream reactivo — **Web:** polling leve; **Mobile:** `snapshots()` limitado.
  ///
  /// Preferir [readModuleCacheFirst] + `setState` no painel web quando possível.
  static Stream<List<Map<String, dynamic>>> watchModuleData({
    required String collectionName,
    required String churchIdHint,
    int limitCount = YahwehPerformanceV4.defaultPageSize,
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)?
        customFilters,
  }) async* {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      yield const [];
      return;
    }

    final sub = normalizeCollection(collectionName);
    final capped =
        FirebasePerformanceLimits.capListLimit(sub, limitCount);

    try {
      final cached = await readModuleCacheFirst(
        collectionName: sub,
        churchIdHint: churchId,
        limitCount: capped,
        customFilters: customFilters,
      );
      if (cached.isNotEmpty) yield cached;
    } catch (e) {
      debugPrint('YahwehDataEngineFetcher.watch cache: $e');
    }

    if (kIsWeb) {
      while (true) {
        try {
          yield await _fetchOnce(
            churchId: churchId,
            subcollection: sub,
            limit: capped,
            customFilters: customFilters,
          );
        } catch (e) {
          debugPrint('YahwehDataEngineFetcher.watch poll: $e');
          yield const [];
        }
        await Future<void>.delayed(const Duration(seconds: 8));
      }
    } else {
      Query<Map<String, dynamic>> query =
          ChurchRepository.collection(sub, churchIdHint: churchId)
              .limit(capped);
      if (customFilters != null) {
        query = customFilters(query);
      }
      yield* query.snapshots().map((snap) => _docsToMaps(snap.docs));
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchOnce({
    required String churchId,
    required String subcollection,
    required int limit,
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> query)?
        customFilters,
  }) async {
    final ref = ChurchFirestoreAccess.collectionRef(churchId, subcollection);
    if (customFilters != null) {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      Query<Map<String, dynamic>> query = ref.limit(limit);
      query = customFilters(query);
      final cacheKey = 'ydef_${churchId}_${subcollection}_$limit';
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => FirestoreReadResilience.getQuery(
          query,
          cacheKey: cacheKey,
        ),
        maxAttempts: kIsWeb ? 4 : 2,
      );
      return _docsToMaps(snap.docs);
    }

    final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ref,
      cacheKey: 'ydef_${churchId}_${subcollection}_$limit',
      limit: limit,
    );
    return _docsToMaps(docs);
  }

  /// Resumo financeiro — doc `_panel_cache/finance_summary` (sem scan de `finance`).
  static Future<Map<String, double>> readFinanceSummary({
    required String churchIdHint,
  }) async {
    final snap = await ChurchDashboardPanelController.readFinanceSummary(
      churchIdHint,
    );
    return _financeMapFromPanelSnapshot(snap);
  }

  /// Stream leve do resumo financeiro (polling web / doc watch mobile).
  static Stream<Map<String, double>> watchFinanceSummary({
    required String churchIdHint,
  }) async* {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      yield const {'receitas': 0, 'despesas': 0, 'saldo': 0};
      return;
    }

    try {
      yield await readFinanceSummary(churchIdHint: churchId);
    } catch (e) {
      debugPrint('YahwehDataEngineFetcher.finance cache: $e');
    }

    if (kIsWeb) {
      while (true) {
        try {
          yield await readFinanceSummary(churchIdHint: churchId);
        } catch (e) {
          debugPrint('YahwehDataEngineFetcher.finance poll: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 12));
      }
    } else {
      final ref = PanelFinanceSnapshotService.cacheRef(churchId);
      yield* ref.snapshots().map((doc) {
        final data = doc.data();
        if (data == null || data.isEmpty) {
          return const {'receitas': 0.0, 'despesas': 0.0, 'saldo': 0.0};
        }
        return _financeMapFromPanelSnapshot(
          PanelFinanceSnapshot.fromMap(data),
        );
      });
    }
  }

  static Map<String, double> _financeMapFromPanelSnapshot(
    PanelFinanceSnapshot snap,
  ) {
    var receitas = 0.0;
    var despesas = 0.0;
    for (final month in snap.months.values) {
      receitas += month.entradas;
      despesas += month.saidas;
    }
    return {
      'receitas': receitas,
      'despesas': despesas,
      'saldo': receitas - despesas,
    };
  }

  /// Config MP — `igrejas/{churchId}/config/{configDocId}` (não `config/` na raiz).
  static Future<Map<String, dynamic>?> readMercadoPagoConfig({
    required String churchIdHint,
    String configDocId = 'mercado_pago',
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return null;
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final hit = await IgrejaDirectFirestoreReads.readIgrejaConfig(
      churchId,
      configDocId,
    );
    if (hit == null) return null;
    final data = Map<String, dynamic>.from(hit.data);
    data['id'] = hit.docId;
    return data;
  }

  static Stream<Map<String, dynamic>?> watchMercadoPagoConfig({
    required String churchIdHint,
    String configDocId = 'mercado_pago',
  }) async* {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      yield null;
      return;
    }

    try {
      yield await readMercadoPagoConfig(
        churchIdHint: churchId,
        configDocId: configDocId,
      );
    } catch (e) {
      debugPrint('YahwehDataEngineFetcher.mp_config: $e');
    }

    if (kIsWeb) {
      while (true) {
        try {
          yield await readMercadoPagoConfig(
            churchIdHint: churchId,
            configDocId: configDocId,
          );
        } catch (e) {
          debugPrint('YahwehDataEngineFetcher.mp_config poll: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 20));
      }
    } else {
      final ref = ChurchRepository.churchDoc(churchId)
          .collection('config')
          .doc(configDocId);
      yield* ref.snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data();
        if (data == null || data.isEmpty) return null;
        return Map<String, dynamic>.from(data)..['id'] = doc.id;
      });
    }
  }

  /// Guia de leitura por módulo — complementa [YahwehCentralEngineService.moduleGuide].
  static String readGuide(YahwehCentralModule module) =>
      'Leitura: YahwehDataEngineFetcher.readModuleCacheFirst('
      'collectionName: «${module.collectionSegment}», churchIdHint: widget.tenantId). '
      'Path: igrejas/{churchId}/${normalizeCollection(module.collectionSegment)}. '
      'Limite inicial: ${YahwehPerformanceV4.defaultPageSize}.';
}
