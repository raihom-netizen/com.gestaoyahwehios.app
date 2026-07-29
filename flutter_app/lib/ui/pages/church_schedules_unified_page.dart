import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';

import 'my_schedules_page.dart';
import 'schedules_page.dart';

/// Ponto único de entrada para o módulo **Escala**.
///
/// Quem pode montar/editar escalas (pastor, adm, gestor, secretário,
/// tesoureiro, líder de departamento) vê a [SchedulesPage] completa.
/// Membros comuns visualizam apenas a [MySchedulesPage] com seus
/// compromissos.
class ChurchSchedulesUnifiedPage extends StatelessWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool embeddedInShell;

  const ChurchSchedulesUnifiedPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    this.embeddedInShell = false,
  });

  bool get _canEditOrLead {
    if (AppPermissions.canEditSchedules(role)) return true;
    if (ChurchRolePermissions.isDepartmentLeaderRoleKey(role)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_canEditOrLead) {
      return SchedulesPage(
        key: key,
        tenantId: tenantId,
        role: role,
        cpf: cpf,
        embeddedInShell: embeddedInShell,
      );
    }
    return MySchedulesPage(
      key: key,
      tenantId: tenantId,
      cpf: cpf,
      role: role,
      embeddedInShell: embeddedInShell,
    );
  }
}
