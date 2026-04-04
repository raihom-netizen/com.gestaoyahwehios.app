import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';

/// Tratamento definitivo de imagens em rede: logo, cadastro igreja, eventos, avisos.
/// Garante exibição no painel e feed — evita tela preta ou erro ao carregar.
/// Na web, [SafeNetworkImage] delega a [StorageFriendlyImage] (SDK Storage + http; último recurso [Image.network] sem recursão).

/// Fallback alinhado a [DefaultFirebaseOptions] quando [Firebase.app] ainda não está disponível.
const String _kDefaultStorageBucket = 'gestaoyahweh-21e23.firebasestorage.app';

class _AsyncLimiter {
  final int maxConcurrent;
  int _running = 0;
  final List<Completer<void>> _waiters = [];

  _AsyncLimiter(this.maxConcurrent);

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) {
        final next = _waiters.removeAt(0);
        if (!next.isCompleted) next.complete();
      }
    }
  }
}

final _mediaDownloadLimiter = _AsyncLimiter(18);
final _mediaPreloadLimiter = _AsyncLimiter(6);
final Set<String> _preloadedMediaUrls = <String>{};

/// Corrige URLs do Firebase Storage gravadas no Firestore **sem** `https://` e sem o prefixo
/// `https://firebasestorage.googleapis.com/v0/b/<bucket>/` (ex.: só `21e23.firebasestorage.app/o/...`).
/// Assim [isValidImageUrl] e os widgets de imagem passam a aceitar o mesmo valor que abre no navegador.
String normalizeFirebaseStorageDownloadUrl(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  final low = t.toLowerCase();
  if (low.startsWith('http://') || low.startsWith('https://')) return t;

  String storageBucket() {
    try {
      final b = Firebase.app().options.storageBucket;
      if (b != null && b.isNotEmpty) return b;
    } catch (_) {}
    return _kDefaultStorageBucket;
  }

  // `gs://` NÃO virar https sintético sem token — quebra na web (CORS / 403) e no CanvasKit.
  // Mantém o prefixo para [freshFirebaseStorageDisplayUrl] / [refFromURL] gerarem URL com token.
  if (low.startsWith('gs://')) {
    return t;
  }

  // Caso comum: Firestore salvou algo como `gestaoyahweh-21e23.firebasestorage.app/o/...`
  // sem o esquema `https://`. Nesse caso, apenas adicionar o protocolo costuma resolver.
  if (!low.contains('://') &&
      low.contains('.firebasestorage.app') &&
      !low.startsWith('o/') &&
      !low.startsWith('/o/')) {
    return 'https://$t';
  }

  // Host da API sem esquema
  if (low.startsWith('firebasestorage.googleapis.com')) {
    return 'https://$t';
  }

  // Legado: Firestore salvou só o caminho do objeto (sem domínio e sem token),
  // ex.: `igrejas/<tenant>/membros/foto.jpg` ou `igrejas%2F...%2Ffoto.jpg`.
  // Como nossas rules permitem `allow read: if true` para essas pastas,
  // montamos a URL do "media" sem token para acelerar e evitar falhas.
  final looksLikeStoragePath = (low.contains('igrejas/') ||
          low.contains('membros/') ||
          low.contains('members/') ||
          low.contains('patrimonio/') ||
          low.contains('certificado_logos/') ||
          low.contains('carteira_logos/') ||
          low.contains('noticias/') ||
          low.contains('avisos/') ||
          low.contains('eventos/') ||
          low.contains('event_templates/') ||
          low.contains('templates/') ||
          low.contains('branding/') ||
          low.contains('logo/') ||
          low.contains('public/') ||
          low.contains('gestao_yahweh') ||
          low.contains('videos/') ||
          low.contains('comprovantes/') ||
          low.contains('departamentos/')) &&
      (low.contains('/') || low.contains('%2f')) &&
      !low.contains('firebasestorage.');
  if (looksLikeStoragePath) {
    final bucket = storageBucket();
    final pathPart = t.replaceAll(RegExp(r'^/+'), '').replaceAll('\\', '/');
    final encoded =
        pathPart.contains('%') ? pathPart : Uri.encodeComponent(pathPart);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media';
  }

  // Padrão truncado: *firebasestorage.app/o/<pathEncoded>?alt=media&token=...
  final oIdx = t.indexOf('/o/');
  if (oIdx >= 0 && low.contains('firebasestorage.app')) {
    final afterO = t.substring(oIdx + 3);
    if (afterO.isEmpty) return t;
    // Quando a URL não possui esquema, o bucket normalmente está no prefixo antes de `/o/`.
    final prefixHost = t
        .substring(0, oIdx)
        .trim()
        .replaceAll(RegExp(r'^https?://', caseSensitive: false), '');
    final bucket = prefixHost.isNotEmpty ? prefixHost : storageBucket();
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$afterO';
  }

  // Só o sufixo `o/...` (alguns exports antigos)
  if ((low.startsWith('o/') || low.startsWith('/o/')) &&
      (t.contains('alt=media') || t.contains('%2F') || t.contains('token='))) {
    final rest = t.replaceFirst(RegExp(r'^/?o/'), '');
    if (rest.isEmpty) return t;
    final bucket = storageBucket();
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$rest';
  }

  // Só caminho codificado + query (sem domínio), ex.: igrejas%2Ftenant%2Fmembros%2Fcpf.jpg?alt=media&token=...
  if (!low.contains('://') &&
      !low.contains('firebasestorage.googleapis.com') &&
      (low.contains('alt=media') || low.contains('token=')) &&
      (low.contains('%2f') || low.contains('%2F'))) {
    final bucket = storageBucket();
    final pathPart = t.split('?').first.replaceFirst(RegExp('^/+'), '');
    if (pathPart.isNotEmpty) {
      final q = t.contains('?') ? '?${t.split('?').skip(1).join('?')}' : '';
      return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$pathPart$q';
    }
  }

  return t;
}

String sanitizeImageUrl(String? url) {
  if (url == null) return '';
  var s = url
      .trim()
      .replaceAll(RegExp(r'[\r\n\t]'), '')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  // Aspas ao colar do Excel/Firestore/JSON quebram o carregamento na web.
  if (s.length >= 2) {
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
  }
  s = normalizeFirebaseStorageDownloadUrl(s);
  return s;
}

/// Pixels para [memCacheWidth]/[memCacheHeight] (ou [Image.cacheWidth]) com nitidez em retina,
/// alinhado ao pipeline de logo em alta (até [maxPx]), sem estourar memória.
int memCacheExtentForLogicalSize(
  double logicalPx,
  double devicePixelRatio, {
  double oversample = 2.0,
  int minPx = 64,
  int maxPx = 3840,
}) {
  final v = (logicalPx * devicePixelRatio * oversample).round();
  if (v < minPx) return minPx;
  if (v > maxPx) return maxPx;
  return v;
}

/// Miniaturas (decode pequeno): [FilterQuality.medium] alivia GPU em listas; detalhe mantém [high].
FilterQuality filterQualityForMemCache(int? cacheWidth, int? cacheHeight) {
  const threshold = 512;
  if (cacheWidth != null && cacheWidth <= threshold) {
    return FilterQuality.medium;
  }
  if (cacheHeight != null && cacheHeight <= threshold) {
    return FilterQuality.medium;
  }
  return FilterQuality.high;
}

/// Retorna [url] se já for absoluta (http/https). Se for caminho relativo e [baseUrl]
/// for informado, retorna a URL completa (ex.: baseUrl + /uploads/foto.jpg).
/// Assim evita "Imagem indisponível" quando o banco guardou só o caminho.
String ensureFullImageUrl(String? url, [String? baseUrl]) {
  final u = sanitizeImageUrl(url);
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  if (baseUrl == null || baseUrl.trim().isEmpty) return u;
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final path = u.replaceAll(RegExp(r'^/+'), '');
  return path.isEmpty ? base : '$base/$path';
}

bool isDataImageUrl(String? url) {
  final u = (url ?? '').trim().toLowerCase();
  return u.startsWith('data:image/') && u.contains(';base64,');
}

/// Decodifica `data:image/...;base64,...` (ex.: preview da carteirinha após escolher da galeria).
Uint8List? decodeDataImageBytes(String raw) {
  final u = raw.trim();
  final low = u.toLowerCase();
  if (!low.startsWith('data:image/')) return null;
  final comma = u.indexOf(',');
  if (comma < 0 || comma >= u.length - 1) return null;
  final header = u.substring(0, comma).toLowerCase();
  if (!header.contains(';base64')) return null;
  try {
    final b =
        base64Decode(u.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
    return b.length > 24 ? b : null;
  } catch (_) {
    return null;
  }
}

bool isValidImageUrl(String? url) {
  final u = sanitizeImageUrl(url);
  if (u.isEmpty) return false;
  if (isDataImageUrl(u)) return true;
  return u.startsWith('http://') || u.startsWith('https://');
}

/// Download URLs do Firebase Storage (formato antigo [googleapis] ou host [*.firebasestorage.app]).
bool isFirebaseStorageHttpUrl(String url) {
  final low = url.toLowerCase();
  if (low.contains('firebasestorage.googleapis.com')) return true;
  if (low.contains('.firebasestorage.app')) return true;
  // GCS / downloads legados apontando ao bucket (não confundir com APIs genéricas do Google).
  if (low.contains('storage.googleapis.com')) return true;
  // Alguns downloads gravados usam host googleapis + /o/ + alt=media (mesmo bucket).
  if (low.contains('googleapis.com') &&
      low.contains('/o/') &&
      (low.contains('alt=media') || low.contains('alt%3dmedia'))) {
    return true;
  }
  // Hosts novos/legados: se extraímos path de objeto Storage, usar pipeline SDK (evita [Image.network] preso na web).
  final u = sanitizeImageUrl(url);
  if (isValidImageUrl(u) && firebaseStorageObjectPathFromHttpUrl(u) != null) {
    return true;
  }
  return false;
}

/// Indica mídia no Firebase Storage (URL ou caminho) — alinhado ao [StorageMediaService] sem import circular.
bool firebaseStorageMediaUrlLooksLike(String url) {
  final low = url.toLowerCase();
  if (low.startsWith('gs://')) return true;
  if (!low.contains('://') &&
      (low.contains('igrejas/') ||
          low.contains('igrejas%2f') ||
          low.contains('eventos/') ||
          low.contains('eventos%2f') ||
          low.contains('membros/') ||
          low.contains('membros%2f') ||
          low.contains('members/') ||
          low.contains('members%2f') ||
          low.contains('noticias/') ||
          low.contains('noticias%2f') ||
          low.contains('avisos/') ||
          low.contains('avisos%2f') ||
          low.contains('videos/') ||
          low.contains('videos%2f') ||
          low.contains('comprovantes/') ||
          low.contains('comprovantes%2f') ||
          low.contains('certificado_logos/') ||
          low.contains('certificado_logos%2f') ||
          low.contains('carteira_logos/') ||
          low.contains('carteira_logos%2f') ||
          low.contains('patrimonio/') ||
          low.contains('patrimonio%2f') ||
          low.contains('departamentos/') ||
          low.contains('departamentos%2f') ||
          low.contains('public/') ||
          low.contains('public%2f') ||
          low.contains('gestao_yahweh'))) {
    return true;
  }
  return isFirebaseStorageHttpUrl(url);
}

/// Legado: URLs/caminhos gravados com `Igrejas/` — o bucket real usa `igrejas/` (minúsculo).
String normalizeFirebaseStorageObjectPath(String path) {
  var p = path.replaceAll('\\', '/').trim();
  if (p.startsWith('Igrejas/')) {
    return 'igrejas/${p.substring(8)}';
  }
  return p;
}

/// Parâmetro de query para forçar o browser a não reutilizar decode antigo (logo/mural após troca no Storage).
String appendFirebaseMediaCacheBust(String httpsUrl) {
  final u = sanitizeImageUrl(httpsUrl);
  if (!isValidImageUrl(u) || isDataImageUrl(u)) return u;
  if (!isFirebaseStorageHttpUrl(u)) return u;
  final b = DateTime.now().millisecondsSinceEpoch;
  return u.contains('?') ? '$u&gy_cb=$b' : '$u?gy_cb=$b';
}

/// Renova token / resolve caminho — **única fonte** para painel, avisos, site público, patrimônio e vídeos.
/// Nunca lança: em timeout ou falha do SDK, devolve a URL já sanitizada (a que abre no navegador).
Future<String> freshFirebaseStorageDisplayUrl(String rawUrl) async {
  final u = sanitizeImageUrl(rawUrl).trim();
  if (u.isEmpty) return u;
  if (!firebaseStorageMediaUrlLooksLike(u)) return u;
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }
  try {
    if (u.toLowerCase().startsWith('gs://')) {
      try {
        final refGs = FirebaseStorage.instance.refFromURL(u);
        final freshGs = await refGs
            .getDownloadURL()
            .timeout(const Duration(seconds: 22), onTimeout: () => '');
        if (freshGs.isNotEmpty) return sanitizeImageUrl(freshGs);
      } catch (_) {}
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      try {
        final bare = normalizeFirebaseStorageObjectPath(
            u.replaceFirst(RegExp(r'^/+'), ''));
        if (!bare.toLowerCase().startsWith('gs://')) {
          final fresh = await FirebaseStorage.instance
              .ref(bare)
              .getDownloadURL()
              .timeout(const Duration(seconds: 22), onTimeout: () => '');
          if (fresh.isNotEmpty) return sanitizeImageUrl(fresh);
        }
      } catch (_) {}
    }
    try {
      final ref = FirebaseStorage.instance.refFromURL(u);
      final fresh = await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 18), onTimeout: () => '');
      if (fresh.isNotEmpty) return sanitizeImageUrl(fresh);
    } catch (_) {}
    try {
      final path = firebaseStorageObjectPathFromHttpUrl(u);
      if (path != null && path.isNotEmpty) {
        final norm = normalizeFirebaseStorageObjectPath(path);
        final fresh = await FirebaseStorage.instance
            .ref(norm)
            .getDownloadURL()
            .timeout(const Duration(seconds: 18), onTimeout: () => '');
        if (fresh.isNotEmpty) return sanitizeImageUrl(fresh);
      }
    } catch (_) {}
  } catch (_) {}
  return u;
}

/// Extrai o caminho do objeto no bucket (ex.: `igrejas/tenant/patrimonio/foto.jpg`) a partir da URL HTTP.
String? firebaseStorageObjectPathFromHttpUrl(String rawUrl) {
  final url = sanitizeImageUrl(rawUrl);
  if (!isValidImageUrl(url)) return null;
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    final segs = uri.pathSegments;

    if (host.contains('firebasestorage.googleapis.com')) {
      if (segs.length >= 5 &&
          segs[0] == 'v0' &&
          segs[1] == 'b' &&
          segs[3] == 'o') {
        final enc = segs.sublist(4).join('/');
        if (enc.isEmpty) return null;
        return normalizeFirebaseStorageObjectPath(
            Uri.decodeComponent(enc.replaceAll('+', ' ')));
      }
    }

    // Novo formato: https://<bucket>.firebasestorage.app/o/<encodedPath>?...
    if (host.contains('firebasestorage.app') &&
        segs.isNotEmpty &&
        segs.first == 'o') {
      if (segs.length < 2) return null;
      final enc = segs.sublist(1).join('/');
      if (enc.isEmpty) return null;
      return normalizeFirebaseStorageObjectPath(
          Uri.decodeComponent(enc.replaceAll('+', ' ')));
    }

    // GCS: https://storage.googleapis.com/<bucket>/<objectPath...>
    if (host == 'storage.googleapis.com' && segs.length >= 2) {
      final objectPath = segs.sublist(1).join('/');
      if (objectPath.isNotEmpty) {
        return normalizeFirebaseStorageObjectPath(
            Uri.decodeComponent(objectPath.replaceAll('+', ' ')));
      }
    }
  } catch (_) {}
  return null;
}

/// URLs em mapas `photoVariants` / `imageVariants` / `logoVariants`.
/// Prefere **full / original** antes de card/thumb (extensão Firebase Resize, uploads antigos com
/// [MediaUploadService.uploadImageVariants] ou paths `*_full` / `thumbs/`).
/// Alinhado a [FirebaseStorageCleanupService.urlsFromVariantMap], com [sanitizeImageUrl].
List<String> imageUrlsFromVariantMap(dynamic v) {
  if (v is! Map) return [];
  final m = Map<dynamic, dynamic>.from(v);
  const priorityKeys = <String>[
    'full',
    'original',
    'source',
    'hd',
    'large',
    'medium',
    'card',
    'thumb',
    'thumbnail',
    'scaled',
  ];
  final out = <String>[];
  final seen = <String>{};

  void addEntry(dynamic e) {
    if (e is Map) {
      for (final k in const [
        'url',
        'downloadUrl',
        'downloadURL',
        'imageUrl',
        'image_url',
      ]) {
        final u = e[k]?.toString().trim();
        if (u == null || u.isEmpty) continue;
        final s = sanitizeImageUrl(u);
        if (s.isNotEmpty && seen.add(s)) out.add(s);
      }
    } else if (e is String) {
      final s = sanitizeImageUrl(e);
      if (s.isNotEmpty && seen.add(s)) out.add(s);
    }
  }

  for (final key in priorityKeys) {
    for (final e in m.entries) {
      if (e.key.toString().toLowerCase() == key) addEntry(e.value);
    }
  }
  for (final e in m.entries) {
    final k = e.key.toString().toLowerCase();
    if (priorityKeys.contains(k)) continue;
    addEntry(e.value);
  }

  int pathRank(String u) {
    final low = u.toLowerCase();
    if (low.contains('_full.') ||
        low.contains('_full?') ||
        low.contains('/full/')) {
      return 0;
    }
    if (low.contains('_scaled') && !low.contains('thumb')) return 1;
    if (low.contains('_card.') || low.contains('_card?')) return 2;
    if (low.contains('thumb') ||
        low.contains('/thumbs/') ||
        low.contains('%2fthumbs%2f')) {
      return 4;
    }
    return 3;
  }

  out.sort((a, b) => pathRank(a).compareTo(pathRank(b)));
  return out;
}

/// Entre candidatos extraídos do mapa, prefere `https` (token Storage) a `gs://` ou path bruto.
/// Evita variantes `thumb_*` / `*_thumb.*` quando existir URL principal sem thumb.
String _pickBestImageUrlCandidate(List<String> ordered) {
  if (ordered.isEmpty) return '';
  int thumbRank(String s) {
    final low = s.toLowerCase();
    if (low.contains('thumb_') ||
        low.contains('_thumb.') ||
        low.contains('_thumb?') ||
        low.contains('/thumbs/') ||
        low.contains('foto_perfil_thumb') ||
        low.contains('thumb_foto_perfil')) {
      return 1;
    }
    return 0;
  }

  final https = ordered.where((s) => s.startsWith('https://')).toList();
  if (https.isNotEmpty) {
    https.sort((a, b) => thumbRank(a).compareTo(thumbRank(b)));
    return https.first;
  }
  for (final s in ordered) {
    if (s.startsWith('http://')) return s;
  }
  for (final s in ordered) {
    if (isDataImageUrl(s)) return s;
  }
  for (final s in ordered) {
    if (s.toLowerCase().startsWith('gs://')) return s;
  }
  for (final s in ordered) {
    final low = s.toLowerCase();
    if (firebaseStorageMediaUrlLooksLike(s) &&
        !low.startsWith('http://') &&
        !low.startsWith('https://')) {
      return s;
    }
  }
  return ordered.first;
}

/// Extrai a primeira URL de imagem válida de um mapa (membro, evento, patrimônio, tenant, etc.).
/// Usado em todos os módulos para garantir que nenhum campo de foto seja ignorado.
/// Se [baseUrl] for passado, caminhos relativos são convertidos em URL completa (evita "Imagem indisponível").
String imageUrlFromMap(Map<String, dynamic>? data, {String? baseUrl}) {
  if (data == null) return '';
  final ordered = <String>[];
  final seen = <String>{};
  void push(String s) {
    final t = sanitizeImageUrl(s);
    if (t.isEmpty) return;
    if (seen.contains(t)) return;
    seen.add(t);
    ordered.add(t);
  }

  void add(dynamic v) {
    if (v == null) return;
    if (v is String) {
      final s = sanitizeImageUrl(v);
      if (s.isEmpty) return;
      if (isDataImageUrl(s)) {
        push(s);
        return;
      }
      final low = s.toLowerCase();
      if (low.startsWith('gs://')) {
        push(s);
        return;
      }
      if (firebaseStorageMediaUrlLooksLike(s) &&
          !low.startsWith('http://') &&
          !low.startsWith('https://')) {
        push(s);
        return;
      }
      if (s.startsWith('http://') || s.startsWith('https://')) {
        push(s);
      } else if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        push(ensureFullImageUrl(s, baseUrl));
      }
      return;
    }
    if (v is Map) {
      final u = v['url'] ??
          v['imageUrl'] ??
          v['downloadURL'] ??
          v['downloadUrl'] ??
          v['fotoUrl'] ??
          v['photoUrl'] ??
          v['photoURL'] ??
          v['foto'] ??
          v['photo'] ??
          v['avatarUrl'] ??
          v['imagem'] ??
          v['img'] ??
          v['link'] ??
          v['src'] ??
          v['fullPath'] ??
          v['storagePath'] ??
          v['path'] ??
          v['ref'];
      if (u != null) add(u);
      return;
    }
    if (v is List) {
      for (final e in v) {
        add(e);
      }
    }
  }

  const keys = [
    'foto_url',
    'FOTO_URL_OU_ID',
    'FOTO',
    'FOTO_PERFIL',
    'foto_perfil',
    'fotoPerfil',
    'FOTO_MEMBRO',
    'foto_membro',
    'fotoMembro',
    'URL_DA_FOTO',
    'url_da_foto',
    'URL_FOTO',
    'fotoUrl',
    'photoUrl',
    'photoURL',
    'avatarUrl',
    'imageUrl',
    'imageStoragePath',
    'image_storage_path',
    'image_url',
    'imagemUrl',
    'imagem_url',
    'foto',
    'photo',
    'imagem',
    'img',
    'url',
    'defaultImageUrl',
    'profilePhoto',
    'profilePhotoUrl',
    'picture',
    'pictureUrl',
    'imagemPerfil',
    'urlFoto',
    'fotoPerfil',
    'logoUrl',
    'logo_url',
    'logo',
    'logoProcessedUrl',
    'logoProcessed',
    'bannerUrl',
    'capaUrl',
    'thumbUrl',
    'thumb_url',
    'thumbnailUrl',
    'thumbnail',
    'imagemDigitalUrl',
    'IMAGEM_DIGITAL_URL',
    'digitalImagemUrl',
    'DIGITAL_URL',
    'storagePath',
    'storage_path',
    'photoStoragePath',
    'photo_storage_path',
    'mediaPath',
    'media_path',
    'path',
    'ref',
    'logoPath',
    'logo_path',
    'imagePath',
    'image_path',
    'fotoPath',
    'foto_path',
    'videoThumb',
    'video_thumb',
  ];
  for (final k in keys) {
    add(data[k]);
  }
  // Legado: variantes em [photoVariants] (novos uploads usam só FOTO_URL_OU_ID + foto_perfil.jpg).
  if (ordered.isEmpty) {
    for (final raw in imageUrlsFromVariantMap(data['photoVariants'])) {
      add(raw);
    }
  }
  if (ordered.isEmpty) {
    for (final raw in imageUrlsFromVariantMap(data['imageVariants'])) {
      add(raw);
    }
  }
  if (ordered.isEmpty) {
    for (final raw in imageUrlsFromVariantMap(data['logoVariants'])) {
      add(raw);
    }
  }
  if (ordered.isEmpty) {
    add(data['fotoUrls']);
    add(data['foto_urls']);
    add(data['fotos']);
    add(data['imageUrls']);
    add(data['imagens']);
    add(data['images']);
    add(data['arquivos']);
  }
  return _pickBestImageUrlCandidate(ordered);
}

/// Logo do documento [igrejas/{id}]: mesma prioridade do site público — a versão
/// **processada** no Storage costuma ser a URL estável; depois [imageUrlFromMap]
/// cobre [logoUrl] e demais campos (evita logo quebrada quando só processada existe).
String churchTenantLogoUrl(Map<String, dynamic>? data) {
  if (data == null) return '';
  // Campos explícitos primeiro (Firestore pode devolver tipos não-String).
  for (final key in [
    'logoProcessedUrl',
    'logoProcessed',
    'logoUrl',
    'logo_url',
    'brandLogoUrl',
    'churchLogoUrl',
    'tenantLogoUrl',
  ]) {
    final v = data[key];
    if (v == null) continue;
    final s = sanitizeImageUrl(v.toString());
    if (isValidImageUrl(s)) return s;
    if (s.toLowerCase().startsWith('gs://')) return s;
    if (firebaseStorageMediaUrlLooksLike(s) &&
        !s.startsWith('http://') &&
        !s.startsWith('https://')) {
      return s;
    }
  }
  return imageUrlFromMap(data);
}

/// Ordem de tentativa para baixar a logo (PDF, retry). Sem duplicatas.
List<String> churchTenantLogoUrlCandidates(Map<String, dynamic>? data) {
  if (data == null) return [];
  final out = <String>[];
  void push(String? s) {
    final u = sanitizeImageUrl(s);
    if (!isValidImageUrl(u)) return;
    if (!out.contains(u)) out.add(u);
  }

  for (final key in [
    'logoProcessedUrl',
    'logoProcessed',
    'logoUrl',
    'logo_url',
    'brandLogoUrl',
    'churchLogoUrl',
    'tenantLogoUrl',
  ]) {
    push(data[key]?.toString());
  }
  push(imageUrlFromMap(data));
  return out;
}

/// Referência utilizável como foto em avisos (URL https, gs://, path Storage — igual galeria/evento).
bool avisoImageListRefAcceptable(String raw) {
  final s = sanitizeImageUrl(raw);
  if (s.isEmpty) return false;
  final low = s.toLowerCase();
  if (low.contains('youtube.com') ||
      low.contains('youtu.be') ||
      low.contains('vimeo.com')) {
    return false;
  }
  if (isDataImageUrl(s)) return true;
  if (isValidImageUrl(s)) {
    final base = low.split('?').first.split('#').first;
    if (RegExp(r'\.(mp4|webm|mov|m4v)$', caseSensitive: false)
        .hasMatch(base)) {
      return false;
    }
    return true;
  }
  if (low.startsWith('gs://')) return true;
  if (firebaseStorageMediaUrlLooksLike(s)) {
    final base = low.split('?').first.split('#').first;
    final hasImg = RegExp(
            r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(%|$|\?|/)',
            caseSensitive: false)
        .hasMatch(base);
    final hasVid = RegExp(
            r'\.(mp4|webm|mov|m4v)(%|$|\?|/)',
            caseSensitive: false)
        .hasMatch(base);
    if (hasVid && !hasImg) return false;
    return true;
  }
  return false;
}

/// Extrai todas as URLs de imagem de um mapa (para galerias, listas de fotos).
List<String> imageUrlsListFromMap(Map<String, dynamic>? data) {
  if (data == null) return [];
  final out = <String>[];
  void add(dynamic v) {
    if (v == null) return;
    if (v is String) {
      final s = sanitizeImageUrl(v);
      if (avisoImageListRefAcceptable(s) && !out.contains(s)) {
        out.add(s);
      }
      return;
    }
    if (v is Map) {
      final u = v['url'] ??
          v['imageUrl'] ??
          v['downloadURL'] ??
          v['downloadUrl'] ??
          v['fotoUrl'] ??
          v['photoUrl'] ??
          v['photoURL'] ??
          v['foto'] ??
          v['photo'] ??
          v['fileUrl'] ??
          v['uri'] ??
          v['src'] ??
          v['fullPath'] ??
          v['storagePath'] ??
          v['path'] ??
          v['ref'];
      if (u != null) add(u);
      return;
    }
    if (v is List) {
      for (final e in v) {
        add(e);
      }
      return;
    }
    // Firestore às vezes devolve Dynamic não tipado como String
    final s = sanitizeImageUrl(v.toString());
    if (avisoImageListRefAcceptable(s) && !out.contains(s)) {
      out.add(s);
    }
  }

  add(data['imageStoragePaths']);
  add(data['imageStoragePath']);
  add(data['fotoUrls']);
  add(data['foto_urls']);
  add(data['arquivos']);
  add(data['imageUrls']);
  add(data['imagemUrls']);
  add(data['fotos']);
  add(data['imagens']);
  add(data['foto_url']);
  add(data['fotoUrl']);
  add(data['photoUrl']);
  add(data['imageUrl']);
  add(data['imagemUrl']);
  add(data['url']);
  add(data['foto']);
  add(data['photo']);
  add(data['imagem']);
  add(data['img']);
  add(data['FOTO_URL_OU_ID']);
  add(data['defaultImageUrl']);
  add(data['logoUrl']);
  add(data['logo']);
  add(data['logoProcessedUrl']);
  add(data['logoProcessed']);
  add(data['thumbUrl']);
  add(data['thumb_url']);
  add(data['thumbnailUrl']);
  return out;
}

Widget defaultImagePlaceholder({double size = 48}) => Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF3F4F6),
      period: const Duration(milliseconds: 1200),
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

Widget defaultImageErrorWidget(
        {String message = 'Imagem indisponível', double iconSize = 64}) =>
    Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/LOGO_GESTAO_YAHWEH.png',
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_rounded,
              size: iconSize,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );

/// Padrão EcoFire: renova token do Storage antes de exibir (patrimônio, avisos, eventos, logo igreja).
/// URLs no Firestore costumam expirar; sem refresh a imagem quebra na web.
class FreshFirebaseStorageImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final void Function(String url, Object? error)? onLoadError;

  const FreshFirebaseStorageImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.onLoadError,
  });

  @override
  State<FreshFirebaseStorageImage> createState() =>
      _FreshFirebaseStorageImageState();
}

class _FreshFirebaseStorageImageState extends State<FreshFirebaseStorageImage> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant FreshFirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.imageUrl) !=
        sanitizeImageUrl(widget.imageUrl)) {
      _future = _resolve();
    }
  }

  Future<String> _resolve() async {
    final raw = widget.imageUrl.trim();
    if (raw.isEmpty) return raw;
    if (isDataImageUrl(raw)) return sanitizeImageUrl(raw);
    final s = sanitizeImageUrl(raw);
    try {
      if (!firebaseStorageMediaUrlLooksLike(s)) return s;
      var out = await freshFirebaseStorageDisplayUrl(s)
          .timeout(const Duration(seconds: 22), onTimeout: () => s);
      var cleaned = sanitizeImageUrl(out);
      if (!isValidImageUrl(cleaned) && !isDataImageUrl(cleaned)) {
        try {
          if (s.toLowerCase().startsWith('gs://')) {
            final r = await FirebaseStorage.instance
                .refFromURL(s)
                .getDownloadURL()
                .timeout(const Duration(seconds: 18), onTimeout: () => '');
            if (r.isNotEmpty) cleaned = sanitizeImageUrl(r);
          } else if (!s.contains('://') && s.contains('/')) {
            final bare =
                normalizeFirebaseStorageObjectPath(s.replaceFirst(RegExp(r'^/+'), ''));
            final r = await FirebaseStorage.instance
                .ref(bare)
                .getDownloadURL()
                .timeout(const Duration(seconds: 18), onTimeout: () => '');
            if (r.isNotEmpty) cleaned = sanitizeImageUrl(r);
          }
        } catch (_) {}
      }
      if (!isValidImageUrl(cleaned) && !isDataImageUrl(cleaned)) return s;
      return appendFirebaseMediaCacheBust(cleaned);
    } catch (_) {
      return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = widget.errorWidget ?? defaultImageErrorWidget();
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return widget.placeholder ?? defaultImagePlaceholder();
        }
        final u = sanitizeImageUrl(snap.data ?? widget.imageUrl);
        if (!isValidImageUrl(u) && !isDataImageUrl(u)) {
          widget.onLoadError?.call(
              widget.imageUrl, StateError('URL inválida após refresh token'));
          return err;
        }
        return SafeNetworkImage(
          imageUrl: u,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          memCacheWidth: widget.memCacheWidth,
          memCacheHeight: widget.memCacheHeight,
          placeholder: widget.placeholder,
          errorWidget: err,
          skipFreshDisplayUrl: true,
          onLoadError: widget.onLoadError,
        );
      },
    );
  }
}

/// HTTPS no app (listas, patrimônio, assinaturas): renova token em URLs do Firebase Storage
/// antes do decode; demais URLs usam [SafeNetworkImage].
class ResilientNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final void Function(String url, Object? error)? onLoadError;

  const ResilientNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.onLoadError,
  });

  @override
  Widget build(BuildContext context) {
    final u = sanitizeImageUrl(imageUrl);
    final err = errorWidget ?? defaultImageErrorWidget();
    final ph = placeholder ?? defaultImagePlaceholder();
    if (!isValidImageUrl(u) && !isDataImageUrl(u)) {
      if (firebaseStorageMediaUrlLooksLike(u) ||
          u.toLowerCase().startsWith('gs://')) {
        return FreshFirebaseStorageImage(
          imageUrl: u,
          fit: fit,
          width: width,
          height: height,
          memCacheWidth: memCacheWidth,
          memCacheHeight: memCacheHeight,
          placeholder: ph,
          errorWidget: err,
          onLoadError: onLoadError,
        );
      }
      return err;
    }
    final useFresh = isFirebaseStorageHttpUrl(u) ||
        (isValidImageUrl(u) &&
            firebaseStorageMediaUrlLooksLike(u) &&
            (u.startsWith('http://') || u.startsWith('https://')));
    if (useFresh) {
      return FreshFirebaseStorageImage(
        imageUrl: u,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: ph,
        errorWidget: err,
        onLoadError: onLoadError,
      );
    }
    return SafeNetworkImage(
      imageUrl: u,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: ph,
      errorWidget: err,
      skipFreshDisplayUrl: false,
      onLoadError: onLoadError,
    );
  }
}

/// Imagem de rede resiliente para **painel, mural, site** e URLs do **Firebase Storage**.
///
/// **Não** substitua por um [CachedNetworkImage] isolado para URLs
/// `firebasestorage.googleapis.com` / `*.firebasestorage.app`: na **web** (CORS / CanvasKit)
/// e no **Android** costuma falhar ou ficar em loading; use **sempre** este widget (ou
/// [StableStorageImage] / [FreshFirebaseStorageImage] quando aplicável).
///
/// Comportamento interno:
/// - **Web + Storage**: [FirebaseStorageMemoryImage] / [StorageFriendlyImage] (SDK + bytes,
///   último recurso [Image.network] sem recursão).
/// - **Mobile + Storage**: [FirebaseStorageMemoryImage].
/// - **Mobile + URL comum (não Storage)**: [CachedNetworkImage] (cache + placeholder).
///
/// **Firestore:** o upload do mural/eventos já grava URL com token via `getDownloadURL()`.
/// Se o documento tiver só path (`igrejas/.../noticias/...`), [sanitizeImageUrl] e
/// [eventNoticiaPhotoUrls] ajudam a montar URL — preferir sempre salvar a URL completa no save.
///
/// **Diagnóstico (ex. 403 / CORS / URL vazia):** use [onLoadError] como equivalente ao
/// `errorWidget` do [CachedNetworkImage] — ex.: `debugPrint('[Mural] $error | $url')`.
/// Depois de aplicar CORS no bucket GCS, recarregue com Ctrl+F5.
class SafeNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  /// Ver [FirebaseStorageMemoryImage.skipFreshDisplayUrl].
  final bool skipFreshDisplayUrl;
  /// Diagnóstico: falha em qualquer ramo (Storage, [CachedNetworkImage], URL inválida).
  final void Function(String url, Object? error)? onLoadError;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.skipFreshDisplayUrl = false,
    this.onLoadError,
  });

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  bool _imageError = false;
  String _lastReportedBadUrl = '';

  @override
  void didUpdateWidget(covariant SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.imageUrl) !=
            sanitizeImageUrl(widget.imageUrl) ||
        oldWidget.skipFreshDisplayUrl != widget.skipFreshDisplayUrl) {
      _imageError = false;
      _lastReportedBadUrl = '';
    }
  }

  void _reportLoadError(String url, Object? error) {
    widget.onLoadError?.call(url, error);
  }

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(widget.imageUrl);
    if (isDataImageUrl(url)) {
      final mem = decodeDataImageBytes(url);
      if (mem != null) {
        return Image.memory(
          mem,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          filterQuality:
              filterQualityForMemCache(widget.memCacheWidth, widget.memCacheHeight),
          cacheWidth: widget.memCacheWidth,
          cacheHeight: widget.memCacheHeight,
        );
      }
      _reportLoadError(widget.imageUrl, StateError('data:image inválida'));
      return widget.errorWidget ?? defaultImageErrorWidget();
    }
    if (!isValidImageUrl(url)) {
      if (firebaseStorageMediaUrlLooksLike(url) ||
          url.toLowerCase().startsWith('gs://')) {
        return FreshFirebaseStorageImage(
          imageUrl: url,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          memCacheWidth: widget.memCacheWidth,
          memCacheHeight: widget.memCacheHeight,
          placeholder: widget.placeholder ?? defaultImagePlaceholder(),
          errorWidget: widget.errorWidget ?? defaultImageErrorWidget(),
          onLoadError: widget.onLoadError,
        );
      }
      if (_lastReportedBadUrl != url) {
        _lastReportedBadUrl = url;
        _reportLoadError(widget.imageUrl, StateError('URL inválida ou vazia'));
      }
      return widget.errorWidget ?? defaultImageErrorWidget();
    }
    final placeholder = widget.placeholder ?? defaultImagePlaceholder();
    final errorWidget = widget.errorWidget ?? defaultImageErrorWidget();
    final cacheW = widget.memCacheWidth;
    final cacheH = widget.memCacheHeight;

    // Web: URLs do Firebase Storage — mesmo pipeline do avatar do header ([FirebaseStorageMemoryImage]);
    // [StorageFriendlyImage] aqui deixava listas de membros/painel presas em loading ou sem foto.
    // Demais https: [StorageFriendlyImage] (http + fallback).
    if (kIsWeb) {
      if (isFirebaseStorageHttpUrl(url)) {
        return FirebaseStorageMemoryImage(
          key: ValueKey<String>('sn_web_fs_$url'),
          imageUrl: url,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          placeholder: placeholder,
          errorWidget: errorWidget,
          memCacheWidth: cacheW,
          memCacheHeight: cacheH,
          skipFreshDisplayUrl: widget.skipFreshDisplayUrl,
          onLoadError: widget.onLoadError,
        );
      }
      return StorageFriendlyImage(
        imageUrl: url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: placeholder,
        errorWidget: errorWidget,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        onLoadError: widget.onLoadError,
      );
    }

    if (_imageError) {
      return errorWidget;
    }

    // Android/iOS: [CachedNetworkImage] costuma falhar com URLs do Storage (googleapis ou *.firebasestorage.app).
    if (isFirebaseStorageHttpUrl(url)) {
      return FirebaseStorageMemoryImage(
        key: ValueKey('snfi_$url'),
        imageUrl: url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: placeholder,
        errorWidget: errorWidget,
        memCacheWidth: cacheW,
        memCacheHeight: cacheH,
        skipFreshDisplayUrl: widget.skipFreshDisplayUrl,
        onLoadError: widget.onLoadError,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      fadeInDuration: const Duration(milliseconds: 100),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (_, __) => placeholder,
      errorWidget: (context, failedUrl, error) {
        _reportLoadError(failedUrl, error);
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _imageError = true);
          });
        }
        return errorWidget;
      },
    );
  }
}

/// Último recurso na web: [Image.network] sem passar por [SafeNetworkImage] (evita recursão).
Widget _webNetworkImageLastResort({
  required String url,
  required BoxFit fit,
  double? width,
  double? height,
  Widget? placeholder,
  Widget? errorWidget,
  int? cacheWidth,
  int? cacheHeight,
  void Function(String url, Object error)? onDecodeError,
}) {
  final err = errorWidget ?? defaultImageErrorWidget();
  final ph = placeholder ?? defaultImagePlaceholder();
  return Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    gaplessPlayback: true,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    filterQuality: filterQualityForMemCache(cacheWidth, cacheHeight),
    loadingBuilder: (_, child, progress) {
      if (progress == null) return child;
      return Stack(fit: StackFit.expand, children: [child, ph]);
    },
    errorBuilder: (_, error, __) {
      onDecodeError?.call(url, error);
      return err;
    },
  );
}

/// Baixa bytes do Firebase Storage na web (token + SDK). [refFromURL] pode falhar em alguns builds;
/// tenta também decodificar o path (`/v0/b/.../o/...` ou `*.firebasestorage.app/o/...`).
/// Fallback: getDownloadURL para URL nova com token válido quando getData falha (token expirado).
/// Prioriza getDownloadURL quando a URL original contém token (site público / usuário não logado).
///
/// Limite global de tempo: evita spinner infinito no painel web se o SDK ou a fila travarem.
Future<Uint8List?> firebaseStorageBytesFromDownloadUrl(String rawUrl,
    {int maxBytes = 15 * 1024 * 1024, bool skipFreshDisplayUrl = false}) async {
  try {
    return await _firebaseStorageBytesFromDownloadUrlImpl(rawUrl,
            maxBytes: maxBytes, skipFreshDisplayUrl: skipFreshDisplayUrl)
        .timeout(
      const Duration(seconds: 45),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _firebaseStorageBytesFromDownloadUrlImpl(String rawUrl,
    {int maxBytes = 15 * 1024 * 1024, bool skipFreshDisplayUrl = false}) async {
  var url = sanitizeImageUrl(rawUrl);
  if (isDataImageUrl(url)) return null;
  if (!isValidImageUrl(url)) {
    if (!firebaseStorageMediaUrlLooksLike(url) &&
        !url.toLowerCase().startsWith('gs://')) {
      return null;
    }
    try {
      final resolved = await freshFirebaseStorageDisplayUrl(rawUrl)
          .timeout(const Duration(seconds: 24), onTimeout: () => url);
      url = sanitizeImageUrl(resolved);
    } catch (_) {}
    if (!isValidImageUrl(url)) return null;
  }

  if (kIsWeb && firebaseStorageMediaUrlLooksLike(url)) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    // Painel (gestor logado): garante token fresco para getData/ref — evita falha silenciosa na lista de membros.
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }

  if (!skipFreshDisplayUrl && firebaseStorageMediaUrlLooksLike(url)) {
    try {
      final refreshed = await freshFirebaseStorageDisplayUrl(url)
          .timeout(const Duration(seconds: 22), onTimeout: () => url);
      if (isValidImageUrl(refreshed)) {
        url = sanitizeImageUrl(refreshed);
      }
    } catch (_) {}
  }

  Future<Uint8List?> tryHttpUri(Uri uri) async {
    try {
      final r = await _mediaDownloadLimiter.run(() {
        return http.get(
          uri,
          headers: const {'Accept': 'image/*,*/*;q=0.8'},
        ).timeout(const Duration(seconds: 25));
      });
      if (r.statusCode == 200 && r.bodyBytes.length > 32) return r.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Na **web**, `http.get` do pacote [http] costuma falhar por CORS; priorizar [getData] do SDK.
  /// Em todo lugar: [getData] com timeout para não travar spinner indefinidamente.
  Future<Uint8List?> tryWithRef(Reference ref) async {
    var freshUrl = '';
    try {
      freshUrl = await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 18), onTimeout: () => '');
    } catch (_) {}

    if (kIsWeb) {
      try {
        final b = await ref
            .getData(maxBytes)
            .timeout(const Duration(seconds: 22), onTimeout: () => null);
        if (b != null && b.length > 32) return b;
      } catch (_) {}
      if (freshUrl.isNotEmpty) {
        try {
          final fromFresh = await tryHttpUri(Uri.parse(freshUrl));
          if (fromFresh != null) return fromFresh;
        } catch (_) {}
      }
      try {
        final fromOriginal = await tryHttpUri(Uri.parse(url));
        if (fromOriginal != null) return fromOriginal;
      } catch (_) {}
      try {
        final again = await ref
            .getDownloadURL()
            .timeout(const Duration(seconds: 12), onTimeout: () => '');
        if (again.isNotEmpty) return await tryHttpUri(Uri.parse(again));
      } catch (_) {}
      return null;
    }

    if (freshUrl.isNotEmpty) {
      try {
        final fromFresh = await tryHttpUri(Uri.parse(freshUrl));
        if (fromFresh != null) return fromFresh;
      } catch (_) {}
    }
    try {
      final fromOriginal = await tryHttpUri(Uri.parse(url));
      if (fromOriginal != null) return fromOriginal;
    } catch (_) {}
    try {
      final b = await ref
          .getData(maxBytes)
          .timeout(const Duration(seconds: 22), onTimeout: () => null);
      if (b != null && b.length > 32) return b;
    } catch (_) {}
    try {
      final again = await ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 12), onTimeout: () => '');
      if (again.isNotEmpty) return await tryHttpUri(Uri.parse(again));
    } catch (_) {}

    return null;
  }

  try {
    final ref = FirebaseStorage.instance.refFromURL(url);
    final b = await tryWithRef(ref);
    if (b != null) return b;
  } catch (_) {}
  try {
    final objectPath = firebaseStorageObjectPathFromHttpUrl(url);
    if (objectPath != null && objectPath.isNotEmpty) {
      final ref = FirebaseStorage.instance.ref(objectPath);
      final b = await tryWithRef(ref);
      if (b != null) return b;
    }
  } catch (_) {}
  return null;
}

/// Nova URL com token válido quando a gravada no Firestore expirou ou falhou no carregamento.
Future<String?> refreshFirebaseStorageDownloadUrl(String? rawUrl) async {
  final u = sanitizeImageUrl(rawUrl ?? '');
  if (u.isEmpty) return null;
  if (!firebaseStorageMediaUrlLooksLike(u)) return null;
  try {
    final out = await freshFirebaseStorageDisplayUrl(u)
        .timeout(const Duration(seconds: 18), onTimeout: () => u);
    return isValidImageUrl(out) ? out : null;
  } catch (_) {
    return null;
  }
}

/// Alguns JPEG (perfil ICC, CMYK, resposta HTML disfarçada) passam o tamanho mínimo mas o motor
/// `Image.memory` na web não renderiza; o descodificador [ui.instantiateImageCodec] falha cedo.
/// Nesse caso usamos [Image.network] com o mesmo URL (renderer HTML / navegador nativo).
Future<bool> storageBytesRenderWithImageMemory(Uint8List bytes) async {
  if (bytes.length < 24) return false;
  try {
    final codec = await ui
        .instantiateImageCodec(bytes)
        .timeout(const Duration(seconds: 10));
    final frame = await codec
        .getNextFrame()
        .timeout(const Duration(seconds: 10));
    final ok = frame.image.width > 0 && frame.image.height > 0;
    try {
      frame.image.dispose();
    } catch (_) {}
    try {
      codec.dispose();
    } catch (_) {}
    return ok;
  } catch (_) {
    return false;
  }
}

/// LRU simples para bytes de fotos de perfil (membros) — evita re-download ao rolar a lista.
class MemberProfilePhotoBytesCache {
  static final Map<String, Uint8List> _map = {};
  static final List<String> _order = [];
  static const int maxEntries = 120;

  static void clear() {
    _map.clear();
    _order.clear();
  }

  static Uint8List? get(String rawUrl) {
    final k = sanitizeImageUrl(rawUrl);
    if (k.isEmpty) return null;
    return _map[k];
  }

  static void remove(String rawUrl) {
    final k = sanitizeImageUrl(rawUrl);
    if (k.isEmpty) return;
    _map.remove(k);
    _order.remove(k);
  }

  static void put(String rawUrl, Uint8List bytes) {
    final k = sanitizeImageUrl(rawUrl);
    if (k.isEmpty || bytes.length < 24) return;
    if (_map.containsKey(k)) {
      _map[k] = bytes;
      return;
    }
    while (_order.length >= maxEntries) {
      final old = _order.removeAt(0);
      _map.remove(old);
    }
    _order.add(k);
    _map[k] = bytes;
  }
}

/// Carrega imagem via **Firebase Storage SDK** ([getData]) ou HTTP, depois [Image.memory].
/// No Android, [CachedNetworkImage] costuma ficar indefinidamente em loading com URLs
/// `firebasestorage.googleapis.com` tokenizadas; este widget contorna o problema.
class FirebaseStorageMemoryImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  /// Quando a URL já passou por [freshFirebaseStorageDisplayUrl] / [AppStorageImageService.resolveImageUrl],
  /// evita segundo refresh em [firebaseStorageBytesFromDownloadUrl] (menos contenção do SDK na web).
  final bool skipFreshDisplayUrl;
  /// Diagnóstico (ex.: mural): falha ao obter bytes ou decodificar.
  final void Function(String url, Object? error)? onLoadError;

  const FirebaseStorageMemoryImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.skipFreshDisplayUrl = false,
    this.onLoadError,
  });

  @override
  State<FirebaseStorageMemoryImage> createState() =>
      _FirebaseStorageMemoryImageState();
}

class _FirebaseStorageMemoryImageState
    extends State<FirebaseStorageMemoryImage> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;
  bool _loadFailureReported = false;

  /// Web: bytes baixados não decodificam com [Image.memory] — último recurso nativo do browser.
  bool _webBrowserImg = false;
  String _webBrowserUrl = '';

  /// Uma tentativa com [refreshFirebaseStorageDownloadUrl] se o token da URL gravada expirou.
  bool _didFreshTokenRetry = false;

  @override
  void initState() {
    super.initState();
    _applyUrl(widget.imageUrl, notify: false);
    if (_loading) _fetch(sanitizeImageUrl(widget.imageUrl));
  }

  @override
  void didUpdateWidget(covariant FirebaseStorageMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.imageUrl) !=
            sanitizeImageUrl(widget.imageUrl) ||
        oldWidget.skipFreshDisplayUrl != widget.skipFreshDisplayUrl) {
      _didFreshTokenRetry = false;
      _webBrowserImg = false;
      _webBrowserUrl = '';
      _loadFailureReported = false;
      _applyUrl(widget.imageUrl, notify: true);
      if (_loading) _fetch(sanitizeImageUrl(widget.imageUrl));
    }
  }

  /// [notify] true quando a URL mudou após o primeiro frame — exige [setState].
  void _applyUrl(String raw, {required bool notify}) {
    final url = sanitizeImageUrl(raw);
    if (!isValidImageUrl(url)) {
      final canResolveStorage = firebaseStorageMediaUrlLooksLike(raw.trim()) ||
          raw.trim().toLowerCase().startsWith('gs://');
      if (canResolveStorage) {
        void applyLoading() {
          _bytes = null;
          _failed = false;
          _loading = true;
          _didFreshTokenRetry = false;
          _webBrowserImg = false;
          _webBrowserUrl = '';
        }

        if (notify) {
          setState(applyLoading);
        } else {
          applyLoading();
        }
        return;
      }
      void apply() {
        _bytes = null;
        _loading = false;
        _failed = true;
        _webBrowserImg = false;
        _webBrowserUrl = '';
        if (!_loadFailureReported) {
          _loadFailureReported = true;
          widget.onLoadError
              ?.call(widget.imageUrl, StateError('URL inválida ou vazia'));
        }
      }

      if (notify) {
        setState(apply);
      } else {
        apply();
      }
      return;
    }
    final hit = MemberProfilePhotoBytesCache.get(url);
    if (hit != null) {
      if (kIsWeb) {
        // Na web o LRU pode ter bytes que o Skia/HTML não decodifica — revalidar em [_fetch].
        void applyLoading() {
          _bytes = null;
          _failed = false;
          _loading = true;
          _didFreshTokenRetry = false;
          _webBrowserImg = false;
          _webBrowserUrl = '';
        }

        if (notify) {
          setState(applyLoading);
        } else {
          applyLoading();
        }
        return;
      }
      void apply() {
        _bytes = hit;
        _loading = false;
        _failed = false;
        _webBrowserImg = false;
        _webBrowserUrl = '';
      }

      if (notify) {
        setState(apply);
      } else {
        apply();
      }
      return;
    }
    void applyLoading() {
      _bytes = null;
      _failed = false;
      _loading = true;
      _didFreshTokenRetry = false;
      _webBrowserImg = false;
      _webBrowserUrl = '';
    }

    if (notify) {
      setState(applyLoading);
    } else {
      applyLoading();
    }
  }

  Future<void> _fetch(String url) async {
    final cached0 = MemberProfilePhotoBytesCache.get(url);
    if (cached0 != null) {
      if (!kIsWeb || await storageBytesRenderWithImageMemory(cached0)) {
        if (!mounted) return;
        setState(() {
          _bytes = cached0;
          _loading = false;
          _failed = false;
          _webBrowserImg = false;
          _webBrowserUrl = '';
        });
        return;
      }
      MemberProfilePhotoBytesCache.remove(url);
    }

    Uint8List? data;
    const storageTimeout = Duration(seconds: 28);
    try {
      if (isFirebaseStorageHttpUrl(url)) {
        data = await firebaseStorageBytesFromDownloadUrl(url,
                maxBytes: 12 * 1024 * 1024,
                skipFreshDisplayUrl: widget.skipFreshDisplayUrl)
            .timeout(storageTimeout, onTimeout: () => null);
      } else {
        final r = await _mediaDownloadLimiter.run(() {
          return http.get(
            Uri.parse(url),
            headers: <String, String>{'Accept': 'image/*,*/*;q=0.8'},
          ).timeout(const Duration(seconds: 45));
        });
        if (r.statusCode == 200 && r.bodyBytes.length > 24) {
          data = r.bodyBytes;
        }
      }
    } catch (_) {
      data = null;
    }

    if (!mounted) return;

    if (data != null && data.length > 24) {
      if (kIsWeb) {
        final okMem = await storageBytesRenderWithImageMemory(data);
        if (!okMem) {
          var fallbackUrl = url;
          try {
            final fresh = await refreshFirebaseStorageDownloadUrl(url);
            final next = fresh != null ? sanitizeImageUrl(fresh) : '';
            if (next.isNotEmpty && isValidImageUrl(next)) {
              fallbackUrl = next;
            }
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            _bytes = null;
            _webBrowserImg = true;
            _webBrowserUrl = sanitizeImageUrl(fallbackUrl);
            _loading = false;
            _failed = false;
          });
          return;
        }
      }
      MemberProfilePhotoBytesCache.put(url, data);
      setState(() {
        _bytes = data;
        _loading = false;
        _failed = false;
        _webBrowserImg = false;
        _webBrowserUrl = '';
      });
      return;
    }

    // EcoFire / painel: token expirado na URL do Firestore — uma segunda tentativa com getDownloadURL.
    if (isFirebaseStorageHttpUrl(url) && !_didFreshTokenRetry) {
      _didFreshTokenRetry = true;
      final fresh = await refreshFirebaseStorageDownloadUrl(url);
      final next = fresh != null ? sanitizeImageUrl(fresh) : '';
      if (next.isNotEmpty &&
          next != sanitizeImageUrl(url) &&
          isValidImageUrl(next) &&
          mounted) {
        setState(() {
          _loading = true;
          _failed = false;
        });
        await _fetch(next);
        return;
      }
    }

    if (!mounted) return;
    if (!_loadFailureReported) {
      _loadFailureReported = true;
      widget.onLoadError?.call(
          url, Exception('Falha ao carregar imagem (Storage/HTTP)'));
    }
    setState(() {
      _bytes = null;
      _loading = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorWidget ?? defaultImageErrorWidget();
    }
    if (_webBrowserImg &&
        kIsWeb &&
        _webBrowserUrl.isNotEmpty &&
        isValidImageUrl(_webBrowserUrl)) {
      return _webNetworkImageLastResort(
        url: _webBrowserUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
        errorWidget: widget.errorWidget,
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
        onDecodeError: widget.onLoadError,
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        filterQuality:
            filterQualityForMemCache(widget.memCacheWidth, widget.memCacheHeight),
        cacheWidth: widget.memCacheWidth,
        cacheHeight: widget.memCacheHeight,
      );
    }
    if (_loading) {
      final sz = (widget.height ?? widget.width ?? 48.0).clamp(32.0, 96.0);
      return widget.placeholder ?? defaultImagePlaceholder(size: sz);
    }
    return widget.errorWidget ?? defaultImageErrorWidget();
  }
}

/// Na **web**, [Image.network] com CanvasKit costuma falhar em URLs do Firebase Storage;
/// [http.get] + [Image.memory] usa o mesmo CORS e em geral exibe a foto no feed/site.
class StorageFriendlyImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final void Function(String url, Object? error)? onLoadError;

  const StorageFriendlyImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth,
    this.memCacheHeight,
    this.onLoadError,
  });

  @override
  State<StorageFriendlyImage> createState() => _StorageFriendlyImageState();
}

class _StorageFriendlyImageState extends State<StorageFriendlyImage> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _webAttemptDone = false;

  @override
  void initState() {
    super.initState();
    final u = sanitizeImageUrl(widget.imageUrl);
    if (isDataImageUrl(u)) {
      final b = decodeDataImageBytes(u);
      if (b != null) {
        _bytes = b;
        _loading = false;
        _webAttemptDone = true;
      } else {
        _webAttemptDone = true;
      }
      return;
    }
    if (kIsWeb && isValidImageUrl(u)) {
      _loading = true;
      _loadWebBytes();
    } else {
      _webAttemptDone = true;
    }
  }

  @override
  void didUpdateWidget(covariant StorageFriendlyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.imageUrl) !=
        sanitizeImageUrl(widget.imageUrl)) {
      _bytes = null;
      _webAttemptDone = false;
      _loading = false;
      final u = sanitizeImageUrl(widget.imageUrl);
      if (isDataImageUrl(u)) {
        final b = decodeDataImageBytes(u);
        setState(() {
          _bytes = b;
          _loading = false;
          _webAttemptDone = true;
        });
        return;
      }
      if (kIsWeb && isValidImageUrl(u)) {
        setState(() => _loading = true);
        _loadWebBytes();
      } else {
        setState(() => _webAttemptDone = true);
      }
    }
  }

  /// Web: [http.get] costuma falhar (CORS) em URLs do Storage; o SDK usa credenciais e funciona.
  Future<void> _loadWebBytes() async {
    final url = sanitizeImageUrl(widget.imageUrl);
    if (!isValidImageUrl(url) || !kIsWeb) {
      if (mounted) setState(() => _webAttemptDone = true);
      return;
    }
    try {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      // Não force refresh: isso reduz MUITO o custo e acelera a renderização em painéis.
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}

    /// GET direto replica o que o navegador faz ao abrir a URL na aba; em muitos casos funciona
    /// quando o SDK [getData] na web falha silenciosamente.
    Future<bool> tryHttp() async {
      try {
        final r = await _mediaDownloadLimiter.run(() {
          return http.get(
            Uri.parse(url),
            headers: <String, String>{'Accept': 'image/*,*/*;q=0.8'},
          ).timeout(const Duration(seconds: 45));
        });
        if (!mounted) return true;
        if (r.statusCode == 200 && r.bodyBytes.length > 32) {
          setState(() {
            _bytes = r.bodyBytes;
            _loading = false;
            _webAttemptDone = true;
          });
          return true;
        }
      } catch (_) {}
      return false;
    }

    /// Para URLs do Firebase Storage, prioriza SDK (getDownloadURL) — funciona melhor
    /// no site público com usuário não logado (token expirado na URL original).
    if (isFirebaseStorageHttpUrl(url)) {
      final bytes = await firebaseStorageBytesFromDownloadUrl(url);
      if (!mounted) return;
      if (bytes != null) {
        setState(() {
          _bytes = bytes;
          _loading = false;
          _webAttemptDone = true;
        });
        return;
      }
    }

    if (await tryHttp()) return;

    if (!mounted) return;
    if (mounted) {
      setState(() {
        _loading = false;
        _webAttemptDone = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(widget.imageUrl);
    if (isDataImageUrl(url)) {
      final mem = decodeDataImageBytes(url);
      if (mem != null) {
        return Image.memory(
          mem,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          filterQuality:
              filterQualityForMemCache(widget.memCacheWidth, widget.memCacheHeight),
        );
      }
      widget.onLoadError
          ?.call(widget.imageUrl, StateError('data:image inválida ou corrompida'));
      return widget.errorWidget ?? defaultImageErrorWidget();
    }
    if (!isValidImageUrl(url)) {
      widget.onLoadError
          ?.call(widget.imageUrl, StateError('URL inválida ou vazia'));
      return widget.errorWidget ?? defaultImageErrorWidget();
    }
    if (!kIsWeb) {
      return SafeNetworkImage(
        imageUrl: url,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
        errorWidget: widget.errorWidget,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        onLoadError: widget.onLoadError,
      );
    }
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        filterQuality:
            filterQualityForMemCache(widget.memCacheWidth, widget.memCacheHeight),
      );
    }
    if (_loading || !_webAttemptDone) {
      final sz = widget.height ?? widget.width ?? 48.0;
      return widget.placeholder ??
          defaultImagePlaceholder(size: sz.clamp(32.0, 96.0));
    }
    // Não usar [SafeNetworkImage] aqui: na web ele delega a [StorageFriendlyImage] → recursão infinita.
    return _webNetworkImageLastResort(
      url: url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: widget.placeholder,
      errorWidget: widget.errorWidget,
      cacheWidth: widget.memCacheWidth,
      cacheHeight: widget.memCacheHeight,
      onDecodeError: widget.onLoadError,
    );
  }
}

class SafeCircleAvatarImage extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final Color? backgroundColor;

  /// Quando não nulo, substitui o cálculo por DPR (miniaturas fixas em listas).
  final int? memCacheSize;

  const SafeCircleAvatarImage({
    super.key,
    required this.imageUrl,
    this.radius = 24,
    this.fallbackIcon = Icons.church_rounded,
    this.fallbackColor,
    this.backgroundColor,
    this.memCacheSize,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Colors.grey.shade200;
    final iconColor = fallbackColor ?? Colors.grey.shade600;
    final url = sanitizeImageUrl(imageUrl);
    if (!isValidImageUrl(url)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Icon(fallbackIcon, size: radius * 1.1, color: iconColor),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = memCacheSize ??
        memCacheExtentForLogicalSize(
          radius * 2,
          dpr,
          maxPx: 640,
        );
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: _SafeCircleAvatarContent(
          key: ValueKey<String>('safe_oval_$url'),
          imageUrl: url,
          radius: radius,
          fallbackIcon: fallbackIcon,
          fallbackColor: iconColor,
          backgroundColor: bg,
          memCacheSize: cacheSize,
        ),
      ),
    );
  }
}

class _SafeCircleAvatarContent extends StatefulWidget {
  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final Color backgroundColor;
  final int? memCacheSize;

  const _SafeCircleAvatarContent({
    super.key,
    required this.imageUrl,
    required this.radius,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.backgroundColor,
    this.memCacheSize,
  });

  @override
  State<_SafeCircleAvatarContent> createState() =>
      _SafeCircleAvatarContentState();
}

class _SafeCircleAvatarContentState extends State<_SafeCircleAvatarContent> {
  bool _showFallback = false;

  @override
  void didUpdateWidget(covariant _SafeCircleAvatarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.imageUrl) !=
        sanitizeImageUrl(widget.imageUrl)) {
      _showFallback = false;
    }
  }

  Widget get _placeholder => Container(
        color: widget.backgroundColor,
        child: Icon(widget.fallbackIcon,
            size: widget.radius * 0.8, color: widget.fallbackColor),
      );

  Widget get _errorIcon => Container(
        color: widget.backgroundColor,
        child: Icon(widget.fallbackIcon,
            size: widget.radius * 1.1, color: widget.fallbackColor),
      );

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(widget.imageUrl);
    if (_showFallback) return _errorIcon;
    final size = (widget.radius * 2).ceil();
    final cache = widget.memCacheSize ?? (size * 2);
    if (isDataImageUrl(url)) {
      final mem = decodeDataImageBytes(url);
      if (mem != null) {
        return Image.memory(
          mem,
          fit: BoxFit.cover,
          width: widget.radius * 2,
          height: widget.radius * 2,
          gaplessPlayback: true,
          filterQuality: filterQualityForMemCache(cache, cache),
        );
      }
      return _errorIcon;
    }
    if (kIsWeb) {
      if (isFirebaseStorageHttpUrl(url)) {
        return FirebaseStorageMemoryImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: widget.radius * 2,
          height: widget.radius * 2,
          memCacheWidth: cache,
          memCacheHeight: cache,
          placeholder: _placeholder,
          errorWidget: _errorIcon,
        );
      }
      // Nunca [Image.network] na web para https: CORS/CanvasKit quebra; mesmo pipeline de [SafeNetworkImage].
      return StorageFriendlyImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: widget.radius * 2,
        height: widget.radius * 2,
        memCacheWidth: cache,
        memCacheHeight: cache,
        placeholder: _placeholder,
        errorWidget: _errorIcon,
      );
    }

    if (isFirebaseStorageHttpUrl(url)) {
      return FirebaseStorageMemoryImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: widget.radius * 2,
        height: widget.radius * 2,
        memCacheWidth: cache,
        memCacheHeight: cache,
        placeholder: _placeholder,
        errorWidget: _errorIcon,
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      width: widget.radius * 2,
      height: widget.radius * 2,
      cacheWidth: cache,
      cacheHeight: cache,
      gaplessPlayback: true,
      filterQuality: filterQualityForMemCache(cache, cache),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _placeholder,
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _showFallback = true);
        });
        return _errorIcon;
      },
    );
  }
}

/// Pré-carrega imagens para evitar "carregando" ao rolar listas grandes.
/// Usa limite de concorrência e evita repetir URL já aquecida.
Future<void> preloadNetworkImages(
  BuildContext context,
  List<String> urls, {
  int maxItems = 16,
}) async {
  final cleaned = urls
      .map(sanitizeImageUrl)
      .where((u) => isValidImageUrl(u) && !_preloadedMediaUrls.contains(u))
      .take(maxItems)
      .toList();
  if (cleaned.isEmpty) return;
  await Future.wait(cleaned.map((u) async {
    await _mediaPreloadLimiter.run(() async {
      try {
        // Na web, [NetworkImage] não usa o SDK do Storage — falha com URLs tokenizadas / CORS.
        if (kIsWeb && isFirebaseStorageHttpUrl(u)) return;
        await precacheImage(NetworkImage(u), context);
        _preloadedMediaUrls.add(u);
      } catch (_) {}
    });
  }));
}
