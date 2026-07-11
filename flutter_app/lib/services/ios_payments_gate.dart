import 'dart:async';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'dart:io' show Platform;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/ios_organization_signup_web_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paridade de checkout — **Web = Android = iOS** (mesmos preços e UI de planos/doação).
///
/// No iOS nativo o Mercado Pago abre no **Safari** ([preferExternalMercadoPagoCheckout])
/// em vez de WebView embutido; preços, cards e módulo Doação são idênticos ao painel web.
class IosPaymentsGate {
  IosPaymentsGate._();

  /// Legado Remote Config — ignorado para exibição de preços (paridade fixa).
  static const String remoteConfigKey = 'exibir_pagamento_ios';

  static bool _initialized = false;

  /// Apple Guideline 3.1.1: cadastro de nova igreja/organizacao so na web.
  /// No app iOS nativo permanece apenas login; gestor altera plano no Safari.
  static bool get hideOrganizationSignup => isIosNative;

  /// Rotas de onboarding de organizacao (gestor) bloqueadas no iOS nativo.
  static bool isOrganizationSignupPath(String path, List<String> pathSegments) {
    if (!hideOrganizationSignup) return false;
    final low = path.toLowerCase();
    if (low == '/signup' || low.startsWith('/signup/')) return true;
    if (low == '/cadastro') return true;
    if (low == '/onboarding' || low.startsWith('/onboarding/')) return true;
    if (low == '/comecar') return true;
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'igreja' &&
        pathSegments[1] != 'login' &&
        pathSegments[2] == 'cadastro') {
      return true;
    }
    if (pathSegments.length == 2 && pathSegments[1].toLowerCase() == 'cadastro') {
      return true;
    }
    return false;
  }

  /// `true` quando o dispositivo eh iOS nativo (nao web / nao desktop).
  static bool get isIosNative {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Checkout externo obrigatório apenas no iOS (Apple 3.1.1 / 3.2.2).
  /// Android e Web devem abrir o checkout no próprio fluxo do app/site.
  static bool get preferExternalMercadoPagoCheckout => isIosNative;

  /// Sempre `true` — preços e checkout visíveis em Web, Android e iOS.
  static bool get paymentsAllowed => true;

  /// Legado — sempre `false` (modo Reader desativado).
  static bool get shouldHidePayments => false;

  /// Menu «Adquirir plano» e checkout interno em todas as plataformas.
  static bool get hideInAppPlanPurchaseUi => false;

  /// Warm-up Remote Config (outras flags futuras). Preços iOS não dependem do RC.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!isIosNative) return;

    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: const Duration(hours: 6),
        ),
      );
      await rc.setDefaults(const <String, dynamic>{
        remoteConfigKey: true,
      });
      try {
        await rc.fetchAndActivate().timeout(const Duration(seconds: 8));
      } on TimeoutException {
        // segue com defaults locais
      }
    } catch (_) {
      // paridade de preços não depende do RC
    }
  }

  /// Rota expressa web `/atualizar-plano` — se já houver sessão no Safari, vai
  /// direto aos planos; senão mostra Google, Apple e e-mail/senha na mesma página.
  static Uri churchAtualizarPlanoExpressUri({
    String utmMedium = 'manage_subscription',
    String? email,
  }) {
    final base = AppConstants.publicWebBaseUrl.trim();
    final root =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$root/atualizar-plano').replace(
      queryParameters: <String, String>{
        'from': 'ios_app',
        'utm_source': 'app_ios',
        'utm_medium': utmMedium,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
    );
  }

  /// Compatível com chamadas antigas — mesmo destino que [churchAtualizarPlanoExpressUri].
  static Uri churchWebLoginThenAtualizarPlanoUri({
    String utmMedium = 'manage_subscription',
    String? email,
  }) =>
      churchAtualizarPlanoExpressUri(utmMedium: utmMedium, email: email);

  /// Abre [RenewPlanPage] — mesma rota em Web, Android e iOS.
  static void navigateToUpgradePlans(BuildContext context) {
    if (!context.mounted) return;
    Navigator.of(context).push(
      ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage()),
    );
  }

  /// Abre `/atualizar-plano` no navegador externo (atalho opcional).
  static Future<bool> openUpgradePlansExternally({
    String source = 'android_app',
  }) async {
    final email = (firebaseDefaultAuth.currentUser?.email ?? '').trim();
    final uri = churchWebLoginThenAtualizarPlanoUri(
      utmMedium: source,
      email: email.isEmpty ? null : email,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Site público da igreja — dízimos/ofertas (PIX e cartão) no **navegador**.
  /// Apple Guideline 3.2.2(iv): doações beneficentes não no binário iOS.
  static Uri churchPublicDonationSafariUri({
    required String churchSlug,
    Map<String, dynamic>? churchData,
  }) {
    final base = churchData != null
        ? AppConstants.publicWebBaseUrlForChurch(churchData)
        : AppConstants.publicWebBaseUrl;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final slug = churchSlug.trim().isEmpty ? 'igreja' : churchSlug.trim();
    return Uri.parse('$root/igreja/$slug').replace(
      queryParameters: const <String, String>{
        'from': 'ios_app',
        'utm_source': 'app_ios',
        'utm_medium': 'church_donation',
      },
    );
  }

  /// Cadastro de nova igreja/organização — apenas no site (Apple 3.1.1).
  static Uri organizationSignupWebUri() {
    final base = AppConstants.publicWebBaseUrl.trim();
    final root =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$root/signup').replace(
      queryParameters: const <String, String>{
        'from': 'ios_app',
        'utm_source': 'app_ios',
        'utm_medium': 'organization_signup',
      },
    );
  }

  /// Abre o cadastro de nova igreja no Safari (fora do app iOS).
  static Future<bool> openOrganizationSignupExternally() {
    return launchUrl(
      organizationSignupWebUri(),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Navegação unificada: iOS → ecrã/link web; demais plataformas → `/signup`.
  static void navigateToOrganizationSignup(BuildContext context) {
    if (hideOrganizationSignup) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const IosOrganizationSignupWebPage(),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamed('/signup');
  }

  /// Abre o site da igreja no Safari (botão «Doação» / dízimos e ofertas).
  static Future<bool> openChurchDonationsExternally({
    required String churchSlug,
    Map<String, dynamic>? churchData,
  }) {
    final uri = churchPublicDonationSafariUri(
      churchSlug: churchSlug,
      churchData: churchData,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

