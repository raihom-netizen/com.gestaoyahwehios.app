import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/app_constants.dart';

/// Domínios oficiais do Gestão YAHWEH — mesmo Firebase, mesmo hosting, mesmas regras.
///
/// [gestaoyahweh.com.br](https://gestaoyahweh.com.br) e
/// [gestaoyahweh-21e23.web.app](https://gestaoyahweh-21e23.web.app) servem o **mesmo** build
/// (`firebase.json` → `flutter_app/build/web`). O app usa o host actual na web para links
/// partilhados; marketing/canónico continua [.com.br].
abstract final class PublicWebOrigin {
  PublicWebOrigin._();

  /// Domínio público preferido (SEO, e-mail, functions).
  static const String canonicalBaseUrl = 'https://gestaoyahweh.com.br';

  /// Hosts autorizados no Firebase Auth (Console → Authentication → Authorized domains).
  static const Set<String> authorizedHosts = {
    'gestaoyahweh.com.br',
    'www.gestaoyahweh.com.br',
    'gestaoyahweh-21e23.web.app',
    'gestaoyahweh-21e23.firebaseapp.com',
    'localhost',
    '127.0.0.1',
  };

  /// Bases centrais (rotas `/igreja/...`, cadastro membro, etc.).
  static const Set<String> centralPublicBases = {
    'https://gestaoyahweh.com.br',
    'https://www.gestaoyahweh.com.br',
    'https://gestaoyahweh-21e23.web.app',
    'https://gestaoyahweh-21e23.firebaseapp.com',
  };

  /// URL base efectiva: na web usa o host actual se for oficial; senão canónico.
  static String get effectiveBaseUrl {
    if (!kIsWeb) return canonicalBaseUrl;
    return baseUrlForHost(Uri.base.host, scheme: Uri.base.scheme);
  }

  static String baseUrlForHost(String host, {String scheme = 'https'}) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return canonicalBaseUrl;
    if (!authorizedHosts.contains(h)) return canonicalBaseUrl;
    final s = scheme.trim().isEmpty ? 'https' : scheme.trim();
    final port = Uri.base.hasPort &&
            ((s == 'https' && Uri.base.port != 443) ||
                (s == 'http' && Uri.base.port != 80))
        ? ':${Uri.base.port}'
        : '';
    return '$s://$h$port';
  }

  static bool isKnownHostingHost(String? host) {
    if (host == null || host.trim().isEmpty) return false;
    return authorizedHosts.contains(host.trim().toLowerCase());
  }

  static bool get isRunningOnOfficialHost =>
      kIsWeb && isKnownHostingHost(Uri.base.host);

  static bool isCentralGestaoBase(String base) {
    final b = base.toLowerCase().replaceAll(RegExp(r'/$'), '');
    return centralPublicBases.contains(b);
  }

  /// Slug de igreja no subdomínio (`igreja.dominio.com.br`). Raiz `.com.br` → null.
  static String? churchTenantSlugFromHost(String? host) {
    final raw = (host ?? Uri.base.host).trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (raw == 'localhost' || raw.startsWith('localhost:')) return null;
    if (raw == '127.0.0.1' || raw.startsWith('127.0.0.1:')) return null;
    final withoutPort = raw.split(':').first;
    final parts = withoutPort.split('.').where((e) => e.isNotEmpty).toList();
    if (parts.length < 3) return null;

    final n = parts.length;
    if (n >= 3 && parts[n - 2] == 'web' && parts[n - 1] == 'app') {
      return null;
    }
    if (n == 3 && parts[1] == 'com' && parts[2] == 'br') {
      return null;
    }

    final sub = parts.first;
    if (sub == 'www') return null;
    if (AppConstants.reservedChurchSlugs.contains(sub)) return null;
    if (AppConstants.isMarketingBrandSlug(sub)) return null;
    if (!RegExp(r'^[a-z0-9_-]{2,}$').hasMatch(sub)) return null;
    return sub;
  }

  /// `/` no domínio central (marketing) — **não** redirecionar sessão para `/painel`.
  static bool isMarketingPublicHomeRoute(String route) {
    if (!kIsWeb) return false;
    final r = route.trim();
    if (r.isNotEmpty && r != '/') return false;
    if (!isRunningOnOfficialHost) return false;
    final host = Uri.base.host.trim().toLowerCase();
    if (host == 'localhost' || host.startsWith('127.0.0.1')) return false;
    return churchTenantSlugFromHost(host) == null;
  }
}
