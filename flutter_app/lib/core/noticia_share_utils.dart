import 'dart:async' show TimeoutException;

import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaThumbStoragePath,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageMediaUrlLooksLike,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
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

/// Resolve URL https da capa/miniatura para anexar na partilha (foto ou poster de vídeo).
Future<String?> resolveNoticiaSharePreviewImageUrl(Map<String, dynamic> p) async {
  Future<String?> fromRef(String? raw) async {
    final s = sanitizeImageUrl(raw ?? '');
    if (s.isEmpty || looksLikeHostedVideoFileUrl(s)) return null;
    if (isValidImageUrl(s)) {
      return AppStorageImageService.instance.resolveImageUrl(imageUrl: s);
    }
    final low = s.toLowerCase();
    if (low.startsWith('gs://')) {
      return AppStorageImageService.instance.resolveImageUrl(gsUrl: s);
    }
    if (firebaseStorageMediaUrlLooksLike(s)) {
      final bare = s.replaceFirst(RegExp(r'^/+'), '');
      final path = normalizeFirebaseStorageObjectPath(bare);
      return AppStorageImageService.instance.resolveImageUrl(storagePath: path);
    }
    return null;
  }

  final coverThumb = await Future.wait<String?>([
    fromRef(eventNoticiaFeedCoverHintUrl(p)),
    fromRef(eventNoticiaDisplayVideoThumbnailUrl(p)),
  ]);
  final cover = coverThumb[0];
  final thumb = coverThumb[1];
  if (cover != null && isValidImageUrl(cover)) return cover;
  if (thumb != null && isValidImageUrl(thumb)) return thumb;

  final sp = eventNoticiaPhotoStoragePathAt(p, 0) ??
      eventNoticiaImageStoragePath(p) ??
      eventNoticiaThumbStoragePath(p);
  if (sp != null && sp.isNotEmpty) {
    final url =
        await AppStorageImageService.instance.resolveImageUrl(storagePath: sp);
    if (url != null && isValidImageUrl(url)) return url;
  }
  return null;
}

/// Capa + vídeo para o bottom sheet de partilha — **em paralelo** e com limite de tempo
/// para o painel abrir rápido (link/texto sempre disponíveis; mídia é opcional).
Future<({String? previewImageUrl, String? videoPlayUrl})> resolveNoticiaShareSheetMedia(
  Map<String, dynamic> data, {
  Duration resolveTimeout = const Duration(seconds: 10),
}) async {
  try {
    final r = await Future.wait<String?>([
      resolveNoticiaSharePreviewImageUrl(data),
      resolveNoticiaHostedVideoShareUrl(data),
    ]).timeout(resolveTimeout);
    return (previewImageUrl: r[0], videoPlayUrl: r[1]);
  } on TimeoutException {
    return (previewImageUrl: null, videoPlayUrl: null);
  }
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
