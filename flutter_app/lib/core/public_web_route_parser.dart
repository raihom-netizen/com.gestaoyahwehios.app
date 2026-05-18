/// Converte URLs/paths do site público em rotas in-app (web, Android, iOS).
abstract final class PublicWebRouteParser {
  PublicWebRouteParser._();

  static String? inAppRouteFromUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t.contains('://') ? t : 'https://local$t');
    if (uri == null) return null;
    return inAppRouteFromUri(uri);
  }

  static String? inAppRouteFromPath(String pathAndQuery) {
    final p = pathAndQuery.trim();
    if (p.isEmpty) return null;
    final uri = Uri(
      scheme: 'https',
      host: 'local',
      path: p.startsWith('/') ? p : '/$p',
    );
    return inAppRouteFromUri(uri);
  }

  static String? inAppRouteFromUri(Uri uri) {
    var path = uri.path;
    if (path.isEmpty) path = '/';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.replaceFirst(RegExp(r'/$'), '');
    }
    final segments =
        path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    String? signupSlug;
    if (segments.length >= 3 &&
        segments[0] == 'igreja' &&
        segments[2] == 'cadastro-membro') {
      signupSlug = segments[1];
    } else if (segments.length == 2 && segments[1] == 'cadastro-membro') {
      signupSlug = segments[0];
    }
    if (signupSlug != null && signupSlug.isNotEmpty) {
      return '/igreja/${Uri.encodeComponent(signupSlug)}/cadastro-membro';
    }

    if (segments.length >= 3 &&
        segments[0] == 'igreja' &&
        segments[2] == 'acompanhar-cadastro') {
      final slug = segments[1];
      final protocolo = uri.queryParameters['protocolo'] ?? '';
      final q = protocolo.isEmpty
          ? ''
          : '?protocolo=${Uri.encodeComponent(protocolo)}';
      return '/igreja/${Uri.encodeComponent(slug)}/acompanhar-cadastro$q';
    }
    if (segments.length == 2 && segments[1] == 'acompanhar-cadastro') {
      final protocolo = uri.queryParameters['protocolo'] ?? '';
      final q = protocolo.isEmpty
          ? ''
          : '?protocolo=${Uri.encodeComponent(protocolo)}';
      return '/igreja/${Uri.encodeComponent(segments[0])}/acompanhar-cadastro$q';
    }

    return null;
  }

  /// Cadastro/acompanhamento público: prioridade sobre last_route no cold start.
  static bool isPublicSignupDeepRoute(String? route) {
    if (route == null || route.isEmpty) return false;
    final low = route.toLowerCase();
    return low.contains('cadastro-membro') ||
        low.contains('acompanhar-cadastro');
  }
}
