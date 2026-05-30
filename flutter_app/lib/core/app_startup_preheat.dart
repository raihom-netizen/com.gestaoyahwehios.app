import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';
import 'package:gestao_yahweh/services/auth_session_service.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';

/// Pré-carga paralela no splash — painel abre com perfil/tenant já em cache.
abstract final class AppStartupPreheat {
  AppStartupPreheat._();

  static Future<void> preheatForDashboard() async {
    if (!await AuthSessionService.hasSession()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final uid = user.uid;
    await Future.wait<void>([
      () async {
        try {
          await user.getIdToken(false);
        } catch (_) {}
      }(),
      () async {
        await AuthProfileCacheService.instance.load(uid);
      }(),
      ChurchAutoSessionService.preheatPanelCaches(),
      () async {
        final tid = await ChurchAutoSessionService.resolveTenantIdForSession();
        if (tid.isEmpty) return;
        final raw = await PanelMediaPrefetchService.readOnce(tid);
        await PanelMediaPrefetchService.applyToUrlCaches(tid, raw: raw);
      }(),
    ]);
  }

  /// Não bloqueia navegação — aquecimento extra após o primeiro frame.
  static void scheduleBackgroundWarmup() {
    unawaited(preheatForDashboard());
  }
}
