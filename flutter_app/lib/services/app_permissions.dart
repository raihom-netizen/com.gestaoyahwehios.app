import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_moderation.dart';

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
    final n = ChurchRolePermissions.normalize(role);
    if (const {
      ChurchRoleKeys.adm,
      ChurchRoleKeys.gestor,
      ChurchRoleKeys.master,
      ChurchRoleKeys.pastorPresidente,
      ChurchRoleKeys.pastor,
      ChurchRoleKeys.secretario,
    }.contains(n)) {
      return true;
    }
    final r = role.toLowerCase();
    return _isAdmLike(r);
  }

  /// Alinhado a [ChurchRolePermissions.isFinanceCoreTeam] (admin, gestor, pastor, tesoureiro).
  static bool canAccessFinanceAndPatrimonio(String role) =>
      ChurchRolePermissions.isFinanceCoreTeam(role);

  /// Escala geral da igreja (todos os departamentos) — não inclui líder de departamento (escopo por CPF).
  static bool canAccessEditSchedules(String role) {
    final r = role.toLowerCase();
    return [
      admin, adm, master, gestor, pastor, presbitero, secretario,
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
    if (set.contains(key)) return true;
    // Aliases (cargos granulares)
    if (key == 'eventos' || key == 'eventos_avisos_edicao') {
      return set.contains('eventos') || set.contains('eventos_avisos_edicao');
    }
    return false;
  }

  /// Permissões granulares recomendadas para [lider_departamento] (mural, eventos, agenda).
  static List<String> defaultDepartmentLeaderModulePermissions() => const [
        'mural_avisos_edicao',
        'eventos_avisos_edicao',
        'eventos',
        'agenda_edicao',
        'agenda_ver',
        'departamentos',
        'escalas',
      ];

  /// Mescla permissões do cargo líder sem remover chaves já concedidas pelo gestor.
  static List<String> mergeDepartmentLeaderModulePermissions(
    List<String>? existing,
  ) {
    final out = <String>{
      ...defaultDepartmentLeaderModulePermissions(),
      ...normalizePermissions(existing),
    };
    out.remove('mural_avisos_somente_leitura');
    out.remove('financeiro');
    out.remove('patrimonio');
    out.remove('fornecedores');
    out.remove('relatorios');
    out.removeWhere((k) => k.startsWith('relatorio_'));
    return out.toList();
  }

  /// Criar/editar/excluir avisos, eventos (feed) e agenda interna.
  /// Alinhado a [canWriteMuralFeed] no Firestore: gestor/admin, pastoral, secretário,
  /// tesoureiro e líder de departamento — não membro comum nem permissão `eventos` isolada.
  static bool canManageChurchMuralEventsAgenda(
    String role, {
    List<String>? permissions,
  }) {
    if (hasModulePermission(permissions, 'agenda_edicao')) return true;
    if (hasModulePermission(permissions, 'mural_avisos_edicao') ||
        hasModulePermission(permissions, 'eventos_avisos_edicao') ||
        hasModulePermission(permissions, 'eventos')) {
      return true;
    }
    if (hasModulePermission(permissions, 'mural_avisos_somente_leitura') &&
        !hasModulePermission(permissions, 'mural_avisos_edicao')) {
      return false;
    }
    if (hasModulePermission(permissions, 'eventos_avisos_ver') &&
        !hasModulePermission(permissions, 'eventos_avisos_edicao') &&
        !hasModulePermission(permissions, 'eventos')) {
      return false;
    }
    if (hasModulePermission(permissions, 'agenda_ver') &&
        !hasModulePermission(permissions, 'agenda_edicao')) {
      return false;
    }
    if (isRestrictedMember(role)) return false;
    final n = ChurchRolePermissions.normalize(role);
    if (ChurchRolePermissions.isDepartmentLeaderRoleKey(n)) return true;
    if (n == ChurchRoleKeys.pastor ||
        n == ChurchRoleKeys.pastorAuxiliar ||
        n == ChurchRoleKeys.pastorPresidente ||
        n == ChurchRoleKeys.presbitero ||
        n == ChurchRoleKeys.secretario ||
        n == ChurchRoleKeys.tesoureiro ||
        n == ChurchRoleKeys.tesouraria) {
      return true;
    }
    return AppRoles.isFullAccess(role);
  }

  /// Escalas: pastoral com escala geral OU líder com pelo menos um departamento (vários permitidos).
  static bool canWriteDepartmentSchedules(
    String role, {
    Set<String> managedDepartmentIds = const {},
  }) {
    if (canEditSchedules(role)) return true;
    return managedDepartmentIds.isNotEmpty;
  }

  /// Há chaves `relatorio_*` sem o guarda-chuva `relatorios` — relatórios passam a ser só os marcados.
  static bool usesGranularChurchReportsOnly(List<String>? permissions) {
    if (permissions == null || permissions.isEmpty) return false;
    final set = permissions.map((e) => e.trim().toLowerCase()).toSet();
    if (set.contains('relatorios')) return false;
    return set.any((k) => k.startsWith('relatorio_'));
  }

  /// PDF Relatório de Eventos (painel).
  static bool canAccessRelatorioEventosPdf({List<String>? permissions}) {
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_eventos')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return true;
  }

  /// PDF Relatório de Membros.
  static bool canAccessRelatorioMembrosPdf(
    String role, {
    List<String>? permissions,
    bool? memberCanEmitFullReports,
  }) {
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_membros')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return canEmitFullChurchReports(
      role,
      memberCanEmitFullReports: memberCanEmitFullReports,
      permissions: permissions,
    );
  }

  /// PDF Aniversariantes.
  static bool canAccessRelatorioAniversariantesPdf(
    String role, {
    List<String>? permissions,
    bool? memberCanEmitFullReports,
  }) {
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_aniversariantes')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return canEmitFullChurchReports(
      role,
      memberCanEmitFullReports: memberCanEmitFullReports,
      permissions: permissions,
    );
  }

  static bool canAccessRelatorioFinanceiroBundle(
    String role, {
    required bool canViewFinance,
    List<String>? permissions,
    bool? memberCanEmitFullReports,
  }) {
    if (!canViewFinance) return false;
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_financeiro')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return canEmitFullChurchReports(
      role,
      memberCanEmitFullReports: memberCanEmitFullReports,
      permissions: permissions,
    );
  }

  static bool canAccessRelatorioFornecedoresBundle(
    String role, {
    required bool canViewFinance,
    List<String>? permissions,
    bool? memberCanEmitFullReports,
  }) {
    if (!canViewFinance) return false;
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_fornecedores')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return canEmitFullChurchReports(
      role,
      memberCanEmitFullReports: memberCanEmitFullReports,
      permissions: permissions,
    );
  }

  static bool canAccessRelatorioPatrimonioBundle(
    String role, {
    required bool canViewPatrimonio,
    List<String>? permissions,
    bool? memberCanEmitFullReports,
  }) {
    if (!canViewPatrimonio) return false;
    if (hasModulePermission(permissions, 'relatorios')) return true;
    if (hasModulePermission(permissions, 'relatorio_patrimonio')) return true;
    if (usesGranularChurchReportsOnly(permissions)) return false;
    return canEmitFullChurchReports(
      role,
      memberCanEmitFullReports: memberCanEmitFullReports,
      permissions: permissions,
    );
  }

  /// Edição no diretório de membros: respeita `membros_ver` só leitura vs `membros_edicao`.
  static bool canEditMembersDirectory(String role, List<String>? permissions) {
    final p = permissions;
    if (p != null && p.isNotEmpty) {
      final set = p.map((e) => e.trim().toLowerCase()).toSet();
      if (set.contains('membros_ver') &&
          !set.contains('membros_edicao') &&
          !set.contains('membros')) {
        return false;
      }
      if (set.contains('membros_edicao') ||
          (set.contains('membros') && !set.contains('membros_ver'))) {
        return true;
      }
    }
    return canEditAnyChurchMember(role);
  }

  /// Histórico global de doações (todas as contribuições): mesmo núcleo que o Financeiro.
  /// Membros sem este papel só veem as próprias linhas em [ChurchDonationsPage] (filtro por CPF).
  static bool canSeeAllChurchDonationHistory(String role) =>
      ChurchRolePermissions.isFinanceCoreTeam(role);

  /// Módulo financeiro (painel) — corpo administrativo + permissão granular `financeiro`.
  static bool canViewFinance(String role, {bool? memberCanViewFinance, List<String>? permissions}) {
    if (hasModulePermission(permissions, 'financeiro')) return true;
    if (memberCanViewFinance == true) return true;
    return ChurchRolePermissions.isFinancePanelTeam(role);
  }

  /// Patrimônio — corpo administrativo ou permissão granular `patrimonio`.
  static bool canViewPatrimonio(String role, {bool? memberCanViewPatrimonio, List<String>? permissions}) {
    if (hasModulePermission(permissions, 'patrimonio')) return true;
    if (memberCanViewPatrimonio == true) return true;
    return ChurchRolePermissions.isCorporateModuleTeam(role);
  }

  /// Editar/excluir/inventário — quem vê o módulo pode gravar (Firestore + Storage).
  static bool canWritePatrimonio(String role, {bool? memberCanViewPatrimonio, List<String>? permissions}) =>
      canViewPatrimonio(
        role,
        memberCanViewPatrimonio: memberCanViewPatrimonio,
        permissions: permissions,
      );

  /// Fornecedores — corpo administrativo; quem tem Financeiro também acede.
  static bool canViewFornecedores(
    String role, {
    bool? memberCanViewFinance,
    bool? memberCanViewFornecedores,
    List<String>? permissions,
  }) {
    if (hasModulePermission(permissions, 'fornecedores')) return true;
    if (memberCanViewFornecedores == true) return true;
    if (canViewFinance(
      role,
      memberCanViewFinance: memberCanViewFinance,
      permissions: permissions,
    )) {
      return true;
    }
    return ChurchRolePermissions.isCorporateModuleTeam(role);
  }

  /// Hub «Relatórios» financeiros — corpo administrativo (gestor, secretário, tesouraria, pastoral).
  static bool canAccessChurchRelatoriosHub(String role) =>
      ChurchRolePermissions.isFinancePanelTeam(role);

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

  /// Trocar foto de perfil de qualquer membro no módulo Membros (alinhado a [canStaffEditAnyMemberRecord] no Firestore).
  static bool canStaffEditAnyMemberProfilePhoto(String role) {
    if (AppRoles.isFullAccess(role)) return true;
    final n = ChurchRolePermissions.normalize(role);
    if (n == ChurchRoleKeys.pastor ||
        n == ChurchRoleKeys.pastorAuxiliar ||
        n == ChurchRoleKeys.pastorPresidente ||
        n == ChurchRoleKeys.secretario ||
        n == ChurchRoleKeys.tesoureiro ||
        n == ChurchRoleKeys.tesouraria) {
      return true;
    }
    return false;
  }

  // Módulo escalas (Escala Geral — membro não vê; só "Minha Escala" do departamento dele)
  static bool canEditSchedules(String role) =>
      ChurchRolePermissions.snapshotFor(role).editSchedulesAll;

  /// Acesso restrito para role "membro": menu reduzido (sem Finance/Património/Relatórios globais).
  static bool isRestrictedMember(String role) =>
      ChurchRolePermissions.snapshotFor(role).restrictedNav;

  /// Integração Mercado Pago da igreja (PIX/cartão na tesouraria) — **muito restrita**:
  /// só [gestor], [master] da igreja ou administrador (`admin`/`adm`/`administrador*`),
  /// ou permissão granular `configuracoes_banco` concedida pelo gestor.
  /// Tesoureiro, pastor e outros papéis **não** vêem esta secção por defeito (alinhado a `saveChurchMercadoPagoCredentials`).
  static bool canViewChurchMercadoPagoSettings(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'configuracoes_banco')) return true;
    if (isRestrictedMember(role)) return false;
    final r = role.toLowerCase().trim();
    final adminLike = r == AppRoles.admin ||
        r == AppRoles.adm ||
        r == 'administrador' ||
        r == 'administradora';
    final gestorLike = r == AppRoles.gestor || r == AppRoles.master;
    return adminLike || gestorLike;
  }

  /// Pagamento / renovação da **licença SaaS** (Mercado Pago) — só liderança financeira.
  /// Membros comuns (ex.: secretária de departamento que não é gestora) **não** podem gerar cobrança.
  static bool canPurchaseChurchLicense(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'licenca_pagamento')) return true;
    if (isRestrictedMember(role)) return false;
    final r = role.toLowerCase().trim();
    if (r == AppRoles.gestor || r == AppRoles.master) return true;
    if (r == AppRoles.admin ||
        r == AppRoles.adm ||
        r == 'administrador' ||
        r == 'administradora') {
      return true;
    }
    if (r == AppRoles.secretario ||
        r == 'secretaria' ||
        r == 'secretário' ||
        r == 'secretária') {
      return true;
    }
    if (r == AppRoles.tesoureiro || r == AppRoles.tesouraria) return true;
    return false;
  }

  /// Links de recebimento (Mercado Pago) — gestor, pastor, tesoureiro.
  static bool canManageChurchPaymentReceiving(
    String role, {
    List<String>? permissions,
  }) {
    if (canViewChurchMercadoPagoSettings(role, permissions: permissions)) {
      return true;
    }
    if (isRestrictedMember(role)) return false;
    final r = role.toLowerCase().trim();
    if (r == AppRoles.tesoureiro ||
        r == AppRoles.tesouraria ||
        r == ChurchRoleKeys.pastor ||
        r == ChurchRoleKeys.pastorPresidente ||
        r == ChurchRoleKeys.pastorAuxiliar) {
      return true;
    }
    return false;
  }

  /// Relatórios PDF completos (membros, aniversariantes, etc.). Perfil restrito: só [Relatório de Eventos], salvo
  /// permissão granular `relatorios` ou `podeEmitirRelatoriosCompletos` no cadastro do membro (gestor).
  static bool canEmitFullChurchReports(
    String role, {
    bool? memberCanEmitFullReports,
    List<String>? permissions,
  }) {
    if (usesGranularChurchReportsOnly(permissions)) return false;
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

  /// Aba Chat → Grupos: vê **todos** os departamentos (adm, gestor, pastor, secretário, tesoureiro).
  /// **Não** inclui líder de departamento — esse vê só os grupos em que participa + os que lidera.
  static bool chatHubSeesAllDepartmentGroups(
    String role, {
    List<String>? permissions,
  }) {
    if (hasModulePermission(permissions, 'departamentos')) return true;
    if (AppRoles.isFullAccess(role)) return true;
    final n = ChurchRolePermissions.normalize(role);
    return const {
      ChurchRoleKeys.pastor,
      ChurchRoleKeys.pastorPresidente,
      ChurchRoleKeys.pastorAuxiliar,
      ChurchRoleKeys.secretario,
      ChurchRoleKeys.presbitero,
      ChurchRoleKeys.tesoureiro,
      ChurchRoleKeys.tesouraria,
    }.contains(n);
  }

  /// Transmissão push + grupos chat (lista de difusão no Chat Igreja).
  static bool canSendChurchBroadcast(
    String role, {
    List<String>? permissions,
  }) {
    if (chatHubSeesAllDepartmentGroups(role, permissions: permissions)) {
      return true;
    }
    return ChurchRolePermissions.isDepartmentLeaderRoleKey(role);
  }

  /// Adicionar/remover membros no grupo do departamento (chat).
  /// Pastoral/gestão ou líder **deste** departamento ([leaderCpfs] / UID).
  static bool canManageDepartmentChatMembers({
    required String role,
    List<String>? permissions,
    Map<String, dynamic>? departmentData,
    required String memberCpfDigits,
  }) {
    if (hasModulePermission(permissions, 'departamentos')) return true;
    return ChurchChatModeration.canManageDepartmentGroup(
      memberRole: role,
      memberCpfDigits: memberCpfDigits,
      isDepartmentThread: true,
      departmentData: departmentData,
    );
  }

  /// Aprovações rápidas (cadastros públicos pendentes) — menu índice 18 + regra `membros` no Firestore.
  static bool canApprovePendingMemberSignups(String role, {List<String>? permissions}) {
    if (hasModulePermission(permissions, 'membros')) return true;
    return ChurchRolePermissions.snapshotFor(role).approvePendingMembers;
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

  /// Gestor, pastor, secretário, administrador (ADM) — exclusão geral no painel igreja.
  static bool canDeleteAnyChurchRecords(
    String role, {
    List<String>? permissions,
  }) {
    if (AppRoles.isFullAccess(role)) return true;
    final n = ChurchRolePermissions.normalize(role);
    if (const {
      ChurchRoleKeys.adm,
      ChurchRoleKeys.gestor,
      ChurchRoleKeys.master,
      ChurchRoleKeys.pastorPresidente,
      ChurchRoleKeys.pastor,
      ChurchRoleKeys.pastorAuxiliar,
      ChurchRoleKeys.secretario,
      ChurchRoleKeys.presbitero,
    }.contains(n)) {
      return true;
    }
    final r = role.toLowerCase().trim();
    return r == 'administrador' || r == 'administradora';
  }

  /// Pedidos de oração — pastoral/admin ou autor do pedido.
  static bool canManagePrayerRequest(
    String role, {
    required String currentUid,
    required Map<String, dynamic> data,
    List<String>? permissions,
  }) {
    if (canDeleteAnyChurchRecords(role, permissions: permissions)) return true;
    final uid = currentUid.trim();
    if (uid.isEmpty) return false;
    return (data['autorUid'] ?? '').toString().trim() == uid;
  }

  /// Excluir lançamento financeiro — equipe admin/pastoral/tesouraria.
  static bool canDeleteFinanceLancamento(
    String role, {
    List<String>? permissions,
  }) {
    if (hasModulePermission(permissions, 'financeiro')) return true;
    if (canDeleteAnyChurchRecords(role, permissions: permissions)) return true;
    return ChurchRolePermissions.isFinanceCoreTeam(role);
  }

  /// UID do autor de post mural (aviso/evento).
  static String muralFeedAuthorUid(Map<String, dynamic> data) =>
      (data['createdByUid'] ?? data['authorUid'] ?? '').toString().trim();

  /// Avisos/eventos: admin/pastoral exclui tudo; líder de departamento só o que criou.
  static bool canDeleteMuralFeedRecord(
    String role, {
    required String currentUid,
    required Map<String, dynamic> data,
    List<String>? permissions,
  }) {
    if (canDeleteAnyChurchRecords(role, permissions: permissions)) return true;
    if (!canManageChurchMuralEventsAgenda(role, permissions: permissions)) {
      return false;
    }
    final author = muralFeedAuthorUid(data);
    final uid = currentUid.trim();
    return author.isNotEmpty && uid.isNotEmpty && author == uid;
  }

  /// Alias semântico — editar segue a mesma regra de exclusão no mural/feed.
  static bool canEditMuralFeedRecord(
    String role, {
    required String currentUid,
    required Map<String, dynamic> data,
    List<String>? permissions,
  }) =>
      canDeleteMuralFeedRecord(
        role,
        currentUid: currentUid,
        data: data,
        permissions: permissions,
      );
}
