import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';

/// Indica se a ficha em `igrejas/{id}/membros` permite acesso ao painel.
bool authGateMemberDocIndicatesActive(Map<String, dynamic>? memberData) {
  if (memberData == null || memberData.isEmpty) return false;
  final status =
      (memberData['STATUS'] ?? memberData['status'] ?? '').toString().trim().toLowerCase();
  if (status == 'pendente' ||
      status == 'inativo' ||
      status == 'inativa' ||
      status == 'desativado' ||
      status == 'desativada') {
    return false;
  }
  if (status == 'ativo' || status.contains('ativo')) return true;
  if (memberData['ativo'] == true || memberData['active'] == true) return true;
  // Mesmo padrão da lista de membros: vazio = ativo.
  if (status.isEmpty) return true;
  return false;
}

bool authGateMemberDocIsPending(Map<String, dynamic>? memberData) {
  if (memberData == null) return false;
  final status =
      (memberData['STATUS'] ?? memberData['status'] ?? '').toString().trim().toLowerCase();
  return status == 'pendente';
}

/// Mescla `users.ativo` com estado da ficha membro.
bool authGateMergeMemberUserActive({
  required bool activeFromUser,
  Map<String, dynamic>? memberData,
}) {
  if (memberData == null) return activeFromUser;
  if (authGateMemberDocIsPending(memberData)) return false;
  if (authGateMemberDocIndicatesActive(memberData)) return true;
  return activeFromUser;
}

/// Papel com privilégio de gestão na ficha membro (FUNCOES / CARGO).
bool authGateMemberDocHasPanelPrivilege(Map<String, dynamic>? memberData) {
  if (memberData == null) return false;
  final funcoes = memberData['FUNCOES'] ?? memberData['funcoes'];
  if (funcoes is List) {
    for (final f in funcoes) {
      final fk = ChurchRolePermissions.normalize(f.toString());
      if (ChurchRolePermissions.snapshotFor(fk).editChurchProfile) {
        return true;
      }
    }
  }
  for (final key in const ['CARGO', 'cargo', 'FUNCAO', 'funcao', 'role', 'ROLE']) {
    final cargo = (memberData[key] ?? '').toString();
    if (cargo.isEmpty) continue;
    if (ChurchRolePermissions.snapshotFor(
      ChurchRolePermissions.normalize(cargo),
    ).editChurchProfile) {
      return true;
    }
  }
  return false;
}

/// Variantes de e-mail para query Firestore (comparação case-sensitive).
List<String> authGateEmailQueryVariants(String? email) {
  final raw = (email ?? '').trim();
  if (raw.isEmpty) return const [];
  final lower = raw.toLowerCase();
  if (lower == raw) return [lower];
  return [lower, raw];
}

/// Perfis de gestor/liderança sempre entram no painel quando reconhecidos.
bool authGateRoleOrClaimsGrantPanel({
  required String role,
  Map<String, dynamic>? memberData,
  Map<String, dynamic>? churchData,
  String? userEmail,
  String? cpfDigitsOrRaw,
  bool? claimsActive,
  bool? userDocAtivo,
}) {
  if (AppConstants.isProductMasterAccount(
    email: userEmail,
    cpfDigitsOrRaw: cpfDigitsOrRaw,
  )) {
    return true;
  }
  if (claimsActive == true || userDocAtivo == true) return true;
  final roleNorm = ChurchRolePermissions.normalize(role);
  if (ChurchRolePermissions.snapshotFor(roleNorm).editChurchProfile ||
      roleNorm == ChurchRoleKeys.master) {
    return true;
  }
  if (authGateMemberDocHasPanelPrivilege(memberData)) return true;
  final emailLower = (userEmail ?? '').trim().toLowerCase();
  if (emailLower.isNotEmpty && churchData != null) {
    for (final k in const [
      'gestorEmail',
      'emailGestor',
      'gestor_email',
      'email',
    ]) {
      final v = (churchData[k] ?? '').toString().trim().toLowerCase();
      if (v.isNotEmpty && v == emailLower) return true;
    }
  }
  return false;
}

/// Gestor/liderança: acesso ao painel mesmo se `users.ativo` estiver ausente ou membro desalinhado.
bool authGateResolvePanelActive({
  required bool activeFromMemberOrUser,
  required String role,
  Map<String, dynamic>? memberData,
  Map<String, dynamic>? churchData,
  String? userEmail,
  String? cpfDigitsOrRaw,
  bool? claimsActive,
  bool? userDocAtivo,
}) {
  if (authGateRoleOrClaimsGrantPanel(
    role: role,
    memberData: memberData,
    churchData: churchData,
    userEmail: userEmail,
    cpfDigitsOrRaw: cpfDigitsOrRaw,
    claimsActive: claimsActive,
    userDocAtivo: userDocAtivo,
  )) {
    return true;
  }
  if (memberData != null &&
      authGateMemberDocIndicatesActive(memberData) &&
      !authGateMemberDocIsPending(memberData)) {
    return true;
  }
  return activeFromMemberOrUser;
}
