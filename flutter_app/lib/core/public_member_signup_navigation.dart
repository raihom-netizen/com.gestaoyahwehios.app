import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/public_web_route_parser.dart';
import 'package:gestao_yahweh/ui/pages/public_member_signup_page.dart';

/// Rotas e URLs do cadastro público de membros — mesmo fluxo na web, Android e iOS.
abstract final class PublicMemberSignupNavigation {
  PublicMemberSignupNavigation._();

  /// Rota in-app (Flutter) — sempre `/igreja/{slug}/cadastro-membro`.
  static String inAppRoute(String slug) {
    final s = slug.trim();
    if (s.isEmpty) return '/igreja/login';
    return '/igreja/${Uri.encodeComponent(s)}/cadastro-membro';
  }

  /// URL partilhável (WhatsApp, QR, painel) — alinhada ao hosting e ao app.
  static String publicUrl(
    String slug, {
    Map<String, dynamic>? church,
  }) =>
      AppConstants.publicChurchMemberSignupUrl(slug, church: church);

  /// No app nativo, abre cadastro público a partir da URL HTTPS; retorna false se não for rota conhecida.
  static bool tryOpenInAppFromUrl(BuildContext context, String url) {
    if (kIsWeb) return false;
    final route = PublicWebRouteParser.inAppRouteFromUrl(url);
    if (route == null || !context.mounted) return false;
    Navigator.pushNamed(context, route);
    return true;
  }

  /// Abre o formulário **dentro** do app (nunca Safari) — mesma página [PublicMemberSignupPage].
  static void open(
    BuildContext context, {
    required String slug,
    String? tenantId,
    Map<String, dynamic>? church,
  }) {
    final s = slug.trim();
    if (s.isNotEmpty) {
      Navigator.pushNamed(context, inAppRoute(s));
      return;
    }
    if (tenantId != null && tenantId.trim().isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PublicMemberSignupPage(tenantId: tenantId.trim()),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Igreja não identificada para abrir o cadastro.'),
      ),
    );
  }
}
