import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Quebra de cache para mídia única (foto perfil, logo) — mesma path Storage, binário novo.
///
/// Adiciona `v=cb{revisionMs}` à query da URL https para Web/Android/iOS recarregarem
/// após sobrescrita de `foto_perfil.jpg` ou `logo_igreja.png`.
abstract final class YahwehMediaCacheBust {
  YahwehMediaCacheBust._();

  static int freshRevisionMs() => DateTime.now().millisecondsSinceEpoch;

  static String apply(String url, int revisionMs) {
    final u = sanitizeImageUrl(url);
    if (u.isEmpty || revisionMs <= 0) return u;
    if (!isValidImageUrl(u)) return u;
    final uri = Uri.tryParse(u);
    if (uri == null) return u;
    final q = Map<String, String>.from(uri.queryParameters);
    q['v'] = 'cb$revisionMs';
    return uri.replace(queryParameters: q).toString();
  }

  /// Firestore: `fotoUrlCacheRevision` / `logoCacheRevision`.
  static String applyFromDocRevision(String url, Map<String, dynamic>? data) {
    if (data == null) return sanitizeImageUrl(url);
    final rev = _revisionFromData(data);
    if (rev == null || rev <= 0) return sanitizeImageUrl(url);
    return apply(url, rev);
  }

  static int? _revisionFromData(Map<String, dynamic> data) {
    for (final k in ['fotoUrlCacheRevision', 'logoCacheRevision']) {
      final r = data[k];
      if (r is int) return r;
      if (r is num) return r.toInt();
    }
    return null;
  }
}
