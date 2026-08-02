/// Impede documentos `users/{uid}` sem e-mail identificável (cadastros fantasmas).
class UserProfileEmailGuard {
  UserProfileEmailGuard._();

  static final _emailRx = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValid(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isNotEmpty && _emailRx.hasMatch(e);
  }

  static String? normalize(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return isValid(e) ? e : null;
  }

  /// `users/{uid}` sem e-mail válido no Firestore.
  static bool isGhostProfile(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return true;
    return !isValid((data['email'] ?? '').toString());
  }

  /// Utilizador completo para painel admin / estatísticas (e-mail cadastrado).
  static bool isRegisteredUser(Map<String, dynamic>? data) {
    return !isGhostProfile(data);
  }

  /// Campos mínimos ao criar perfil — falha se [email] inválido.
  static Map<String, dynamic> requireEmailFields({
    required String email,
    required Map<String, dynamic> fields,
  }) {
    final norm = normalize(email);
    if (norm == null) {
      throw StateError('user_profile_email_guard: e-mail obrigatório');
    }
    return {
      ...fields,
      'email': norm,
    };
  }

  /// Merge seguro: nunca cria `users/{uid}` sem e-mail no patch.
  static Map<String, dynamic> safeMergePatch(
    Map<String, dynamic> patch, {
    String? fallbackEmail,
  }) {
    final fromPatch = normalize((patch['email'] ?? '').toString());
    final fromFallback = normalize(fallbackEmail);
    final email = fromPatch ?? fromFallback;
    if (email == null) {
      // Atualização parcial em doc existente — não incluir email vazio.
      final copy = Map<String, dynamic>.from(patch);
      copy.remove('email');
      return copy;
    }
    return {...patch, 'email': email, 'emailRegistered': true};
  }
}
