import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/pages/site_public_page.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logout do painel da igreja — web/PWA vai à [SitePublicPage] (`/`) sem sobrepor o shell.
abstract final class ChurchSignOutNavigation {
  ChurchSignOutNavigation._();

  static Future<void> _clearWebLastRoute() async {
    if (!kIsWeb) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('last_route');
    } catch (_) {}
  }

  /// Substitui a pilha raiz pela landing (path `/` no histórico).
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

  /// Após `signOut` — destino `/` (divulgação) ou override (`/igreja/login`, etc.).
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

  /// Botão «Sair» no painel (web, PWA e app).
  static Future<void> signOutFromChurchPanel() async {
    final pendingOverride =
        await LoginPreferences.peekPostSignOutRouteOverride();
    final preNav = (pendingOverride != null && pendingOverride.isNotEmpty)
        ? pendingOverride
        : (kIsWeb ? '/' : null);

    await _clearWebLastRoute();

    // Web: troca a pilha ANTES do signOut — evita AuthGate com SitePublicPage sob o shell (tela esbranquiçada).
    if (kIsWeb && preNav != null) {
      if (preNav == '/') {
        navigateWebToPublicLanding();
      } else {
        _navigateWebToRoute(preNav);
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    await LoginPreferences.clearOAuthHints();
    if (!kIsWeb) {
      await appGoogleSignOutForAccountPicker();
    }
    await ChurchAutoSessionService.clearAutoPainel();
    if (uid != null && uid.isNotEmpty) {
      await AuthProfileCacheService.instance.clear(uid);
    }
    await FirebaseAuth.instance.signOut();

    if (!kIsWeb) {
      await redirectAfterSignOut();
    } else {
      // Segurança: se ainda estiver em /painel, força landing de novo.
      await redirectAfterSignOut();
    }
  }
}
