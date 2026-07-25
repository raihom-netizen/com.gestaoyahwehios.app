import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Preferir variante medium do optimizeImage (share rápido; evita full 1920).
String preferShareFriendlyPhotoUrl(String raw) {
  final s = sanitizeImageUrl(raw);
  if (s.isEmpty) return s;
  final swapped = s
      .replaceAll('_full_1920.webp', '_medium_800.webp')
      .replaceAll('_full_1920.jpg', '_medium_800.webp')
      .replaceAll('/full_1920.', '/medium_800.')
      .replaceAll('_full.webp', '_medium_800.webp');
  return sanitizeImageUrl(swapped);
}

/// Teto de bytes por foto no share (500 KB — partilha mais rápida).
const int kNoticiaSharePhotoMaxBytes = 500 * 1024;
