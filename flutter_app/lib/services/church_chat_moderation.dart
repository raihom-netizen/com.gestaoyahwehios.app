import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';

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

  /// [memberCpfDigits] — só dígitos; usado para conferir líder no doc do departamento.
  static bool canDeleteChatMessage({
    required String memberRole,
    required String memberCpfDigits,
    required bool isDepartmentThread,
    Map<String, dynamic>? departmentData,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final n = ChurchRolePermissions.normalize(memberRole);
    if (_churchManagement(n) || _pastorLike(n)) return true;
    if (isDepartmentThread && departmentData != null) {
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
  /// **DM** — qualquer participante pode apagar qualquer mensagem (estilo «limpar conversa»).
  /// **Grupo** — o autor apaga a própria; moderadores (pastor/gestor/ADM/líder depto) apagam as dos outros.
  static bool canDeleteMessageForEveryone({
    required String senderUid,
    required bool isDepartmentThread,
    required String memberRole,
    required String memberCpfDigits,
    Map<String, dynamic>? departmentData,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
}
