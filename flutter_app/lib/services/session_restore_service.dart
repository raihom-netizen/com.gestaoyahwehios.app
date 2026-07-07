import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';

/// Restaura sessão Firebase no cold start (disco lento ou Google silencioso — Controle Total).
abstract final class SessionRestoreService {
  SessionRestoreService._();

  static bool _restoreAttempted = false;

  static Duration get _diskPollDelay =>
      kIsWeb ? const Duration(milliseconds: 50) : const Duration(milliseconds: 80);
  static Duration get _diskPollCap =>
      kIsWeb ? const Duration(seconds: 3) : const Duration(milliseconds: 1400);

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
      final polled = await _pollAuthUserFromDisk();
      if (polled != null) return polled;

      if (!kIsWeb && await LoginPreferences.getLastOAuthProvider() == 'google') {
        try {
          await ExpressLoginService.tryGoogleSilentOnly().timeout(
            const Duration(seconds: 4),
          );
        } catch (_) {}
      }
      return firebaseDefaultAuth.currentUser;
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
    final startedAt = DateTime.now();
    while (true) {
      final u = firebaseDefaultAuth.currentUser;
      if (u != null && !u.isAnonymous) return u;

      if (DateTime.now().difference(startedAt) >= _diskPollCap) {
        break;
      }
      await Future<void>.delayed(_diskPollDelay);
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
