import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/widgets/ios_license_reader_blocked_view.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionExpiredPage extends StatelessWidget {
  final String churchName;
  final String? logoUrl;
  final VoidCallback onRenew;
  final VoidCallback onLogout;
  final bool canPurchaseLicense;

  const SubscriptionExpiredPage({
    super.key,
    required this.churchName,
    required this.onRenew,
    required this.onLogout,
    this.logoUrl,
    this.canPurchaseLicense = true,
  });

  Future<void> _openSupportWhatsApp() async {
    final phone =
        AppConstants.masterSupportWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) return;
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent('Olá, preciso de suporte para renovar a assinatura do sistema.')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (IosPaymentsGate.hideInAppPlanPurchaseUi) {
      return IosLicenseReaderBlockedView(
        variant: IosLicenseBlockedVariant.expired,
        churchName: churchName,
        logoUrl: logoUrl,
        onLogout: onLogout,
        showBackButton: false,
      );
    }

    final contactLine =
        '\n\nDúvidas? Fale com ${AppConstants.masterSupportName} — '
        '${AppConstants.masterSupportPhoneLabel} no WhatsApp.';
    final blockedMsg = (canPurchaseLicense
            ? '$churchName está com acesso bloqueado após o período de carência.\n\n'
                'Renove a licença (PIX ou cartão, mensal ou anual) para liberar o '
                'painel, módulos e notificações. A licença é ativada automaticamente '
                'assim que o pagamento é confirmado.'
            : '$churchName está com acesso bloqueado.\n\n'
                'Somente pastor, gestor, administrador, secretário ou tesoureiro '
                'pode gerar o pagamento da licença. Peça a um deles para concluir '
                'a renovação.') +
        contactLine;

    return YahwehSaasLicenseStatePage(
      title: 'Assinatura suspensa',
      churchName: churchName,
      logoUrl: logoUrl,
      message: blockedMsg,
      icon: Icons.lock_clock_rounded,
      primaryLabel:
          canPurchaseLicense ? 'Alterar plano / Pagar agora' : null,
      onPrimary: canPurchaseLicense ? onRenew : null,
      secondaryLabel: AppConstants.masterSupportWhatsApp.trim().isNotEmpty
          ? 'WhatsApp — ${AppConstants.masterSupportName}'
          : null,
      onSecondary: AppConstants.masterSupportWhatsApp.trim().isNotEmpty
          ? _openSupportWhatsApp
          : null,
      tertiaryLabel: 'Sair da conta',
      onTertiary: onLogout,
    );
  }
}
