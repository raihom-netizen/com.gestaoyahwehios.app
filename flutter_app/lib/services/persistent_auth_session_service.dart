import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/app_startup_route.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/session_restore_service.dart';

/// **Única** fonte de verdade para sessão persistida e autologin no arranque.
///
/// Proibido no cold start / reabertura da Login:
/// - [ExpressLoginService.tryExpressLogin]
/// - `GoogleSignIn.signInSilently` / `signInSilently`
/// - [GestorOAuthOnboardingService.signInWithGoogleNative] (só no botão manual)
abstract final class PersistentAuthSessionService {
  PersistentAuthSessionService._();

  static void _log(String message) {
    // ignore: avoid_print
    print(message);
    debugPrint(message);
  }

  /// Arranque nativo: só aguarda Firebase em disco (sem OAuth Google).
  static Future<bool> warmColdStart() async {
    if (kIsWeb) return false;
    if (await LoginPreferences.isAccountSwitchPending()) return false;
    await ensureFirebaseInitialized();
    final user = await currentPersistedUser();
    _log('AUTOLOGIN currentUser=${user?.uid}');
    if (user != null) {
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      return true;
    }
    return false;
  }

  /// Utilizador Firebase (memória + poll curto no disco).
  static Future<User?> currentPersistedUser() async {
    await ensureFirebaseInitialized();
    if (await LoginPreferences.isAccountSwitchPending()) return null;
    final sync = FirebaseAuth.instance.currentUser;
    if (sync != null && !sync.isAnonymous) {
      _log('AUTOLOGIN currentUser=${sync.uid}');
      return sync;
    }
    return SessionRestoreService.waitForPersistedFirebaseUser();
  }

  static Future<bool> hasPersistedSession() async {
    final u = await currentPersistedUser();
    return u != null && !u.isAnonymous;
  }

  static Future<bool> isBiometricUnlockEnabled() =>
      BiometricService().isEnabled();

  /// Digital/Face ID — sem fallback Google.
  static Future<bool> promptBiometricUnlock() async {
    if (kIsWeb) return true;
    final enabled = await isBiometricUnlockEnabled();
    _log('BIOMETRIA ATIVA=$enabled');
    if (!enabled) return true;
    final ok = await BiometricService().authenticate();
    if (ok) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    return ok;
  }

  /// Fluxo canónico: sessão → biometria (se activa) → pode abrir painel.
  static Future<bool> canProceedToDashboard() async {
    final user = await currentPersistedUser();
    if (user == null || user.isAnonymous) {
      _log('AUTOLOGIN currentUser=null (sem sessao)');
      return false;
    }
    final enabled = await isBiometricUnlockEnabled();
    _log('BIOMETRIA ATIVA=$enabled');
    if (!enabled) {
      _log('ABRINDO PAINEL');
      return true;
    }
    final ok = await promptBiometricUnlock();
    if (ok) {
      _log('ABRINDO PAINEL');
    }
    return ok;
  }

  /// Rota inicial nativa: sessão → `/painel`; senão login.
  static Future<String> resolveNativeStartupRoute(String candidate) async {
    final route = candidate.trim().isEmpty ? '/' : candidate.trim();
    if (await LoginPreferences.isAccountSwitchPending()) {
      return kIsWeb ? '/login' : AppStartupRoute.nativeLoginRoute;
    }
    if (!await hasPersistedSession()) {
      if (route == '/painel' || route.startsWith('/painel/')) {
        return kIsWeb ? '/login' : AppStartupRoute.nativeLoginRoute;
      }
      return route;
    }
    const entry = {'/', '', '/login', '/igreja/login'};
    if (entry.contains(route)) {
      return '/painel';
    }
    return route;
  }
}
