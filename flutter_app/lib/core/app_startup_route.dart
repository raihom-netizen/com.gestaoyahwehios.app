import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/persistent_auth_session_service.dart';

/// Rota inicial nativa — só [PersistentAuthSessionService] (sem OAuth no arranque).
abstract final class AppStartupRoute {
  AppStartupRoute._();

  static bool get isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get nativeLoginRoute =>
      defaultTargetPlatform == TargetPlatform.iOS ? '/igreja/login' : '/login';

  static Future<String> finalizeNativeRoute(String candidate) async {
    if (!isNativeMobile) return candidate;
    if (await LoginPreferences.isAccountSwitchPending()) {
      return nativeLoginRoute;
    }
    await PersistentAuthSessionService.warmColdStart();
    return PersistentAuthSessionService.resolveNativeStartupRoute(candidate);
  }
}
