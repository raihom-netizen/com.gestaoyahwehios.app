import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageMediaUrlLooksLike,
        isValidImageUrl,
        sanitizeImageUrl;

/// Texto único para convite (WhatsApp, partilha nativa, cópia de link).
String buildNoticiaInviteShareMessage({
  required String churchName,
  required String noticiaKind,
  required String title,
  required String bodyText,
  DateTime? startAt,
  String? location,
  double? locationLat,
  double? locationLng,
  required String publicSiteUrl,
  required String inviteCardUrl,
}) {
  final cn = churchName.trim().isNotEmpty ? churchName.trim() : 'Nossa igreja';
  final defaultTitle = noticiaKind == 'evento' ? 'Evento' : 'Aviso';
  final t = title.trim().isEmpty ? defaultTitle : title.trim();
  String dateLine = '';
  if (startAt != null) {
    final d = startAt;
    dateLine =
        '📅 ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} às ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}\n';
  }
  final cleanText = bodyText.trim();
  final textSnippet = cleanText.isEmpty
      ? ''
      : (cleanText.length > 300
          ? '\n\n${cleanText.substring(0, 297)}…'
          : '\n\n$cleanText');
  final loc = location?.trim() ?? '';
  final locLine = loc.isNotEmpty ? '📍 $loc\n' : '';
  final mapsUrl = AppConstants.mapsShortUrl(
    lat: locationLat,
    lng: locationLng,
    address: loc.isNotEmpty ? loc : null,
  );
  final mapLine = mapsUrl.isNotEmpty ? '\n🗺️ $mapsUrl\n' : '';
  return '✨ *Convite* — $cn\n\n'
      '📌 *$t*\n'
      '$dateLine'
      '$locLine'
      '$textSnippet\n\n'
      '🔗 $publicSiteUrl\n'
      '$mapLine'
      '👉 $inviteCardUrl\n\n'
      '— _Gestão YAHWEH_';
}

/// Primeiro vídeo hospedado (MP4/Storage) com URL https — partilha nativa.
Future<String?> resolveNoticiaHostedVideoShareUrl(Map<String, dynamic> d) async {
  for (final m in eventNoticiaVideosFromDoc(d)) {
    var raw = sanitizeImageUrl((m['videoUrl'] ?? '').toString());
    if (raw.isEmpty) continue;
    final low = raw.toLowerCase();
    if (low.contains('youtube.com') ||
        low.contains('youtu.be') ||
        low.contains('vimeo.com')) {
      continue;
    }
    if (!isValidImageUrl(raw) && firebaseStorageMediaUrlLooksLike(raw)) {
      raw = (await AppStorageImageService.instance.resolveImageUrl(
            imageUrl: raw,
          )) ??
          raw;
    }
    if (raw.isEmpty) continue;
    if (looksLikeHostedVideoFileUrl(raw) ||
        raw.contains('firebasestorage.googleapis.com') ||
        raw.contains('.firebasestorage.app')) {
      if (isValidImageUrl(raw)) return sanitizeImageUrl(raw);
    }
  }
  final h = sanitizeImageUrl(eventNoticiaHostedVideoPlayUrl(d) ?? '');
  if (h.isNotEmpty && isValidImageUrl(h) && looksLikeHostedVideoFileUrl(h)) {
    return h;
  }
  return null;
}
