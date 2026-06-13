import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/auth_gate_member_active.dart';

/// Metadados gravados no cache de perfil do AuthGate.
abstract final class AuthGateProfileMeta {
  AuthGateProfileMeta._();

  /// Perfil confirmado por servidor (Firestore/CF/claims) — seguro para bloquear acesso.
  static const accessVerified = 'accessVerified';

  /// Origem da última resolução (`server`, `claims`, `callable`).
  static const accessSource = 'accessSource';
}

/// Resultado da busca do membro ligado ao utilizador autenticado.
class AuthGateMemberBinding {
  final Map<String, dynamic>? memberData;
  final String? memberDocId;

  const AuthGateMemberBinding({this.memberData, this.memberDocId});
}

/// Política de cache — evita persistir «desativado» stale no dispositivo.
abstract final class AuthGateProfileCachePolicy {
  AuthGateProfileCachePolicy._();

  static bool requiresOnlineVerification(Map<String, dynamic>? profile) {
    if (profile == null) return true;
    if (profile[AuthGateProfileMeta.accessVerified] == true) return false;
    if (profile['memberStatusPending'] == true) return false;
    return profile['active'] != true;
  }

  static Map<String, dynamic> stampVerified(
    Map<String, dynamic> profile, {
    required String source,
  }) {
    return {
      ...profile,
      AuthGateProfileMeta.accessVerified: true,
      AuthGateProfileMeta.accessSource: source,
    };
  }

  static bool shouldPersistToDisk(Map<String, dynamic> profile) {
    if (profile[AuthGateProfileMeta.accessVerified] == true) return true;
    if (profile['active'] == true) return true;
    if (profile['memberStatusPending'] == true) return true;
    return false;
  }
}

/// Resolve acesso ao painel — fonte única no cliente.
abstract final class AuthGatePanelAccessService {
  AuthGatePanelAccessService._();

  static ({bool active, bool memberStatusPending}) resolve({
    required bool activeFromMemberOrUser,
    required String role,
    Map<String, dynamic>? memberData,
    Map<String, dynamic>? churchData,
    String? userEmail,
    String? cpfDigitsOrRaw,
    bool? claimsActive,
    bool? userDocAtivo,
  }) {
    if (memberData != null && authGateMemberDocIsPending(memberData)) {
      return (active: false, memberStatusPending: true);
    }

    final status =
        (memberData?['STATUS'] ?? memberData?['status'] ?? '').toString().toLowerCase();
    final explicitlyInactive = memberData != null &&
        (status == 'inativo' ||
            status == 'inativa' ||
            status == 'desativado' ||
            status == 'desativada' ||
            memberData['ativo'] == false ||
            memberData['active'] == false);

    if (explicitlyInactive) {
      return (active: false, memberStatusPending: false);
    }

    final active = authGateResolvePanelActive(
      activeFromMemberOrUser: activeFromMemberOrUser,
      role: role,
      memberData: memberData,
      churchData: churchData,
      userEmail: userEmail,
      cpfDigitsOrRaw: cpfDigitsOrRaw,
      claimsActive: claimsActive,
      userDocAtivo: userDocAtivo,
    );

    return (active: active, memberStatusPending: false);
  }

  /// Busca ficha membro: doc(uid) → authUid → CPF → e-mail (variantes).
  static Future<AuthGateMemberBinding> findMemberForUser({
    required String igrejaId,
    required User user,
    required Map<String, dynamic> userData,
  }) async {
    if (igrejaId.trim().isEmpty) {
      return const AuthGateMemberBinding();
    }
    final membersCol = ChurchUiCollections.membros(igrejaId.trim());

    AuthGateMemberBinding? fromDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null || data.isEmpty) return null;
      return AuthGateMemberBinding(memberData: data, memberDocId: snap.id);
    }

    try {
      final direct = fromDoc(await membersCol.doc(user.uid).get());
      if (direct != null) return direct;

      final byAuthUid =
          await membersCol.where('authUid', isEqualTo: user.uid).limit(1).get();
      if (byAuthUid.docs.isNotEmpty) {
        final d = byAuthUid.docs.first;
        return AuthGateMemberBinding(memberData: d.data(), memberDocId: d.id);
      }

      final cpfDigits =
          (userData['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (cpfDigits.length == 11) {
        final cpfHit = fromDoc(await membersCol.doc(cpfDigits).get());
        if (cpfHit != null) return cpfHit;
      }

      for (final emailCandidate in authGateEmailQueryVariants(user.email)) {
        for (final field in const ['email', 'EMAIL', 'e-mail', 'mail']) {
          try {
            final byEmail = await membersCol
                .where(field, isEqualTo: emailCandidate)
                .limit(1)
                .get();
            if (byEmail.docs.isNotEmpty) {
              final d = byEmail.docs.first;
              return AuthGateMemberBinding(memberData: d.data(), memberDocId: d.id);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return const AuthGateMemberBinding();
  }
}
