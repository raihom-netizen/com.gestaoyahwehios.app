import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';

/// Resolve o papel efectivo do painel — evita menu «membro» quando claims ainda não actualizaram.
abstract final class AuthGatePanelRole {
  AuthGatePanelRole._();

  static bool emailMatchesChurchGestor(
    String? userEmail,
    Map<String, dynamic>? churchData,
  ) {
    final emailLower = (userEmail ?? '').trim().toLowerCase();
    if (emailLower.isEmpty || churchData == null) return false;
    for (final k in const [
      'gestorEmail',
      'gestor_email',
      'emailGestor',
      'email',
    ]) {
      final v = (churchData[k] ?? '').toString().trim().toLowerCase();
      if (v.isNotEmpty && v == emailLower) return true;
    }
    return false;
  }

  static String? _roleFromMember(Map<String, dynamic> memberData) {
    try {
      final cargo =
          (memberData['CARGO'] ?? memberData['cargo'] ?? '').toString().trim();
      if (cargo.isNotEmpty) {
        final n = ChurchRolePermissions.normalize(cargo);
        if (!_isWeakRole(n)) return n;
      }
      final funcoes = memberData['FUNCOES'] ?? memberData['funcoes'];
      if (funcoes is List) {
        String? best;
        var bestRank = -1;
        for (final f in funcoes) {
          final n = ChurchRolePermissions.normalize(f.toString());
          if (_isWeakRole(n)) continue;
          final rank = _privilegeRank(n);
          if (rank > bestRank) {
            bestRank = rank;
            best = n;
          }
        }
        if (best != null) return best;
      }
    } catch (_) {}
    return null;
  }

  static bool _isWeakRole(String roleKey) {
    final n = ChurchRolePermissions.normalize(roleKey);
    return n == ChurchRoleKeys.membro || n == ChurchRoleKeys.visitante;
  }

  static int _privilegeRank(String roleKey) {
    final n = ChurchRolePermissions.normalize(roleKey);
    if (const {
      ChurchRoleKeys.master,
      ChurchRoleKeys.adm,
      ChurchRoleKeys.gestor,
      ChurchRoleKeys.pastorPresidente,
    }.contains(n)) {
      return 100;
    }
    final s = ChurchRolePermissions.snapshotFor(n);
    if (!s.restrictedNav && s.editChurchProfile && s.viewFinance) return 90;
    if (!s.restrictedNav && s.editChurchProfile) return 80;
    if (!s.restrictedNav) return 60;
    return 10;
  }

  /// Escolhe o papel com **maior** privilégio entre claims, users, cache, igreja e membro.
  static String resolve({
    String? roleFromClaims,
    String? roleFromUserDoc,
    String? roleFromCache,
    Map<String, dynamic>? churchData,
    Map<String, dynamic>? memberData,
    String? userEmail,
    String? cpfDigitsOrRaw,
  }) {
    if (AppConstants.isProductMasterAccount(
      email: userEmail,
      cpfDigitsOrRaw: cpfDigitsOrRaw,
    )) {
      return ChurchRoleKeys.gestor;
    }
    if (emailMatchesChurchGestor(userEmail, churchData)) {
      return ChurchRoleKeys.gestor;
    }

    final candidates = <String>[];
    void add(String? raw) {
      final t = (raw ?? '').trim();
      if (t.isEmpty || _isWeakRole(t)) return;
      candidates.add(ChurchRolePermissions.normalize(t));
    }

    add(roleFromClaims);
    add(roleFromUserDoc);
    add(roleFromCache);
    final fromMember =
        memberData != null ? _roleFromMember(memberData) : null;
    add(fromMember);

    if (candidates.isEmpty) {
      return ChurchRoleKeys.membro;
    }
    candidates.sort((a, b) => _privilegeRank(b).compareTo(_privilegeRank(a)));
    return candidates.first;
  }

  /// Reaplica [resolve] num perfil já montado (cache / bootstrap).
  static Map<String, dynamic> applyToProfile(
    Map<String, dynamic> profile, {
    String? userEmail,
    Map<String, dynamic>? memberData,
  }) {
    final church = profile['church'] is Map
        ? Map<String, dynamic>.from(profile['church'] as Map)
        : null;
    final resolved = resolve(
      roleFromClaims: (profile['role'] ?? '').toString(),
      roleFromUserDoc: (profile['role'] ?? '').toString(),
      roleFromCache: (profile['role'] ?? '').toString(),
      churchData: church,
      memberData: memberData,
      userEmail: userEmail,
      cpfDigitsOrRaw: (profile['cpf'] ?? '').toString(),
    );
    if (resolved == (profile['role'] ?? '').toString().trim().toLowerCase()) {
      return profile;
    }
    return {...profile, 'role': resolved};
  }
}
