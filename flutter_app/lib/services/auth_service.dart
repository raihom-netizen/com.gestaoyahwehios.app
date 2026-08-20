import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

  /// Persistência efetivamente aceite pelo browser nesta sessão.
  ///
  /// `null` até [configurePersistentSession] correr.
  static Persistence? persistenciaAtiva;

  /// Web: sessão sobrevive a fechar aba / reiniciar browser + Firestore online.
  ///
  /// **Com degrau.** `Persistence.LOCAL` guarda a sessão no IndexedDB, e há
  /// browsers/estados em que o IndexedDB simplesmente não está disponível:
  /// janela anónima, armazenamento cheio, ou a base a fechar durante a troca
  /// de service worker de um deploy. Antes a falha era engolida por um
  /// `catch (_) {}` e o Auth ficava num estado meio-configurado — o login
  /// seguinte rebentava com «Error: Database is closing/hidden», sem saída
  /// nenhuma para o utilizador.
  ///
  /// Agora desce um degrau de cada vez: LOCAL → SESSION → NONE. Perde-se
  /// persistência entre sessões, mas **entra-se sempre**.
  static Future<void> configurePersistentSession() async {
    if (!kIsWeb) return;
    for (final modo in const [
      Persistence.LOCAL,
      Persistence.SESSION,
      Persistence.NONE,
    ]) {
      try {
        await firebaseDefaultAuth.setPersistence(modo);
        persistenciaAtiva = modo;
        break;
      } catch (e) {
        debugPrint('configurePersistentSession: $modo indisponivel ($e)');
      }
    }
    await FirestoreWebGuard.ensureWebDatabaseConnected(refreshAuth: true);
  }

  /// `true` quando o erro veio do IndexedDB do browser, não das credenciais.
  static bool ehFalhaDeArmazenamentoLocal(Object error) {
    final m = error.toString().toLowerCase();
    return m.contains('database is closing') ||
        m.contains('database is hidden') ||
        m.contains('indexeddb') ||
        m.contains('idbdatabase');
  }

  /// Baixa a persistência um degrau e diz se vale a pena repetir a operação.
  static Future<bool> degradarPersistenciaEReTentar() async {
    if (!kIsWeb) return false;
    for (final modo in const [Persistence.SESSION, Persistence.NONE]) {
      if (persistenciaAtiva == modo) continue;
      try {
        await firebaseDefaultAuth.setPersistence(modo);
        persistenciaAtiva = modo;
        return true;
      } catch (_) {}
    }
    return false;
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
