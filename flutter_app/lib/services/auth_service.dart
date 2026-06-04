import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/church_sign_out_navigation.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/session_restore_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Sessão Firebase persistente (estilo Controle Total).
///
/// - Arranque: se [hasActiveSession], o [AuthGate] abre o painel sem login.
/// - Logout: só via Configurações → «Trocar de conta» ([signOutForAccountSwitch]).
abstract final class AuthService {
  AuthService._();

  /// Utilizador autenticado (não anónimo).
  static User? get currentUser => firebaseDefaultAuth.currentUser;

  static bool get hasActiveSession {
    final u = currentUser;
    return u != null && !u.isAnonymous;
  }

  /// Web: sessão sobrevive a fechar aba / reiniciar browser + Firestore online.
  static Future<void> configurePersistentSession() async {
    if (!kIsWeb) return;
    try {
      await firebaseDefaultAuth.setPersistence(Persistence.LOCAL);
    } catch (_) {}
    await FirestoreWebGuard.ensureWebDatabaseConnected(refreshAuth: true);
  }

  /// Rota inicial quando há sessão (mobile nativo).
  static String painelRouteIfSession({required String fallback}) {
    return hasActiveSession ? '/painel' : fallback;
  }

  /// Configurações → «Trocar de conta»: signOut, limpa cache local, vai ao login.
  static Future<void> signOutForAccountSwitch() =>
      ChurchSignOutNavigation.signOutForAccountSwitch();

  /// Limpa pistas locais após logout (não chame fora do fluxo «Trocar conta»).
  static Future<void> clearLocalSessionCache({String? uid}) async {
    await LoginPreferences.clearOAuthHints();
    SessionRestoreService.resetAttemptFlag();
    final id = uid ?? currentUser?.uid;
    if (id != null && id.isNotEmpty) {
      await AuthProfileCacheService.instance.clear(id);
    }
  }

  /// Biometria antes do painel — digital / Face ID (mobile).
  static Future<bool> shouldRequireBiometricUnlock() =>
      BiometricService().shouldRequireBiometricUnlock();

  static Future<bool> authenticateWithBiometrics() =>
      BiometricService().authenticate();

  static Future<void> configureBiometricAfterLogin() =>
      BiometricService().enableForReturningUserAfterLogin();
}
