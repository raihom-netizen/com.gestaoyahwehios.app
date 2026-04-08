import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre https/http no navegador (app externo). Não depende só de [canLaunchUrl]
/// (no Android 11+ falha sem `<queries>` no manifest; mesmo assim tentamos [launchUrl]).
Future<void> openHttpsUrlInBrowser(BuildContext context, String rawUrl) async {
  var t = rawUrl.trim();
  if (t.isEmpty) return;
  var uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    uri = Uri.tryParse('https://$t');
  }
  if (uri == null || !uri.hasScheme) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Link inválido.'),
      );
    }
    return;
  }
  try {
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Não foi possível abrir o navegador. Use «Copiar link» e cole no browser.',
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao abrir link: $e'),
      );
    }
  }
}

/// Estado de erro padronizado para módulos do painel da igreja (cartão premium + retry).
class ChurchPanelErrorBody extends StatelessWidget {
  final String title;
  final Object? error;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ChurchPanelErrorBody({
    super.key,
    required this.title,
    this.error,
    this.onRetry,
    this.retryLabel = 'Tentar novamente',
  });

  @override
  Widget build(BuildContext context) {
    final detail = kDebugMode && error != null ? error.toString() : null;
    return ThemeCleanPremium.premiumErrorState(
      title: title,
      subtitle: detail ??
          'Verifique sua conexão ou tente novamente em instantes.',
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }
}

/// Indicador de carregamento centralizado (módulos do painel).
class ChurchPanelLoadingBody extends StatelessWidget {
  const ChurchPanelLoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
