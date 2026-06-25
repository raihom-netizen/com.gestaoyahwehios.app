import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/pages/site_public_page.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/session_restore_service.dart';
import 'package:gestao_yahweh/services/church_panel_access_bootstrap.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// Logout do painel da igreja â€” web/PWA vai Ã  [SitePublicPage] (`/`) sem sobrepor o shell.
abstract final class ChurchSignOutNavigation {
  ChurchSignOutNavigation._();

  static Future<void> _clearWebLastRoute() async {
    if (!kIsWeb) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('last_route');
    } catch (_) {}
  }

  /// Substitui a pilha raiz pela landing (path `/` no histÃ³rico).
  static void navigateWebToPublicLanding() {
    if (!kIsWeb) return;
    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => const SitePublicPage(),
      ),
      (_) => false,
    );
  }

  static void _navigateWebToRoute(String route) {
    if (!kIsWeb) return;
    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;
    final dest = route.trim().isEmpty ? '/' : route.trim();
    if (dest == '/') {
      navigateWebToPublicLanding();
      return;
    }
    nav.pushNamedAndRemoveUntil(dest, (_) => false);
  }

  /// ApÃ³s `signOut` â€” destino `/` (divulgaÃ§Ã£o) ou override (`/igreja/login`, etc.).
  static Future<void> redirectAfterSignOut() async {
    await _clearWebLastRoute();
    await ChurchAutoSessionService.clearAutoPainel();

    final override = await LoginPreferences.consumePostSignOutRouteOverride();
    final dest = (override != null && override.isNotEmpty)
        ? override
        : (kIsWeb ? '/' : '/login');

    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;

    if (kIsWeb) {
      if (dest == '/') {
        navigateWebToPublicLanding();
      } else {
        _navigateWebToRoute(dest);
      }
      return;
    }

    nav.pushNamedAndRemoveUntil(dest, (_) => false);
  }

  /// ConfiguraÃ§Ãµes â†’ Â«Trocar e-mail de loginÂ»: limpa Firebase + Google no aparelho.
  static Future<void> signOutForAccountSwitch() async {
    await LoginPreferences.prepareChurchAccountSwitch();
    await signOutFromChurchPanel();
  }

  /// SÃ³ desloga de facto apÃ³s [prepareChurchAccountSwitch] (igual Controle Total).
  /// Outros botÃµes Â«SairÂ» nÃ£o devem chamar isto sem a flag â€” a sessÃ£o permanece.
  static Future<void> signOutFromChurchPanel() async {
    if (!await LoginPreferences.isAccountSwitchPending()) {
      return;
    }
    final pendingOverride =
        await LoginPreferences.peekPostSignOutRouteOverride();
    final preNav = (pendingOverride != null && pendingOverride.isNotEmpty)
        ? pendingOverride
        : (kIsWeb ? '/' : null);

    await _clearWebLastRoute();

    // Web: troca a pilha ANTES do signOut â€” evita AuthGate com SitePublicPage sob o shell (tela esbranquiÃ§ada).
    if (kIsWeb && preNav != null) {
      if (preNav == '/') {
        navigateWebToPublicLanding();
      } else {
        _navigateWebToRoute(preNav);
      }
    }

    final uid = firebaseDefaultAuth.currentUser?.uid;
    await LoginPreferences.clearOAuthHints();
    SessionRestoreService.resetAttemptFlag();
    if (!kIsWeb) {
      await appGoogleSignOutForAccountPicker();
    }
    await ChurchAutoSessionService.clearAutoPainel();
    WebPanelStability.clearOnSignOut();
    ChurchPanelAccessBootstrap.resetSession();
    ChurchContextService.clear();
    ChurchOperationalFirestoreTrace.clear();
    if (uid != null && uid.isNotEmpty) {
      await AuthProfileCacheService.instance.clear(uid);
    }
    BiometricService.clearSessionBiometricUnlock();
    await firebaseDefaultAuth.signOut();

    if (!kIsWeb) {
      await redirectAfterSignOut();
    } else {
      // SeguranÃ§a: se ainda estiver em /painel, forÃ§a landing de novo.
      await redirectAfterSignOut();
    }
  }
}

