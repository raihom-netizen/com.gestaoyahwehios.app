import 'package:gestao_yahweh/core/app_constants.dart';

/// Converte URLs/paths do site público em rotas in-app (web, Android, iOS).
abstract final class PublicWebRouteParser {
  PublicWebRouteParser._();

  static bool _isReservedSlug(String slug) {
    final s = slug.trim().toLowerCase();
    if (s.isEmpty) return true;
    return AppConstants.reservedChurchSlugs.contains(s) ||
        AppConstants.isMarketingBrandSlug(s);
  }

  /// Site público `/igreja/{slug}` (sem cadastro-membro / evento).
  static String? churchPublicSiteRouteFromUri(Uri uri) {
    var path = uri.path;
    if (path.isEmpty) path = '/';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.replaceFirst(RegExp(r'/$'), '');
    }
    final segments =
        path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    String? slug;
    if (segments.length >= 2 && segments[0] == 'igreja') {
      final second = segments[1].toLowerCase();
      if (second == 'login' ||
          second == 'cadastro-membro' ||
          second == 'acompanhar-cadastro' ||
          second == 'cadastro' ||
          second == 'evento') {
        return null;
      }
      slug = segments[1];
    } else if (segments.length == 1 && !_isReservedSlug(segments[0])) {
      slug = segments[0];
    }
    if (slug == null || slug.isEmpty || _isReservedSlug(slug)) return null;
    return '/igreja/${Uri.encodeComponent(slug)}';
  }

  static String? churchPublicSiteRouteFromUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t.contains('://') ? t : 'https://local$t');
    if (uri == null) return null;
    return churchPublicSiteRouteFromUri(uri);
  }

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

    final publicSite = churchPublicSiteRouteFromUri(uri);
    if (publicSite != null) return publicSite;

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
