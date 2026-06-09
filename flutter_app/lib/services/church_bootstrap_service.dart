import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';

/// Resultado do bootstrap paralelo do painel igreja (cadastro, logo, deps).
class ChurchBootstrapResult {
  const ChurchBootstrapResult({
    required this.churchId,
    required this.churchData,
    required this.loadDuration,
    this.logoPath,
    this.departmentsCount = 0,
    this.cargosCount = 0,
    this.membersCount = 0,
    this.firestoreMs,
    this.logoMs,
    this.departmentsMs,
    this.cargosMs,
    this.membersMs,
    this.error,
    this.readSource,
    this.fromCache = false,
  });

  final String churchId;
  final Map<String, dynamic> churchData;
  final Duration loadDuration;
  final String? logoPath;
  final int departmentsCount;
  final int cargosCount;
  final int membersCount;
  final int? firestoreMs;
  final int? logoMs;
  final int? departmentsMs;
  final int? cargosMs;
  final int? membersMs;
  final String? error;
  final String? readSource;
  final bool fromCache;

  bool get ok => error == null && churchData.isNotEmpty;
}

/// Carregamento paralelo com timeout — evita spinner infinito no Cadastro.
abstract final class ChurchBootstrapService {
  ChurchBootstrapService._();

  static const Duration kPanelTimeout = Duration(seconds: 15);

  /// Bootstrap do Cadastro — sem contagem de membros (mais rápido).
  static Future<ChurchBootstrapResult> loadCadastroPanel({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
  }) {
    return loadPanel(
      seedTenantId: seedTenantId,
      userUid: userUid,
      forceRefresh: forceRefresh,
      includeMembers: false,
    );
  }

  /// Bootstrap completo (cadastro + deps + logo + membros opcional).
  static Future<ChurchBootstrapResult> loadPanel({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
    bool includeMembers = true,
  }) async {
    final sw = Stopwatch()..start();
    var churchId = '';
    Map<String, dynamic> data = const {};
    String? logoPath;
    var deptCount = 0;
    var cargosCount = 0;
    var membersCount = 0;
    int? firestoreMs;
    int? logoMs;
    int? deptMs;
    int? cargosMsVal;
    int? membersMs;
    String? readSource;
    String? error;
    var fromCache = false;

    try {
      churchId = await ChurchContextService.resolveAndBind(
        seed: seedTenantId,
        userUid: userUid,
        forceRefresh: forceRefresh,
      ).timeout(ChurchContextService.kResolveTimeout);

      if (churchId.isEmpty) {
        throw StateError('churchId não resolvido.');
      }

      if (!forceRefresh) {
        final cached = await ChurchPanelLocalCache.readMap(
          churchId: churchId,
          module: ChurchPanelLocalCache.moduleCadastro,
        );
        if (cached != null && cached.isNotEmpty) {
          data = cached;
          fromCache = true;
          readSource = 'local_cache';
          logoPath = await ChurchPanelLocalCache.readLogoPath(churchId);
          deptCount = await ChurchPanelLocalCache.readModuleCount(
                churchId: churchId,
                module: 'departamentos',
              ) ??
              0;
          cargosCount = await ChurchPanelLocalCache.readModuleCount(
                churchId: churchId,
                module: 'cargos',
              ) ??
              0;
          if (includeMembers) {
            membersCount = await ChurchPanelLocalCache.readModuleCount(
                  churchId: churchId,
                  module: 'membros',
                ) ??
                0;
          }
          ChurchContextService.bindChurchData(
            churchId: churchId,
            data: data,
            bootstrapMs: sw.elapsedMilliseconds,
          );
          sw.stop();
          return ChurchBootstrapResult(
            churchId: churchId,
            churchData: data,
            loadDuration: sw.elapsed,
            logoPath: logoPath,
            departmentsCount: deptCount,
            cargosCount: cargosCount,
            membersCount: membersCount,
            readSource: readSource,
            fromCache: true,
          );
        }
      }

      final firestoreSw = Stopwatch()..start();
      final churchFuture = ChurchRepository.loadChurchData(
        seedTenantId: churchId,
        userUid: userUid,
        forceRefresh: forceRefresh,
        directDocOnly: true,
      ).timeout(kPanelTimeout);

      final logoFuture = ChurchBrandService.getLogoPath(
        churchId: churchId,
        verifyStorage: false,
      ).timeout(kPanelTimeout);

      final deptFuture =
          _countSubcollection(churchId, 'departamentos').timeout(kPanelTimeout);
      final cargosFuture =
          _countSubcollection(churchId, 'cargos').timeout(kPanelTimeout);
      final membersFuture = includeMembers
          ? _countSubcollection(churchId, 'membros').timeout(kPanelTimeout)
          : Future<int>.value(0);

      final batch = await Future.wait<Object?>([
        churchFuture,
        logoFuture,
        deptFuture,
        cargosFuture,
        membersFuture,
      ]).timeout(kPanelTimeout);

      firestoreSw.stop();
      firestoreMs = firestoreSw.elapsedMilliseconds;

      final churchResult = batch[0] as ChurchDataLoadResult;
      data = churchResult.data;
      readSource = churchResult.readSource;
      logoPath = batch[1] as String?;
      logoMs = sw.elapsedMilliseconds;
      deptCount = batch[2] as int;
      deptMs = sw.elapsedMilliseconds;
      cargosCount = batch[3] as int;
      cargosMsVal = sw.elapsedMilliseconds;
      membersCount = batch[4] as int;
      membersMs = sw.elapsedMilliseconds;

      ChurchContextService.bindChurchData(
        churchId: churchId,
        data: data,
        bootstrapMs: sw.elapsedMilliseconds,
      );
      unawaited(ChurchPanelLocalCache.saveMap(
        churchId: churchId,
        module: ChurchPanelLocalCache.moduleCadastro,
        data: data,
      ));
      if (logoPath != null && logoPath.isNotEmpty) {
        unawaited(ChurchPanelLocalCache.saveLogoPath(
          churchId: churchId,
          logoPath: logoPath,
        ));
      }
      unawaited(ChurchPanelLocalCache.saveModuleCount(
        churchId: churchId,
        module: 'departamentos',
        count: deptCount,
      ));
      unawaited(ChurchPanelLocalCache.saveModuleCount(
        churchId: churchId,
        module: 'cargos',
        count: cargosCount,
      ));
      if (includeMembers) {
        unawaited(ChurchPanelLocalCache.saveModuleCount(
          churchId: churchId,
          module: 'membros',
          count: membersCount,
        ));
      }
    } on TimeoutException {
      error =
          'Tempo esgotado (${kPanelTimeout.inSeconds}s) ao carregar o painel. '
          'Verifique a conexão e tente novamente.';
    } catch (e) {
      error = e.toString();
      debugPrint('ChurchBootstrapService.loadPanel: $e');
    }

    sw.stop();
    return ChurchBootstrapResult(
      churchId: churchId,
      churchData: data,
      loadDuration: sw.elapsed,
      logoPath: logoPath,
      departmentsCount: deptCount,
      cargosCount: cargosCount,
      membersCount: membersCount,
      firestoreMs: firestoreMs,
      logoMs: logoMs,
      departmentsMs: deptMs,
      cargosMs: cargosMsVal,
      membersMs: membersMs,
      error: error,
      readSource: readSource,
      fromCache: fromCache,
    );
  }

  static Future<int> _countSubcollection(
    String churchId,
    String subcollection,
  ) async {
    try {
      if (subcollection == 'departamentos') {
        final snap = await ChurchTenantResilientReads.departamentos(
          churchId,
          limit: 200,
        );
        return snap.docs.length;
      }
      final snap = await ChurchOperationalPaths.churchDoc(churchId)
          .collection(subcollection)
          .limit(200)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }
}
