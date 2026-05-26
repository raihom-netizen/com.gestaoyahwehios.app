import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;

/// Carregamento progressivo: thumb → medium → full (feed, perfil, site).
abstract final class ProgressiveMediaResolver {
  ProgressiveMediaResolver._();

  /// Lista / feed — menor payload primeiro.
  static String feedListUrl(Map<String, dynamic>? data) {
    if (data == null) return '';
    final hint = eventNoticiaFeedCoverHintUrl(data);
    if (hint.isNotEmpty) return sanitizeImageUrl(hint);
    return sanitizeImageUrl(imageUrlFromMap(data));
  }

  /// Detalhe / tela cheia.
  static String feedFullUrl(Map<String, dynamic>? data) {
    if (data == null) return '';
    final iv = data['imageVariants'];
    if (iv is Map) {
      for (final key in const ['full_1920', 'full', 'medium_800', 'medium']) {
        final e = iv[key];
        final raw = e is Map ? (e['url'] ?? e['downloadUrl']) : e;
        final s = sanitizeImageUrl('$raw');
        if (s.isNotEmpty) return s;
      }
    }
    return feedListUrl(data);
  }

  /// Avatar em lista.
  static String memberListUrl(Map<String, dynamic>? member) {
    final thumb = MemberProfileVariantsService.listPhotoUrl(member);
    if (thumb != null && thumb.isNotEmpty) return sanitizeImageUrl(thumb);
    return sanitizeImageUrl(imageUrlFromMap(member));
  }

  /// Perfil / carteirinha.
  static String memberProfileUrl(Map<String, dynamic>? member) {
    final med = MemberProfileVariantsService.profilePhotoUrl(member);
    if (med != null && med.isNotEmpty) return sanitizeImageUrl(med);
    return memberListUrl(member);
  }

  /// Par (lista, HD) para transição opcional na UI.
  static ({String list, String full}) feedPair(Map<String, dynamic>? data) {
    return (list: feedListUrl(data), full: feedFullUrl(data));
  }
}
