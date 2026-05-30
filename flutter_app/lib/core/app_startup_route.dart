import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/services/auth_session_service.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';

/// Rota inicial nativa — sessão Firebase persistida abre o painel sem passar pelo login.
abstract final class AppStartupRoute {
  AppStartupRoute._();

  static bool get isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get nativeLoginRoute =>
      defaultTargetPlatform == TargetPlatform.iOS ? '/igreja/login' : '/login';

  static const _loginRoutes = {'/login', '/igreja/login'};
  static const _entryRoutes = {'/', '', '/login', '/igreja/login'};

  /// Sessão ativa → `/painel`; sem sessão → login (nunca painel vazio).
  static Future<String> finalizeNativeRoute(String candidate) async {
    if (!isNativeMobile) return candidate;
    var route = candidate.trim().isEmpty ? '/' : candidate.trim();

    if (await AuthSessionService.hasSession()) {
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
      if (_loginRoutes.contains(route) || _entryRoutes.contains(route)) {
        return '/painel';
      }
      return route;
    }

    if (route == '/painel' || route.startsWith('/painel/')) {
      return nativeLoginRoute;
    }
    return route;
  }
}
