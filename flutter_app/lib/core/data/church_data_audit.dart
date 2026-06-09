import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/church_repository.dart';

/// Relatório de aceite — camada de dados unificada.
class ChurchDataAuditReport {
  const ChurchDataAuditReport({
    required this.churchId,
    required this.platform,
    required this.rows,
    required this.verdict,
  });

  final String churchId;
  final String platform;
  final List<ChurchDataAuditRow> rows;
  final String verdict;

  bool get allOk => rows.every((r) => r.ok);

  String toReportTable() {
    final b = StringBuffer()
      ..writeln('=== RELATÓRIO CAMADA DE DADOS — GESTÃO YAHWEH ===')
      ..writeln('churchId: $churchId')
      ..writeln('plataforma: $platform')
      ..writeln('VEREDITO: $verdict')
      ..writeln('')
      ..writeln('| Módulo | Path | Docs | Status |');
    for (final r in rows) {
      b.writeln(
        '| ${r.module} | ${r.path} | ${r.count} | ${r.ok ? "OK" : "FALHA"} |',
      );
      if (r.error != null) b.writeln('| | ERRO: ${r.error} | | |');
    }
    return b.toString().trimRight();
  }
}

class ChurchDataAuditRow {
  const ChurchDataAuditRow({
    required this.module,
    required this.path,
    required this.count,
    required this.ok,
    this.error,
  });

  final String module;
  final String path;
  final int count;
  final bool ok;
  final String? error;
}

abstract final class ChurchDataAudit {
  ChurchDataAudit._();

  static String platformLabel() {
    if (kIsWeb) return 'WEB';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'IOS';
    if (defaultTargetPlatform == TargetPlatform.android) return 'ANDROID';
    return defaultTargetPlatform.name.toUpperCase();
  }

  static Future<ChurchDataAuditReport> runFull({
    required String churchIdHint,
  }) async {
    final id = ChurchDataRepository.churchId(churchIdHint);
    final probes = <ChurchDataAuditRow>[];

    Future<void> probe(String module, Future<dynamic> Function() fn) async {
      try {
        final r = await fn();
        final count = r.count as int? ?? 0;
        final path = r.collectionPath as String? ?? '';
        probes.add(ChurchDataAuditRow(
          module: module,
          path: path,
          count: count,
          ok: r.ok == true,
          error: r.error?.toString(),
        ));
      } catch (e) {
        probes.add(ChurchDataAuditRow(
          module: module,
          path: '',
          count: 0,
          ok: false,
          error: '$e',
        ));
      }
    }

    Future<void> countProbe(String module, String sub) async {
      try {
        final c = await ChurchFirestoreAccess.countOnce(
          module: module,
          churchId: id,
          subcollectionName: sub,
        );
        probes.add(ChurchDataAuditRow(
          module: module,
          path: ChurchDataPaths.subcollection(id, sub),
          count: c,
          ok: true,
        ));
      } catch (e) {
        probes.add(ChurchDataAuditRow(
          module: module,
          path: ChurchDataPaths.subcollection(id, sub),
          count: 0,
          ok: false,
          error: '$e',
        ));
      }
    }

    await countProbe('MEMBROS', ChurchDataPaths.membros);
    await countProbe('DEPARTAMENTOS', ChurchDataPaths.departamentos);
    await countProbe('CARGOS', ChurchDataPaths.cargos);
    await countProbe('EVENTOS', ChurchDataPaths.eventos);
    await countProbe('AVISOS', ChurchDataPaths.avisos);
    await countProbe('PATRIMÔNIO', ChurchDataPaths.patrimonio);
    await countProbe('CHAT', ChurchDataPaths.chats);
    await countProbe('FINANCEIRO', ChurchDataPaths.financeiro);
    await probe('FORNECEDORES', () => ChurchDataRepository.fornecedores.list(churchIdHint: id, limit: 20));
    await probe('ESCALAS', () => ChurchDataRepository.escalas.list(churchIdHint: id, limit: 20));
    await probe('AGENDA', () => ChurchDataRepository.agenda.list(churchIdHint: id, limit: 20));
    await probe('DOAÇÕES', () => ChurchDataRepository.doacoes.list(churchIdHint: id, limit: 20));
    await probe('MERCADO PAGO', () => ChurchDataRepository.mercadopago.list(churchIdHint: id, limit: 10));
    await probe('LÍDERES', () => ChurchDataRepository.lideres.list(churchIdHint: id, limit: 20));
    await probe('ADMINISTRATIVO', () => ChurchDataRepository.administrativo.list(churchIdHint: id, limit: 20));
    await probe('PEDIDOS ORAÇÃO', () => ChurchDataRepository.pedidosOracao.list(churchIdHint: id, limit: 20));
    await probe('TRANSFERÊNCIAS', () => ChurchDataRepository.transferencias.list(churchIdHint: id, limit: 20));
    await probe('CERTIFICADOS', () => ChurchDataRepository.certificados.list(churchIdHint: id, limit: 20));
    await probe('CARTÃO MEMBRO', () => ChurchDataRepository.cartoes.list(churchIdHint: id, limit: 10));

    final root = await ChurchDataRepository.loadChurchRoot(churchIdHint: id);
    probes.add(ChurchDataAuditRow(
      module: 'DASHBOARD/CADASTRO',
      path: root.documentPath,
      count: root.data.length,
      ok: root.ok,
      error: root.error,
    ));

    final allOk = probes.every((p) => p.ok);
    final platform = platformLabel();
    return ChurchDataAuditReport(
      churchId: id,
      platform: platform,
      rows: probes,
      verdict: allOk
          ? 'APROVADO — $platform OK'
          : 'REPROVADO — revisar módulos com FALHA',
    );
  }

  static String acceptanceChecklist(ChurchDataAuditReport report) {
    const modules = [
      'MEMBROS',
      'DEPARTAMENTOS',
      'CARGOS',
      'EVENTOS',
      'AVISOS',
      'CHAT',
      'PATRIMÔNIO',
      'FINANCEIRO',
      'FORNECEDORES',
      'ESCALAS',
      'AGENDA',
      'LÍDERES',
      'ADMINISTRATIVO',
      'DOAÇÕES',
      'MERCADO PAGO',
      'CARTÃO MEMBRO',
      'CERTIFICADOS',
      'PEDIDOS ORAÇÃO',
      'TRANSFERÊNCIAS',
      'DASHBOARD/CADASTRO',
    ];
    final byName = {for (final r in report.rows) r.module: r.ok};
    final b = StringBuffer()..writeln('CHECKLIST ACEITE:');
    for (final m in modules) {
      final ok = byName[m] == true ? 'OK' : 'PENDENTE';
      b.writeln('$m $ok');
    }
    b.writeln('WEB ${report.platform == "WEB" && report.allOk ? "OK" : "—"}');
    b.writeln('ANDROID ${report.platform == "ANDROID" && report.allOk ? "OK" : "—"}');
    b.writeln('IOS ${report.platform == "IOS" && report.allOk ? "OK" : "—"}');
    return b.toString().trimRight();
  }
}
