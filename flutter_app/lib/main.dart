import 'dart:async';
import 'package:flutter/foundation.dart'
    show
        PlatformDispatcher,
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:gestao_yahweh/core/app_startup_preheat.dart';
import 'package:gestao_yahweh/core/app_startup_route.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/auth_session_service.dart';
import 'package:gestao_yahweh/services/auth_service.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/ui/pages/firebase_bootstrap_recovery_page.dart';
import 'package:gestao_yahweh/ui/pages/system_firebase_health_page.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/offline/offline_first_coordinator.dart';
import 'package:gestao_yahweh/services/app_session_stability.dart';
import 'package:gestao_yahweh/url_strategy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'ui/pages/login_page_novo.dart';
import 'ui/login_page.dart';
import 'ui/pages/cadastro_usuario_page.dart';
import 'ui/pages/usuarios_permissoes_page.dart';
import 'ui/pages/aprovar_membros_pendentes_page.dart';
import 'ui/auth_gate.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'ui/church_public_page.dart';
import 'ui/pages/public_member_signup_page.dart';
import 'ui/pages/public_carteirinha_consulta_page.dart';
import 'ui/pages/public_certificado_consulta_page.dart';
import 'ui/pages/public_certificado_validacao_page.dart';
import 'ui/pages/department_invite_page.dart';
import 'ui/pages/legal_pages.dart';
import 'pages/site_public_page.dart';
import 'ui/admin_panel_page.dart';
import 'ui/landing_page.dart';
import 'ui/signup_page.dart';
import 'ui/pages/signup_completar_gestor_page.dart';
import 'ui/widgets/ios_organization_signup_web_page.dart';
import 'ui/pages/plans/express_renew_gate_page.dart';
import 'package:gestao_yahweh/ui/widgets/update_checker.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/persistent_auth_session_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/panel_preheat_coordinator.dart';
import 'package:gestao_yahweh/window_close_handler_stub.dart'
    if (dart.library.io) 'package:gestao_yahweh/window_close_handler_io.dart'
    as window_close_handler;
import 'package:gestao_yahweh/core/app_scroll_behavior.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/public_site_analytics.dart';
import 'package:gestao_yahweh/services/yahweh_observability.dart';
import 'package:gestao_yahweh/services/domain_daily_hit_service.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_alert_notification_service.dart';
import 'package:gestao_yahweh/services/panel_notification_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'ui/widgets/ios_payment_unavailable_view.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/ui/widgets/sync_feedback_listener.dart';
import 'package:gestao_yahweh/utils/brasilia_datetime_format.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gestao_yahweh/core/app_deep_link.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/core/public_web_route_parser.dart';
import 'package:gestao_yahweh/debug/agent_debug_log.dart';
import 'package:gestao_yahweh/web_resume_repaint_stub.dart'
    if (dart.library.html) 'package:gestao_yahweh/web_resume_repaint_web.dart';

import 'package:gestao_yahweh/services/crashlytics_benign_errors.dart';

/// Erros que não devem contar como crash fatal no Crashlytics (rede, sessão, streams).
bool _crashlyticsFlutterErrorLikelyBenign(FlutterErrorDetails details) {
  final ex = details.exception;
  if (CrashlyticsBenignErrors.isBenign(ex)) return true;
  if (ex is NetworkImageLoadException) return true;
  final msg = details.exceptionAsString().toLowerCase();
  if (msg.contains('http request failed')) return true;
  if (msg.contains('http request') && msg.contains('statuscode')) return true;
  if (msg.contains('bad state:') && msg.contains('stream has already been listened')) {
    return true;
  }
  if (msg.contains('sessão expirada')) return true;
  if (msg.contains('firebasebootstrapexception')) return true;
  return false;
}

const _kAllowedChurchPostLoginPaths = {
  '/painel',
  '/atualizar-plano',
  '/planos',
};

String _sanitizeChurchPostLoginRoute(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '/painel';
  final Uri? u = s.startsWith('http://') || s.startsWith('https://')
      ? Uri.tryParse(s)
      : Uri.tryParse(
          'https://placeholder.invalid${s.startsWith('/') ? s : '/$s'}',
        );
  if (u == null) return '/painel';
  var p = u.path.isEmpty ? '/' : u.path;
  if (!p.startsWith('/')) p = '/$p';
  if (!_kAllowedChurchPostLoginPaths.contains(p)) return '/painel';
  if (u.hasQuery && u.query.isNotEmpty) return '$p?${u.query}';
  return p;
}

/// Query `after` em `/igreja/login` e `/igreja/login/apple` (whitelist). Fluxo iOS (`from=ios_app`)
/// garante `from=ios_app` em `/atualizar-plano` para o gate expresso.
String _resolveIgrejaLoginAfterRoute(Uri loginUri) {
  final fromIosApp =
      loginUri.queryParameters['from']?.toLowerCase() == 'ios_app';
  final afterRaw = loginUri.queryParameters['after']?.trim();
  if (afterRaw != null && afterRaw.isNotEmpty) {
    var target = _sanitizeChurchPostLoginRoute(afterRaw);
    if (fromIosApp) {
      final pathOnly = target.split('?').first;
      if (pathOnly == '/atualizar-plano') {
        final hasIosFrom = target.contains('from=ios_app');
        if (!hasIosFrom) {
          target = target.contains('?')
              ? '$target&from=ios_app'
              : '$target?from=ios_app';
        }
      }
    }
    return target;
  }
  // `/igreja/login/apple` sem `after`: renovação/planos — evita pós-login em `/painel`
  // (que reativa a escolha «Sou membro / gestor» na web).
  final loginPath = loginUri.path;
  if (loginPath.endsWith('/igreja/login/apple')) {
    return fromIosApp ? '/atualizar-plano?from=ios_app' : '/atualizar-plano';
  }
  if (fromIosApp) return '/atualizar-plano?from=ios_app';
  return '/painel';
}

/// Salva a rota atual para, ao reabrir o app pelo ícone, abrir onde parou (evita tela preta).
class _LastRouteObserver extends NavigatorObserver {
  static const _key = 'last_route';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _save(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _save(previousRoute);
  }

  void _save(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    // Evita gravar rotas de login/entrada para não criar loops ao reabrir o app.
    if (name == '/' || name.startsWith('/login')) return;
    if (name == '/login_admin' ||
        name.startsWith('/igreja/login')) {
      return;
    }
    // Focamos em estabilidade do painel principal.
    final isPainel = name == '/painel' ||
        name == '/admin' ||
        name.startsWith('/painel') ||
        name.startsWith('/admin');
    if (!isPainel) return;
    unawaited(AppResumeStateService.saveLastRoute(name));
  }
}

/// Protege o painel master: só exibe após login com usuário e senha e se for ADM.
class _MasterPanelGuard extends StatefulWidget {
  const _MasterPanelGuard();

  @override
  State<_MasterPanelGuard> createState() => _MasterPanelGuardState();
}

class _MasterPanelGuardState extends State<_MasterPanelGuard>
    with WidgetsBindingObserver {
  int? _accessLevel;
  bool _resolveInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accessLevel = AppSessionStability.peekCachedMasterAccessLevel();
    if (_accessLevel == null) {
      unawaited(_resolveAccess());
    } else {
      unawaited(
        AppSessionStability.resolveMasterAccessLevel().then((level) {
          if (!mounted) return;
          if (level != _accessLevel) setState(() => _accessLevel = level);
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppSessionStability.onGlobalResume();
      if (_accessLevel != null && _accessLevel! >= 2) return;
      unawaited(_resolveAccess());
    }
  }

  Future<void> _resolveAccess() async {
    if (_resolveInFlight) return;
    _resolveInFlight = true;
    try {
      final level = await AppSessionStability.resolveMasterAccessLevel();
      if (!mounted) return;
      setState(() => _accessLevel = level);
    } finally {
      _resolveInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = _accessLevel;
    if (level == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A3D91),
          foregroundColor: Colors.white,
          title: const Text('Painel Master',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Color(0xFF0A3D91)),
              ),
              const SizedBox(height: 20),
              Text(
                'Verificando acesso...',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }
    switch (level) {
          case 0:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login_admin');
              }
            });
            return Scaffold(
              backgroundColor: const Color(0xFFF0F4FF),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(height: 16),
                    Text('Redirecionando para login...',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            );
          case 1:
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Acesso restrito. Apenas administradores podem acessar o Painel Master.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            );
      default:
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Use o botão "Sair" no menu para encerrar a sessão.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const AdminPanelPage(),
            );
    }
  }
}

String? _extractChurchSlugFromHost(String host) {
  final raw = host.trim().toLowerCase();
  if (raw.isEmpty) return null;
  if (raw == 'localhost' || raw.startsWith('localhost:')) return null;
  if (raw == '127.0.0.1' || raw.startsWith('127.0.0.1:')) return null;
  final withoutPort = raw.split(':').first;
  final parts = withoutPort.split('.').where((e) => e.isNotEmpty).toList();
  if (parts.length < 3) return null;

  // Firebase Hosting: <projeto>.web.app — o 1º segmento é o ID do projeto, não slug de igreja.
  final n = parts.length;
  if (n >= 3 && parts[n - 2] == 'web' && parts[n - 1] == 'app') {
    return null;
  }

  // Domínio .com.br na raiz: `marca.com.br` tem 3 partes (marca, com, br).
  // Só há subdomínio de igreja em `igreja.marca.com.br` (4+ partes).
  if (n == 3 && parts[1] == 'com' && parts[2] == 'br') {
    return null;
  }

  final sub = parts.first;
  if (sub == 'www') return null;
  if (AppConstants.reservedChurchSlugs.contains(sub)) return null;
  if (AppConstants.isMarketingBrandSlug(sub)) return null;
  if (!RegExp(r'^[a-z0-9_-]{2,}$').hasMatch(sub)) return null;
  return sub;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Controle Total: um único initializeApp (firebase/firebase_bootstrap.dart).
  await FirebaseBootstrap.ensureInitialized();
  try {
    unawaited(
      OfflineFirstCoordinator.initialize().catchError((Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('OfflineFirstCoordinator.initialize (main): $e\n$st');
        }
      }),
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('OfflineFirstCoordinator.initialize (main): $e\n$st');
    }
  }
  // Controle Total: cache de imagens conservador (menos GC em listas com fotos).
  if (kIsWeb) {
    PaintingBinding.instance.imageCache.maximumSize = 200;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  } else {
    PaintingBinding.instance.imageCache.maximumSize = 400;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 80 * 1024 * 1024;
  }
  initUrlStrategy();

  // Mesmo padrão do Controle Total: iPhone (todas as versões) e Android
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Android 15+: evitar cores opacas nas barras (alinhado a edge-to-edge / APIs deprecadas na Play).
    if (defaultTargetPlatform == TargetPlatform.android) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: true,
        ),
      );
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Health check + Firestore settings — sem segundo initializeApp.
  final firebaseBoot = await FirebaseBootstrapService.initialize();
  await Future.wait<void>([
    LoginPreferences.warmUpForStartup(),
    AppShellSessionCache.warmUp(),
    AuthProfileCacheService.warmUpForStartup(),
  ]);
  if (!firebaseBoot.isReady) {
    runApp(
      MaterialApp(
        title: 'Gestão Yahweh',
        home: FirebaseBootstrapRecoveryPage(
          result: firebaseBoot,
          onRecovered: runGestaoYahwehAfterFirebaseBootstrap,
        ),
      ),
    );
    return;
  }
  await runGestaoYahwehAfterFirebaseBootstrap();
}

String _normalizeWebAppPath(String raw) {
  var path = raw.trim().isEmpty ? '/' : raw.trim();
  if (!path.startsWith('/')) path = '/$path';
  if (path.length > 1 && path.endsWith('/')) {
    path = path.replaceFirst(RegExp(r'/$'), '');
  }
  final low = path.toLowerCase();
  if (low == '/index.html' || low.endsWith('/index.html')) {
    return '/';
  }
  return path;
}

/// Rota inicial web **sem** SharedPreferences nem poll de sessão — 1.º frame rápido.
String _resolveWebInitialRouteFast() {
  var initialRoute =
      Uri.base.path.isNotEmpty ? _normalizeWebAppPath(Uri.base.path) : '/';
  if (initialRoute == '/' || initialRoute.isEmpty) {
    final subdomainSlug = _extractChurchSlugFromHost(Uri.base.host);
    if (subdomainSlug != null && subdomainSlug.isNotEmpty) {
      initialRoute = '/igreja/$subdomainSlug';
    }
  }
  final syncUser = FirebaseAuth.instance.currentUser;
  if (syncUser != null && !syncUser.isAnonymous) {
    const entryRoutes = {'/', '', '/login', '/igreja/login'};
    if (entryRoutes.contains(initialRoute)) {
      return '/painel';
    }
  }
  return initialRoute;
}

Future<String> _resolveWebInitialRouteWithSession(String bootRoute) async {
  var initialRoute = bootRoute;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (initialRoute == '/painel' ||
        initialRoute == '/admin' ||
        initialRoute.startsWith('/painel') ||
        initialRoute.startsWith('/admin')) {
      await prefs.setString('last_route', '/painel');
    }
    final last = prefs.getString('last_route');
    final hasSession = AuthService.hasActiveSession;
    if (last != null && last.isNotEmpty) {
      final isPublicRoot = initialRoute == '/' || initialRoute.isEmpty;
      if (!isPublicRoot) {
        final keepCurrent = initialRoute != '/' && initialRoute != '';
        final isPublicChurchDeep =
            PublicWebRouteParser.isPublicChurchDeepRoute(initialRoute);
        if (!keepCurrent && !isPublicChurchDeep) {
          if (hasSession) {
            initialRoute = '/painel';
          } else {
            initialRoute = last;
          }
        }
      }
    }
    if (hasSession && (initialRoute == '/' || initialRoute.isEmpty)) {
      initialRoute = '/painel';
    }
    final autoPainel = await ChurchAutoSessionService
        .painelRouteIfSessionRestored(initialRoute)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (autoPainel != null) {
      initialRoute = autoPainel;
    }
  } catch (_) {}
  return initialRoute;
}

/// Android/iOS: 1.º frame rápido — sem poll de sessão nem SharedPreferences.
String _resolveNativeInitialRouteFast() {
  if (LoginPreferences.startupAccountSwitchPending == true) {
    return AppStartupRoute.nativeLoginRoute;
  }
  final syncUser = FirebaseAuth.instance.currentUser;
  if (syncUser != null && !syncUser.isAnonymous) {
    return '/painel';
  }
  if (LoginPreferences.autoPainelLoginSync) {
    final shellUid = AppShellSessionCache.cachedUidSync();
    if (shellUid != null && shellUid.isNotEmpty) {
      return '/painel';
    }
  }
  return AppStartupRoute.nativeLoginRoute;
}

Future<String> _resolveNativeInitialRouteWithSession(String bootRoute) async {
  var initialRoute = bootRoute;
  try {
    initialRoute = await AppStartupRoute.finalizeNativeRoute(initialRoute);
    final autoPainel = await ChurchAutoSessionService
        .painelRouteIfSessionRestored(initialRoute)
        .timeout(const Duration(seconds: 1), onTimeout: () => null);
    if (autoPainel != null) {
      initialRoute = autoPainel;
    }
    if (initialRoute == '/painel' || initialRoute.startsWith('/painel/')) {
      if (!await AuthSessionService.hasSession()) {
        initialRoute = AppStartupRoute.nativeLoginRoute;
      }
    }
  } catch (_) {}
  return initialRoute;
}

Future<void> _finalizeNativeStartupAfterFirstFrame(String bootRoute) async {
  try {
    await AppConnectivityService.instance.start();
    AppFinalizeBootstrap.bindOnColdStart();
  } catch (_) {}

  final resolved = await _resolveNativeInitialRouteWithSession(bootRoute);
  final painelReopen =
      resolved == '/painel' || resolved.startsWith('/painel/');
  if (painelReopen) {
    unawaited(
      PanelPreheatCoordinator.preheatOnce().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
    );
    AppStartupPreheat.scheduleBackgroundWarmup();
  }

  if (resolved == bootRoute) return;
  final page = _explicitStartupPage(resolved);
  if (page == null) return;
  final nav = appRootNavigatorKey.currentState;
  if (nav == null) return;
  nav.pushReplacement(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: resolved),
      builder: (_) => page,
    ),
  );
}

Future<void> _finalizeWebStartupAfterFirstFrame(String bootRoute) async {
  try {
    await AuthService.configurePersistentSession();
  } catch (_) {}
  try {
    await FirestoreWebGuard.bindWebHostingDomainSession();
  } catch (_) {}
  try {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
  } catch (_) {}
  try {
    await AppConnectivityService.instance.start();
    AppFinalizeBootstrap.bindOnColdStart();
  } catch (_) {}

  final resolved = await _resolveWebInitialRouteWithSession(bootRoute);
  final painelReopen =
      resolved == '/painel' || resolved.startsWith('/painel/');
  if (painelReopen) {
    unawaited(
      PanelPreheatCoordinator.preheatOnce().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      ),
    );
  }

  if (resolved == bootRoute) return;
  const entryRoutes = {'/', '', '/login', '/igreja/login'};
  if (!entryRoutes.contains(bootRoute)) return;
  if (resolved != '/painel' &&
      !resolved.startsWith('/painel/') &&
      resolved != '/admin' &&
      !resolved.startsWith('/admin/')) {
    return;
  }

  final page = _explicitStartupPage(resolved);
  if (page == null) return;
  final nav = appRootNavigatorKey.currentState;
  if (nav == null) return;
  nav.pushReplacement(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: resolved),
      builder: (_) => page,
    ),
  );
}

/// Crashlytics nativo — pode correr após o 1.º frame (não bloquear [runApp]).
Future<void> _bindNativeCrashlyticsHandlers() async {
  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(kReleaseMode);
  } catch (_) {}
  FlutterError.onError = (FlutterErrorDetails details) {
    Future<void> fallbackChain(Object e, StackTrace st) async {
      try {
        await FirebaseCrashlytics.instance.recordError(
          Exception(
            '${details.exceptionAsString()} | crashlytics_report: $e',
          ),
          details.stack ?? st,
          fatal: !_crashlyticsFlutterErrorLikelyBenign(details),
        );
      } catch (_) {}
    }

    try {
      if (_crashlyticsFlutterErrorLikelyBenign(details)) {
        FirebaseCrashlytics.instance
            .recordFlutterError(details, fatal: false)
            .catchError((Object e, StackTrace st) {
          unawaited(fallbackChain(e, st));
        });
      } else {
        FirebaseCrashlytics.instance
            .recordFlutterFatalError(details)
            .catchError((Object e, StackTrace st) {
          unawaited(fallbackChain(e, st));
        });
      }
    } catch (e, st) {
      unawaited(fallbackChain(e, st));
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final benign = CrashlyticsBenignErrors.isBenign(error);
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: !benign,
      );
    } catch (e) {
      try {
        FirebaseCrashlytics.instance.recordError(
          Exception('zone_error: $error | crashlytics_wrap: $e'),
          stack,
          fatal: true,
        );
      } catch (_) {}
    }
    return true;
  };
}

void _installFriendlyErrorWidget() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFFF7F8FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível abrir esta tela. Feche e abra o app de novo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  };
}

/// Continuação do arranque após Firebase OK (ou após ecrã de recuperação).
Future<void> runGestaoYahwehAfterFirebaseBootstrap() async {
  _installFriendlyErrorWidget();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(
      PersistentAuthSessionService.warmColdStart().catchError((_) => false),
    );
  }
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    unawaited(
      PanelNotificationService.instance
          .registerAndroidChannelsForBoot()
          .catchError((_) {}),
    );
    unawaited(
      ChurchChatAlertNotificationService.instance
          .registerFcmChatAndroidChannelsForBoot()
          .catchError((Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('FCM chat channels boot: $e\n$st');
        }
      }),
    );
  }
  ensureBrasiliaTimeZoneInitialized();
  unawaited(
    YahwehObservability.ensureInitialized().catchError((Object e, StackTrace st) {
      if (kDebugMode) debugPrint('YahwehObservability: $e\n$st');
    }),
  );
  // Crashlytics: só Android/iOS (evita desktop/web onde o plugin não aplica).
  final crashlyticsOk = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  if (AppStartupRoute.isNativeMobile) {
    final initialRoute = _resolveNativeInitialRouteFast();
    AppDeepLink.registerWarmLinkHandler();
    unawaited(
      initializeDateFormatting('pt_BR', null).catchError((Object e, StackTrace st) {
        debugPrint('initializeDateFormatting(pt_BR): $e\n$st');
      }),
    );
    runApp(UpdateChecker(
      child: _AppWithTheme(initialRoute: initialRoute),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (crashlyticsOk) {
        unawaited(_bindNativeCrashlyticsHandlers().catchError((_) {}));
      }
      unawaited(
        IosPaymentsGate.initialize().catchError((_) {}),
      );
      unawaited(_finalizeNativeStartupAfterFirstFrame(initialRoute));
    });
    return;
  }

  if (crashlyticsOk) {
    await _bindNativeCrashlyticsHandlers();
  }
  if (!kIsWeb) {
    try {
      await IosPaymentsGate.initialize();
    } catch (_) {}
  }

  if (kIsWeb) {
    final initialRoute = _resolveWebInitialRouteFast();
    AppDeepLink.registerWarmLinkHandler();
    unawaited(
      initializeDateFormatting('pt_BR', null).catchError((Object e, StackTrace st) {
        debugPrint('initializeDateFormatting(pt_BR): $e\n$st');
      }),
    );
    runApp(UpdateChecker(
      child: _AppWithTheme(initialRoute: initialRoute),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_finalizeWebStartupAfterFirstFrame(initialRoute));
      unawaited(DomainDailyHitService.recordIfEligible());
    });
    return;
  }

  String initialRoute = '/';
  AppDeepLink.registerWarmLinkHandler();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      final deepPath = await AppDeepLink.initialPath();
      final fromDeep = PublicWebRouteParser.inAppRouteFromPath(deepPath ?? '');
      if (fromDeep != null &&
          PublicWebRouteParser.isPublicSignupDeepRoute(fromDeep)) {
        initialRoute = fromDeep;
      }
    } catch (_) {}
  }
  // Web: ao reabrir com sessão, abrir sempre o painel inicial (não a última rota/aba).
  if (true) {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (initialRoute == '/painel' ||
          initialRoute == '/admin' ||
          initialRoute.startsWith('/painel') ||
          initialRoute.startsWith('/admin')) {
        await prefs.setString('last_route', '/painel');
      }
      final last = prefs.getString('last_route');
      final hasSession = AuthService.hasActiveSession;
      if (last != null && last.isNotEmpty) {
        final isPublicRoot =
            kIsWeb && (initialRoute == '/' || initialRoute.isEmpty);
        if (!isPublicRoot) {
          final keepCurrent = kIsWeb && initialRoute != '/' && initialRoute != '';
          final isPublicChurchDeep =
              PublicWebRouteParser.isPublicChurchDeepRoute(initialRoute);
          if (!keepCurrent && !isPublicChurchDeep) {
            if (hasSession) {
              initialRoute = '/painel';
            } else if (kIsWeb) {
              initialRoute = last;
            } else {
              initialRoute = '/login';
            }
          }
        }
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        // Android/iOS: com sessão Firebase persistida abre directo o painel.
        initialRoute = AuthService.hasActiveSession
            ? '/painel'
            : (defaultTargetPlatform == TargetPlatform.iOS
                ? '/igreja/login'
                : '/login');
      }
      if (kIsWeb &&
          AuthService.hasActiveSession &&
          (initialRoute == '/' || initialRoute.isEmpty)) {
        initialRoute = '/painel';
      }
      final autoPainel = await ChurchAutoSessionService
          .painelRouteIfSessionRestored(initialRoute)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (autoPainel != null) {
        initialRoute = autoPainel;
      }
    } catch (_) {}
    // Fallback se SharedPreferences falhar no app móvel.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (initialRoute == '/' || initialRoute.isEmpty)) {
      initialRoute = AuthService.hasActiveSession
          ? '/painel'
          : (defaultTargetPlatform == TargetPlatform.iOS
              ? '/igreja/login'
              : '/login');
    }
    if (AppStartupRoute.isNativeMobile) {
      initialRoute = await AppStartupRoute.finalizeNativeRoute(initialRoute);
    }
    final reopenUid = FirebaseAuth.instance.currentUser?.uid ??
        AppShellSessionCache.cachedUidSync();
    final shellFast = reopenUid != null &&
        reopenUid.isNotEmpty &&
        AppShellSessionCache.isShellReadyForSync(reopenUid) &&
        (LoginPreferences.autoPainelLoginSync ||
            initialRoute == '/painel' ||
            initialRoute.startsWith('/painel/'));
    final painelReopen = initialRoute == '/painel' ||
        initialRoute.startsWith('/painel/');
    if (shellFast && painelReopen && !kIsWeb) {
      unawaited(
        PanelPreheatCoordinator.preheatOnce().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        ).catchError((Object e, StackTrace st) {
          if (kDebugMode) debugPrint('PanelPreheatCoordinator: $e\n$st');
        }),
      );
    } else if (painelReopen &&
        (kIsWeb ||
            (AppStartupRoute.isNativeMobile &&
                await AuthSessionService.hasSession()))) {
      unawaited(
        PanelPreheatCoordinator.preheatOnce().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        ),
      );
      if (AppStartupRoute.isNativeMobile) {
        unawaited(AppStartupPreheat.preheatForDashboard());
      }
    }
  }
  unawaited(
    initializeDateFormatting('pt_BR', null).catchError((Object e, StackTrace st) {
      debugPrint('initializeDateFormatting(pt_BR): $e\n$st');
    }),
  );
  runApp(UpdateChecker(
    child: _AppWithTheme(initialRoute: initialRoute),
  ));
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(DomainDailyHitService.recordIfEligible());
    });
  }
}

class _AppWithTheme extends StatefulWidget {
  final String initialRoute;

  const _AppWithTheme({required this.initialRoute});

  @override
  State<_AppWithTheme> createState() => _AppWithThemeState();
}

class _AppWithThemeState extends State<_AppWithTheme>
    with WidgetsBindingObserver {
  late final ThemeModeProvider _themeProvider;
  Timer? _webResumeRepaintDebounce;
  StreamSubscription<String>? _deepLinkSub;
  void _onThemeChanged() => setState(() {});

  /// Web/PWA (CanvasKit): ao voltar de outro app, o canvas pode ficar preto até recompositor.
  void _repaintAfterWebResume() {
    _webResumeRepaintDebounce?.cancel();
    _webResumeRepaintDebounce = Timer(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      setState(() {});
      SchedulerBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SchedulerBinding.instance.scheduleFrame();
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSessionStability.bindGlobal(this);
    AppSessionStability.bindSessionKeepalive();
    if (kIsWeb) {
      registerWebResumeRepaint(_repaintAfterWebResume);
    }
    _themeProvider = ThemeModeProvider();
    _themeProvider.addListener(_onThemeChanged);
    if (!kIsWeb) {
      _deepLinkSub = AppDeepLink.warmLinks.listen((path) {
        final route = PublicWebRouteParser.inAppRouteFromPath(path);
        if (route == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appRootNavigatorKey.currentState?.pushNamed(route);
        });
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      window_close_handler.initWindowCloseHandler(appRootNavigatorKey);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSub?.cancel();
    _webResumeRepaintDebounce?.cancel();
    if (kIsWeb) {
      unregisterWebResumeRepaint(_repaintAfterWebResume);
    }
    _themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AppSessionStability.onGlobalResume();
      if (kIsWeb) _repaintAfterWebResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeModeScope(
        notifier: _themeProvider,
        child: MaterialApp(
          navigatorKey: appRootNavigatorKey,
          scrollBehavior: const GestaoYahwehScrollBehavior(),
          title: 'Gestão Yahweh - Igrejas',
          theme: ThemeCleanPremium.themeData,
          darkTheme: ThemeCleanPremium.themeDataDark,
          themeMode: _themeProvider.mode,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [
            Locale('pt', 'BR'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _initialAppHome(widget.initialRoute),
          debugShowCheckedModeBanner: false,
          navigatorObservers: [
            _LastRouteObserver(),
            if (PublicSiteAnalytics.navigatorObserver != null)
              PublicSiteAnalytics.navigatorObserver!,
          ],
          builder: (context, child) {
            // Evita tela preta ao voltar de outro app ou ao abrir pelo ícone: fundo sempre visível
            final c = child ?? const SizedBox.shrink();
            final bg = Theme.of(context).scaffoldBackgroundColor;
            return SyncFeedbackListener(
              child: Container(
                color: bg,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: c,
                ),
              ),
            );
          },
          onGenerateRoute: (settings) {
            final nomeRota = (settings.name ?? '/');
            final uri = Uri.parse(nomeRota);
            String path = uri.path.isEmpty ? '/' : uri.path;
            if (path != '/' && !path.startsWith('/')) path = '/$path';
            if (path.length > 1 && path.endsWith('/')) {
              path = path.replaceFirst(RegExp(r'/$'), '');
            }
            final lowPath = path.toLowerCase();
            if (lowPath == '/index.html' || lowPath.endsWith('/index.html')) {
              path = '/';
            }
            final pathSegments = path == '/'
                ? <String>[]
                : path.split('/').where((s) => s.isNotEmpty).toList();

            // ── iOS App Store (Apple Guideline 3.1.1 / 3.1.3) ──
            // No app iOS nativo, NUNCA expor páginas com preços/checkout
            // (LandingPage, RenewPlanPage, SitePublicPage). Redireciona
            // tudo para login ou para a tela informativa sem preços.
            if (IosPaymentsGate.isIosNative) {
              if (path == '/') {
                final em = uri.queryParameters['email']?.trim();
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => LoginPage(
                    title: 'Entrar com conta existente',
                    afterLoginRoute: '/painel',
                    showFleetBranding: false,
                    backRoute: '/',
                    prefillEmail:
                        (em != null && em.isNotEmpty) ? em : null,
                  ),
                );
              }
              if (path == '/planos' ||
                  path == '/pagamento' ||
                  path == '/atualizar-plano') {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => const IosPaymentUnavailableView(),
                );
              }
              if (IosPaymentsGate.isOrganizationSignupPath(path, pathSegments)) {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => const IosOrganizationSignupWebPage(),
                );
              }
            }

            Widget pagina;
            // Rota dinâmica para /igreja_<slug> ou /igreja-<slug> — exibe perfil público da igreja
            final igrejaMatch =
                RegExp(r'^/igreja[_-]([\w\d_-]+)').firstMatch(path);
            if (igrejaMatch != null) {
              final slug = igrejaMatch.group(1)!;
              pagina = AppConstants.isMarketingBrandSlug(slug)
                  ? const SitePublicPage()
                  : ChurchPublicPage(slug: slug);
            } else if (pathSegments.isNotEmpty &&
                pathSegments[0] == 'i' &&
                pathSegments.length >= 2) {
              // Rota curta /i/<slug> — redireciona para site público da igreja
              final slug = pathSegments[1];
              pagina = AppConstants.isMarketingBrandSlug(slug)
                  ? const SitePublicPage()
                  : ChurchPublicPage(slug: slug);
            } else if (pathSegments.isNotEmpty &&
                pathSegments[0] == 'igreja' &&
                pathSegments.length >= 2 &&
                pathSegments[1] != 'login') {
              // Rotas /igreja/<slug>, /igreja/<slug>/evento/<noticiaId>, cadastro, etc.
              final slug = pathSegments[1];
              if (AppConstants.isMarketingBrandSlug(slug)) {
                pagina = const SitePublicPage();
              } else if (pathSegments.length >= 4 &&
                  pathSegments[2].toLowerCase() == 'evento') {
                pagina = ChurchPublicPage(
                  slug: slug,
                  openNoticiaId: pathSegments[3],
                );
              } else if (pathSegments.length >= 3 &&
                  pathSegments[2] == 'cadastro-membro') {
                pagina = PublicMemberSignupPage(slug: slug);
              } else if (pathSegments.length >= 3 &&
                  pathSegments[2] == 'acompanhar-cadastro') {
                pagina = PublicSignupStatusPage(
                  slug: slug,
                  protocolo: uri.queryParameters['protocolo'] ?? '',
                );
              } else if (pathSegments.length >= 3 &&
                  pathSegments[2] == 'cadastro') {
                pagina = IosPaymentsGate.isIosNative
                    ? const IosOrganizationSignupWebPage()
                    : SignupPage(
                        initialEmail:
                            uri.queryParameters['email']?.trim(),
                      );
              } else {
                pagina = ChurchPublicPage(slug: slug);
              }
            } else if (pathSegments.length == 1 &&
                pathSegments[0].isNotEmpty &&
                !AppConstants.reservedChurchSlugs
                    .contains(pathSegments[0].toLowerCase())) {
              // Domínio único: /{slug}
              pagina = ChurchPublicPage(slug: pathSegments[0]);
            } else if (pathSegments.length == 2 &&
                pathSegments[0].isNotEmpty &&
                !AppConstants.reservedChurchSlugs
                    .contains(pathSegments[0].toLowerCase())) {
              final slug = pathSegments[0];
              final second = pathSegments[1];
              final low = second.toLowerCase();
              if (low == 'cadastro-membro') {
                pagina = PublicMemberSignupPage(slug: slug);
              } else if (low == 'acompanhar-cadastro') {
                pagina = PublicSignupStatusPage(
                  slug: slug,
                  protocolo: uri.queryParameters['protocolo'] ?? '',
                );
              } else if (low == 'cadastro') {
                pagina = IosPaymentsGate.isIosNative
                    ? const IosOrganizationSignupWebPage()
                    : SignupPage(
                        initialEmail:
                            uri.queryParameters['email']?.trim(),
                      );
              } else {
                pagina = ChurchPublicPage(slug: slug, openNoticiaId: second);
              }
            } else {
              switch (path) {
                case '/cadastro':
                  pagina = IosPaymentsGate.isIosNative
                      ? const IosOrganizationSignupWebPage()
                      : const CadastroUsuarioPage();
                  break;
                case '/usuarios_permissoes':
                  pagina = const UsuariosPermissoesPage(
                      tenantId: 'TENANT_ID', gestorRole: 'admin');
                  break;
                case '/aprovar_membros_pendentes':
                  pagina = const AprovarMembrosPendentesPage(
                      tenantId: 'TENANT_ID', gestorRole: 'admin');
                  break;
                case '/admin':
                  pagina = const _MasterPanelGuard();
                  break;
                case '/admin/firebase-saude':
                  pagina = const SystemFirebaseHealthPage();
                  break;
                case '/login_admin':
                  pagina = const LoginPage(
                    title: 'Entrar no Painel Master',
                    afterLoginRoute: '/admin',
                    showFleetBranding: false,
                  );
                  break;
                case '/login': {
                  final em = uri.queryParameters['email']?.trim();
                  pagina = LoginPageNovo(
                    prefillEmail:
                        (em != null && em.isNotEmpty) ? em : null,
                  );
                  break;
                }
                case '/igreja/login': {
                  final em = uri.queryParameters['email']?.trim();
                  // App iOS nativo: só login → painel; plano/licença no Safari (3.1.1).
                  final afterLogin = IosPaymentsGate.isIosNative
                      ? '/painel'
                      : _resolveIgrejaLoginAfterRoute(uri);
                  pagina = LoginPage(
                    title: IosPaymentsGate.isIosNative
                        ? 'Entrar com conta existente'
                        : 'Entrar — Painel da Igreja',
                    afterLoginRoute: afterLogin,
                    showFleetBranding: false,
                    backRoute: '/',
                    showSmartLoginFlow: false,
                    prefillEmail:
                        (em != null && em.isNotEmpty) ? em : null,
                  );
                  break;
                }
                case '/igreja/login/apple': {
                  final em = uri.queryParameters['email']?.trim();
                  final afterLogin = IosPaymentsGate.isIosNative
                      ? '/painel'
                      : _resolveIgrejaLoginAfterRoute(uri);
                  pagina = LoginPage(
                    title: IosPaymentsGate.isIosNative
                        ? 'Entrar com conta existente'
                        : 'Entrar — Painel da Igreja',
                    afterLoginRoute: afterLogin,
                    showFleetBranding: false,
                    backRoute: '/',
                    prefillEmail:
                        (em != null && em.isNotEmpty) ? em : null,
                    // Só na web (Safari): fluxo expresso pós-login em /atualizar-plano.
                    churchWebAppleIosRenewEntry: kIsWeb,
                  );
                  break;
                }
                case '/planos':
                  pagina = const LandingPage();
                  break;
                case '/pagamento':
                  // Mesmo gate que `/atualizar-plano`: exige login com claims da igreja.
                  pagina = const ExpressRenewGatePage();
                  break;
                case '/atualizar-plano': {
                  // Fluxo «Atualizar plano expresso» — vindo do app iOS via
                  // Safari (IosPaymentUnavailableView). Só pede login para
                  // identificar a igreja e leva direto ao checkout MP.
                  final em = uri.queryParameters['email']?.trim();
                  final fromIos = uri.queryParameters['from']?.toLowerCase() ==
                      'ios_app';
                  pagina = ExpressRenewGatePage(
                    prefillEmail:
                        (em != null && em.isNotEmpty) ? em : null,
                    openedFromIosApp: fromIos,
                  );
                  break;
                }
                case '/signup': {
                  pagina = IosPaymentsGate.isIosNative
                      ? const IosOrganizationSignupWebPage()
                      : SignupPage(
                          initialEmail:
                              uri.queryParameters['email']?.trim(),
                        );
                  break;
                }
                case '/signup/completar-dados':
                  pagina = IosPaymentsGate.isIosNative
                      ? const IosOrganizationSignupWebPage()
                      : const SignupCompletarGestorPage();
                  break;
                case '/painel': {
                  final openMember =
                      uri.queryParameters['openMemberId']?.trim() ?? '';
                  final openMod =
                      uri.queryParameters['openModule']?.trim().toLowerCase() ??
                          '';
                  int? shellFromQuery;
                  if (openMod == 'minha_escala' ||
                      openMod == 'my_schedules' ||
                      openMod == 'minhaescala') {
                    shellFromQuery = kChurchShellIndexMySchedules;
                  } else if (openMod == 'escala_geral' ||
                      openMod == 'schedules' ||
                      openMod == 'escalas') {
                    shellFromQuery = kChurchShellIndexEscalaGeral;
                  }
                  pagina = AuthGate(
                    initialOpenMemberDocId:
                        openMember.isEmpty ? null : openMember,
                    initialShellIndex: shellFromQuery,
                  );
                  break;
                }
                case '/':
                  pagina = const SitePublicPage();
                  break;
                case '/s/evento':
                  pagina = const SitePublicPage(isConviteRoute: true);
                  break;
                case '/carteirinha-validar':
                  pagina = PublicCarteirinhaConsultaPage(
                    tenantId: uri.queryParameters['tenantId'] ?? '',
                    memberId: uri.queryParameters['memberId'] ?? '',
                  );
                  break;
                case '/certificado-validar':
                  pagina = PublicCertificadoConsultaPage(
                    tenantId: uri.queryParameters['tenantId'] ?? '',
                    memberId: uri.queryParameters['memberId'] ?? '',
                    certTipoId: uri.queryParameters['tipo'] ?? '',
                    issuedKey: uri.queryParameters['emitido'] ?? '',
                  );
                  break;
                case '/validar':
                  pagina = PublicCertificadoValidacaoPage(
                    certificadoId: uri.queryParameters['cid'] ?? '',
                  );
                  break;
                case '/convite-departamento':
                  pagina = DepartmentInvitePage(
                    tenantIdOrSlug: uri.queryParameters['tid'] ?? '',
                    departmentId: uri.queryParameters['did'] ?? '',
                  );
                  break;
                case '/termos-de-uso':
                case '/termos':
                case '/termodeuso':
                  pagina = const TermosDeUsoPage();
                  break;
                case '/politica-de-privacidade':
                case '/privacidade':
                  pagina = const PoliticaPrivacidadePage();
                  break;
                default:
                  pagina = const SitePublicPage();
                  break;
              }
            }
            return MaterialPageRoute(
                builder: (_) => pagina, settings: settings);
          },
        ));
  }
}

/// Home inicial: rotas críticas sem splash (web + Android/iOS).
Widget _initialAppHome(String rawRoute) {
  final r = rawRoute.trim().isEmpty ? '/' : rawRoute.trim();
  if (r == '/') return const SitePublicPage();
  final page = _explicitStartupPage(r);
  if (page != null) return page;
  return _StartupSplashGate(targetRoute: r);
}

/// Site público da igreja / cadastro — cold start web (evita fallback para [SitePublicPage]).
Widget? _widgetForChurchPublicPath(Uri uri) {
  var path = uri.path.isEmpty ? '/' : uri.path;
  if (path != '/' && !path.startsWith('/')) path = '/$path';
  if (path.length > 1 && path.endsWith('/')) {
    path = path.replaceFirst(RegExp(r'/$'), '');
  }
  final pathSegments = path == '/'
      ? <String>[]
      : path.split('/').where((s) => s.isNotEmpty).toList();

  final igrejaMatch = RegExp(r'^/igreja[_-]([\w\d_-]+)').firstMatch(path);
  if (igrejaMatch != null) {
    final slug = igrejaMatch.group(1)!;
    if (AppConstants.isMarketingBrandSlug(slug)) return const SitePublicPage();
    return ChurchPublicPage(slug: slug);
  }

  if (pathSegments.length >= 2 && pathSegments[0] == 'i') {
    final slug = pathSegments[1];
    if (AppConstants.isMarketingBrandSlug(slug)) return const SitePublicPage();
    return ChurchPublicPage(slug: slug);
  }

  if (pathSegments.length >= 2 &&
      pathSegments[0] == 'igreja' &&
      pathSegments[1] != 'login') {
    final slug = pathSegments[1];
    if (AppConstants.isMarketingBrandSlug(slug)) return const SitePublicPage();
    if (pathSegments.length >= 4 &&
        pathSegments[2].toLowerCase() == 'evento') {
      return ChurchPublicPage(
        slug: slug,
        openNoticiaId: pathSegments[3],
      );
    }
    if (pathSegments.length >= 3 && pathSegments[2] == 'cadastro-membro') {
      return PublicMemberSignupPage(slug: slug);
    }
    if (pathSegments.length >= 3 && pathSegments[2] == 'acompanhar-cadastro') {
      return PublicSignupStatusPage(
        slug: slug,
        protocolo: uri.queryParameters['protocolo'] ?? '',
      );
    }
    return ChurchPublicPage(slug: slug);
  }

  if (pathSegments.length == 1 &&
      pathSegments[0].isNotEmpty &&
      !AppConstants.reservedChurchSlugs
          .contains(pathSegments[0].toLowerCase())) {
    return ChurchPublicPage(slug: pathSegments[0]);
  }

  if (pathSegments.length == 2 &&
      pathSegments[0].isNotEmpty &&
      !AppConstants.reservedChurchSlugs
          .contains(pathSegments[0].toLowerCase())) {
    final slug = pathSegments[0];
    final second = pathSegments[1];
    final low = second.toLowerCase();
    if (low == 'cadastro-membro') {
      return PublicMemberSignupPage(slug: slug);
    }
    if (low == 'acompanhar-cadastro') {
      return PublicSignupStatusPage(
        slug: slug,
        protocolo: uri.queryParameters['protocolo'] ?? '',
      );
    }
    return ChurchPublicPage(slug: slug, openNoticiaId: second);
  }

  return null;
}

/// Rotas críticas com [MaterialPageRoute] explícita — `pushReplacementNamed` falha
/// no Flutter Web quando [MaterialApp.home] é o splash.
Widget? _explicitStartupPage(String rawRoute) {
  final uri = rawRoute.contains('://')
      ? (Uri.tryParse(rawRoute) ?? Uri(path: '/'))
      : Uri.parse('https://gestao.invalid$rawRoute');
  var path = uri.path.isEmpty ? '/' : uri.path;
  if (path != '/' && !path.startsWith('/')) path = '/$path';
  if (path.length > 1 && path.endsWith('/')) {
    path = path.replaceFirst(RegExp(r'/$'), '');
  }
  switch (path) {
    case '/painel':
      final openMember = uri.queryParameters['openMemberId']?.trim() ?? '';
      final openMod =
          uri.queryParameters['openModule']?.trim().toLowerCase() ?? '';
      int? shellFromQuery;
      if (openMod == 'minha_escala' ||
          openMod == 'my_schedules' ||
          openMod == 'minhaescala') {
        shellFromQuery = kChurchShellIndexMySchedules;
      } else if (openMod == 'escala_geral' ||
          openMod == 'schedules' ||
          openMod == 'escalas') {
        shellFromQuery = kChurchShellIndexEscalaGeral;
      }
      return AuthGate(
        initialOpenMemberDocId: openMember.isEmpty ? null : openMember,
        initialShellIndex: shellFromQuery,
      );
    case '/login':
      final em = uri.queryParameters['email']?.trim();
      return LoginPageNovo(
        prefillEmail: (em != null && em.isNotEmpty) ? em : null,
      );
    case '/igreja/login':
      final em = uri.queryParameters['email']?.trim();
      return LoginPage(
        title: IosPaymentsGate.isIosNative
            ? 'Entrar com conta existente'
            : 'Entrar — Painel da Igreja',
        afterLoginRoute: IosPaymentsGate.isIosNative
            ? '/painel'
            : _resolveIgrejaLoginAfterRoute(uri),
        showFleetBranding: false,
        backRoute: '/',
        showSmartLoginFlow: false,
        prefillEmail: (em != null && em.isNotEmpty) ? em : null,
      );
    case '/admin':
      return const _MasterPanelGuard();
    case '/login_admin':
      return const LoginPage(
        title: 'Entrar no Painel Master',
        afterLoginRoute: '/admin',
        showFleetBranding: false,
      );
    default:
      return _widgetForChurchPublicPath(uri);
  }
}

class _StartupSplashGate extends StatefulWidget {
  final String targetRoute;
  const _StartupSplashGate({required this.targetRoute});

  @override
  State<_StartupSplashGate> createState() => _StartupSplashGateState();
}

class _StartupSplashGateState extends State<_StartupSplashGate> {
  Timer? _navFallbackTimer;

  @override
  void initState() {
    super.initState();
    final route = widget.targetRoute.trim().isEmpty ? '/' : widget.targetRoute;
    if (route != '/') {
      unawaited(_goNext());
      _navFallbackTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _navigateOffSplash(route, force: true);
      });
    }
  }

  @override
  void dispose() {
    _navFallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    var route = widget.targetRoute.trim().isEmpty ? '/' : widget.targetRoute;

    if (AppStartupRoute.isNativeMobile) {
      route = await AppStartupRoute.finalizeNativeRoute(route)
          .timeout(const Duration(seconds: 2), onTimeout: () => route);
      if (route == '/painel' || route.startsWith('/painel/')) {
        if (!await AuthSessionService.hasSession()) {
          route = AppStartupRoute.nativeLoginRoute;
        } else {
          AppStartupPreheat.scheduleBackgroundWarmup();
        }
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateOffSplash(route);
    });
  }

  void _navigateOffSplash(String route, {bool force = false}) {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final r = route.trim();
    if (r.isEmpty || r == '/') {
      nav.pushReplacement(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/'),
          builder: (_) => const SitePublicPage(),
        ),
      );
      _navFallbackTimer?.cancel();
      return;
    }
    final explicit = _explicitStartupPage(r);
    if (explicit != null) {
      nav.pushReplacement(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: r),
          builder: (_) => explicit,
        ),
      );
      _navFallbackTimer?.cancel();
      return;
    }
    if (!force) {
      nav.pushReplacementNamed(r).catchError((Object _) {
        if (mounted) _navigateOffSplash(r, force: true);
      });
      return;
    }
    final uri = Uri.parse('https://gestao.invalid$r');
    final churchPage = _widgetForChurchPublicPath(uri);
    AgentDebugLog.log(
      location: 'main.dart:_navigateOffSplash',
      message: 'splash_nav_force_fallback',
      hypothesisId: 'ROUTE-A',
      data: {
        'route': r,
        'resolvedChurchPage': churchPage != null,
        'widget': churchPage?.runtimeType.toString() ?? 'SitePublicPage',
      },
    );
    nav.pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: r),
        builder: (_) => churchPage ?? const SitePublicPage(),
      ),
    );
    _navFallbackTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.targetRoute.trim().isEmpty ? '/' : widget.targetRoute;
    if (route == '/') {
      // Abre direto o site de divulgação, sem splash/espera.
      return const SitePublicPage();
    }

    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
