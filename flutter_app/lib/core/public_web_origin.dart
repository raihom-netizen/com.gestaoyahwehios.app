import 'package:flutter/foundation.dart' show kIsWeb;

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
}
