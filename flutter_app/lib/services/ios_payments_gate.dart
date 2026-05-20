import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// Controla se o app pode exibir UI de cobranca direta (Mercado Pago / cartao / PIX)
/// em iOS, conforme Guideline 3.1.1 da App Store (compras digitais devem usar IAP
/// ou o app precisa se comportar como "Reader/SaaS" — sem botoes de compra).
///
/// Em Android, Web e Desktop o gate fica sempre aberto.
/// Em iOS, leitura do Firebase Remote Config:
///   chave: `exibir_pagamento_ios`
///   default: `false` (= comportar-se como Reader/SaaS — sem checkout no app)
///
/// Quando o gate esta `closed`:
///   - `RenewPlanPage` exibe `IosPaymentUnavailableView` (sem precos / sem checkout).
///   - Banners e botoes "Adquirir Plano" / "Ver planos" sao escondidos.
///   - Dialogos de limite usam mensagem neutra ("Limite atingido. Contate o
///     administrador.") sem direcionar para checkout.
///
/// Para liberar pagamentos em iOS sem republicar o IPA: alterar a chave
/// `exibir_pagamento_ios` para `true` no console do Firebase Remote Config.
class IosPaymentsGate {
  IosPaymentsGate._();

  static const String remoteConfigKey = 'exibir_pagamento_ios';

  /// Default conservador: nao exibe pagamento em iOS ate o Remote Config ser
  /// lido. Garante que a primeira sessao apos o app abrir no iOS ja respeite
  /// a regra (zero risco de mostrar checkout durante revisao da Apple).
  static const bool _defaultIosShowPayments = false;

  static bool _initialized = false;
  static bool _flagShowPayments = _defaultIosShowPayments;

  /// Apple Guideline 3.1.1: cadastro de nova igreja/organizacao so na web.
  /// No app iOS nativo permanece apenas login; gestor altera plano no Safari.
  static bool get hideOrganizationSignup => isIosNative;

  /// Rotas de onboarding de organizacao (gestor) bloqueadas no iOS nativo.
  static bool isOrganizationSignupPath(String path, List<String> pathSegments) {
    if (!hideOrganizationSignup) return false;
    final low = path.toLowerCase();
    if (low == '/signup' || low.startsWith('/signup/')) return true;
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

  /// `true` se o app pode exibir UI de checkout / cobranca / planos com preco.
  /// Sempre `true` fora do iOS. Em iOS depende do Remote Config.
  static bool get paymentsAllowed {
    if (!isIosNative) return true;
    return _flagShowPayments;
  }

  /// Atalho semantico: esta em iOS com a flag desligada (modo Reader/SaaS).
  static bool get shouldHidePayments => !paymentsAllowed;

  /// Inicializa Remote Config com defaults e busca a flag.
  /// Nunca propaga excecao — em qualquer falha mantem o default conservador
  /// ([_defaultIosShowPayments] = false em iOS).
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!isIosNative) {
      return;
    }

    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: const Duration(hours: 6),
        ),
      );
      await rc.setDefaults(const <String, dynamic>{
        remoteConfigKey: _defaultIosShowPayments,
      });
      try {
        await rc
            .fetchAndActivate()
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        // segue com defaults
      }
      try {
        _flagShowPayments = rc.getBool(remoteConfigKey);
      } catch (_) {
        _flagShowPayments = _defaultIosShowPayments;
      }
    } catch (_) {
      _flagShowPayments = _defaultIosShowPayments;
    }
  }

  /// URL do site: login da igreja em `/igreja/login/apple` (sem `after` vai a
  /// `/atualizar-plano` no site) e, após autenticar, fluxo de planos/checkout.
  ///
  /// O Safari abre o mesmo ecrã de credenciais (Google / Apple / e-mail),
  /// com `igrejaId` nas claims antes do checkout embebido.
  static Uri churchWebLoginThenAtualizarPlanoUri({
    String utmMedium = 'manage_subscription',
    String? email,
  }) {
    final base = AppConstants.publicWebBaseUrl.trim();
    final root =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$root/igreja/login/apple').replace(
      queryParameters: <String, String>{
        'after': '/atualizar-plano?from=ios_app',
        'from': 'ios_app',
        'utm_source': 'app_ios',
        'utm_medium': utmMedium,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      },
    );
  }

  /// Em iOS Reader/SaaS: abre o site no **login da igreja**; depois do login
  /// segue para alteração de plano (PIX/cartão na própria página web).
  /// Inclui e-mail atual (quando disponível) para pré-preencher o login.
  static Future<bool> openUpgradePlansExternally({
    String source = 'ios_app',
  }) async {
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
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
