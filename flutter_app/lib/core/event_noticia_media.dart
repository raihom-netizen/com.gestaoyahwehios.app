/// Mídia de eventos no Firestore (`noticias`): mesma lógica no painel e no site público.
/// Evita tratar URL de vídeo (.mp4 / pasta videos) como imagem — isso gerava "Falha ao carregar".
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        firebaseStorageMediaUrlLooksLike,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        imageUrlsFromVariantMap,
        imageUrlsListFromMap,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;

/// Prioridade de capa: foto canónica (banner/galeria) antes de variantes V4 (`medium_800`, `thumb_200`).
int _noticiaRefDisplayRank(String s) {
  final low = s.toLowerCase();
  if (low.contains('banner_evento') ||
      low.contains('galeria_') ||
      low.contains('foto_perfil') ||
      (low.contains('/noticias/') &&
          !low.contains('thumb') &&
          !low.contains('medium_800'))) {
    return 0;
  }
  if (low.contains('medium_800') ||
      low.contains('_medium.') ||
      low.contains('_medium?') ||
      low.contains('/medium/')) {
    return 2;
  }
  if (low.contains('thumb_300') ||
      low.contains('thumb_200') ||
      low.contains('thumb_') ||
      low.contains('_thumb.') ||
      low.contains('/thumbs/') ||
      low.contains('%2fthumbs%2f')) {
    return 3;
  }
  if (low.contains('thumb')) return 3;
  return 1;
}

int _noticiaRefSortKey(String s) {
  final rank = _noticiaRefDisplayRank(s);
  final low = s.toLowerCase();
  final proto = low.startsWith('https://')
      ? 0
      : low.startsWith('gs://')
          ? 4
          : low.startsWith('http://')
              ? 8
              : 12;
  return rank * 16 + proto;
}

/// Para exibição: foto principal antes de miniaturas V4; `https` canónico antes de `thumb` quebrado.
List<String> noticiaImageRefsPreferDisplayOrder(Iterable<String> refs) {
  final out = <String>[];
  final seen = <String>{};
  for (final r in refs) {
    final x = sanitizeImageUrl(r);
    if (x.isEmpty || seen.contains(x)) continue;
    seen.add(x);
    out.add(x);
  }
  out.sort((a, b) => _noticiaRefSortKey(a).compareTo(_noticiaRefSortKey(b)));
  return out;
}

/// Normaliza `&amp;` e URLs truncadas do Firebase Storage (mesmo fluxo de [sanitizeImageUrl]).
String _photoUrlFromFirestore(String? raw) {
  final withAmp = (raw ?? '').toString().replaceAll('&amp;', '&');
  return sanitizeImageUrl(withAmp);
}

bool _isYoutubeVimeo(String low) {
  return low.contains('youtube.com') ||
      low.contains('youtu.be') ||
      low.contains('vimeo.com');
}

/// URL aponta para arquivo de vídeo hospedado (não usar como imagem no carrossel).
/// Não confundir com fotos salvas em pasta `videos/` (ex.: thumb.jpg) — isso quebrava a capa no site público.
bool looksLikeHostedVideoFileUrl(String url) {
  final low = url.toLowerCase();
  if (_isYoutubeVimeo(low)) return false;
  final base = low.split('?').first.split('#').first;
  // Miniaturas / posters com extensão de imagem: sempre tratar como imagem.
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?)', caseSensitive: false)
      .hasMatch(base)) {
    return false;
  }
  if (base.endsWith('.mp4') ||
      base.endsWith('.webm') ||
      base.endsWith('.mov') ||
      base.endsWith('.m4v') ||
      base.endsWith('.m3u8')) {
    return true;
  }
  if (low.contains('.m3u8')) return true;
  // Pasta eventos/.../videos/ pode ter thumb.jpg — não tratar como MP4 só pelo segmento "videos".
  if ((low.contains('%2fvideos%2f') || low.contains('/videos/')) &&
      !RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?)', caseSensitive: false).hasMatch(base)) {
    return true;
  }
  // URL tokenizada sem extensão óbvia no final: inspecionar path decodificado.
  try {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final dec = Uri.decodeComponent(uri.path).toLowerCase();
      if (RegExp(r'\.(mp4|webm|mov|m4v|m3u8)(\?|$|/)', caseSensitive: false).hasMatch(dec)) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}

/// Vídeo para player **inline** (painel, mural, site): ficheiro `.mp4`/`.m3u8` **ou**
/// URL Firebase Storage que não é claramente imagem (evita token sem extensão no path).
bool eventNoticiaUrlEligibleForHostedInlinePlayer(String url) {
  final t = url.trim();
  if (t.isEmpty) return false;
  final low = t.toLowerCase();
  if (_isYoutubeVimeo(low)) return false;
  if (looksLikeHostedVideoFileUrl(t)) return true;
  if (low.contains('firebasestorage.googleapis.com') ||
      low.contains('.firebasestorage.app')) {
    final head = low.split('?').first;
    if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?|/)',
            caseSensitive: false)
        .hasMatch(head)) {
      return false;
    }
    return true;
  }
  return false;
}

/// Lista de URLs só de fotos (painel feed, galeria, site).
List<String> eventNoticiaPhotoUrls(Map<String, dynamic>? data) {
  if (data == null) return [];
  final out = <String>[];
  final seen = <String>{};
  void pushString(String? raw) {
    final s = _photoUrlFromFirestore(raw);
    if (s.isEmpty) return;
    if (_isYoutubeVimeo(s.toLowerCase())) return;
    if (looksLikeHostedVideoFileUrl(s)) return;
    final okHttp = isValidImageUrl(s);
    final okGs = s.toLowerCase().startsWith('gs://');
    final okPath = firebaseStorageMediaUrlLooksLike(s);
    if (!okHttp && !okGs && !okPath) return;
    if (seen.add(s)) out.add(s);
  }

  void pushFromMap(Map m) {
    // Alguns documentos antigos guardam a URL do arquivo em outras chaves.
    pushString(m['url']?.toString());
    pushString(m['storagePath']?.toString());
    pushString(m['storage_path']?.toString());
    pushString(m['path']?.toString());
    pushString(m['ref']?.toString());
    pushString(m['imageUrl']?.toString());
    pushString(m['image_url']?.toString());
    pushString(m['downloadUrl']?.toString());
    pushString(m['downloadURL']?.toString());
    pushString(m['fotoUrl']?.toString());
    pushString(m['imagemUrl']?.toString());

    // fallback: alguns guardam "thumbUrl" mesmo em payload de foto.
    pushString(m['thumbUrl']?.toString());
    pushString(m['thumb_url']?.toString());
    pushString(m['thumbnailUrl']?.toString());
    pushString(m['src']?.toString());
  }

  void pushFromAny(dynamic raw) {
    if (raw == null) return;
    if (raw is String) {
      pushString(raw);
      return;
    }
    if (raw is Map) {
      pushFromMap(raw);
      return;
    }
  }

  void pushFromList(dynamic raw) {
    if (raw is! List) return;
    for (final e in raw) {
      if (e is String) {
        pushString(e);
      } else if (e is Map) {
        pushFromMap(e);
      }
    }
  }

  // 1) Canónico no painel/site: `imagem_url` / imagemUrl = getDownloadURL (https com token)
  pushFromAny(data['imagem_url']);
  pushFromAny(data['imagemUrl']);
  pushFromAny(data['imageUrl']);
  // Avisos/eventos: `media` como mapa ou lista de mapas (url / storagePath).
  final mediaRoot = data['media'];
  if (mediaRoot is Map) {
    pushFromMap(mediaRoot);
  } else if (mediaRoot is List) {
    pushFromList(mediaRoot);
  }
  pushFromList(data['attachments']);
  pushFromList(data['attachmentsUrls']);
  pushFromList(data['attachmentUrls']);
  pushFromAny(data['defaultImageUrl']);
  pushFromList(data['imageUrls']);
  pushFromList(data['photos']); // alguns clientes salvam lista em "photos"
  pushFromList(data['imageStoragePaths']);
  pushFromAny(data['imageStoragePath']); // legado: só string, sem lista / sem https
  pushFromList(data['fotoStoragePaths']);

  // 2) Estruturas legadas / variações comuns
  for (final key in [
    'fotos',
    'foto',
    'photo',
    'fotoUrls',
    'foto_url',
    'fotoUrl',
    'imagens',
    'imagem',
    'imagemUrls',
    'imagem_url',
    'imagemUrl',
    'photos',
    'photoUrls',
  ]) {
    if (data.containsKey(key)) {
      final raw = data[key];
      if (raw is List) {
        pushFromList(raw);
      } else {
        pushFromAny(raw);
      }
    }
  }

  // 3) Chaves soltas de URL (casos em que salvou "uma foto" ou capa)
  for (final key in [
    'image_url',
    'imageURL',
    'thumbUrl',
    'coverUrl',
    'capaUrl',
    'coverImageUrl',
    'posterUrl',
    'bannerUrl',
    'banner',
    'heroUrl',
    'heroImageUrl',
    'pictureUrl',
    'picture',
    'fileUrl',
    'file_url',
  ]) {
    if (data.containsKey(key)) pushFromAny(data[key]);
  }
  // 4) Variantes V4 — só quando campos canónicos não trouxeram URL (evita thumb https quebrado em posts antigos)
  if (out.isEmpty) {
    final iv = data['imageVariants'];
    if (iv is Map) {
      for (final key in const [
        'full_1920',
        'full',
        'medium_800',
        'medium',
        'thumb_200',
        'thumb',
      ]) {
        final e = iv[key];
        if (e is Map) {
          pushFromAny(e['url'] ?? e['downloadUrl']);
        } else {
          pushFromAny(e);
        }
      }
    }
  }
  if (out.isEmpty) {
    for (final raw in imageUrlsFromVariantMap(data['imageVariants'])) {
      pushString(raw);
      if (out.isNotEmpty) break;
    }
  }
  if (out.isEmpty) {
    for (final raw in imageUrlsFromVariantMap(data['photoVariants'])) {
      pushString(raw);
      if (out.isNotEmpty) break;
    }
  }
  return dedupeImageRefsByStorageIdentity(
      noticiaImageRefsPreferDisplayOrder(out));
}

/// Proporção do carrossel estilo feed (retrato tipo Instagram 4:5; vídeo 16:9).
/// [media_info.aspect_ratio] = largura / altura da primeira foto quando salva no editor.
double postFeedCarouselAspectRatioForIndex(
  Map<String, dynamic>? data,
  int index,
  int photoCount,
) {
  if (photoCount <= 0) return 16 / 9;
  if (index >= photoCount) return 16 / 9;
  final mi = data?['media_info'];
  if (mi is Map) {
    final oar = mi['aspect_ratio'] ?? mi['aspectRatio'];
    if (oar is num) {
      // Largura÷altura. Flyers muito altos (~0,45+) e paisagem larga até ~1,85.
      return oar.toDouble().clamp(0.45, 1.85);
    }
  }
  return 4 / 5;
}

/// Caminho no Storage para foto/capa do post (quando [imageUrl] no Firestore está vazio ou expirado).
String? eventNoticiaImageStoragePath(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final k in [
    'imageStoragePath',
    'image_storage_path',
    'coverStoragePath',
    'cover_storage_path',
    'photoStoragePath',
    'defaultImageStoragePath',
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }
  final list = data['imageStoragePaths'];
  if (list is List) {
    for (final e in list) {
      final v = e?.toString().trim() ?? '';
      if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    }
  }
  // Derivar path a partir de URLs https do Storage (token expirado / site público).
  String? derivedFromHttpUrl(String? raw) {
    final u = _photoUrlFromFirestore(raw);
    if (u.isEmpty || looksLikeHostedVideoFileUrl(u)) return null;
    final path = firebaseStorageObjectPathFromHttpUrl(u);
    if (path == null || path.isEmpty) return null;
    return normalizeFirebaseStorageObjectPath(path);
  }

  for (final key in [
    'imageUrl',
    'defaultImageUrl',
    'thumbUrl',
    'coverUrl',
    'capaUrl',
    'coverImageUrl',
  ]) {
    final d = derivedFromHttpUrl(data[key]?.toString());
    if (d != null) return d;
  }
  final imgs = data['imageUrls'];
  if (imgs is List) {
    for (final e in imgs) {
      final d = derivedFromHttpUrl(e?.toString());
      if (d != null) return d;
    }
  }
  // Avisos/eventos que guardam a foto só em `fotoUrl` / `imagemUrl` / lista `fotos` — derivar path para token expirado na web.
  for (final raw in eventNoticiaPhotoUrls(data)) {
    final d = derivedFromHttpUrl(raw);
    if (d != null) return d;
  }
  return null;
}

/// Path canónico `eventos/{postId}/banner_evento.jpg` quando o doc não tem metadados mas a foto existe no Storage.
String? eventNoticiaCanonicalPhotoPathFallback(
  Map<String, dynamic>? data, {
  required String docId,
  int index = 0,
  String? churchIdOverride,
}) {
  if (data == null || docId.trim().isEmpty || index < 0) return null;
  if ((data['type'] ?? '').toString() != 'evento') return null;
  if (!_eventDocShouldTryCanonicalPhotoPath(data)) return null;
  var churchId = churchIdOverride?.trim() ?? '';
  if (churchId.isEmpty) {
    for (final k in ['churchId', 'tenantId', 'igrejaId', 'canonicalTenantId']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) {
        churchId = v;
        break;
      }
    }
  }
  if (churchId.isEmpty) return null;
  return ChurchStorageLayout.eventPostPhotoPath(churchId, docId.trim(), index);
}

bool _eventDocShouldTryCanonicalPhotoPath(Map<String, dynamic> data) {
  if (data['publicado'] == true) return true;
  final status = (data['status'] ?? '').toString().trim();
  if (status == 'publicado' || status == 'published') return true;
  final ps = (data['photoUploadState'] ?? data['publishState'] ?? '')
      .toString()
      .toLowerCase();
  return ps.contains('upload') || ps == 'pending_sync';
}

/// Caminho Storage da foto no índice [index] (lista [imageStoragePaths] ou primeiro [eventNoticiaImageStoragePath]).
String? eventNoticiaPhotoStoragePathAt(
  Map<String, dynamic>? data,
  int index, {
  String? docIdHint,
  String? churchIdHint,
}) {
  if (data == null || index < 0) return null;
  for (final key in ['imageStoragePaths', 'fotoStoragePaths']) {
    final list = data[key];
    if (list is List && index < list.length) {
      final v = list[index]?.toString().trim() ?? '';
      if (v.isNotEmpty) {
        return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      }
    }
  }
  if (index == 0) {
    final direct = eventNoticiaImageStoragePath(data);
    if (direct != null && direct.isNotEmpty) return direct;
    if (docIdHint != null && docIdHint.trim().isNotEmpty) {
      return eventNoticiaCanonicalPhotoPathFallback(
        data,
        docId: docIdHint.trim(),
        index: index,
        churchIdOverride: churchIdHint,
      );
    }
  }
  return null;
}

/// Miniatura de vídeo só como path (sem URL https no doc).
String? eventNoticiaThumbStoragePath(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final k in ['thumbStoragePath', 'thumb_storage_path', 'videoThumbStoragePath', 'video_thumb_storage_path']) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }
  final raw = data['videos'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        for (final k in ['thumbStoragePath', 'thumb_storage_path', 'thumbPath']) {
          final v = (e[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
        }
      }
    }
  }
  return null;
}

/// Primeira URL https utilizável como capa do feed (foto ou thumb de vídeo, nunca arquivo .mp4).
bool _isUsableFeedCoverRef(String s) {
  if (s.isEmpty || looksLikeHostedVideoFileUrl(s)) return false;
  if (isValidImageUrl(s)) return true;
  if (s.toLowerCase().startsWith('gs://')) return true;
  return firebaseStorageMediaUrlLooksLike(s);
}

String eventNoticiaFeedCoverHintUrl(Map<String, dynamic>? p) {
  if (p == null) return '';
  final thumbPath = eventNoticiaThumbStoragePath(p);
  if (thumbPath != null && thumbPath.isNotEmpty) return thumbPath;
  final iv = p['imageVariants'];
  if (iv is Map) {
    for (final key in const ['thumb_300', 'thumb_200', 'medium_800', 'medium']) {
      final e = iv[key];
      if (e is Map) {
        final sp = (e['storagePath'] ?? '').toString().trim();
        if (sp.isNotEmpty) return sp;
      }
    }
  }
  for (final raw in eventNoticiaPhotoUrls(p)) {
    final s = sanitizeImageUrl(raw);
    if (_isUsableFeedCoverRef(s)) return s;
  }
  if (iv is Map) {
    for (final key in const ['full_1920', 'full', 'medium_800', 'medium']) {
      final e = iv[key];
      final raw = e is Map ? (e['url'] ?? e['downloadUrl'] ?? e['storagePath']) : e;
      final s = sanitizeImageUrl('$raw');
      if (_isUsableFeedCoverRef(s)) return s;
    }
  }
  final thumb = eventNoticiaDisplayVideoThumbnailUrl(p);
  if (thumb != null && thumb.isNotEmpty) {
    final s = sanitizeImageUrl(thumb);
    if (_isUsableFeedCoverRef(s)) return s;
  }
  for (final raw in imageUrlsListFromMap(p)) {
    final s = sanitizeImageUrl(raw);
    if (!_isUsableFeedCoverRef(s)) continue;
    final low = s.toLowerCase();
    if (low.contains('youtube.com') || low.contains('youtu.be') || low.contains('vimeo.com')) continue;
    return s;
  }
  final single = imageUrlFromMap(p);
  if (single.isNotEmpty) {
    final s = sanitizeImageUrl(single);
    if (_isUsableFeedCoverRef(s)) return s;
  }
  return '';
}

/// Há algo para exibir na faixa visual do post (capa/thumb resolvível).
bool eventNoticiaPostHasFeedCoverRow(
  Map<String, dynamic>? p, {
  String coverHint = '',
  String? docIdHint,
}) {
  if (p == null) return coverHint.isNotEmpty;
  final h = coverHint.isNotEmpty ? sanitizeImageUrl(coverHint) : '';
  if (h.isNotEmpty && _isUsableFeedCoverRef(h)) return true;
  if (eventNoticiaFeedCoverHintUrl(p).isNotEmpty) return true;
  if (eventNoticiaImageStoragePath(p) != null) return true;
  if (docIdHint != null &&
      docIdHint.trim().isNotEmpty &&
      eventNoticiaCanonicalPhotoPathFallback(
            p,
            docId: docIdHint.trim(),
          ) !=
          null) {
    return true;
  }
  if (eventNoticiaThumbStoragePath(p) != null) return true;
  final hosted = eventNoticiaHostedVideoPlayUrl(p);
  if (hosted != null && hosted.isNotEmpty) {
    final u = sanitizeImageUrl(hosted);
    if (looksLikeHostedVideoFileUrl(u)) return true;
  }
  return false;
}

Map<String, String> _videoRowFromEntryMap(Map e) {
  var vUrl = _photoUrlFromFirestore(
      (e['videoUrl'] ?? e['video_url'] ?? e['url'] ?? '').toString());
  if (vUrl.isEmpty) {
    for (final k in [
      'videoStoragePath',
      'video_storage_path',
      'storagePath',
      'storage_path',
      'path',
      'ref',
    ]) {
      final p = (e[k] ?? '').toString().trim();
      if (p.isNotEmpty) {
        vUrl = _photoUrlFromFirestore(p);
        break;
      }
    }
  }
  final tUrl = _photoUrlFromFirestore(
      (e['thumbUrl'] ?? e['thumb_url'] ?? e['thumb'] ?? '').toString());
  return {'videoUrl': vUrl, 'thumbUrl': tUrl};
}

List<Map<String, String>> eventNoticiaVideosFromDoc(Map<String, dynamic>? data) {
  if (data == null) return [];
  final raw = data['videos'];
  if (raw is List && raw.isNotEmpty) {
    return raw
        .map((e) {
          if (e is Map) {
            return _videoRowFromEntryMap(e);
          }
          return <String, String>{};
        })
        .where((m) => (m['videoUrl'] ?? '').isNotEmpty)
        .toList();
  }
  var vUrl = _photoUrlFromFirestore(data['videoUrl']?.toString());
  if (vUrl.isEmpty) {
    for (final k in [
      'videoStoragePath',
      'video_storage_path',
    ]) {
      final p = (data[k] ?? '').toString().trim();
      if (p.isNotEmpty) {
        vUrl = _photoUrlFromFirestore(p);
        break;
      }
    }
  }
  if (vUrl.isEmpty) return [];
  final tUrl = _photoUrlFromFirestore(data['thumbUrl']?.toString());
  return [
    {'videoUrl': vUrl, 'thumbUrl': tUrl}
  ];
}

/// Link YouTube/Vimeo no campo videoUrl.
String? eventNoticiaExternalVideoUrl(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final m in eventNoticiaVideosFromDoc(data)) {
    final v = (m['videoUrl'] ?? '').toLowerCase();
    if (_isYoutubeVimeo(v)) return m['videoUrl'];
  }
  return null;
}

/// Primeira miniatura de vídeo hospedado (Firebase).
String? eventNoticiaVideoThumbUrl(Map<String, dynamic>? data) {
  for (final m in eventNoticiaVideosFromDoc(data)) {
    final t = _photoUrlFromFirestore(m['thumbUrl']);
    if (t.isNotEmpty && isValidImageUrl(t)) return t;
  }
  return null;
}

/// Primeira URL de vídeo arquivo (Firebase Storage) para abrir no player/navegador.
String? eventNoticiaHostedVideoPlayUrl(Map<String, dynamic>? data) {
  for (final m in eventNoticiaVideosFromDoc(data)) {
    final u = _photoUrlFromFirestore(m['videoUrl']);
    if (u.isEmpty) continue;
    if (_isYoutubeVimeo(u.toLowerCase())) continue;
    if (isValidImageUrl(u)) return u;
    if (looksLikeHostedVideoFileUrl(u)) return u;
  }
  return null;
}

/// Extrai ID de vídeo do YouTube (watch, embed, shorts, youtu.be).
String? youtubeVideoIdFromUrl(String? raw) {
  final u = (raw ?? '').trim();
  if (u.isEmpty) return null;
  final uri = Uri.tryParse(u.startsWith('http://') || u.startsWith('https://') ? u : 'https://$u');
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (seg.isNotEmpty) return seg.split('/').first;
  }
  if (host.contains('youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final segs = uri.pathSegments;
    if (segs.length >= 2) {
      final head = segs[0].toLowerCase();
      if (head == 'embed' || head == 'shorts' || head == 'live' || head == 'v') {
        return segs[1];
      }
    }
  }
  return null;
}

/// Miniatura estática do YouTube (funciona sem API).
String? youtubeThumbnailUrlForVideoUrl(String? videoUrl) {
  final id = youtubeVideoIdFromUrl(videoUrl);
  if (id == null || id.isEmpty) return null;
  return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

/// URL para exibir no card: thumb salva no Storage/Firestore ou preview do YouTube.
String? eventNoticiaDisplayVideoThumbnailUrl(Map<String, dynamic>? data) {
  if (data == null) return null;
  // Capa / poster no documento (painel ou importação legada)
  for (final key in [
    'posterUrl',
    'videoPosterUrl',
    'coverUrl',
    'capaUrl',
    'videoThumbUrl',
    'video_thumbnail',
    'thumbnailUrl',
    'thumbUrl',
    'previewImageUrl',
  ]) {
    final raw = _photoUrlFromFirestore(data[key]?.toString());
    if (raw.isEmpty || !isValidImageUrl(raw)) continue;
    if (looksLikeHostedVideoFileUrl(raw)) continue;
    final s = sanitizeImageUrl(raw);
    if (isValidImageUrl(s)) return s;
  }
  final stored = eventNoticiaVideoThumbUrl(data);
  if (stored != null && stored.isNotEmpty) {
    final s = sanitizeImageUrl(stored);
    if (isValidImageUrl(s)) return s;
  }
  for (final m in eventNoticiaVideosFromDoc(data)) {
    final v = (m['videoUrl'] ?? '').toString().trim();
    if (v.isEmpty) continue;
    final y = youtubeThumbnailUrlForVideoUrl(v);
    if (y != null) return y;
  }
  final legacy = (data['videoUrl'] ?? '').toString().trim();
  if (legacy.isNotEmpty) {
    final y = youtubeThumbnailUrlForVideoUrl(legacy);
    if (y != null) return y;
  }
  return null;
}

/// Revisão para cache-bust de imagens (banner/capa com nome ficheiro fixo no Storage).
int? eventNoticiaMediaCacheRevision(Map<String, dynamic>? p) {
  if (p == null) return null;
  final r = p['fotoUrlCacheRevision'];
  if (r is int) return r;
  if (r is num) return r.toInt();
  final t = p['ATUALIZADO_EM'];
  if (t is Timestamp) return t.millisecondsSinceEpoch;
  final c = p['CRIADO_EM'];
  if (c is Timestamp) return c.millisecondsSinceEpoch;
  return null;
}

/// Adiciona `v=cb…` à query para o browser não mostrar imagem antiga após novo upload (mesmo path).
String cacheBustImageUrl(String url, {int? revisionMs}) {
  final u = sanitizeImageUrl(url);
  if (u.isEmpty || revisionMs == null) return u;
  final uri = Uri.tryParse(u);
  if (uri == null) return u;
  final q = Map<String, String>.from(uri.queryParameters);
  q['v'] = 'cb$revisionMs';
  return uri.replace(queryParameters: q).toString();
}
