import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaPhotoUrls,
        eventNoticiaThumbStoragePath,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        imageUrlFromMap,
        imageUrlsListFromMap,
        isDataImageUrl,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart';

bool _yahwehPostHostedVideoPreloadLayer(String? raw) {
  if (!kIsWeb || raw == null || raw.trim().isEmpty) return false;
  final w = sanitizeImageUrl(raw);
  return looksLikeHostedVideoFileUrl(w);
}

/// URLs/paths utilizáveis como foto no feed (inclui caminhos Storage sem https — painel fazia drop).
List<String> yahwehPostGalleryRefs(Map<String, dynamic> p) {
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
  return out;
}

String? _yahwehPostVideoPosterUrl(Map<String, dynamic>? p) {
  if (p == null) return null;
  final t = eventNoticiaDisplayVideoThumbnailUrl(p);
  if (t == null || t.isEmpty) return null;
  final s = sanitizeImageUrl(t);
  if (!isValidImageUrl(s) || looksLikeHostedVideoFileUrl(s)) return null;
  return s;
}

/// Card estilo Instagram para Avisos/Eventos no site público.
/// Com [postFirestoreData], resolve [imageStoragePath] / thumb no Storage antes de exibir (site público).
class YahwehPostCard extends StatelessWidget {
  final bool isEvento;
  final String title;
  final String body;
  final String eventDateStr;
  final String createdWhen;
  final String coverUrl;
  /// Documento Firestore do post — resolução assíncrona de capa (path + URL).
  final Map<String, dynamic>? postFirestoreData;
  /// Exibir faixa de mídia (capa/thumb); calculado no pai com [eventNoticiaPostHasFeedCoverRow].
  final bool showCoverStrip;
  /// Web: URL de vídeo hospedado (ex. Storage) para preview HTML quando a imagem não resolve.
  final String? webHostedVideoUrl;
  /// Chave estável para [PremiumHtmlFeedVideo] (ex.: id do documento Firestore).
  final String feedMediaVisibilityKey;
  /// Ex.: vídeo sem capa ou link externo — botão “Assistir” abaixo do texto.
  final bool showPlayButton;
  final bool showVideoOverlay;
  final int extraPhotoCount;
  final int memCacheW;
  final int memCacheH;
  final VoidCallback onShare;
  final Future<void> Function() onOpenVideo;

  const YahwehPostCard({
    super.key,
    required this.isEvento,
    required this.title,
    required this.body,
    required this.eventDateStr,
    required this.createdWhen,
    required this.coverUrl,
    this.postFirestoreData,
    required this.showCoverStrip,
    this.webHostedVideoUrl,
    this.feedMediaVisibilityKey = '',
    required this.showPlayButton,
    required this.showVideoOverlay,
    this.extraPhotoCount = 0,
    required this.memCacheW,
    required this.memCacheH,
    required this.onShare,
    required this.onOpenVideo,
  });

  Widget _coverImage(String url) {
    final u = sanitizeImageUrl(url);
    if (looksLikeHostedVideoFileUrl(u)) return _broken();
    final storageLike = isFirebaseStorageHttpUrl(u) ||
        firebaseStorageMediaUrlLooksLike(u) ||
        u.toLowerCase().startsWith('gs://');
    if (!isValidImageUrl(u) && !isDataImageUrl(u) && !storageLike) {
      return _broken();
    }
    final ph = YahwehPremiumFeedShimmer.mediaCover();
    final err = _broken();
    if (isDataImageUrl(u)) {
      return SafeNetworkImage(
        imageUrl: u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: memCacheW,
        memCacheHeight: memCacheH,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: false,
      );
    }
    // Caminho `igrejas/.../noticias/...` ou `gs://` sem https: [SafeNetworkImage] rejeita —
    // [FreshFirebaseStorageImage] resolve via SDK e token fresco.
    if (storageLike) {
      return FreshFirebaseStorageImage(
        imageUrl: u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: memCacheW,
        memCacheHeight: memCacheH,
        placeholder: ph,
        errorWidget: err,
      );
    }
    return SafeNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: memCacheW,
      memCacheHeight: memCacheH,
      placeholder: ph,
      errorWidget: err,
      skipFreshDisplayUrl: false,
    );
  }

  Widget _broken() {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(20),
      child: Image.asset(
        'assets/LOGO_GESTAO_YAHWEH.png',
        fit: BoxFit.contain,
        width: 120,
        height: 120,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded,
            size: 46, color: Color(0xFFCBD5E1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = postFirestoreData;
    final gallery = data != null ? yahwehPostGalleryRefs(data) : <String>[];
    final wvClean = sanitizeImageUrl((webHostedVideoUrl ?? '').trim());
    final webEmbedVideo =
        kIsWeb && wvClean.isNotEmpty && looksLikeHostedVideoFileUrl(wvClean);

    return YahwehInstagramHoverCard(
      child: ChurchPublicPremiumFeedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PostTitleStrip(
              isEvento: isEvento,
              title: title,
              eventDateStr: eventDateStr,
              createdWhen: createdWhen,
              onShare: onShare,
            ),
            if (showCoverStrip)
              InkWell(
                onTap: webEmbedVideo
                    ? null
                    : (gallery.length > 1
                        ? null
                        : (showVideoOverlay
                            ? () async {
                                await onOpenVideo();
                              }
                            : () {
                                final u = sanitizeImageUrl(coverUrl);
                                if (isValidImageUrl(u)) {
                                  showYahwehFullscreenZoomableImage(context,
                                      imageUrl: u);
                                }
                              })),
                child: ChurchPublicConstrainedMedia(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFE2E8F0),
                                Colors.white.withValues(alpha: 0.96),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_yahwehPostHostedVideoPreloadLayer(webHostedVideoUrl) &&
                          !webEmbedVideo)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.02,
                              child: PremiumHtmlFeedVideo(
                                videoUrl: sanitizeImageUrl(webHostedVideoUrl!),
                                visibilityKey:
                                    '${feedMediaVisibilityKey}_preload',
                                showControls: false,
                                startLoadingImmediately: true,
                              ),
                            ),
                          ),
                        ),
                      if (webEmbedVideo)
                        Positioned.fill(
                          child: PremiumHtmlFeedVideo(
                            videoUrl: wvClean,
                            visibilityKey: feedMediaVisibilityKey,
                            showControls: true,
                            posterUrl: _yahwehPostVideoPosterUrl(data),
                            startLoadingImmediately: true,
                            videoObjectFitContain: false,
                          ),
                        )
                      else if (gallery.length > 1 && data != null)
                        _YahwehPublicGalleryStack(
                          post: data,
                          urls: gallery,
                          memCacheW: memCacheW,
                          memCacheH: memCacheH,
                        )
                      else if (data != null)
                        _ResolvedNoticiaCover(
                          post: data,
                          coverHint: coverUrl,
                          memCacheW: memCacheW,
                          memCacheH: memCacheH,
                          webHostedVideoUrl: webHostedVideoUrl,
                          feedMediaVisibilityKey: feedMediaVisibilityKey,
                          onOpenVideo: onOpenVideo,
                          fallbackBuild: _coverImage,
                        )
                      else
                        (coverUrl.isNotEmpty
                            ? _coverImage(coverUrl)
                            : YahwehPremiumFeedShimmer.mediaCover()),
                      if (showVideoOverlay && !webEmbedVideo)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.45),
                              ],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ChurchPublicPremiumPlayOrb(diameter: 62),
                              const SizedBox(height: 12),
                              Text(
                                'Assistir vídeo',
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.98),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                  shadows: const [
                                    Shadow(
                                        blurRadius: 12,
                                        color: Colors.black54),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (extraPhotoCount > 0 && gallery.length <= 1)
                        Positioned(
                          left: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              '+ $extraPhotoCount foto(s)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (body.trim().isNotEmpty)
                    SelectableText(
                      body,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.5,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (showPlayButton) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        await onOpenVideo();
                      },
                      icon: const Icon(Icons.play_circle_filled_rounded,
                          size: 20),
                      label: const Text('Assistir vídeo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _CoverImageBuilder = Widget Function(String url);

/// Resolve capa do post: paths [imageStoragePath] / thumb no Storage + URL https (token).
class _ResolvedNoticiaCover extends StatefulWidget {
  final Map<String, dynamic> post;
  final String coverHint;
  final int memCacheW;
  final int memCacheH;
  final String? webHostedVideoUrl;
  final String feedMediaVisibilityKey;
  final Future<void> Function() onOpenVideo;
  final _CoverImageBuilder fallbackBuild;

  const _ResolvedNoticiaCover({
    required this.post,
    required this.coverHint,
    required this.memCacheW,
    required this.memCacheH,
    this.webHostedVideoUrl,
    this.feedMediaVisibilityKey = '',
    required this.onOpenVideo,
    required this.fallbackBuild,
  });

  @override
  State<_ResolvedNoticiaCover> createState() => _ResolvedNoticiaCoverState();
}

class _ResolvedNoticiaCoverState extends State<_ResolvedNoticiaCover> {
  Future<String?>? _future;

  bool _usableCoverRef(String s) {
    final u = sanitizeImageUrl(s);
    if (u.isEmpty || looksLikeHostedVideoFileUrl(u)) return false;
    if (isDataImageUrl(u)) return true;
    if (isValidImageUrl(u)) return true;
    if (u.toLowerCase().startsWith('gs://')) return true;
    return firebaseStorageMediaUrlLooksLike(u);
  }

  Future<String?> _resolveStorageRef(String refLike) async {
    final norm = sanitizeImageUrl(refLike);
    if (norm.isEmpty) return null;
    final gs = norm.toLowerCase().startsWith('gs://');
    final pathOnly = !isValidImageUrl(norm) &&
        firebaseStorageMediaUrlLooksLike(norm) &&
        !gs;
    final path = pathOnly
        ? normalizeFirebaseStorageObjectPath(
            norm.replaceFirst(RegExp(r'^/+'), ''),
          )
        : null;
    return AppStorageImageService.instance.resolveImageUrl(
      gsUrl: gs ? norm : null,
      storagePath: path,
      imageUrl: (!gs && !pathOnly) ? norm : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant _ResolvedNoticiaCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverHint != widget.coverHint ||
        oldWidget.memCacheW != widget.memCacheW ||
        oldWidget.memCacheH != widget.memCacheH) {
      _future = _resolve();
      return;
    }
    if (!mapEquals(widget.post, oldWidget.post)) {
      _future = _resolve();
    }
  }

  Future<String?> _resolve() async {
    final p = widget.post;
    String? hintNorm;
    final hint = widget.coverHint.trim();
    if (hint.isNotEmpty) {
      final s = sanitizeImageUrl(hint);
      if (_usableCoverRef(s)) {
        hintNorm = s;
      }
    }
    if (hintNorm == null) {
      final fromDoc = eventNoticiaFeedCoverHintUrl(p);
      if (fromDoc.isNotEmpty) {
        final s = sanitizeImageUrl(fromDoc);
        if (_usableCoverRef(s)) {
          hintNorm = s;
        }
      }
    }
    final spImg = eventNoticiaImageStoragePath(p);
    final spThumb = eventNoticiaThumbStoragePath(p);
    for (final sp in <String?>[spImg, spThumb]) {
      if (sp == null || sp.isEmpty) continue;
      final u = await AppStorageImageService.instance.resolveImageUrl(
        storagePath: sp,
        imageUrl: (hintNorm != null && isValidImageUrl(hintNorm))
            ? hintNorm
            : null,
      );
      final c = u != null ? sanitizeImageUrl(u) : '';
      if (c.isNotEmpty && isValidImageUrl(c) && !looksLikeHostedVideoFileUrl(c)) {
        return c;
      }
    }
    if (hintNorm != null) {
      final u = await _resolveStorageRef(hintNorm);
      final c = u != null ? sanitizeImageUrl(u) : '';
      if (c.isNotEmpty && isValidImageUrl(c) && !looksLikeHostedVideoFileUrl(c)) {
        return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            snap.data == null &&
            !snap.hasError) {
          return YahwehPremiumFeedShimmer.mediaCover();
        }
        final resolved = snap.hasError ? null : snap.data;
        if (resolved != null && resolved.isNotEmpty) {
          return widget.fallbackBuild(resolved);
        }
        final h = sanitizeImageUrl(widget.coverHint);
        if (h.isNotEmpty && _usableCoverRef(h)) {
          return widget.fallbackBuild(h);
        }
        final alt = eventNoticiaFeedCoverHintUrl(widget.post);
        final a = sanitizeImageUrl(alt);
        if (a.isNotEmpty && _usableCoverRef(a)) {
          return widget.fallbackBuild(a);
        }
        if (kIsWeb) {
          final rawV = (widget.webHostedVideoUrl ?? '').trim();
          if (rawV.isNotEmpty) {
            final v = sanitizeImageUrl(rawV);
            if (looksLikeHostedVideoFileUrl(v)) {
              return _HostedVideoTapPoster(
                post: widget.post,
                memCacheW: widget.memCacheW,
                memCacheH: widget.memCacheH,
                visibilityKey: widget.feedMediaVisibilityKey,
                onOpenVideo: widget.onOpenVideo,
              );
            }
          }
        }
        return Container(
          alignment: Alignment.center,
          color: const Color(0xFFE2E8F0),
          child: Icon(Icons.perm_media_rounded, size: 48, color: Colors.grey.shade400),
        );
      },
    );
  }
}

/// Web: `<video>` com [preload=auto] e poster (miniatura) — play imediato como no Instagram.
class _HostedVideoTapPoster extends StatelessWidget {
  final Map<String, dynamic> post;
  final int memCacheW;
  final int memCacheH;
  final String visibilityKey;
  final Future<void> Function() onOpenVideo;

  const _HostedVideoTapPoster({
    required this.post,
    required this.memCacheW,
    required this.memCacheH,
    required this.visibilityKey,
    required this.onOpenVideo,
  });

  @override
  Widget build(BuildContext context) {
    var play = (eventNoticiaHostedVideoPlayUrl(post) ?? '').toString().trim();
    if (play.isEmpty) {
      play = (post['videoUrl'] ?? '').toString().trim();
    }
    play = sanitizeImageUrl(play);
    final td = sanitizeImageUrl(
      (eventNoticiaDisplayVideoThumbnailUrl(post) ?? '').toString().trim(),
    );
    final posterOk = isValidImageUrl(td);

    if (!looksLikeHostedVideoFileUrl(play)) {
      return Material(
        color: const Color(0xFF0F172A),
        child: InkWell(
          onTap: () => unawaited(onOpenVideo()),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterOk)
                FreshFirebaseStorageImage(
                  imageUrl: td,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: memCacheW,
                  memCacheHeight: memCacheH,
                  placeholder: YahwehPremiumFeedShimmer.mediaCover(),
                  errorWidget: const SizedBox.shrink(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: posterOk ? 0.38 : 0.62),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
              const Center(
                child: ChurchPublicPremiumPlayOrb(diameter: 62),
              ),
            ],
          ),
        ),
      );
    }

    final vidKey =
        visibilityKey.isNotEmpty ? visibilityKey : play.hashCode.toString();
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PremiumHtmlFeedVideo(
            videoUrl: play,
            visibilityKey: vidKey,
            showControls: true,
            posterUrl: posterOk ? td : null,
            startLoadingImmediately: true,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: 'Tela cheia',
                onPressed: () => unawaited(onOpenVideo()),
                icon: const Icon(Icons.fullscreen_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Galeria horizontal (PageView) no site público — mesma ideia do mural da igreja.
class _YahwehPublicGalleryStack extends StatefulWidget {
  final Map<String, dynamic> post;
  final List<String> urls;
  final int memCacheW;
  final int memCacheH;

  const _YahwehPublicGalleryStack({
    required this.post,
    required this.urls,
    required this.memCacheW,
    required this.memCacheH,
  });

  @override
  State<_YahwehPublicGalleryStack> createState() =>
      _YahwehPublicGalleryStackState();
}

class _YahwehPublicGalleryStackState extends State<_YahwehPublicGalleryStack> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (ctx, idx) {
            final path = eventNoticiaPhotoStoragePathAt(widget.post, idx);
            final url = widget.urls[idx];
            return StableStorageImage(
              storagePath: path,
              imageUrl: url,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              memCacheWidth: widget.memCacheW,
              memCacheHeight: widget.memCacheH,
              placeholder: YahwehPremiumFeedShimmer.mediaCover(),
              errorWidget: ColoredBox(
                color: const Color(0xFFF1F5F9),
                child: Icon(Icons.image_not_supported_outlined,
                    color: Colors.grey.shade400, size: 44),
              ),
            );
          },
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.urls.length,
              (i) => Container(
                width: i == _page ? 8 : 6,
                height: i == _page ? 8 : 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_page + 1}/${widget.urls.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostTitleStrip extends StatelessWidget {
  final bool isEvento;
  final String title;
  final String eventDateStr;
  final String createdWhen;
  final VoidCallback onShare;

  const _PostTitleStrip({
    required this.isEvento,
    required this.title,
    required this.eventDateStr,
    required this.createdWhen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitleOrDate = title.isNotEmpty || eventDateStr.isNotEmpty;
    if (!hasTitleOrDate && createdWhen.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!hasTitleOrDate) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isEvento
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isEvento ? 'Evento' : 'Aviso',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isEvento
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF6D28D9),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Compartilhar',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: ThemeCleanPremium.minTouchTarget,
                minHeight: ThemeCleanPremium.minTouchTarget,
              ),
              icon: Icon(Icons.share_rounded,
                  size: 20, color: Colors.grey.shade600),
              onPressed: onShare,
            ),
            Text(
              createdWhen,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    const kCardRadius = 16.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(kCardRadius),
          topRight: Radius.circular(kCardRadius),
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isEvento
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isEvento ? 'Evento' : 'Aviso',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isEvento
                        ? const Color(0xFFC2410C)
                        : const Color(0xFF2563EB),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Compartilhar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: ThemeCleanPremium.minTouchTarget,
                  minHeight: ThemeCleanPremium.minTouchTarget,
                ),
                icon: Icon(
                  Icons.ios_share_rounded,
                  size: 22,
                  color: Colors.grey.shade600,
                ),
                onPressed: onShare,
              ),
              if (createdWhen.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    createdWhen,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.25,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
          ],
          if (eventDateStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event_rounded, size: 15, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    eventDateStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
