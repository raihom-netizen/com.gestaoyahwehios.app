import 'package:gestao_yahweh/services/app_permissions.dart';

/// Atalhos legíveis para RBAC no painel (ex.: `if (widget.role.canEditChurchMembers) …`).
extension ChurchPanelRoleX on String {
  bool get canEditChurchMembers =>
      AppPermissions.canEditAnyChurchMember(trim().isEmpty ? 'membro' : this);

  bool get canViewMemberSensitiveFields =>
      AppPermissions.canViewSensitiveMembers(trim().isEmpty ? 'membro' : this);

  bool get isRestrictedChurchNavMember =>
      AppPermissions.isRestrictedMember(trim().isEmpty ? 'membro' : this);

  bool get canViewChurchFinance =>
      AppPermissions.canViewFinance(trim().isEmpty ? 'membro' : this);

  bool get canViewChurchPatrimonio =>
      AppPermissions.canViewPatrimonio(trim().isEmpty ? 'membro' : this);
}
