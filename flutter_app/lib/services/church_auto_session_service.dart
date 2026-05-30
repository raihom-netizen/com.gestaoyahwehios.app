import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/gestor_oauth_onboarding_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mantém login do painel «automático» nas próximas aberturas (web + Android):
/// rota salva, Google silencioso, cache de perfil e pré-carga de dados.
class ChurchAutoSessionService {
  ChurchAutoSessionService._();

  static const kAutoPainelPrefsKey = kAutoPainelLogin;

  /// Chamado após login bem-sucedido no painel (`/painel`).
  static Future<void> persistAfterSuccessfulPainelLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoPainelPrefsKey, true);
    await prefs.setString('last_route', '/painel');

    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      await LoginPreferences.setLastLoginIdentifier(email);
    }
    final providers = user.providerData.map((p) => p.providerId).toList();
    if (providers.contains('google.com')) {
      await LoginPreferences.setLastOAuthProvider('google');
    } else if (providers.contains('apple.com')) {
      await LoginPreferences.setLastOAuthProvider('apple');
    } else if (email.isNotEmpty) {
      await LoginPreferences.setLastOAuthProvider('email');
    }
  }

  static Future<bool> isAutoPainelEnabled() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kAutoPainelPrefsKey) == true) return true;
    // Utilizadores que já abriam o painel antes desta flag existir.
    final last = (prefs.getString('last_route') ?? '').trim();
    return last == '/painel' || last.startsWith('/painel/');
  }

  /// Sessão Firebase persistida — garante reabertura directa no painel (estilo apps bancários).
  static Future<void> ensureAutoPainelFlagForPersistedSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    if (await isAutoPainelEnabled()) return;
    await persistAfterSuccessfulPainelLogin();
  }

  static Future<void> clearAutoPainel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAutoPainelPrefsKey);
    await LoginPreferences.clearOAuthHints();
  }

  /// Resolve `igrejaId` do utilizador e aquece caches (painel, membros, Firestore).
  static Future<void> preheatPanelCaches({String? tenantIdHint}) async {
    if (FirebaseAuth.instance.currentUser == null) return;

    var tid = (tenantIdHint ?? '').trim();
    if (tid.isEmpty) {
      tid = await _resolveTenantIdFromUserDoc();
    }
    if (tid.isEmpty) return;

    ChurchTenantOfflineWarmupService.instance.resetForNewSession();
    unawaited(
      ChurchTenantOfflineWarmupService.instance.scheduleWarmupAfterLogin(tid),
    );
    await Future.wait<void>([
      PanelDashboardSnapshotService.warmFromCallableIfStale(tid).then((_) {}),
      MembersDirectorySnapshotService.warmFromCallableIfStale(tid).then((_) {}),
      PanelMediaPrefetchService.readOnce(tid).then((raw) {
        return PanelMediaPrefetchService.applyToUrlCaches(tid, raw: raw);
      }),
    ]);
  }

  /// Tenant da sessão atual — usado no pré-aquecimento do splash.
  static Future<String> resolveTenantIdForSession() =>
      _resolveTenantIdFromUserDoc();

  static Future<String> _resolveTenantIdFromUserDoc() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '';
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      return (data?['igrejaId'] ?? data?['tenantId'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Android: restaura sessão Google sem UI (após login bem-sucedido anterior).
  static Future<bool> trySilentGoogleRestore() async {
    return restoreOAuthSessionForQuickUnlock();
  }

  /// Sessão Firebase expirada mas utilizador já entrou antes — **só** Google/Apple
  /// silencioso. Nunca abre «Escolha uma conta» (isso é só no botão Entrar com Google
  /// ou após Configurações → Trocar conta).
  static Future<bool> restoreOAuthSessionForQuickUnlock() async {
    if (kIsWeb) return false;
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null && !existing.isAnonymous) return true;

    if (!await _shouldAttemptOAuthRestore()) return false;

    final last = await LoginPreferences.getLastOAuthProvider();
    if (last != 'google' && last != 'apple') return false;

    try {
      if (last == 'google') {
        final cred = await ExpressLoginService.tryGoogleSilentOnly();
        if (cred?.user != null) return true;
      }

      if (last == 'apple' && defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final apple =
              await GestorOAuthOnboardingService.signInWithAppleIfAvailable();
          if (apple?.user != null) return true;
        } catch (_) {}
      }

      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'ChurchAutoSessionService.restoreOAuthSessionForQuickUnlock: $e\n$st',
        );
      }
      return false;
    }
  }

  static Future<bool> _shouldAttemptOAuthRestore() async {
    if (await isAutoPainelEnabled()) return true;
    final prefs = await SharedPreferences.getInstance();
    final last = (prefs.getString('last_route') ?? '').trim();
    return last == '/painel' || last.startsWith('/painel/');
  }

  /// `main.dart`: antes de escolher rota inicial — evita ecrã Entrar com sessão Google/Apple no telemóvel.
  static Future<bool> tryRestoreSessionOnColdStart() async {
    if (kIsWeb) return false;
    await ensureFirebaseInitialized();
    if (firebaseDefaultAuth.currentUser != null) return true;
    if (!await _shouldAttemptOAuthRestore()) return false;
    return restoreOAuthSessionForQuickUnlock();
  }

  /// `main.dart`: abrir direto o painel se já houve login com sucesso.
  static Future<String?> painelRouteIfSessionRestored(String currentRoute) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    await ensureAutoPainelFlagForPersistedSession();

    final r = currentRoute.trim();
    if (r == '/painel' || r.startsWith('/painel/')) return null;
    if (r == '/admin' || r.startsWith('/admin')) return null;

    const entryRoutes = {'/', '', '/login', '/igreja/login'};
    if (!entryRoutes.contains(r)) return null;

    unawaited(preheatPanelCaches());
    return '/painel';
  }

  /// Após restaurar OAuth no arranque: garante flag de auto-login do painel.
  static Future<void> markAutoPainelAfterOAuthRestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await persistAfterSuccessfulPainelLogin();
  }
}
