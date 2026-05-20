import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
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
    unawaited(PanelDashboardSnapshotService.warmFromCallableIfStale(tid));
    unawaited(MembersDirectorySnapshotService.warmFromCallableIfStale(tid));
  }

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
    if (kIsWeb) return false;
    if (FirebaseAuth.instance.currentUser != null) return true;
    if (!await isAutoPainelEnabled()) return false;

    final last = await LoginPreferences.getLastOAuthProvider();
    if (last != 'google') return false;
    final id = (await LoginPreferences.getLastLoginIdentifier()).trim();
    if (!id.contains('@')) return false;

    try {
      final cred = await ExpressLoginService.tryGoogleSilentOnly();
      return cred?.user != null;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChurchAutoSessionService.trySilentGoogleRestore: $e\n$st');
      }
      return false;
    }
  }

  /// `main.dart`: abrir direto o painel se já houve login com sucesso.
  static Future<String?> painelRouteIfSessionRestored(String currentRoute) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;
    if (!await isAutoPainelEnabled()) return null;

    final r = currentRoute.trim();
    if (r == '/painel' || r.startsWith('/painel/')) return null;
    if (r == '/admin' || r.startsWith('/admin')) return null;

    const entryRoutes = {'/', '', '/login', '/igreja/login'};
    if (!entryRoutes.contains(r)) return null;

    unawaited(preheatPanelCaches());
    return '/painel';
  }
}
