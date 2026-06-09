import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';

/// Linha de módulo na Central de Saúde do painel igreja.
class ChurchModuleHealthRow {
  const ChurchModuleHealthRow({
    required this.label,
    required this.count,
    required this.ok,
    this.path = '',
    this.detail = '',
  });

  final String label;
  final int count;
  final bool ok;
  final String path;
  final String detail;
}

/// Snapshot completo — infraestrutura + contagens por módulo.
class ChurchPanelHealthSnapshot {
  const ChurchPanelHealthSnapshot({
    required this.churchId,
    required this.infraChecks,
    required this.moduleRows,
    required this.audit,
    required this.productionReady,
  });

  final String churchId;
  final List<SystemHealthCheck> infraChecks;
  final List<ChurchModuleHealthRow> moduleRows;
  final ChurchDataAuditReport audit;
  final bool productionReady;

  bool get allModulesOk => moduleRows.every((r) => r.ok);

  int countFor(String label) {
    for (final r in moduleRows) {
      if (r.label == label) return r.count;
    }
    return 0;
  }
}

/// Saúde do sistema — painel igreja (Configurações → Saúde do Sistema).
abstract final class ChurchPanelHealthService {
  ChurchPanelHealthService._();

  static const _displayOrder = <String>[
    'Membros',
    'Departamentos',
    'Cargos',
    'Eventos',
    'Avisos',
    'Patrimônio',
    'Chat',
    'Financeiro',
    'Fornecedores',
    'Escalas',
    'Agenda',
    'Doações',
    'Mercado Pago',
    'Líderes',
    'Administrativo',
    'Pedidos Oração',
    'Transferências',
    'Certificados',
    'Cartão Membro',
    'Cadastro',
  ];

  static const _auditModuleLabels = <String, String>{
    'MEMBROS': 'Membros',
    'DEPARTAMENTOS': 'Departamentos',
    'CARGOS': 'Cargos',
    'EVENTOS': 'Eventos',
    'AVISOS': 'Avisos',
    'PATRIMÔNIO': 'Patrimônio',
    'CHAT': 'Chat',
    'FINANCEIRO': 'Financeiro',
    'FORNECEDORES': 'Fornecedores',
    'ESCALAS': 'Escalas',
    'AGENDA': 'Agenda',
    'DOAÇÕES': 'Doações',
    'MERCADO PAGO': 'Mercado Pago',
    'LÍDERES': 'Líderes',
    'ADMINISTRATIVO': 'Administrativo',
    'PEDIDOS ORAÇÃO': 'Pedidos Oração',
    'TRANSFERÊNCIAS': 'Transferências',
    'CERTIFICADOS': 'Certificados',
    'CARTÃO MEMBRO': 'Cartão Membro',
    'DASHBOARD/CADASTRO': 'Cadastro',
  };

  static Future<ChurchPanelHealthSnapshot> probe({
    String? churchIdHint,
    bool requireAuth = true,
  }) async {
    final id = ChurchRepository.resolveChurchId(churchIdHint);
    final audit = await ChurchRepository.runFullAudit(churchIdHint: id);
    final central = await SystemHealthService.probe(
      tenantIdHint: id,
      requireAuth: requireAuth,
    );

    final byLabel = <String, ChurchDataAuditRow>{};
    for (final row in audit.rows) {
      final label = _auditModuleLabels[row.module];
      if (label != null) byLabel[label] = row;
    }

    final moduleRows = <ChurchModuleHealthRow>[];
    for (final label in _displayOrder) {
      final row = byLabel[label];
      if (row == null) continue;
      moduleRows.add(
        ChurchModuleHealthRow(
          label: label,
          count: row.count,
          ok: row.ok,
          path: row.path,
          detail: row.error ?? (row.ok ? 'OK' : 'Falha na leitura'),
        ),
      );
    }

    final infra = _infraChecksFromCentral(central.checks);

    return ChurchPanelHealthSnapshot(
      churchId: id,
      infraChecks: infra,
      moduleRows: moduleRows,
      audit: audit,
      productionReady: central.productionReady && audit.allOk,
    );
  }

  static List<SystemHealthCheck> _infraChecksFromCentral(
    List<SystemHealthCheck> checks,
  ) {
    const wanted = {
      'Firebase Auth',
      'Firestore',
      'Storage',
      'Mercado Pago',
      'FCM',
      'Chat / Avisos / Eventos',
      'Site Público',
    };
    final out = <SystemHealthCheck>[];
    for (final c in checks) {
      if (wanted.contains(c.label)) out.add(c);
    }
    for (final c in checks) {
      if (c.label.startsWith('Chat') && !out.any((x) => x.label == c.label)) {
        out.add(c);
      }
      if (c.label == 'Avisos' || c.label == 'Eventos') {
        if (!out.any((x) => x.label == c.label)) out.add(c);
      }
    }
    if (out.isEmpty) return checks.take(8).toList();
    return out;
  }
}
