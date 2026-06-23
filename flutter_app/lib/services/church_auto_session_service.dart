import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/public_web_origin.dart';
import 'package:gestao_yahweh/services/church_panel_module_prefetch_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/persistent_auth_session_service.dart';
import 'package:gestao_yahweh/services/panel_preheat_coordinator.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MantÃ©m login do painel Â«automÃ¡ticoÂ» nas prÃ³ximas aberturas (web + Android):
/// rota salva, Google silencioso, cache de perfil e prÃ©-carga de dados.
class ChurchAutoSessionService {
  ChurchAutoSessionService._();

  static const kAutoPainelPrefsKey = kAutoPainelLogin;

  /// Chamado apÃ³s login bem-sucedido no painel (`/painel`).
  static Future<void> persistAfterSuccessfulPainelLogin() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAutoPainelPrefsKey, true);
    await prefs.setString('last_route', '/painel');
    await AppShellSessionCache.markShellReady(user.uid);

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
    await LoginPreferences.markSuccessfulLogin();
  }

  static Future<bool> isAutoPainelEnabled() async {
    if (firebaseDefaultAuth.currentUser == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kAutoPainelPrefsKey) == true) return true;
    // Utilizadores que jÃ¡ abriam o painel antes desta flag existir.
    final last = (prefs.getString('last_route') ?? '').trim();
    return last == '/painel' || last.startsWith('/painel/');
  }

  /// SessÃ£o Firebase persistida â€” garante reabertura directa no painel (estilo apps bancÃ¡rios).
  static Future<void> ensureAutoPainelFlagForPersistedSession() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return;
    if (await isAutoPainelEnabled()) return;
    await persistAfterSuccessfulPainelLogin();
  }

  static Future<void> clearAutoPainel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAutoPainelPrefsKey);
    await LoginPreferences.clearOAuthHints();
    await AppShellSessionCache.clear();
    PanelPreheatCoordinator.resetForAccountSwitch();
  }

  /// Resolve `igrejaId` do utilizador e aquece caches (painel, membros, Firestore).
  static Future<void> preheatPanelCaches({String? tenantIdHint}) async {
    if (firebaseDefaultAuth.currentUser == null) return;

    var tid = (tenantIdHint ?? '').trim();
    if (tid.isEmpty) {
      tid = await _resolveTenantIdFromUserDoc();
    }
    if (tid.isEmpty) return;

    final churchId = ChurchRepository.churchId(tid);
    if (churchId.isNotEmpty) {
      ChurchContextService.bindPanelIdImmediate(
        seed: tid,
        canonicalId: churchId,
      );
      tid = churchId;
    }

    unawaited(
      ChurchTenantOfflineWarmupService.instance.scheduleWarmupAfterLogin(tid),
    );
    ChurchPanelModulePrefetchService.scheduleFullPrefetch(tid);
    final results = await Future.wait<dynamic>([
      PanelDashboardSnapshotService.warmFromCallableIfStale(tid),
      MembersDirectorySnapshotService.warmFromCallableIfStale(tid),
      PanelMediaPrefetchService.readOnce(tid),
    ]);
    final panel = results[0] as PanelDashboardSnapshot;
    final prefetchRaw = results[2] as Map<String, dynamic>?;
    await PanelMediaPrefetchService.applyToUrlCaches(tid, raw: prefetchRaw);
    unawaited(
      ChurchGalleryPhotoWarmup.warmBytesFromMediaPrefetch(tid, prefetchRaw),
    );
    unawaited(
      ChurchGalleryPhotoWarmup.warmBytesForPanel(tenantId: tid, panel: panel),
    );
  }

  /// Delega ao coordenador â€” uma onda de callable por tenant/sessÃ£o.
  static Future<void> preheatPanelCachesCoordinated({String? tenantIdHint}) =>
      PanelPreheatCoordinator.preheatOnce(tenantIdHint: tenantIdHint);

  /// Tenant da sessÃ£o atual â€” usado no prÃ©-aquecimento do splash.
  static Future<String> resolveTenantIdForSession() =>
      _resolveTenantIdFromUserDoc();

  static Future<String> _resolveTenantIdFromUserDoc() async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
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

  /// Android: restaura sessÃ£o Google sem UI (apÃ³s login bem-sucedido anterior).
  @Deprecated('Use PersistentAuthSessionService.hasPersistedSession')
  static Future<bool> trySilentGoogleRestore() async {
    return PersistentAuthSessionService.hasPersistedSession();
  }

  @Deprecated('Use PersistentAuthSessionService.hasPersistedSession')
  static Future<bool> restoreOAuthSessionForQuickUnlock() async {
    return PersistentAuthSessionService.hasPersistedSession();
  }

  static Future<bool> _shouldAttemptOAuthRestore() async {
    if (await isAutoPainelEnabled()) return true;
    final prefs = await SharedPreferences.getInstance();
    final last = (prefs.getString('last_route') ?? '').trim();
    return last == '/painel' || last.startsWith('/painel/');
  }

  /// `main.dart`: antes de escolher rota inicial â€” evita ecrÃ£ Entrar com sessÃ£o Google/Apple no telemÃ³vel.
  static Future<bool> tryRestoreSessionOnColdStart() async =>
      PersistentAuthSessionService.warmColdStart();

  /// `main.dart`: abrir direto o painel se jÃ¡ houve login com sucesso.
  static Future<String?> painelRouteIfSessionRestored(String currentRoute) async {
    if (await LoginPreferences.isAccountSwitchPending()) return null;
    var user = await PersistentAuthSessionService.currentPersistedUser();
    if (user == null || user.isAnonymous) return null;
    await ensureAutoPainelFlagForPersistedSession();

    final r = currentRoute.trim();
    if (r == '/painel' || r.startsWith('/painel/')) return null;
    if (r == '/admin' || r.startsWith('/admin')) return null;

    const entryRoutes = {'/', '', '/login', '/igreja/login'};
    if (!entryRoutes.contains(r)) return null;
    if (PublicWebOrigin.isMarketingPublicHomeRoute(r)) return null;

    unawaited(preheatPanelCaches());
    return '/painel';
  }

  /// ApÃ³s restaurar OAuth no arranque: garante flag de auto-login do painel.
  static Future<void> markAutoPainelAfterOAuthRestore() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return;
    await persistAfterSuccessfulPainelLogin();
  }
}

