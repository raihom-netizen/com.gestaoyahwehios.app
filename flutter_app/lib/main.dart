import 'dart:async';
import 'package:flutter/foundation.dart'
    show
        PlatformDispatcher,
        TargetPlatform,
        defaultTargetPlatform,
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
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/ui/pages/firebase_bootstrap_recovery_page.dart';
import 'package:gestao_yahweh/ui/pages/system_firebase_health_page.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
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
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
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
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'ui/widgets/ios_payment_unavailable_view.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/utils/brasilia_datetime_format.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gestao_yahweh/core/app_deep_link.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/core/firestore_app_config.dart';
import 'package:gestao_yahweh/core/public_web_route_parser.dart';
import 'package:gestao_yahweh/web_resume_repaint_stub.dart'
    if (dart.library.html) 'package:gestao_yahweh/web_resume_repaint_web.dart';

/// Erros de carregamento de imagem/rede viram [FlutterError] com mensagem tipo "HTTP request failed..."
/// e não indicam falha do Firestore. Registrar como **não fatal** evita ruído no Crashlytics.
bool _crashlyticsFlutterErrorLikelyBenignNetwork(FlutterErrorDetails details) {
  final ex = details.exception;
  if (ex is NetworkImageLoadException) return true;
  final msg = details.exceptionAsString().toLowerCase();
  if (msg.contains('http request failed')) return true;
  if (msg.contains('http request') && msg.contains('statuscode')) return true;
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
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_key, name);
    });
  }
}

/// Protege o painel master: só exibe após login com usuário e senha e se for ADM.
class _MasterPanelGuard extends StatefulWidget {
  const _MasterPanelGuard();

  @override
  State<_MasterPanelGuard> createState() => _MasterPanelGuardState();
}

class _MasterPanelGuardState extends State<_MasterPanelGuard> {
  late final Future<int> _checkFuture;

  @override
  void initState() {
    super.initState();
    _checkFuture = _check();
  }

  Future<int> _check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final email = (user.email ?? '').toString().toLowerCase();
    if (email == 'raihom@gmail.com') return 2;

    // 1) Custom claims (definidos pelo backend) — não dependem do Firestore
    try {
      final token = await user.getIdTokenResult(true);
      final roleClaim = (token.claims?['role'] ?? token.claims?['nivel'] ?? '')
          .toString()
          .toUpperCase();
      if (roleClaim == 'ADM' || roleClaim == 'ADMIN' || roleClaim == 'MASTER') {
        return 2;
      }
      if ((token.claims?['nivel'] ?? '').toString().toLowerCase() == 'adm') {
        return 2;
      }
      if (token.claims?['admin'] == true) return 2;
    } catch (_) {}

    // 2) Firestore users/{uid}
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 12),
              onTimeout: () => throw TimeoutException('check'));
      final data = doc.data() ?? {};
      final role =
          (data['role'] ?? data['nivel'] ?? '').toString().toUpperCase();
      final nivel = (data['nivel'] ?? '').toString().toLowerCase();
      if (role == 'ADM' ||
          role == 'ADMIN' ||
          role == 'MASTER' ||
          nivel == 'adm') {
        return 2;
      }
      return 1;
    } on TimeoutException {
      try {
        final fn = FirebaseFunctions.instance.httpsCallable('getAdminCheck');
        final res = await fn
            .call<Map<String, dynamic>>()
            .timeout(const Duration(seconds: 8));
        if (res.data['allowed'] == true) return 2;
      } catch (_) {}
      return 0;
    } catch (_) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));
        final nivel = (doc.data()?['nivel'] ?? '').toString().toLowerCase();
        if (nivel == 'adm') return 2;
      } catch (_) {}
      try {
        final fn = FirebaseFunctions.instance.httpsCallable('getAdminCheck');
        final res = await fn
            .call<Map<String, dynamic>>()
            .timeout(const Duration(seconds: 8));
        if (res.data['allowed'] == true) return 2;
      } catch (_) {}
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _checkFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Não foi possível verificar o acesso.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .pushReplacementNamed('/login_admin'),
                      icon: const Icon(Icons.login),
                      label: const Text('Ir para login'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
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
        switch (snapshot.data!) {
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
      },
    );
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
  await FirebaseBootstrap.ensureInitialized();
  // Cache de imagem: um pouco acima do padrão — listas com fotos (membros, mural).
  // Mais fotos em RAM (logos, mural, membros) = menos decode repetido ao navegar.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 140 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 280;
  initUrlStrategy();

  // Mesmo padrão do Controle Total: iPhone (todas as versões) e Android
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

  final firebaseBoot = await FirebaseBootstrapService.initialize();
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

/// Continuação do arranque após Firebase OK (ou após ecrã de recuperação).
Future<void> runGestaoYahwehAfterFirebaseBootstrap() async {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      final restored =
          await ChurchAutoSessionService.tryRestoreSessionOnColdStart();
      if (restored) {
        await ChurchAutoSessionService.markAutoPainelAfterOAuthRestore();
      }
    } catch (_) {}
  }
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await ChurchChatAlertNotificationService.instance
          .registerFcmChatAndroidChannelsForBoot();
    } catch (_) {}
  }
  ensureBrasiliaTimeZoneInitialized();
  await YahwehObservability.ensureInitialized();
  // Crashlytics: só Android/iOS (evita desktop/web onde o plugin não aplica).
  final crashlyticsOk = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (crashlyticsOk) {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = (FlutterErrorDetails details) {
      // [recordFlutterError] pode falhar em cenários raros (ex.: informação do framework);
      // garantimos que o erro original ainda chega ao Crashlytics.
      Future<void> fallbackChain(Object e, StackTrace st) async {
        try {
          await FirebaseCrashlytics.instance.recordError(
            Exception(
              '${details.exceptionAsString()} | crashlytics_report: $e',
            ),
            details.stack ?? st,
            fatal: !_crashlyticsFlutterErrorLikelyBenignNetwork(details),
          );
        } catch (_) {}
      }

      try {
        if (_crashlyticsFlutterErrorLikelyBenignNetwork(details)) {
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
      try {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
  // Garante que a sessão não “some” quando o usuário fechar/renovar a aba no web
  // ou ao reabrir pelo ícone (fica até o usuário clicar em Sair).
  try {
    await firebaseDefaultAuth.setPersistence(Persistence.LOCAL);
  } catch (_) {}
  if (kIsWeb) {
    try {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    } catch (_) {}
  }
  configureFirestoreForOfflineAndSpeed();
  // Apple Guideline 3.1.1: em iOS, le `exibir_pagamento_ios` do Remote Config
  // antes de qualquer rota que possa exibir checkout/precos. Nao bloqueante:
  // mantem default conservador (sem cobranca no app) se o fetch falhar.
  try {
    await IosPaymentsGate.initialize();
  } catch (_) {}
  try {
    await AppConnectivityService.instance.start();
    AppFinalizeBootstrap.bindOnColdStart();
  } catch (_) {}
  String initialRoute =
      kIsWeb && Uri.base.path.isNotEmpty ? Uri.base.path : '/';
  if (kIsWeb && initialRoute != '/') {
    if (!initialRoute.startsWith('/')) initialRoute = '/$initialRoute';
    if (initialRoute.length > 1 && initialRoute.endsWith('/')) {
      initialRoute = initialRoute.replaceFirst(RegExp(r'/$'), '');
    }
  }
  // Hosting SPA: alguns proxies/CDNs expõem /index.html — tratar como raiz (site de divulgação).
  if (kIsWeb) {
    final p = initialRoute.toLowerCase();
    if (p == '/index.html' || p.endsWith('/index.html')) {
      initialRoute = '/';
    }
  }
  if (kIsWeb && (initialRoute == '/' || initialRoute.isEmpty)) {
    final subdomainSlug = _extractChurchSlugFromHost(Uri.base.host);
    if (subdomainSlug != null && subdomainSlug.isNotEmpty) {
      initialRoute = '/igreja/$subdomainSlug';
    }
  }
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
  // Web: não chamar checkAndReloadIfNewVersion para evitar reload automático e tela piscando.
  // Ao abrir pelo ícone: restaura última rota para abrir onde parou (evita tela preta/branca)
  if (true) {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Se o usuário já iniciou direto no painel, sempre atualizamos o last_route.
      // (Ajuda em PWA instalada quando o observer não registra o route inicial.)
      if (initialRoute == '/painel' ||
          initialRoute == '/admin' ||
          initialRoute.startsWith('/painel') ||
          initialRoute.startsWith('/admin')) {
        await prefs.setString('last_route', initialRoute);
      }
      final last = prefs.getString('last_route');
      if (last != null && last.isNotEmpty) {
        // Raiz `/` = site de divulgação: não sobrescrever com last_route (ex.: /painel).
        final isPublicRoot =
            kIsWeb && (initialRoute == '/' || initialRoute.isEmpty);
        if (!isPublicRoot) {
          // PWA/ícone costuma abrir em `/`; aí restauramos painel onde parou.
          final keepCurrent = kIsWeb && initialRoute != '/' && initialRoute != '';
          final isPublicSignupDeep =
              PublicWebRouteParser.isPublicSignupDeepRoute(initialRoute);
          if (!keepCurrent && !isPublicSignupDeep) {
            // Web/PWA: restaurar última rota. App nativo: só se já houver sessão —
            // senão /painel abre AuthGate com user==null e fica preso no loading.
            if (kIsWeb) {
              initialRoute = last;
            } else if (FirebaseAuth.instance.currentUser != null) {
              initialRoute = last;
            } else {
              initialRoute = '/login';
            }
          }
        }
      } else if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        // Android/iOS: sem rota salva — com sessão Firebase persistida abre direto o painel.
        final cu = FirebaseAuth.instance.currentUser;
        initialRoute = (cu != null && !cu.isAnonymous)
            ? '/painel'
            : (defaultTargetPlatform == TargetPlatform.iOS
                ? '/igreja/login'
                : '/login');
      }
      final autoPainel =
          await ChurchAutoSessionService.painelRouteIfSessionRestored(
        initialRoute,
      );
      if (autoPainel != null) {
        initialRoute = autoPainel;
      }
    } catch (_) {}
    // Fallback se SharedPreferences falhar no app móvel.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (initialRoute == '/' || initialRoute.isEmpty)) {
      final cu = FirebaseAuth.instance.currentUser;
      initialRoute = (cu != null && !cu.isAnonymous)
          ? '/painel'
          : (defaultTargetPlatform == TargetPlatform.iOS
              ? '/igreja/login'
              : '/login');
    }
    final autoPainelFallback =
        await ChurchAutoSessionService.painelRouteIfSessionRestored(
      initialRoute,
    );
    if (autoPainelFallback != null) {
      initialRoute = autoPainelFallback;
    }
    if (AppStartupRoute.isNativeMobile) {
      initialRoute = await AppStartupRoute.finalizeNativeRoute(initialRoute);
      if (await AuthSessionService.hasSession() &&
          (initialRoute == '/painel' || initialRoute.startsWith('/painel/'))) {
        unawaited(AppStartupPreheat.preheatForDashboard());
      }
    }
  }
  await initializeDateFormatting('pt_BR', null);
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
      unregisterWebResumeRepaint();
    }
    _themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(AppFinalizeBootstrap.onAppResume());
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
          home: _StartupSplashGate(targetRoute: widget.initialRoute),
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
            return Container(
              color: bg,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: c,
                  ),
                  ValueListenableBuilder<GlobalUploadProgressState?>(
                    valueListenable: GlobalUploadProgress.instance.state,
                    builder: (context, state, _) {
                      if (state == null) return const SizedBox.shrink();
                      return Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Material(
                            elevation: 4,
                            color: Theme.of(context).colorScheme.surface,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LinearProgressIndicator(
                                  value: state.progress >= 1
                                      ? null
                                      : state.progress,
                                  minHeight: 3,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  child: Text(
                                    state.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
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

class _StartupSplashGate extends StatefulWidget {
  final String targetRoute;
  const _StartupSplashGate({required this.targetRoute});

  @override
  State<_StartupSplashGate> createState() => _StartupSplashGateState();
}

class _StartupSplashGateState extends State<_StartupSplashGate> {

  @override
  void initState() {
    super.initState();
    final route = widget.targetRoute.trim().isEmpty ? '/' : widget.targetRoute;
    if (route != '/') {
      unawaited(_goNext());
    }
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    var route = widget.targetRoute.trim().isEmpty ? '/' : widget.targetRoute;

    if (AppStartupRoute.isNativeMobile) {
      route = await AppStartupRoute.finalizeNativeRoute(route);
      if (route == '/painel' || route.startsWith('/painel/')) {
        if (!await AuthSessionService.hasSession()) {
          route = AppStartupRoute.nativeLoginRoute;
        } else {
          await AppStartupPreheat.preheatForDashboard();
        }
      }
    }

    void navigateOffSplash() {
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      final r = route.trim();
      // Raiz do site de divulgação: rota explícita evita falha silenciosa de
      // pushReplacementNamed no Flutter Web com MaterialApp(home: splash).
      if (r.isEmpty || r == '/') {
        nav.pushReplacement(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/'),
            builder: (_) => const SitePublicPage(),
          ),
        );
        return;
      }
      nav.pushReplacementNamed(route);
    }

    // Dois frames: Navigator do MaterialApp às vezes ainda não aceita replace no primeiro tick (web).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigateOffSplash());
    });
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
