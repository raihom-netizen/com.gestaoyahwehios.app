import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';

/// Sessão Firebase + pistas locais de «já entrei no painel neste aparelho».
abstract final class AuthSessionService {
  AuthSessionService._();

  /// Utilizador autenticado no Firebase (não anónimo).
  static Future<bool> hasSession() async {
    await ensureFirebaseInitialized();
    final user = firebaseDefaultAuth.currentUser;
    return user != null && !user.isAnonymous;
  }

  /// Indica que este aparelho já concluiu login no painel (Google/Apple/e-mail).
  static Future<bool> hasStoredChurchUnlockHints() async {
    final lastId = (await LoginPreferences.getLastLoginIdentifier()).trim();
    if (!lastId.contains('@')) return false;
    final lastProv = await LoginPreferences.getLastOAuthProvider();
    if (lastProv == 'google' || lastProv == 'apple' || lastProv == 'email') {
      return true;
    }
    return false;
  }
}
