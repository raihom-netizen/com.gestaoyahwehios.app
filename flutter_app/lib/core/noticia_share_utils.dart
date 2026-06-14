import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/services/noticia_share_prefetch_service.dart';
import 'package:gestao_yahweh/core/noticia_share_links.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaPhotoUrls,
        eventNoticiaThumbStoragePath,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        firebaseStorageBytesFromDownloadUrl,
        firebaseStorageMediaUrlLooksLike,
        imageUrlFromMap,
        imageUrlsListFromMap,
        isDataImageUrl,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;

/// Extensão/MIME coerentes com os bytes (evita anexar PNG como `*.jpg` no share / galeria).
({String mime, String filename}) noticiaShareImageDescriptorFromBytes(
    Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return (mime: 'image/png', filename: 'publicacao.png');
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return (mime: 'image/gif', filename: 'publicacao.gif');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return (mime: 'image/jpeg', filename: 'publicacao.jpg');
  }
  return (mime: 'image/jpeg', filename: 'publicacao.jpg');
}

/// Baixa a mesma capa usada na partilha nativa (até ~4 MB).
Future<Uint8List?> fetchNoticiaCoverImageBytes(Map<String, dynamic> post) async {
  final imgHttps = await resolveNoticiaSharePreviewImageUrl(post);
  if (imgHttps == null || !isValidImageUrl(imgHttps)) return null;
  final u = sanitizeImageUrl(imgHttps);
  Uint8List? bytes;
  try {
    if (isFirebaseStorageHttpUrl(u)) {
      bytes = await firebaseStorageBytesFromDownloadUrl(u,
          maxBytes: 4 * 1024 * 1024);
    }
    if (bytes == null) {
      final response = await http
          .get(
            Uri.parse(u),
            headers: const {'Accept': 'image/*'},
          )
          .timeout(const Duration(seconds: 22));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        bytes = response.bodyBytes;
      }
    }
  } catch (_) {
    return null;
  }
  if (bytes == null || bytes.length <= 32) return null;
  return bytes;
}

/// Dias da semana (Dart: weekday 1 = segunda … 7 = domingo) — formato longo na mensagem premium.
String buildNoticiaInviteShareMessage({
  required String churchName,
  required String noticiaKind,
  required String title,
  required String bodyText,
  DateTime? startAt,
  String? location,
  double? locationLat,
  double? locationLng,
  String? publicSiteUrl,
  String? inviteCardUrl,
  String? tenantId,
  String? noticiaId,
  String? churchSlug,
  Map<String, dynamic>? churchData,
}) {
  final cn = churchName.trim().isNotEmpty ? churchName.trim() : 'Nossa igreja';
  final defaultTitle = noticiaKind == 'evento' ? 'Evento' : 'Aviso';
  final t = title.trim().isEmpty ? defaultTitle : title.trim();
  final cleanText = bodyText.trim();

  NoticiaShareLinks? links;
  if ((tenantId ?? '').trim().isNotEmpty && (noticiaId ?? '').trim().isNotEmpty) {
    links = resolveNoticiaShareLinks(
      tenantId: tenantId!.trim(),
      noticiaId: noticiaId!.trim(),
      churchSlug: churchSlug,
      churchData: churchData,
    );
  }

  final site = (publicSiteUrl ?? links?.publicSiteUrl ?? '').trim();
  final eventUrl = (inviteCardUrl ?? links?.eventPageUrl ?? '').trim();

  final buf = StringBuffer();
  final kindEmoji = noticiaKind == 'evento' ? '🎉' : '📢';
  buf.writeln('$kindEmoji *${cn.toUpperCase()}*');
  buf.writeln('━━━━━━━━━━━━━━━━━━');
  buf.writeln();

  if (startAt != null) {
    final d = startAt;
    final wd = _kWeekdayPtLong[d.weekday - 1];
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year;
    final hm =
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    buf.writeln('🗓 *$wd*');
    buf.writeln('⏰ *$dd/$mm/$yyyy · $hm*');
    buf.writeln('🎯 *${t.toUpperCase()}*');
  } else {
    buf.writeln('📌 *$t*');
  }

  if (cleanText.isNotEmpty) {
    buf.writeln();
    buf.writeln('💬 $cleanText');
  }

  final locBlock = _formatShareLocationBlock(
    location: location,
    lat: locationLat,
    lng: locationLng,
  );
  if (locBlock.isNotEmpty) {
    buf.writeln();
    buf.writeln(locBlock);
  }

  if (site.isNotEmpty || eventUrl.isNotEmpty) {
    buf.writeln();
    buf.writeln('━━━━━━━━━━━━━━━━━━');
  }

  if (site.isNotEmpty) {
    buf.writeln('🌐 *Site da igreja*');
    buf.writeln('🔗 $site');
  }

  if (eventUrl.isNotEmpty) {
    buf.writeln();
    final cta = noticiaKind == 'evento'
        ? '🎟 *Ver evento completo* — fotos e vídeos'
        : '📢 *Ver aviso completo* — fotos e detalhes';
    buf.writeln(cta);
    buf.writeln('🔗 $eventUrl');
  }

  buf.writeln();
  buf.writeln('✨ _Gestão YAHWEH_');

  return buf.toString().trimRight();
}

const _kWeekdayPtLong = <String>[
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
  'Domingo',
];

String _formatShareLocationBlock({
  String? location,
  double? lat,
  double? lng,
}) {
  final mapsUrl = AppConstants.mapsShortUrl(
    lat: lat,
    lng: lng,
    address: (lat != null && lng != null) ? null : location,
  );
  if (mapsUrl.isEmpty) return '';

  final label = _shortLocationLabel(location, lat, lng);
  return '📍 *$label*\n🗺 _Abrir no mapa:_\n$mapsUrl';
}

String _shortLocationLabel(String? location, double? lat, double? lng) {
  final loc = location?.trim() ?? '';
  if (loc.isNotEmpty) {
    var s = loc.replaceAll(RegExp(r'\s+'), ' ');
    if (s.contains(',')) {
      final parts = s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        final city = parts[parts.length - 2];
        final uf = parts.last.replaceAll(RegExp(r'\d.*'), '').trim();
        if (city.isNotEmpty && uf.isNotEmpty && uf.length <= 3) {
          return '$city · $uf';
        }
        return '${parts[parts.length - 2]}, ${parts.last}';
      }
    }
    if (s.length > 56) s = '${s.substring(0, 53)}…';
    return s;
  }
  if (lat != null && lng != null) return 'Abrir no mapa';
  return 'Local do evento';
}

/// Item de mídia pronto para partilha nativa (WhatsApp, Telegram…).
class NoticiaShareMediaFile {
  const NoticiaShareMediaFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// Capa + galeria (até 5 fotos) + 1 vídeo hospedado — para anexar na partilha.
Future<List<NoticiaShareMediaFile>> fetchNoticiaShareMediaBundle(
  Map<String, dynamic> data, {
  int maxPhotos = 5,
  String? tenantId,
  String? postId,
  String? collection,
}) async {
  final out = <NoticiaShareMediaFile>[];
  final tid = (tenantId ?? data['tenantId'] ?? data['churchId'] ?? '').toString().trim();
  final pid = (postId ?? data['id'] ?? data['postId'] ?? data['docId'] ?? '').toString().trim();
  final colRaw = (collection ?? data['collection'] ?? data['type'] ?? 'eventos').toString();
  final col = colRaw == 'avisos' ? 'avisos' : 'eventos';

  final httpUrls = <String>[
    ...NoticiaSharePrefetchService.httpPhotoUrlsFromPost(data),
  ];

  if (httpUrls.length < maxPhotos && tid.isNotEmpty && pid.isNotEmpty) {
    final pack = await NoticiaSharePrefetchService.fetch(
      tenantId: tid,
      postId: pid,
      collection: col,
      postDataHint: data,
    );
    if (pack != null) {
      for (final u in pack.photoUrls) {
        if (!httpUrls.contains(u)) httpUrls.add(u);
      }
    }
  }

  if (httpUrls.isEmpty) {
    httpUrls.addAll(noticiaGalleryRefsForShare(data));
  }

  final photoJobs = <Future<NoticiaShareMediaFile?>>[];

  Future<NoticiaShareMediaFile?> downloadPhoto(String ref, int index) async {
    try {
      final u = sanitizeImageUrl(ref);
      if (!isValidImageUrl(u)) return null;
      Uint8List? bytes;
      if (isFirebaseStorageHttpUrl(u)) {
        bytes = await firebaseStorageBytesFromDownloadUrl(
          u,
          maxBytes: 4 * 1024 * 1024,
        ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      }
      bytes ??= await http
          .get(Uri.parse(u), headers: const {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 8))
          .then((r) => r.statusCode == 200 && r.bodyBytes.isNotEmpty
              ? r.bodyBytes
              : null);
      if (bytes == null || bytes.length <= 32) return null;
      final desc = noticiaShareImageDescriptorFromBytes(bytes);
      return NoticiaShareMediaFile(
        bytes: bytes,
        fileName: index == 0
            ? desc.filename
            : 'foto_${index + 1}.${desc.filename.split('.').last}',
        mimeType: desc.mime,
      );
    } catch (_) {
      return null;
    }
  }

  for (var i = 0; i < httpUrls.length && i < maxPhotos; i++) {
    photoJobs.add(downloadPhoto(httpUrls[i], i));
  }

  if (photoJobs.isNotEmpty) {
    final results = await Future.wait(photoJobs);
    for (final f in results) {
      if (f != null) out.add(f);
    }
  }

  if (out.isEmpty) {
    final cover = await fetchNoticiaCoverImageBytes(data);
    if (cover != null && cover.length > 32) {
      final desc = noticiaShareImageDescriptorFromBytes(cover);
      out.add(NoticiaShareMediaFile(
        bytes: cover,
        fileName: desc.filename,
        mimeType: desc.mime,
      ));
    }
  }

  try {
    var videoUrl = await resolveNoticiaHostedVideoShareUrl(data);
    if ((videoUrl == null || videoUrl.isEmpty) &&
        tid.isNotEmpty &&
        pid.isNotEmpty) {
      final pack = NoticiaSharePrefetchService.peek(
        tenantId: tid,
        collection: col,
        postId: pid,
      );
      videoUrl = pack?.hostedVideoUrl;
    }
    if (videoUrl != null && videoUrl.isNotEmpty) {
      final vBytes = await firebaseStorageBytesFromDownloadUrl(
        videoUrl,
        maxBytes: 16 * 1024 * 1024,
      ).timeout(const Duration(seconds: 18), onTimeout: () => null);
      if (vBytes != null && vBytes.length > 512) {
        out.add(NoticiaShareMediaFile(
          bytes: vBytes,
          fileName: 'video_evento.mp4',
          mimeType: 'video/mp4',
        ));
      }
    }
  } catch (_) {}

  return out;
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

/// URLs/paths utilizáveis como fotos no feed e na partilha (mesma lógica do cartão público).
List<String> noticiaGalleryRefsForShare(Map<String, dynamic> p) {
  final seen = <String>{};
  final out = <String>[];
  void add(String? raw) {
    final s = sanitizeImageUrl(raw ?? '');
    if (s.isEmpty || looksLikeHostedVideoFileUrl(s)) return;
    final low = s.toLowerCase();
    if (low.contains('youtube.com') ||
        low.contains('youtu.be') ||
        low.contains('vimeo.com')) {
      return;
    }
    final ok = isValidImageUrl(s) ||
        isDataImageUrl(s) ||
        low.startsWith('gs://') ||
        firebaseStorageMediaUrlLooksLike(s);
    if (!ok) return;
    if (seen.add(s)) out.add(s);
  }

  for (final u in eventNoticiaPhotoUrls(p)) {
    add(u);
  }
  for (final u in imageUrlsListFromMap(p)) {
    add(u);
  }
  if (out.isEmpty) {
    add(imageUrlFromMap(p));
  }
  return dedupeImageRefsByStorageIdentity(out);
}
