import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// Quem pode **apagar para todos** (alinhado a `chatMessageDeleteForEveryoneAllowed` nas regras).
abstract final class ChurchChatModeration {
  ChurchChatModeration._();

  static bool _pastorLike(String normalized) {
    return const {
      ChurchRoleKeys.pastor,
      ChurchRoleKeys.pastorAuxiliar,
      ChurchRoleKeys.pastorPresidente,
    }.contains(normalized);
  }

  /// ADM / gestor / master (igreja).
  static bool _churchManagement(String normalized) {
    return const {
      ChurchRoleKeys.adm,
      ChurchRoleKeys.gestor,
      ChurchRoleKeys.master,
    }.contains(normalized);
  }

  static bool _churchWideChatModerator(String normalized) {
    return _churchManagement(normalized) ||
        _pastorLike(normalized) ||
        const {
          ChurchRoleKeys.secretario,
          ChurchRoleKeys.presbitero,
          ChurchRoleKeys.tesoureiro,
          ChurchRoleKeys.tesouraria,
        }.contains(normalized);
  }

  /// Apagar mensagem de **outro** no grupo â€” pastoral/gestÃ£o ou lÃ­der deste departamento.
  static bool canDeleteChatMessage({
    required String memberRole,
    required String memberCpfDigits,
    required bool isDepartmentThread,
    Map<String, dynamic>? departmentData,
  }) {
    return canManageDepartmentGroup(
      memberRole: memberRole,
      memberCpfDigits: memberCpfDigits,
      isDepartmentThread: isDepartmentThread,
      departmentData: departmentData,
    );
  }

  /// Adicionar/remover membros, apagar mensagens alheias, envio em massa a grupos.
  static bool canManageDepartmentGroup({
    required String memberRole,
    required String memberCpfDigits,
    required bool isDepartmentThread,
    Map<String, dynamic>? departmentData,
  }) {
    if (!isDepartmentThread) return true;
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return false;
    final n = ChurchRolePermissions.normalize(memberRole);
    if (_churchWideChatModerator(n)) return true;
    if (departmentData != null) {
      if (ChurchDepartmentLeaders.memberIsLeaderOfDepartment(
        departmentData,
        memberCpfDigits,
      )) {
        return true;
      }
      if (ChurchDepartmentLeaders.leaderUidsFromDepartmentData(departmentData)
          .contains(uid)) {
        return true;
      }
    }
    return false;
  }

  /// Apagar para **todos** (alinhado a `chatMessageDeleteForEveryoneAllowed` nas regras):
  /// **DM** â€” qualquer participante pode apagar qualquer mensagem (estilo Â«limpar conversaÂ»).
  /// **Grupo** â€” o autor apaga a prÃ³pria; moderadores (pastor/gestor/ADM/lÃ­der depto) apagam as dos outros.
  static bool canDeleteMessageForEveryone({
    required String senderUid,
    required bool isDepartmentThread,
    required String memberRole,
    required String memberCpfDigits,
    Map<String, dynamic>? departmentData,
  }) {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) return false;
    if (!isDepartmentThread) return true;
    if (senderUid == uid) return true;
    return canDeleteChatMessage(
      memberRole: memberRole,
      memberCpfDigits: memberCpfDigits,
      isDepartmentThread: isDepartmentThread,
      departmentData: departmentData,
    );
  }

  /// Excluir **grupo** de departamento (thread + histÃ³rico) â€” moderadores do grupo.
  static bool canDeleteGroupConversation(
    String memberRole, {
    Map<String, dynamic>? departmentData,
    String memberCpfDigits = '',
  }) {
    return canManageDepartmentGroup(
      memberRole: memberRole,
      memberCpfDigits: memberCpfDigits,
      isDepartmentThread: true,
      departmentData: departmentData,
    );
  }
}

