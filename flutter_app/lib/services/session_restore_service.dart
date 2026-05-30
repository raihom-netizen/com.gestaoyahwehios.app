import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/gestor_oauth_onboarding_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';

/// Restaura sessão Firebase no cold start / após biometria (padrão Controle Total).
///
/// A sessão **não expira** por timeout da app — só `signOut` em Configurações → trocar conta.
abstract final class SessionRestoreService {
  SessionRestoreService._();

  static bool _restoreAttempted = false;

  static const _diskPollAttempts = 12;
  static const _diskPollDelay = Duration(milliseconds: 50);
  static const _silentOAuthTimeout = Duration(seconds: 12);

  static Future<User?> tryRestoreIfNeeded() async {
    await ensureFirebaseInitialized();

    final sync = firebaseDefaultAuth.currentUser;
    if (sync != null && !sync.isAnonymous) return sync;

    if (await LoginPreferences.isAccountSwitchPending()) return null;
    if (!await _deviceHasReturningLoginHints()) return null;

    if (!_restoreAttempted) {
      _restoreAttempted = true;
      final fromDisk = await _pollAuthUserFromDisk();
      if (fromDisk != null) return fromDisk;
      await _silentOAuthRestore();
    }

    final u = firebaseDefaultAuth.currentUser;
    if (u != null && !u.isAnonymous) return u;
    return null;
  }

  /// Após biometria OK: disco → Google/Apple silencioso (sem abrir seletor de conta).
  static Future<User?> restoreAfterBiometricUnlock() async {
    await ensureFirebaseInitialized();

    final sync = firebaseDefaultAuth.currentUser;
    if (sync != null && !sync.isAnonymous) return sync;

    final fromDisk = await _pollAuthUserFromDisk();
    if (fromDisk != null) return fromDisk;

    await _silentOAuthRestore(force: true);
    final u = firebaseDefaultAuth.currentUser;
    if (u != null && !u.isAnonymous) return u;
    return null;
  }

  static Future<User?> _pollAuthUserFromDisk() async {
    for (var i = 0; i < _diskPollAttempts; i++) {
      if (i > 0) await Future<void>.delayed(_diskPollDelay);
      final u = firebaseDefaultAuth.currentUser;
      if (u != null && !u.isAnonymous) return u;
    }
    return null;
  }

  static Future<void> _silentOAuthRestore({bool force = false}) async {
    if (!force && _restoreAttempted) return;
    if (kIsWeb) return;
    if (await LoginPreferences.isAccountSwitchPending()) return;

    final last = await LoginPreferences.getLastOAuthProvider();
    if (last == null) return;

    try {
      if (last == 'google') {
        await ExpressLoginService.tryGoogleSilentOnly().timeout(
          _silentOAuthTimeout,
          onTimeout: () => null,
        );
      } else if (last == 'apple' &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        await GestorOAuthOnboardingService.signInWithAppleIfAvailable().timeout(
          _silentOAuthTimeout,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SessionRestoreService._silentOAuthRestore: $e\n$st');
      }
    }
  }

  static Future<bool> _deviceHasReturningLoginHints() async {
    if (LoginPreferences.autoPainelLoginSync) return true;
    final lastId = (await LoginPreferences.getLastLoginIdentifier()).trim();
    if (lastId.isNotEmpty) return true;
    final shellUid = AppShellSessionCache.cachedUidSync();
    if (shellUid != null && shellUid.isNotEmpty) return true;
    return ChurchAutoSessionService.isAutoPainelEnabled();
  }

  static void resetAttemptFlag() {
    _restoreAttempted = false;
  }
}
