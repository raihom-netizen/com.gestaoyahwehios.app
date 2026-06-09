import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';

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

    Future<void> probeDoc(String module) async {
      final sw = Stopwatch()..start();
      try {
        final r = await ChurchRepository.loadChurchData(
          seedTenantId: churchId,
          directDocOnly: true,
        );
        sw.stop();
        results.add(ChurchModuleProbeResult(
          module: module,
          churchId: r.churchId,
          collectionPath: docPath,
          documentPath: r.firestorePath,
          ok: r.data.isNotEmpty,
          count: r.fieldCount,
          durationMs: sw.elapsedMilliseconds,
        ));
      } catch (e) {
        sw.stop();
        results.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: docPath,
          documentPath: docPath,
          durationMs: sw.elapsedMilliseconds,
          error: '$e',
        ));
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
        final n = (snap as dynamic).docs?.length as int? ?? 0;
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

    await probeDoc('Cadastro Igreja');
    await probeDoc('Configurações');
    await probeQuery(
      'Financeiro',
      'finance',
      () => ChurchTenantResilientReads.financeRecentNetwork(churchId, limit: 24),
    );
    await probeQuery(
      'Fornecedores',
      'fornecedores',
      () => ChurchTenantResilientReads.fornecedoresNetwork(churchId, limit: 24),
    );
    await probeQuery(
      'Patrimônio',
      'patrimonio',
      () => ChurchTenantResilientReads.patrimonio(churchId, limit: 12),
    );
    await probeQuery(
      'Carteirinhas',
      'membros',
      () => ChurchTenantResilientReads.membrosRecent(churchId, limit: 8),
    );
    await probeQuery(
      'Certificados',
      'certificados_emitidos',
      () => ChurchRepository.certificadosEmitidos(churchIdHint: churchId, limit: 8),
    );

    return results;
  }
}
