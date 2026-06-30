import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';

/// Variante do ecrã neutro iOS (Apple Guideline 3.1.1 — Reader / SaaS).
enum IosLicenseBlockedVariant {
  /// Licença vencida — bloqueio total do painel.
  expired,

  /// Utilizador tentou aceder a planos/pagamento (não disponível no app iOS).
  planManagement,
}

/// Ecrã **sem** checkout, **sem** preços e **sem** links externos de vendas.
class IosLicenseReaderBlockedView extends StatelessWidget {
  final IosLicenseBlockedVariant variant;
  final String? churchName;
  final String? logoUrl;
  final VoidCallback? onLogout;
  final bool showBackButton;

  const IosLicenseReaderBlockedView({
    super.key,
    this.variant = IosLicenseBlockedVariant.planManagement,
    this.churchName,
    this.logoUrl,
    this.onLogout,
    this.showBackButton = true,
  });

  String get _title {
    switch (variant) {
      case IosLicenseBlockedVariant.expired:
        return 'Licença expirada';
      case IosLicenseBlockedVariant.planManagement:
        return 'Gestão de plano';
    }
  }

  String get _body {
    switch (variant) {
      case IosLicenseBlockedVariant.expired:
        final name = (churchName ?? '').trim();
        if (name.isNotEmpty) {
          return '$name está com o acesso bloqueado.\n\n'
              'Sua licença expirou. Entre em contato com o administrador do '
              'sistema ou acesse o painel web para regularizar.';
        }
        return 'Sua licença expirou. Entre em contato com o administrador do '
            'sistema ou acesse o painel web para regularizar.';
      case IosLicenseBlockedVariant.planManagement:
        return 'A contratação e a renovação de planos são feitas fora deste '
            'aplicativo.\n\n'
            'Entre em contato com o administrador da sua igreja ou acesse o '
            'painel web pelo computador para regularizar a licença.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return YahwehSaasLicenseStatePage(
      title: _title,
      churchName: churchName,
      logoUrl: logoUrl,
      message: _body,
      showBackButton: showBackButton,
      icon: variant == IosLicenseBlockedVariant.expired
          ? Icons.phonelink_lock_rounded
          : Icons.info_outline_rounded,
      accent: ThemeCleanPremium.primary,
      secondaryLabel: onLogout != null ? 'Sair da conta' : null,
      onSecondary: onLogout,
    );
  }
}
