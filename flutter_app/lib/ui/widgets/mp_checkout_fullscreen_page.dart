import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/mp_checkout_embed.dart';

/// Checkout Pro em tela quase cheia (root navigator), com área segura para o WebView/iframe.
/// Evita o corte do rodapé do MP em bottom sheet empilhado ou com altura ~90%.
Future<void> showMercadoPagoCheckoutFullscreen(
  BuildContext context, {
  required String checkoutUrl,
  required String returnUrlHint,
  String? footerHint,
  required Color primaryColor,
  String title = 'Checkout Mercado Pago',
  String subtitle = 'Cartão ou PIX no mesmo painel — rápido e seguro',
  required Future<void> Function(String url) onPaymentReturn,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      barrierDismissible: false,
      pageBuilder: (ctx, _, __) => _MpCheckoutFullscreenScaffold(
        checkoutUrl: checkoutUrl,
        returnUrlHint: returnUrlHint,
        footerHint: footerHint,
        primaryColor: primaryColor,
        title: title,
        subtitle: subtitle,
        onPaymentReturn: onPaymentReturn,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _MpCheckoutFullscreenScaffold extends StatelessWidget {
  final String checkoutUrl;
  final String returnUrlHint;
  final String? footerHint;
  final Color primaryColor;
  final String title;
  final String subtitle;
  final Future<void> Function(String url) onPaymentReturn;

  const _MpCheckoutFullscreenScaffold({
    required this.checkoutUrl,
    required this.returnUrlHint,
    required this.footerHint,
    required this.primaryColor,
    required this.title,
    required this.subtitle,
    required this.onPaymentReturn,
  });

  @override
  Widget build(BuildContext context) {
    final deep = Color.lerp(primaryColor, const Color(0xFF0F172A), 0.35)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, deep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: MpCheckoutEmbed(
                    key: ValueKey<String>(checkoutUrl),
                    checkoutUrl: checkoutUrl,
                    returnUrlHint: returnUrlHint,
                    footerHint: footerHint,
                    onLikelyFinished: (u) async {
                      if (context.mounted) Navigator.of(context).pop();
                      await onPaymentReturn(u);
                    },
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
