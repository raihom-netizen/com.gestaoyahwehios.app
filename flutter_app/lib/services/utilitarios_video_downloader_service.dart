import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Plataforma detectada a partir da URL.
enum VideoDownPlatform {
  youtube,
  instagram,
  facebook,
  tiktok,
  generic,
  unknown
}

/// Resultado do download de vídeo.
class VideoDownloadResult {
  const VideoDownloadResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.title,
    required this.isAudioOnly,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String title;
  final bool isAudioOnly;
}

/// Informações do vídeo antes de baixar (preview).
class VideoInfo {
  const VideoInfo({
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.platform,
  });

  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final VideoDownPlatform platform;
}

/// Serviço local de download de vídeos — YouTube, Instagram, Facebook, TikTok e qualquer vídeo.
/// 100% no aparelho, sem servidor Firebase.
abstract final class UtilitariosVideoDownloaderService {
  UtilitariosVideoDownloaderService._();

  static final YoutubeExplode _yt = YoutubeExplode();

  /// Detecta a plataforma a partir da URL.
  static VideoDownPlatform detectPlatform(String url) {
    final u = url.trim().toLowerCase();
    if (u.contains('youtube.com') ||
        u.contains('youtu.be') ||
        u.contains('youtube.com/shorts')) {
      return VideoDownPlatform.youtube;
    }
    if (u.contains('instagram.com') || u.contains('instagr.am')) {
      return VideoDownPlatform.instagram;
    }
    if (u.contains('facebook.com') ||
        u.contains('fb.watch') ||
        u.contains('fb.com')) {
      return VideoDownPlatform.facebook;
    }
    if (u.contains('tiktok.com') ||
        u.contains('vm.tiktok.com') ||
        u.contains('vt.tiktok.com') ||
        u.contains('tiktokv.com')) {
      return VideoDownPlatform.tiktok;
    }
    // Qualquer URL http/https ? genérico (tenta extrair vídeo automaticamente)
    if (u.startsWith('http://') || u.startsWith('https://')) {
      return VideoDownPlatform.generic;
    }
    return VideoDownPlatform.unknown;
  }

  /// Valida se a URL parece válida — aceita qualquer link http/https.
  static bool isValidUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// Limpa parâmetros de tracking da URL (igsh, igshid, si, etc.) mantendo a URL funcional.
  static String _cleanUrl(String url) {
    var u = url.trim();
    // Remove tracking params do Instagram (?igsh=... & ?igshid=...)
    u = u.replaceAll(RegExp(r'[?&]igsh=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]igshid=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]utm_[^&]*'), '');
    // Remove tracking params do YouTube (?si=... & playnext=... & feature=...)
    u = u.replaceAll(RegExp(r'[?&]si=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]playnext=\d+'), '');
    u = u.replaceAll(RegExp(r'[?&]feature=[^&]*'), '');
    // Remove tracking params do TikTok
    u = u.replaceAll(RegExp(r'[?&]_r=1'), '');
    u = u.replaceAll(RegExp(r'[?&]_d=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]sec_uid=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]share_app_id=[^&]*'), '');
    // Remove tracking params do Facebook
    u = u.replaceAll(RegExp(r'[?&]ref=[^&]*'), '');
    u = u.replaceAll(RegExp(r'[?&]mibextid=[^&]*'), '');
    // Limpa ?& ou ? vazio no final
    u = u.replaceAll(RegExp(r'\?&'), '?');
    u = u.replaceAll(RegExp(r'\?$'), '');
    u = u.replaceAll(RegExp(r'&$'), '');
    return u;
  }

  /// Extrai o ID de um vídeo YouTube a partir de várias formas de URL.
  /// Retorna null se não for possível extrair (ex.: playlist sem vídeo individual).
  static String? _extractYoutubeVideoId(String url) {
    final u = url.trim();
    // youtube.com/watch?v=XXXX
    final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(u);
    if (watchMatch != null) return watchMatch.group(1);
    // youtu.be/XXXX
    final shortMatch = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})').firstMatch(u);
    if (shortMatch != null) return shortMatch.group(1);
    // youtube.com/shorts/XXXX
    final shortsMatch =
        RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})').firstMatch(u);
    if (shortsMatch != null) return shortsMatch.group(1);
    // youtube.com/embed/XXXX
    final embedMatch =
        RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})').firstMatch(u);
    if (embedMatch != null) return embedMatch.group(1);
    return null;
  }

  /// Verifica se a URL é uma playlist do YouTube (sem vídeo individual).
  static bool _isYoutubePlaylistOnly(String url) {
    final u = url.trim().toLowerCase();
    return u.contains('youtube.com/playlist') &&
        _extractYoutubeVideoId(url) == null;
  }

  /// Busca informações do vídeo (preview) — rápido para YouTube.
  static Future<VideoInfo> fetchVideoInfo(String url) async {
    final platform = detectPlatform(url);
    switch (platform) {
      case VideoDownPlatform.youtube:
        return _fetchYoutubeInfo(url);
      case VideoDownPlatform.instagram:
        return VideoInfo(
          title: 'Vídeo Instagram',
          author: 'Instagram',
          duration: null,
          thumbnailUrl: '',
          platform: platform,
        );
      case VideoDownPlatform.facebook:
        return VideoInfo(
          title: 'Vídeo Facebook',
          author: 'Facebook',
          duration: null,
          thumbnailUrl: '',
          platform: platform,
        );
      case VideoDownPlatform.tiktok:
        return VideoInfo(
          title: 'Vídeo TikTok',
          author: 'TikTok',
          duration: null,
          thumbnailUrl: '',
          platform: platform,
        );
      case VideoDownPlatform.generic:
        return VideoInfo(
          title: 'Vídeo',
          author: 'Web',
          duration: null,
          thumbnailUrl: '',
          platform: platform,
        );
      case VideoDownPlatform.unknown:
        throw StateError('Link não reconhecido. Cole um link de vídeo válido.');
    }
  }

  static Future<VideoInfo> _fetchYoutubeInfo(String url) async {
    try {
      final cleanUrl = _cleanUrl(url);
      if (_isYoutubePlaylistOnly(url)) {
        throw StateError(
          'Links de playlist não são suportados. Abra a playlist no YouTube, escolha um vídeo individual e copie o link dele.',
        );
      }
      final videoId = _extractYoutubeVideoId(cleanUrl);
      final video = videoId != null
          ? await _yt.videos.get(videoId)
          : await _yt.videos.get(cleanUrl);
      return VideoInfo(
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
        platform: VideoDownPlatform.youtube,
      );
    } catch (e) {
      debugPrint('[VideoDown] YouTube info error: $e');
      throw StateError('Não foi possível obter informações do vídeo YouTube.');
    }
  }

  /// Baixa o vídeo ou áudio — 100% local.
  static Future<VideoDownloadResult> download({
    required String url,
    required bool audioOnly,
    void Function(double progress)? onProgress,
  }) async {
    final platform = detectPlatform(url);
    switch (platform) {
      case VideoDownPlatform.youtube:
        return _downloadYoutube(url, audioOnly, onProgress);
      case VideoDownPlatform.instagram:
        return _downloadInstagram(url, audioOnly, onProgress);
      case VideoDownPlatform.facebook:
        return _downloadFacebook(url, audioOnly, onProgress);
      case VideoDownPlatform.tiktok:
        return _downloadTikTok(url, audioOnly, onProgress);
      case VideoDownPlatform.generic:
        return _downloadGeneric(url, audioOnly, onProgress);
      case VideoDownPlatform.unknown:
        throw StateError('Link não reconhecido.');
    }
  }

  /// Download YouTube via youtube_explode_dart (+ Cobalt fallback).
  static Future<VideoDownloadResult> _downloadYoutube(
    String url,
    bool audioOnly,
    void Function(double)? onProgress,
  ) async {
    final cleanUrl = _cleanUrl(url);
    if (_isYoutubePlaylistOnly(url)) {
      throw StateError(
        'Links de playlist não são suportados. Abra a playlist no YouTube, escolha um vídeo individual e copie o link dele.',
      );
    }

    try {
      final videoId = _extractYoutubeVideoId(cleanUrl);
      final video = videoId != null
          ? await _yt.videos.get(videoId)
          : await _yt.videos.get(cleanUrl);
      final title = video.title;
      final safeName = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

      if (audioOnly) {
        final manifest = await _yt.videos.streamsClient.getManifest(video.id);
        final audioStream = manifest.audioOnly.withHighestBitrate();
        final stream = _yt.videos.streamsClient.get(audioStream);

        final tmpDir = await getTemporaryDirectory();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final outPath = '${tmpDir.path}/ct_dl_$stamp.m4a';
        final file = File(outPath);
        final sink = file.openWrite();

        var downloaded = 0;
        final total = audioStream.size.totalBytes;
        await for (final chunk in stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (total > 0) onProgress?.call(downloaded / total);
        }
        await sink.flush();
        await sink.close();

        final bytes = await file.readAsBytes();
        try {
          await file.delete();
        } catch (_) {}
        return VideoDownloadResult(
          bytes: bytes,
          fileName: '${safeName.isEmpty ? "audio" : safeName}.m4a',
          mimeType: 'audio/mp4',
          title: title,
          isAudioOnly: true,
        );
      }

      // Video + audio — muxed stream (rápido, sem FFmpeg)
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final videoStream = manifest.muxed.withHighestBitrate();
      final stream = _yt.videos.streamsClient.get(videoStream);

      final tmpDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${tmpDir.path}/ct_dl_$stamp.mp4';
      final file = File(outPath);
      final sink = file.openWrite();

      var downloaded = 0;
      final total = videoStream.size.totalBytes;
      await for (final chunk in stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (total > 0) onProgress?.call(downloaded / total);
      }
      await sink.flush();
      await sink.close();

      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      return VideoDownloadResult(
        bytes: bytes,
        fileName: '${safeName.isEmpty ? "video" : safeName}.mp4',
        mimeType: 'video/mp4',
        title: title,
        isAudioOnly: false,
      );
    } catch (e) {
      debugPrint('[VideoDown] YouTube explode error: $e ? tentando Cobalt?');
      // Fallback rápido via Cobalt quando o player do YouTube muda.
      final cobaltUrl = await _cobaltExtract(cleanUrl);
      if (cobaltUrl != null && cobaltUrl.isNotEmpty) {
        return _downloadDirectFile(
          cobaltUrl,
          title: 'video_youtube',
          audioOnly: audioOnly,
          onProgress: onProgress,
          referer: 'https://www.youtube.com/',
        );
      }
      throw StateError(
        'Não foi possível baixar o vídeo do YouTube. Verifique o link e tente novamente.',
      );
    }
  }

  /// Download Instagram — sessão real (CSRF + cookies) + GraphQL + scraping multi-UA.
  static Future<VideoDownloadResult> _downloadInstagram(
    String url,
    bool audioOnly,
    void Function(double)? onProgress,
  ) async {
    try {
      var resolvedUrl = await _igResolveShortUrl(url.trim());
      resolvedUrl = _cleanUrl(resolvedUrl);

      final shortcodeMatch = RegExp(
        r'instagram\.com/(?:reel|p|tv)/([a-zA-Z0-9_-]+)',
      ).firstMatch(resolvedUrl);
      if (shortcodeMatch == null) {
        throw StateError(
            'Link do Instagram inválido. Use um link de reel, post ou IGTV.');
      }
      final shortcode = shortcodeMatch.group(1)!;
      final postUrl = 'https://www.instagram.com/p/$shortcode/';

      // Passo 1: Cobalt API (paralelo — mais rápido e confiável)
      String? videoUrl = await _cobaltExtract(resolvedUrl);

      // Passo 2: obter sessão (CSRF token + cookies reais)
      if (videoUrl == null || videoUrl.isEmpty) {
        final session = await _igFetchSession(postUrl);

        // GraphQL com sessão real
        videoUrl =
            await _instagramGraphQLWithSession(shortcode, session: session);

        // Fallback: endpoint __a=1
        if (videoUrl == null || videoUrl.isEmpty) {
          videoUrl = await _instagramJsonEndpoint(postUrl, session: session);
        }

        // Fallback: scraping desktop com sessão
        if (videoUrl == null || videoUrl.isEmpty) {
          videoUrl =
              await _instagramScrapeWithSession(postUrl, session: session);
        }
      }

      // Fallback: scraping mobile
      if (videoUrl == null || videoUrl.isEmpty) {
        videoUrl = await _instagramMobileScrape(postUrl);
      }

      // Fallback: Googlebot
      if (videoUrl == null || videoUrl.isEmpty) {
        videoUrl = await _instagramOgVideoScrape(postUrl);
      }

      if (videoUrl == null || videoUrl.isEmpty) {
        throw StateError(
          'Não foi possível extrair o vídeo do Instagram. O perfil pode ser privado ou o conteúdo removido.',
        );
      }

      return await _downloadDirectFile(
        videoUrl,
        title: 'instagram_$shortcode',
        audioOnly: audioOnly,
        onProgress: onProgress,
        referer: 'https://www.instagram.com/',
      );
    } catch (e) {
      debugPrint('[VideoDown] Instagram download error: $e');
      if (e is StateError) rethrow;
      throw StateError(
        'Não foi possível baixar o vídeo do Instagram. Verifique o link.',
      );
    }
  }

  /// Resolve URLs curtas (sh=, instagr.am) seguindo redirects até obter a URL real do reel/post.
  static Future<String> _igResolveShortUrl(String url) async {
    final u = url.trim();
    if (RegExp(r'instagram\.com/(?:reel|p|tv)/[a-zA-Z0-9_-]+').hasMatch(u)) {
      return u;
    }
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(u))
        ..followRedirects = false
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
      var response =
          await client.send(request).timeout(const Duration(seconds: 10));
      var hops = 0;
      while ((response.statusCode >= 300 && response.statusCode < 400) &&
          hops < 6) {
        final loc = response.headers['location'];
        if (loc == null || loc.isEmpty) break;
        final nextUri = Uri.parse(loc).isAbsolute
            ? Uri.parse(loc)
            : response.request!.url.resolve(loc);
        if (RegExp(r'instagram\.com/(?:reel|p|tv)/[a-zA-Z0-9_-]+')
            .hasMatch(nextUri.toString())) {
          return nextUri.toString();
        }
        final req2 = http.Request('GET', nextUri)..followRedirects = false;
        response = await client.send(req2).timeout(const Duration(seconds: 10));
        hops++;
      }
      client.close();
    } catch (e) {
      debugPrint('[VideoDown] IG resolve short URL error: $e');
    }
    return u;
  }

  /// Sessão Instagram: CSRF token + cookies obtidos de uma visita real à página.
  static Future<({String? csrfToken, String cookieHeader})> _igFetchSession(
      String postUrl) async {
    String? csrf;
    final cookies = <String>[];
    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse(postUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Site': 'none',
        },
      );
      for (final h in response.headers.entries) {
        if (h.key.toLowerCase() == 'set-cookie') {
          for (final part in h.value.split(',')) {
            final c = part.trim().split(';').first;
            if (c.isNotEmpty) cookies.add(c);
            final m = RegExp(r'csrftoken=([^;]+)').firstMatch(part);
            if (m != null) csrf = m.group(1);
          }
        }
      }
      csrf ??= RegExp(r'"csrf_token"\s*:\s*"([^"]+)"')
              .firstMatch(response.body)
              ?.group(1) ??
          RegExp(r'"config"\s*:\s*\{[^}]*"csrf_token"\s*:\s*"([^"]+)"')
              .firstMatch(response.body)
              ?.group(1);
      client.close();
    } catch (e) {
      debugPrint('[VideoDown] IG session fetch error: $e');
    }
    return (csrfToken: csrf, cookieHeader: cookies.join('; '));
  }

  /// GraphQL com sessão real (CSRF + cookies).
  static Future<String?> _instagramGraphQLWithSession(
    String shortcode, {
    required ({String? csrfToken, String cookieHeader}) session,
  }) async {
    try {
      final client = http.Client();
      final variables = '{"shortcode":"$shortcode"}';
      final queryUrl =
          'https://www.instagram.com/graphql/query/?doc_id=8845758582119845'
          '&variables=${Uri.encodeComponent(variables)}';
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'X-IG-App-ID': '936619743392459',
        'X-Requested-With': 'XMLHttpRequest',
        'X-ASBD-ID': '129477',
        'Origin': 'https://www.instagram.com',
        'Referer': 'https://www.instagram.com/p/$shortcode/',
      };
      if (session.csrfToken != null) {
        headers['X-CSRFToken'] = session.csrfToken!;
      }
      if (session.cookieHeader.isNotEmpty) {
        headers['Cookie'] = session.cookieHeader;
      }
      final response = await client
          .get(Uri.parse(queryUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();
      if (response.statusCode != 200) return null;
      return _igExtractVideoFromJson(response.body);
    } catch (e) {
      debugPrint('[VideoDown] IG GraphQL session error: $e');
      return null;
    }
  }

  /// Endpoint ?__a=1&__d=dis (JSON direto sem GraphQL).
  static Future<String?> _instagramJsonEndpoint(
    String postUrl, {
    required ({String? csrfToken, String cookieHeader}) session,
  }) async {
    try {
      final sep = postUrl.endsWith('/') ? '?' : '&';
      final aUrl = '$postUrl${sep}__a=1&__d=dis';
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
        'X-IG-App-ID': '936619743392459',
      };
      if (session.csrfToken != null) {
        headers['X-CSRFToken'] = session.csrfToken!;
      }
      if (session.cookieHeader.isNotEmpty) {
        headers['Cookie'] = session.cookieHeader;
      }
      final response = await http
          .get(Uri.parse(aUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _igExtractVideoFromJson(response.body);
    } catch (e) {
      debugPrint('[VideoDown] IG __a=1 error: $e');
      return null;
    }
  }

  /// Scraping desktop com sessão real.
  static Future<String?> _instagramScrapeWithSession(
    String postUrl, {
    required ({String? csrfToken, String cookieHeader}) session,
  }) async {
    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9',
        'Accept-Language': 'en-US,en;q=0.9',
      };
      if (session.cookieHeader.isNotEmpty) {
        headers['Cookie'] = session.cookieHeader;
      }
      final response = await http
          .get(Uri.parse(postUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _igExtractVideoFromHtml(response.body);
    } catch (e) {
      debugPrint('[VideoDown] IG scraping session error: $e');
      return null;
    }
  }

  /// Scraping mobile (sem sessão).
  static Future<String?> _instagramMobileScrape(String cleanUrl) async {
    try {
      final response = await http.get(Uri.parse(cleanUrl), headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _igExtractVideoFromHtml(response.body);
    } catch (e) {
      debugPrint('[VideoDown] IG mobile scrape error: $e');
      return null;
    }
  }

  /// Scraping Googlebot.
  static Future<String?> _instagramOgVideoScrape(String cleanUrl) async {
    try {
      final response = await http.get(Uri.parse(cleanUrl), headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _igExtractVideoFromHtml(response.body);
    } catch (e) {
      debugPrint('[VideoDown] IG og:video scrape error: $e');
      return null;
    }
  }

  /// Extrai URL de vídeo de resposta JSON (GraphQL ou __a=1).
  static String? _igExtractVideoFromJson(String body) {
    // video_url (principal)
    final v1 = RegExp(r'"video_url"\s*:\s*"([^"]+)"', caseSensitive: false)
        .firstMatch(body);
    if (v1 != null) return _decodeHtmlEntity(v1.group(1)!);
    // video_versions array
    final v2 = RegExp(
            r'"video_versions"\s*:\s*\[[^\]]*\{[^}]*"url"\s*:\s*"([^"]+)"',
            caseSensitive: false)
        .firstMatch(body);
    if (v2 != null) return _decodeHtmlEntity(v2.group(1)!);
    // playback_video_uri
    final v3 =
        RegExp(r'"playback_video_uri"\s*:\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(body);
    if (v3 != null) return _decodeHtmlEntity(v3.group(1)!);
    return null;
  }

  /// Extrai URL de vídeo de HTML (og:video + JSON embutido).
  static String? _igExtractVideoFromHtml(String html) {
    final og = _extractOgVideoUrl(html);
    if (og != null && og.isNotEmpty) return og;
    return _igExtractVideoFromJson(html);
  }

  /// Retorna a primeira URL não-nula entre várias tentativas em paralelo.
  static Future<String?> _raceFirstUrl(List<Future<String?>> futures) async {
    if (futures.isEmpty) return null;
    final completer = Completer<String?>();
    var pending = futures.length;
    for (final f in futures) {
      unawaited(f.then((v) {
        final url = (v ?? '').trim();
        if (url.isNotEmpty &&
            url.startsWith('http') &&
            !completer.isCompleted) {
          completer.complete(url);
        }
      }).catchError((_) {
        // ignora falhas individuais
      }).whenComplete(() {
        pending--;
        if (pending <= 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }));
    }
    return completer.future.timeout(
      const Duration(seconds: 22),
      onTimeout: () => null,
    );
  }

  /// Resolve short links (vm.tiktok / vt.tiktok / fb.watch) seguindo redirects.
  static Future<String> _resolveRedirectUrl(String url) async {
    final u = url.trim();
    final lower = u.toLowerCase();
    final needsResolve = lower.contains('vm.tiktok.com') ||
        lower.contains('vt.tiktok.com') ||
        lower.contains('fb.watch') ||
        lower.contains('fb.com/') ||
        RegExp(r'tiktok\.com/t/').hasMatch(lower);
    if (!needsResolve) return u;
    try {
      final client = http.Client();
      try {
        var current = Uri.parse(u);
        for (var hop = 0; hop < 8; hop++) {
          final req = http.Request('GET', current)
            ..followRedirects = false
            ..headers.addAll({
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
              'Accept': 'text/html,*/*',
            });
          final res =
              await client.send(req).timeout(const Duration(seconds: 10));
          if (res.statusCode >= 300 && res.statusCode < 400) {
            final loc = res.headers['location'];
            if (loc == null || loc.isEmpty) break;
            current = Uri.parse(loc).isAbsolute
                ? Uri.parse(loc)
                : current.resolve(loc);
            continue;
          }
          return current.toString();
        }
        return current.toString();
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[VideoDown] resolveRedirect: $e');
      return u;
    }
  }

  /// Cobalt API — instâncias em paralelo (primeira que responder ganha).
  static Future<String?> _cobaltExtract(String mediaUrl) {
    const instances = [
      'https://api.cobalt.tools',
      'https://cobalt-api.ayo.tf',
      'https://cobalt.minaev.su',
      'https://dlapi.miichelle.moe',
      'https://cblt.fariz.dev',
      'https://api.cobalt.tacohitbox.com',
    ];
    return _raceFirstUrl([
      for (final base in instances) _cobaltTryOne(base, mediaUrl),
    ]);
  }

  static Future<String?> _cobaltTryOne(String base, String mediaUrl) async {
    try {
      final isNewApi = !base.contains('tacohitbox');
      final endpoint = isNewApi ? '$base/' : '$base/api/json';
      final bodyMap = isNewApi
          ? {
              'url': mediaUrl,
              'downloadMode': 'auto',
              'videoQuality': '1080',
            }
          : {
              'url': mediaUrl,
              'vQuality': '1080',
            };
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            body: jsonEncode(bodyMap),
          )
          .timeout(const Duration(seconds: 14));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      String? videoUrl;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final u = (decoded['url'] ??
                  decoded['tunnel'] ??
                  (decoded['picker'] is List &&
                          (decoded['picker'] as List).isNotEmpty
                      ? ((decoded['picker'] as List).first is Map
                          ? (decoded['picker'] as List).first['url']
                          : null)
                      : null) ??
                  '')
              .toString()
              .trim();
          if (u.startsWith('http')) videoUrl = u;
        }
      } catch (_) {
        final urlMatch =
            RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(response.body);
        if (urlMatch != null) videoUrl = urlMatch.group(1);
      }
      if (videoUrl == null || videoUrl.isEmpty) return null;
      videoUrl = _decodeMediaUrl(videoUrl);
      if (!videoUrl.startsWith('http')) return null;
      debugPrint(
        '[VideoDown] Cobalt OK ($base): ${videoUrl.substring(0, videoUrl.length > 70 ? 70 : videoUrl.length)}?',
      );
      return videoUrl;
    } catch (e) {
      debugPrint('[VideoDown] Cobalt error ($base): $e');
      return null;
    }
  }

  /// Download Facebook ? Cobalt + scrape em paralelo.
  static Future<VideoDownloadResult> _downloadFacebook(
    String url,
    bool audioOnly,
    void Function(double)? onProgress,
  ) async {
    try {
      final resolved = await _resolveRedirectUrl(url);
      final cleanUrl = _cleanUrl(resolved);

      final videoUrl = await _raceFirstUrl([
        _cobaltExtract(cleanUrl),
        _facebookMbasicScrape(cleanUrl),
        _facebookMobileScrape(cleanUrl),
        _facebookDesktopScrape(cleanUrl),
      ]);

      if (videoUrl == null || videoUrl.isEmpty) {
        throw StateError(
          'Não foi possível extrair o vídeo do Facebook. O vídeo pode ser privado ou o link inválido.',
        );
      }

      return await _downloadDirectFile(
        videoUrl,
        title: 'video_facebook',
        audioOnly: audioOnly,
        onProgress: onProgress,
        referer: 'https://www.facebook.com/',
      );
    } catch (e) {
      debugPrint('[VideoDown] Facebook download error: $e');
      if (e is StateError) rethrow;
      throw StateError(
        'Não foi possível baixar o vídeo do Facebook. Verifique o link.',
      );
    }
  }

  /// Facebook: scraping via mbasic (HTML simplificado com link direto).
  static Future<String?> _facebookMbasicScrape(String url) async {
    try {
      final mbasicUrl = url
          .replaceAll('www.facebook.com', 'mbasic.facebook.com')
          .replaceAll('m.facebook.com', 'mbasic.facebook.com')
          .replaceAll('facebook.com', 'mbasic.facebook.com');
      final response = await http.get(
        Uri.parse(mbasicUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      if (response.statusCode != 200) return null;
      final html = response.body;
      // mbasic tem <a href="/video_redirect/..."> com link direto
      final redirectMatch = RegExp(
        r'href="(/video_redirect/[^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (redirectMatch != null) {
        final redirectUrl =
            'https://mbasic.facebook.com${_decodeHtmlEntity(redirectMatch.group(1)!)}';
        // Segue o redirect para obter URL real
        final realResponse = await http.get(
          Uri.parse(redirectUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36',
          },
        );
        if (realResponse.statusCode == 200 ||
            (realResponse.statusCode >= 300 && realResponse.statusCode < 400)) {
          // Pega URL do vídeo do redirect ou do body
          final realUrl = _extractVideoUrlFromHtml(realResponse.body);
          if (realUrl != null) return realUrl;
        }
      }
      // Tenta extrair direto do HTML
      return _extractFacebookVideoUrl(html);
    } catch (e) {
      debugPrint('[VideoDown] Facebook mbasic error: $e');
      return null;
    }
  }

  /// Facebook: scraping com User-Agent mobile.
  static Future<String?> _facebookMobileScrape(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Site': 'none',
        },
      );
      if (response.statusCode != 200) return null;
      return _extractFacebookVideoUrl(response.body);
    } catch (e) {
      debugPrint('[VideoDown] Facebook mobile error: $e');
      return null;
    }
  }

  /// Facebook: scraping com User-Agent desktop.
  static Future<String?> _facebookDesktopScrape(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Site': 'none',
          'Sec-Fetch-Mode': 'navigate',
        },
      );
      if (response.statusCode != 200) return null;
      return _extractFacebookVideoUrl(response.body);
    } catch (e) {
      debugPrint('[VideoDown] Facebook desktop error: $e');
      return null;
    }
  }

  /// Extrai URL de vídeo de HTML genérico.
  static String? _extractVideoUrlFromHtml(String html) {
    // browser_native_hd_url / browser_native_sd_url
    final nativeHd = RegExp(
      r'"browser_native_hd_url"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (nativeHd != null) return _decodeHtmlEntity(nativeHd.group(1)!);

    final nativeSd = RegExp(
      r'"browser_native_sd_url"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (nativeSd != null) return _decodeHtmlEntity(nativeSd.group(1)!);

    // Fallback para métodos padrão
    return _extractFacebookVideoUrl(html);
  }

  static String? _extractOgVideoUrl(String html) {
    // Find <meta> tag containing og:video
    final metaRe = RegExp('<meta[^>]*og:video[^>]*>', caseSensitive: false);
    for (final m in metaRe.allMatches(html)) {
      final tag = m.group(0)!;
      final urlRe = RegExp('content="([^"]+)"', caseSensitive: false);
      final u = urlRe.firstMatch(tag);
      if (u != null) return _decodeHtmlEntity(u.group(1)!);
    }

    // Try video_url in JSON
    final jsonMatch = RegExp(
      '"video_url"\\s*:\\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (jsonMatch != null) return _decodeHtmlEntity(jsonMatch.group(1)!);

    return null;
  }

  static String? _extractFacebookVideoUrl(String html) {
    // Try browser_native_hd_url
    final nativeHd = RegExp(
      r'"browser_native_hd_url"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (nativeHd != null) return _decodeHtmlEntity(nativeHd.group(1)!);

    // Try browser_native_sd_url
    final nativeSd = RegExp(
      r'"browser_native_sd_url"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (nativeSd != null) return _decodeHtmlEntity(nativeSd.group(1)!);

    // Try hd_src
    final hdMatch = RegExp(
      r'"hd_src"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (hdMatch != null) return _decodeHtmlEntity(hdMatch.group(1)!);

    // Try sd_src
    final sdMatch = RegExp(
      r'"sd_src"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (sdMatch != null) return _decodeHtmlEntity(sdMatch.group(1)!);

    // Try hd_src_no_watermark
    final hdNw = RegExp(
      r'"hd_src_no_watermark"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (hdNw != null) return _decodeHtmlEntity(hdNw.group(1)!);

    // Try sd_src_no_watermark
    final sdNw = RegExp(
      r'"sd_src_no_watermark"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (sdNw != null) return _decodeHtmlEntity(sdNw.group(1)!);

    // Try playable_url
    final playable = RegExp(
      r'"playable_url"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (playable != null) return _decodeHtmlEntity(playable.group(1)!);

    // Try playable_url_quality_hd
    final playableHd = RegExp(
      r'"playable_url_quality_hd"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (playableHd != null) return _decodeHtmlEntity(playableHd.group(1)!);

    // Try og:video
    return _extractOgVideoUrl(html);
  }

  /// Download TikTok — Cobalt paralelo + scrape reforçado + Referer no CDN.
  static Future<VideoDownloadResult> _downloadTikTok(
    String url,
    bool audioOnly,
    void Function(double)? onProgress,
  ) async {
    try {
      final resolved = await _resolveRedirectUrl(url);
      final cleanUrl = _cleanUrl(resolved);

      final videoUrl = await _raceFirstUrl([
        _cobaltExtract(cleanUrl),
        _tikTokScrapeVideoUrl(cleanUrl),
        // Segunda passagem Cobalt com URL original (às vezes short link resolve melhor no Cobalt)
        if (resolved != url.trim()) _cobaltExtract(_cleanUrl(url.trim())),
      ]);

      if (videoUrl == null || videoUrl.isEmpty) {
        throw StateError(
          'Não foi possível extrair o vídeo do TikTok. Verifique se o vídeo é público e o link está completo.',
        );
      }

      String title = 'video_tiktok';
      try {
        final meta = await http
            .get(
              Uri.parse(cleanUrl),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
                'Accept': 'text/html',
              },
            )
            .timeout(const Duration(seconds: 8));
        final titleMatch = RegExp(
          r'<title>([^<]+)</title>',
          caseSensitive: false,
        ).firstMatch(meta.body);
        if (titleMatch != null) {
          title =
              titleMatch.group(1)!.trim().replaceAll(' | TikTok', '').trim();
          if (title.isEmpty) title = 'video_tiktok';
          if (title.length > 80) title = title.substring(0, 80);
        }
      } catch (_) {}

      return await _downloadDirectFile(
        videoUrl,
        title: title,
        audioOnly: audioOnly,
        onProgress: onProgress,
        referer: 'https://www.tiktok.com/',
      );
    } catch (e) {
      debugPrint('[VideoDown] TikTok download error: $e');
      if (e is StateError) rethrow;
      throw StateError(
        'Não foi possível baixar o vídeo do TikTok. Verifique o link.',
      );
    }
  }

  /// Scrape TikTok HTML (mobile + desktop) ? downloadAddr / playAddr / og:video.
  static Future<String?> _tikTokScrapeVideoUrl(String url) async {
    Future<String?> tryOnce(Map<String, String> headers) async {
      try {
        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) return null;
        return _extractTikTokVideoUrl(response.body);
      } catch (e) {
        debugPrint('[VideoDown] TikTok scrape: $e');
        return null;
      }
    }

    return _raceFirstUrl([
      tryOnce({
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,pt-BR;q=0.8',
        'Referer': 'https://www.tiktok.com/',
      }),
      tryOnce({
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://www.tiktok.com/',
      }),
    ]);
  }

  static String? _extractTikTokVideoUrl(String html) {
    // 1) og:video
    var videoUrl = _extractOgVideoUrl(html);
    if (videoUrl != null && videoUrl.isNotEmpty) return _decodeMediaUrl(videoUrl);

    // 2) downloadAddr (preferido — sem marca d'água quando disponível)
    final patterns = <RegExp>[
      RegExp(r'"downloadAddr"\s*:\s*"([^"]+)"', caseSensitive: false),
      RegExp(r'"playAddr"\s*:\s*"([^"]+)"', caseSensitive: false),
      RegExp(r'"play_addr"[^}]*"url_list"\s*:\s*\[\s*"([^"]+)"',
          caseSensitive: false),
      RegExp(r'"download_addr"[^}]*"url_list"\s*:\s*\[\s*"([^"]+)"',
          caseSensitive: false),
      RegExp(r'"contentUrl"\s*:\s*"([^"]+\.mp4[^"]*)"', caseSensitive: false),
      RegExp(r'"(https:\\?/\\?/[^"]*tiktokcdn[^"]+\.mp4[^"]*)"',
          caseSensitive: false),
      RegExp(r'(https://[^"\s\\]+tiktokcdn[^"\s\\]+\.mp4[^"\s\\]*)',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null) {
        final decoded = _decodeMediaUrl(m.group(1)!);
        if (decoded.startsWith('http')) return decoded;
      }
    }
    return null;
  }

  /// Download genérico — tenta extrair vídeo de qualquer URL via og:video.
  static Future<VideoDownloadResult> _downloadGeneric(
    String url,
    bool audioOnly,
    void Function(double)? onProgress,
  ) async {
    try {
      final cleanUrl = _cleanUrl(url);

      // Se a URL já termina com extensão de vídeo, baixa direto
      final lower = cleanUrl.toLowerCase();
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.m4v')) {
        return await _downloadDirectFile(
          cleanUrl,
          title: 'video',
          audioOnly: audioOnly,
          onProgress: onProgress,
        );
      }

      // Busca a página e tenta extrair og:video
      final response = await http.get(
        Uri.parse(cleanUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );

      if (response.statusCode != 200) {
        throw StateError('Site retornou código ${response.statusCode}.');
      }

      final html = response.body;
      String? videoUrl;

      // 1) og:video
      videoUrl = _extractOgVideoUrl(html);

      // 2) twitter:player:stream
      if (videoUrl == null || videoUrl.isEmpty) {
        final twMatch = RegExp(
          '<meta[^>]*twitter:player:stream[^>]*content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(html);
        if (twMatch != null) videoUrl = _decodeHtmlEntity(twMatch.group(1)!);
      }

      // 3) <source src="..."> em <video>
      if (videoUrl == null || videoUrl.isEmpty) {
        final srcMatch = RegExp(
          r'<source[^>]*src="([^"]+\.mp4[^"]*)"',
          caseSensitive: false,
        ).firstMatch(html);
        if (srcMatch != null) videoUrl = _decodeHtmlEntity(srcMatch.group(1)!);
      }

      // 4) Qualquer .mp4 no HTML
      if (videoUrl == null || videoUrl.isEmpty) {
        final mp4Match = RegExp(
          r'(https?://[^"\s]+\.mp4[^"\s]*)',
          caseSensitive: false,
        ).firstMatch(html);
        if (mp4Match != null) videoUrl = _decodeHtmlEntity(mp4Match.group(1)!);
      }

      if (videoUrl == null || videoUrl.isEmpty) {
        throw StateError(
          'Não foi possível encontrar um vídeo neste link. Verifique a URL.',
        );
      }

      // Extrai título da página
      String title = 'video';
      final titleMatch = RegExp(
        r'<title>([^<]+)</title>',
        caseSensitive: false,
      ).firstMatch(html);
      if (titleMatch != null) {
        title = titleMatch.group(1)!.trim();
        if (title.length > 80) title = title.substring(0, 80);
      }

      return await _downloadDirectFile(
        videoUrl,
        title: title,
        audioOnly: audioOnly,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[VideoDown] Generic download error: $e');
      if (e is StateError) rethrow;
      throw StateError(
        'Não foi possível baixar o vídeo. Verifique o link e tente novamente.',
      );
    }
  }

  static String _decodeHtmlEntity(String s) => _decodeMediaUrl(s);

  /// Decodifica URL escapada (HTML entities + JSON unicode + bars).
  static String _decodeMediaUrl(String raw) {
    var s = raw.trim();
    // Unicode escapes comuns no JSON do TikTok/IG/FB
    s = s.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    s = s
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003F', '?')
        .replaceAll(r'\/', '/')
        .replaceAll('\\/', '/')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('%3A', ':')
        .replaceAll('%2F', '/');
    return s;
  }

  static Future<VideoDownloadResult> _downloadDirectFile(
    String fileUrl, {
    required String title,
    required bool audioOnly,
    void Function(double)? onProgress,
    String? referer,
  }) async {
    final decodedUrl = _decodeMediaUrl(fileUrl);
    final client = http.Client();
    try {
      Future<http.StreamedResponse> sendGet(Map<String, String> headers) {
        final req = http.Request('GET', Uri.parse(decodedUrl))
          ..headers.addAll(headers);
        return client.send(req).timeout(const Duration(seconds: 90));
      }

      final baseHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
        if (referer != null && referer.isNotEmpty)
          'Origin': referer.replaceAll(RegExp(r'/$'), ''),
      };

      var response = await sendGet(baseHeaders);

      // CDN TikTok/IG às vezes exige Referer; tenta de novo com fallback.
      if ((response.statusCode == 403 || response.statusCode == 401) &&
          (referer == null || referer.isEmpty)) {
        response = await sendGet({
          ...baseHeaders,
          'Referer': 'https://www.tiktok.com/',
        });
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw StateError('Download falhou (HTTP ${response.statusCode}).');
      }

      final total = response.contentLength ?? 0;
      final tmpDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = audioOnly ? 'm4a' : 'mp4';
      final outPath = '${tmpDir.path}/ct_dl_$stamp.$ext';
      final file = File(outPath);
      final sink = file.openWrite();

      var downloaded = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (total > 0) onProgress?.call(downloaded / total);
      }
      await sink.flush();
      await sink.close();

      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}

      final safeName = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      return VideoDownloadResult(
        bytes: bytes,
        fileName: '${safeName.isEmpty ? "video" : safeName}.$ext',
        mimeType: audioOnly ? 'audio/mp4' : 'video/mp4',
        title: title,
        isAudioOnly: audioOnly,
      );
    } finally {
      client.close();
    }
  }

  /// Libera recursos.
  static void dispose() {
    _yt.close();
  }
}
