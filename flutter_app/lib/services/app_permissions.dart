import 'package:gestao_yahweh/core/roles_permissions.dart';

/// Central de papéis e permissões do sistema.
/// Atualize conforme novos módulos e regras forem criados.
class AppRoles {
  static const admin = 'admin';
  static const adm = 'adm';
  static const gestor = 'gestor';
  static const master = 'master';
  static const tesouraria = 'tesouraria';
  static const tesoureiro = 'tesoureiro';
  static const lider = 'lider';
  static const membro = 'membro';
  static const visitante = 'visitante';
  static const secretario = 'secretario';
  static const pastor = 'pastor';
  static const presbitero = 'presbitero';
  static const diacono = 'diacono';
  static const evangelista = 'evangelista';
  static const musico = 'musico';

  static const values = [
    admin, adm, gestor, master, tesouraria, tesoureiro, lider, membro, visitante,
    secretario, pastor, presbitero, diacono, evangelista, musico,
  ];

  /// Sinônimo de [adm] quando o Firestore gravou rótulo ou [resolvePermissionBase] devolveu a palavra inteira.
  static bool _isAdmLike(String r) =>
      r == admin || r == adm || r == 'administrador' || r == 'administradora';

  /// Funções que têm acesso total (painel completo)
  static bool isFullAccess(String role) {
    final r = role.toLowerCase();
    return _isAdmLike(r) ||
        r == gestor ||
        r == master ||
        r == 'pastor_presidente';
  }

  /// Funções que podem ver financeiro e patrimônio
  static bool canAccessFinanceAndPatrimonio(String role) {
    final r = role.toLowerCase();
    return [
      admin, adm, master, gestor, tesouraria, tesoureiro, secretario, pastor, presbitero,
      'administrador', 'administradora',
    ].contains(r);
  }

  /// Funções que podem editar escalas
  static bool canAccessEditSchedules(String role) {
    final r = role.toLowerCase();
    return [
      admin, adm, master, gestor, lider, pastor, presbitero, secretario,
      'administrador', 'administradora',
    ].contains(r);
  }

  /// Funções que podem editar departamentos
  static bool canAccessEditDepartments(String role) {
    final r = role.toLowerCase();
    return [
      admin, adm, master, gestor, pastor, 'pastora', presbitero, 'presbitera', secretario,
      'administrador', 'administradora',
    ].contains(r);
  }
}

class AppPermissions {
  static List<String> normalizePermissions(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>{};
    for (final e in raw) {
      final p = e.toString().trim().toLowerCase();
      if (p.isNotEmpty) out.add(p);
    }
    return out.toList();
  }

  static bool hasModulePermission(List<String>? permissions, String moduleKey) {
    if (permissions == null || permissions.isEmpty) return false;
    final key = moduleKey.trim().toLowerCase();
    final set = permissions.map((e) => e.trim().toLowerCase()).toSet();
    return set.contains(key);
  }

  // Módulo financeiro — gestor pode liberar para membro via flag no doc do membro (podeVerFinanceiro)
  static bool canViewFinance(String role, {bool? memberCanViewFinance, List<String>? permissions}) {
    final s = ChurchRolePermissions.snapshotFor(role);
    if (s.viewFinance) return true;
    final r = role.toLowerCase();
    if (hasModulePermission(permissions, 'financeiro')) return true;
    if (r == AppRoles.membro && memberCanViewFinance == true) return true;
    return false;
  }

  // Módulo patrimônio — membro só se gestor liberar (podeVerPatrimonio no doc)
  static bool canViewPatrimonio(String role, {bool? memberCanViewPatrimonio, List<String>? permissions}) {
    final s = ChurchRolePermissions.snapshotFor(role);
    if (s.viewPatrimonio) return true;
    final r = role.toLowerCase();
    if (hasModulePermission(permissions, 'patrimonio')) return true;
    if (r == AppRoles.membro && memberCanViewPatrimonio == true) return true;
    return false;
  }

  /// Fornecedores/prestadores — granular `fornecedores`, flag no membro, ou mesmo critério do financeiro (tesoureiro, etc.).
  static bool canViewFornecedores(
    String role, {
    bool? memberCanViewFinance,
    bool? memberCanViewFornecedores,
    List<String>? permissions,
  }) {
    if (hasModulePermission(permissions, 'fornecedores')) return true;
    final r = role.toLowerCase();
    if (r == AppRoles.membro && memberCanViewFornecedores == true) return true;
    return canViewFinance(
      role,
      memberCanViewFinance: memberCanViewFinance,
      permissions: permissions,
    );
  }

  /// Módulo Certificados (emissão / histórico) — não para papel [membro] básico.
  /// Acesso: ADM, gestor, secretário, pastor, etc. (editAnyMember), tesoureiro(a), ou permissão `certificados`.
  static bool canAccessCertificados(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'certificados')) return true;
    final s = ChurchRolePermissions.snapshotFor(role);
    final r = role.toLowerCase();
    if (s.restrictedNav) return false;
    if (r == AppRoles.tesouraria || r == AppRoles.tesoureiro) return true;
    return s.editAnyMember || s.approvePendingMembers;
  }

  /// Cartas de apresentação / transferência (PDF) — mesmo perfil que certificados ou chave `cartas_transferencias`.
  static bool canAccessChurchLetters(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'cartas_transferencias')) return true;
    return canAccessCertificados(role, permissions: permissions);
  }

  /// Converter visitante em membro: equipe com cadastro — não o papel [membro].
  static bool canConvertVisitorToMember(String role) {
    final s = ChurchRolePermissions.snapshotFor(role);
    return s.editAnyMember || s.approvePendingMembers;
  }

  // Módulo membros (dados sensíveis)
  static bool canViewSensitiveMembers(String role) {
    final s = ChurchRolePermissions.snapshotFor(role);
    return s.viewMemberDirectory || s.editAnyMember;
  }

  /// Quem pode editar/excluir qualquer membro, criar login, redefinir senha de terceiros, cargos e status.
  /// Papel [membro] só altera o próprio cadastro (UI + fluxo "Meu cadastro").
  static bool canEditAnyChurchMember(String role) {
    return ChurchRolePermissions.snapshotFor(role).editAnyMember;
  }

  // Módulo escalas (Escala Geral — membro não vê; só "Minha Escala" do departamento dele)
  static bool canEditSchedules(String role) =>
      ChurchRolePermissions.snapshotFor(role).editSchedulesAll;

  /// Acesso restrito para role "membro": só Painel, Mural, Eventos, Pedidos, Agenda, Minha Escala, Cartão (e Finance se gestor liberar).
  static bool isRestrictedMember(String role) =>
      ChurchRolePermissions.snapshotFor(role).restrictedNav;

  /// Configurações de integração bancária / Mercado Pago na igreja — só gestores, tesouraria ou permissão granular `configuracoes_banco`.
  /// Membro restrito não vê salvo o gestor conceder a chave em [permissions] no cadastro.
  static bool canViewChurchMercadoPagoSettings(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'configuracoes_banco')) return true;
    if (isRestrictedMember(role)) return false;
    final r = role.toLowerCase();
    return AppRoles.isFullAccess(role) || r == AppRoles.tesoureiro || r == AppRoles.tesouraria;
  }

  /// Relatórios PDF completos (membros, aniversariantes, etc.). Perfil restrito: só [Relatório de Eventos], salvo
  /// permissão granular `relatorios` ou `podeEmitirRelatoriosCompletos` no cadastro do membro (gestor).
  static bool canEmitFullChurchReports(
    String role, {
    bool? memberCanEmitFullReports,
    List<String>? permissions,
  }) {
    final s = ChurchRolePermissions.snapshotFor(role);
    if (!s.restrictedNav) return true;
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (memberCanEmitFullReports == true) return true;
    return false;
  }

  // Módulo departamentos (hub, kit, vínculos) — papel + módulo granular `departamentos`.
  static bool canEditDepartments(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'departamentos')) return true;
    return ChurchRolePermissions.snapshotFor(role).editDepartments;
  }

  /// Despesa acima do limite exige segunda aprovação (tesoureiro/líder não “auto-aprovam”).
  static bool despesaFinanceiraExigeSegundaAprovacao(String? role) {
    if (role == null) return true;
    final r = role.toLowerCase();
    if (r == 'gestor' ||
        r == 'adm' ||
        r == 'admin' ||
        r == 'master' ||
        r == 'pastor_presidente' ||
        r == 'pastor' ||
        r == 'pastora') {
      return false;
    }
    return true;
  }

  /// Quem pode aprovar uma despesa pendente (`aprovacaoPendente`).
  static bool canApproveFinanceDespesaPendente(String role) {
    if (!canViewFinance(role)) return false;
    final s = ChurchRolePermissions.snapshotFor(role);
    final r = role.toLowerCase();
    if (s.editAnyMember || s.approvePendingMembers) return true;
    if (r == 'tesoureiro' || r == 'tesouraria') return true;
    return false;
  }

  /// Limite de aprovação e orçamentos por categoria (`config/finance_settings`).
  static bool canManageFinanceTenantSettings(String role) {
    if (!canViewFinance(role)) return false;
    if (canApproveFinanceDespesaPendente(role)) return true;
    return !despesaFinanceiraExigeSegundaAprovacao(role);
  }
}
