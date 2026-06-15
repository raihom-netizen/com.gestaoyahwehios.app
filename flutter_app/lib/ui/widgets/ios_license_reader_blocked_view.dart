import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Variante do ecrã neutro iOS (Apple Guideline 3.1.1 — Reader / SaaS).
enum IosLicenseBlockedVariant {
  /// Licença vencida — bloqueio total do painel.
  expired,

  /// Utilizador tentou aceder a planos/pagamento (não disponível no app iOS).
  planManagement,
}

/// Ecrã **sem** checkout, **sem** preços e **sem** links externos de vendas.
///
/// O app iOS apenas reflete o estado da licença no Firestore; cobrança só na web.
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
    final hasLogo = (logoUrl ?? '').trim().isNotEmpty;
    final canPop = showBackButton && Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: canPop
          ? AppBar(
              title: Text(_title),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEFF4FF), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(color: Colors.white.withValues(alpha: 0.08)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 30,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (variant == IosLicenseBlockedVariant.expired) ...[
                          CircleAvatar(
                            radius: 42,
                            backgroundColor: const Color(0xFFF3F4F6),
                            child: ClipOval(
                              child: SizedBox(
                                width: 76,
                                height: 76,
                                child: hasLogo
                                    ? SafeNetworkImage(
                                        imageUrl: logoUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 180,
                                        memCacheHeight: 180,
                                        errorWidget: const Icon(
                                          Icons.church_rounded,
                                          color: Color(0xFF0052CC),
                                          size: 32,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.church_rounded,
                                        color: Color(0xFF0052CC),
                                        size: 32,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
                          Container(
                            height: 56,
                            width: 56,
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.verified_user_outlined,
                              color: ThemeCleanPremium.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Icon(
                          variant == IosLicenseBlockedVariant.expired
                              ? Icons.lock_rounded
                              : Icons.info_outline_rounded,
                          color: variant == IosLicenseBlockedVariant.expired
                              ? const Color(0xFFDC2626)
                              : ThemeCleanPremium.primary,
                          size: 34,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.45,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.sync_rounded,
                                size: 20,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Quando a licença for regularizada no painel web, '
                                  'feche e abra o aplicativo ou entre novamente para '
                                  'atualizar o acesso.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade700,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onLogout != null) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: onLogout,
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Sair da conta'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ThemeCleanPremium.primary,
                                side: BorderSide(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.35),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
