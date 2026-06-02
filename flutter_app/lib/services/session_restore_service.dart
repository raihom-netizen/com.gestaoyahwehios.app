import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';

/// Restaura **apenas** a sessão Firebase já persistida no aparelho.
///
/// Não chama `GoogleSignIn.signInSilently()` no arranque — evita o erro
/// «Não foi possível restaurar a sessão Google automaticamente» quando o Firebase
/// já tem `currentUser`. OAuth silencioso só no botão «Continuar com Google».
abstract final class SessionRestoreService {
  SessionRestoreService._();

  static bool _restoreAttempted = false;

  static const _diskPollAttempts = 16;
  static const _diskPollDelay = Duration(milliseconds: 80);

  /// Aguarda `currentUser` do Firebase Auth (memória + persistência local).
  static Future<User?> waitForPersistedFirebaseUser() async {
    await ensureFirebaseInitialized();
    final sync = firebaseDefaultAuth.currentUser;
    if (sync != null && !sync.isAnonymous) return sync;
    return _pollAuthUserFromDisk();
  }

  /// Compatível com chamadas antigas — **sem** OAuth silencioso.
  static Future<User?> tryRestoreIfNeeded({bool allowRetry = false}) async {
    await ensureFirebaseInitialized();

    final sync = firebaseDefaultAuth.currentUser;
    if (sync != null && !sync.isAnonymous) return sync;

    if (await LoginPreferences.isAccountSwitchPending()) return null;

    if (!_restoreAttempted || allowRetry) {
      _restoreAttempted = true;
      return _pollAuthUserFromDisk();
    }

    final u = firebaseDefaultAuth.currentUser;
    if (u != null && !u.isAnonymous) return u;
    return null;
  }

  /// @deprecated Arranque não usa Google silencioso — só Firebase persistido.
  static Future<User?> tryGoogleSilentReconnect() async {
    if (kDebugMode) {
      debugPrint(
        'SessionRestoreService.tryGoogleSilentReconnect: ignorado no arranque '
        '(use FirebaseAuth.currentUser).',
      );
    }
    return waitForPersistedFirebaseUser();
  }

  /// Após biometria OK: só Firebase em disco (sem Google Sign-In).
  static Future<User?> restoreAfterBiometricUnlock() async {
    return waitForPersistedFirebaseUser();
  }

  static Future<User?> _pollAuthUserFromDisk() async {
    for (var i = 0; i < _diskPollAttempts; i++) {
      if (i > 0) await Future<void>.delayed(_diskPollDelay);
      final u = firebaseDefaultAuth.currentUser;
      if (u != null && !u.isAnonymous) return u;
    }
    return null;
  }

  static Future<bool> _deviceHasReturningLoginHints() async {
    if (LoginPreferences.autoPainelLoginSync) return true;
    final lastId = (await LoginPreferences.getLastLoginIdentifier()).trim();
    if (lastId.isNotEmpty) return true;
    final shellUid = AppShellSessionCache.cachedUidSync();
    if (shellUid != null && shellUid.isNotEmpty) return true;
    return false;
  }

  /// Indica se vale a pena mostrar «A restaurar sessão…» no AuthGate.
  static Future<bool> shouldAttemptRestoreUi() async {
    if (kIsWeb) return false;
    if (await LoginPreferences.isAccountSwitchPending()) return false;
    if (firebaseDefaultAuth.currentUser != null) return false;
    return _deviceHasReturningLoginHints();
  }

  static void resetAttemptFlag() {
    _restoreAttempted = false;
  }
}
