import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Probe de paths por módulo — Configurações → Diagnóstico.
abstract final class ChurchModulePathAuditService {
  ChurchModulePathAuditService._();

  static Future<List<ChurchModuleProbeResult>> probeAllModules(
    String seedTenantId,
  ) async {
    final seed = seedTenantId.trim();
    if (seed.isEmpty) return const [];

    final churchId = ChurchRepository.churchId(seed).isNotEmpty
        ? ChurchRepository.churchId(seed)
        : seed;

    final docPath = 'igrejas/$churchId';
    final results = <ChurchModuleProbeResult>[];

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Future<void> probeChurchRootDoc() async {
      final sw = Stopwatch()..start();
      try {
        final r = await FirestoreWebGuard.runWithWebRecovery(
          () => ChurchRepository.loadByChurchId(
            churchId,
            seedTenantId: churchId,
          ),
          maxAttempts: kIsWeb ? 4 : 1,
        );
        sw.stop();
        final base = ChurchModuleProbeResult(
          module: 'Cadastro Igreja',
          churchId: r.churchId,
          collectionPath: docPath,
          documentPath: r.firestorePath,
          ok: r.data.isNotEmpty,
          count: r.fieldCount,
          durationMs: sw.elapsedMilliseconds,
        );
        results.add(base.copyWith(module: 'Cadastro Igreja'));
        results.add(
          base.copyWith(
            module: 'Configurações',
            collectionPath: '$docPath/config',
          ),
        );
      } catch (e) {
        sw.stop();
        final err = ChurchModuleProbeResult(
          module: 'Cadastro Igreja',
          churchId: churchId,
          collectionPath: docPath,
          documentPath: docPath,
          durationMs: sw.elapsedMilliseconds,
          error: '$e',
        );
        results.add(err);
        results.add(
          err.copyWith(
            module: 'Configurações',
            collectionPath: '$docPath/config',
          ),
        );
      }
    }

    Future<void> probeQuery(
      String module,
      String subcollection,
      Future<dynamic> Function() fetch,
    ) async {
      final path = '$docPath/$subcollection';
      final sw = Stopwatch()..start();
      try {
        final snap = await ChurchModuleFirestoreAudit.traceQuery(
          module: module,
          churchId: churchId,
          path: path,
          run: fetch,
        );
        sw.stop();
        final n = snap is ChurchDataListResult
            ? snap.count
            : (snap as dynamic).docs?.length as int? ?? 0;
        results.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: path,
          ok: true,
          count: n,
          durationMs: sw.elapsedMilliseconds,
        ));
      } catch (e) {
        sw.stop();
        results.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: path,
          durationMs: sw.elapsedMilliseconds,
          error: '$e',
        ));
      }
    }

    Future<void> webPause() async {
      if (kIsWeb) {
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
    }

    await probeChurchRootDoc();
    await webPause();
    await probeQuery(
      'Financeiro',
      'finance',
      () => ChurchTenantResilientReads.financeRecentNetwork(churchId, limit: 24),
    );
    await webPause();
    await probeQuery(
      'Fornecedores',
      'fornecedores',
      () => ChurchTenantResilientReads.fornecedoresNetwork(churchId, limit: 24),
    );
    await webPause();
    await probeQuery(
      'Patrimônio',
      'patrimonio',
      () => ChurchTenantResilientReads.patrimonio(churchId, limit: 12),
    );
    await webPause();
    await probeQuery(
      'Carteirinhas',
      'membros',
      () => ChurchTenantResilientReads.membrosRecent(churchId, limit: 8),
    );
    await webPause();
    await probeQuery(
      'Certificados',
      'certificados_emitidos',
      () => ChurchRepository.certificadosEmitidos(churchIdHint: churchId, limit: 8),
    );

    return results;
  }
}
