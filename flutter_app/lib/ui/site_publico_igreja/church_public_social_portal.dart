import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaPhotoUrls,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show shareChurchNoticiaForOgPreview;
import 'package:gestao_yahweh/ui/widgets/yahweh_social_post_bar.dart';

/// Miniatura rápida quando o post tem [media_info] (mural Instagram).
String? churchPublicPostThumbUrl(Map<String, dynamic> p) {
  final mi = p['media_info'];
  if (mi is Map) {
    for (final k in ['url_thumb', 'urlThumb', 'url_original', 'urlOriginal']) {
      final u = sanitizeImageUrl((mi[k] ?? '').toString());
      if (u.isNotEmpty && isValidImageUrl(u)) return u;
    }
  }
  final img = sanitizeImageUrl(
      (p['imageUrl'] ?? p['imagemUrl'] ?? p['defaultImageUrl'] ?? '')
          .toString());
  if (img.isNotEmpty && isValidImageUrl(img)) return img;
  return null;
}

/// Barra de navegação fixa (abaixo da AppBar): âncoras da página.
class ChurchPublicPortalNavSliver extends StatelessWidget {
  final Color accent;
  final VoidCallback onInicio;
  final VoidCallback onMural;
  final VoidCallback onEventos;
  final VoidCallback onAcessarSistema;

  const ChurchPublicPortalNavSliver({
    super.key,
    required this.accent,
    required this.onInicio,
    required this.onMural,
    required this.onEventos,
    required this.onAcessarSistema,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PortalNavDelegate(
        child: Material(
          color: Colors.white.withValues(alpha: 0.94),
          elevation: 0,
          shadowColor: const Color(0x12000000),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 20 : 10,
              vertical: 8,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _NavChip(
                              label: 'Início',
                              onTap: onInicio,
                              accent: accent,
                            ),
                            _NavChip(
                              label: 'Mural',
                              onTap: onMural,
                              accent: accent,
                            ),
                            _NavChip(
                              label: 'Eventos',
                              onTap: onEventos,
                              accent: accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: onAcessarSistema,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          44,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Acessar Sistema',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color accent;

  const _NavChip({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalNavDelegate extends SliverPersistentHeaderDelegate {
  _PortalNavDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PortalNavDelegate oldDelegate) =>
      oldDelegate.child != child;
}

/// Grade estilo Instagram + modal desktop (mídia | texto).
class ChurchPublicSocialFeedGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String igrejaId;
  final String churchSlug;
  final Color accent;
  final int memCacheW;
  final int memCacheH;
  final Future<void> Function(
    BuildContext context,
    Map<String, dynamic> post,
    String postId,
  ) onOpenHostedVideo;

  const ChurchPublicSocialFeedGrid({
    super.key,
    required this.docs,
    required this.igrejaId,
    required this.churchSlug,
    required this.accent,
    required this.memCacheW,
    required this.memCacheH,
    required this.onOpenHostedVideo,
  });

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        return churchPublicSocialFeedTile(
          context: context,
          doc: docs[i],
          igrejaId: igrejaId,
          churchSlug: churchSlug,
          accent: accent,
          memCacheW: memCacheW,
          memCacheH: memCacheH,
          onOpenHostedVideo: onOpenHostedVideo,
        );
      },
    );
  }
}

/// Um cartão do feed público (altura conforme a largura) — para [SliverList] lazy.
Widget churchPublicSocialFeedTile({
  required BuildContext context,
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required String igrejaId,
  required String churchSlug,
  required Color accent,
  required int memCacheW,
  required int memCacheH,
  required Future<void> Function(
    BuildContext context,
    Map<String, dynamic> post,
    String postId,
  ) onOpenHostedVideo,
}) {
  return LayoutBuilder(
    builder: (context, c) {
      final tileH = (c.maxWidth * 0.92).clamp(240.0, 420.0);
      return SizedBox(
        height: tileH,
        child: _SocialGridTile(
          postId: doc.id,
          post: doc.data(),
          igrejaId: igrejaId,
          churchSlug: churchSlug,
          accent: accent,
          memCacheW: memCacheW,
          memCacheH: memCacheH,
          onOpenHostedVideo: onOpenHostedVideo,
          onOpenDetail: () => unawaited(ChurchPublicPostLightbox.show(
                context,
                doc: doc,
                igrejaId: igrejaId,
                churchSlug: churchSlug,
                accent: accent,
                memCacheW: memCacheW,
                memCacheH: memCacheH,
                onOpenHostedVideo: onOpenHostedVideo,
              )),
        ),
      );
    },
  );
}

class _SocialGridTile extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> post;
  final String igrejaId;
  final String churchSlug;
  final Color accent;
  final int memCacheW;
  final int memCacheH;
  final VoidCallback onOpenDetail;
  final Future<void> Function(
    BuildContext context,
    Map<String, dynamic> post,
    String postId,
  ) onOpenHostedVideo;

  const _SocialGridTile({
    required this.postId,
    required this.post,
    required this.igrejaId,
    required this.churchSlug,
    required this.accent,
    required this.memCacheW,
    required this.memCacheH,
    required this.onOpenDetail,
    required this.onOpenHostedVideo,
  });

  @override
  State<_SocialGridTile> createState() => _SocialGridTileState();
}

class _SocialGridTileState extends State<_SocialGridTile> {
  bool _hover = false;

  Future<void> _copyLink(BuildContext context) async {
    final url = AppConstants.shareNoticiaPublicUrl(
        widget.churchSlug, widget.postId);
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Link copiado — cole no WhatsApp.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final type = (p['type'] ?? 'aviso').toString();
    final isEvento = type == 'evento';
    final title = (p['title'] ?? '').toString();
    final hosted =
        sanitizeImageUrl((eventNoticiaHostedVideoPlayUrl(p) ?? '').trim());
    final ext = eventNoticiaExternalVideoUrl(p);
    final legacy = (p['videoUrl'] ?? '').toString().trim();
    final hasVideo = hosted.isNotEmpty ||
        (ext != null && ext.isNotEmpty) ||
        legacy.isNotEmpty;
    final playWeb = kIsWeb &&
        hosted.isNotEmpty &&
        looksLikeHostedVideoFileUrl(hosted);
    final thumb = churchPublicPostThumbUrl(p);
    final cover = eventNoticiaFeedCoverHintUrl(p);
    final displayRef = (thumb != null && thumb.isNotEmpty) ? thumb : cover;
    final path = eventNoticiaPhotoStoragePathAt(p, 0) ??
        eventNoticiaImageStoragePath(p);
    final poster = sanitizeImageUrl(
        (eventNoticiaDisplayVideoThumbnailUrl(p) ?? '').trim());
    final badge = isEvento ? 'Evento' : 'Aviso';

    Widget mediaChild;
    if (playWeb) {
      mediaChild = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (poster.isNotEmpty &&
                (isValidImageUrl(poster) ||
                    isFirebaseStorageHttpUrl(poster) ||
                    firebaseStorageMediaUrlLooksLike(poster)))
              _gridImageOrStable(
                displayRef: poster,
                path: null,
                memW: widget.memCacheW,
                memH: widget.memCacheH,
              )
            else if (displayRef.isNotEmpty)
              _gridImageOrStable(
                displayRef: displayRef,
                path: path,
                memW: widget.memCacheW,
                memH: widget.memCacheH,
              )
            else
              Container(color: const Color(0xFFE5E7EB)),
            PremiumHtmlFeedVideo(
              videoUrl: hosted,
              visibilityKey: 'pubgrid_${widget.postId}',
              showControls: false,
              posterUrl: poster.isNotEmpty ? poster : null,
              startLoadingImmediately: true,
              videoObjectFitContain: false,
            ),
          ],
        ),
      );
    } else if (hasVideo && displayRef.isNotEmpty) {
      mediaChild = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _gridImageOrStable(
              displayRef: displayRef,
              path: path,
              memW: widget.memCacheW,
              memH: widget.memCacheH,
            ),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 52, color: Colors.white70),
            ),
          ],
        ),
      );
    } else if (displayRef.isNotEmpty || (path != null && path.isNotEmpty)) {
      mediaChild = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _gridImageOrStable(
          displayRef: displayRef,
          path: path,
          memW: widget.memCacheW,
          memH: widget.memCacheH,
        ),
      );
    } else {
      mediaChild = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: const Color(0xFFF1F5F9),
          child: Center(
            child: Icon(Icons.article_rounded,
                size: 40, color: widget.accent.withValues(alpha: 0.35)),
          ),
        ),
      );
    }

    final tile = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: const Color(0x10000000),
      child: InkWell(
        onTap: () {
          if (playWeb) {
            widget.onOpenDetail();
            return;
          }
          if (hasVideo &&
              (hosted.isNotEmpty ||
                  (ext != null && ext.isNotEmpty) ||
                  legacy.isNotEmpty)) {
            unawaited(widget.onOpenHostedVideo(
                context, p, widget.postId));
            return;
          }
          widget.onOpenDetail();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(
              scale: _hover ? 1.04 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _hover ? 1.0 : 0.97,
                duration: const Duration(milliseconds: 200),
                child: mediaChild,
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Copiar link',
                  icon: Icon(Icons.near_me_rounded,
                      size: 20, color: widget.accent),
                  onPressed: () => _copyLink(context),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.fromLTRB(10, 24, 10, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Text(
                  title.isEmpty ? 'Publicação' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: tile,
    );
  }
}

Widget _gridImageOrStable({
  required String displayRef,
  required String? path,
  required int memW,
  required int memH,
}) {
  final url = sanitizeImageUrl(displayRef);
  if (path != null && path.isNotEmpty) {
    return StableStorageImage(
      storagePath: path,
      imageUrl: url.isNotEmpty ? url : null,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      memCacheWidth: memW,
      memCacheHeight: memH,
    );
  }
  final storageLike = url.isNotEmpty &&
      (isFirebaseStorageHttpUrl(url) ||
          firebaseStorageMediaUrlLooksLike(url) ||
          url.toLowerCase().startsWith('gs://'));
  if (storageLike) {
    return FreshFirebaseStorageImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: memW,
      memCacheHeight: memH,
      placeholder: Container(color: const Color(0xFFF1F5F9)),
      errorWidget: Container(color: const Color(0xFFE5E7EB)),
    );
  }
  if (url.isNotEmpty && isValidImageUrl(url)) {
    return SafeNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: memW,
      memCacheHeight: memH,
    );
  }
  return Container(color: const Color(0xFFE5E7EB));
}

/// Modal estilo Instagram (desktop: mídia à esquerda, texto à direita).
class ChurchPublicPostLightbox {
  ChurchPublicPostLightbox._();

  static Future<void> show(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String igrejaId,
    required String churchSlug,
    required Color accent,
    required int memCacheW,
    required int memCacheH,
    required Future<void> Function(
      BuildContext context,
      Map<String, dynamic> post,
      String postId,
    ) onOpenHostedVideo,
  }) async {
    final p = doc.data();
    final postId = doc.id;
    final type = (p['type'] ?? 'aviso').toString();
    final isEvento = type == 'evento';
    final title = (p['title'] ?? 'Publicação').toString();
    final body = (p['body'] ?? p['text'] ?? '').toString();
    final hosted =
        sanitizeImageUrl((eventNoticiaHostedVideoPlayUrl(p) ?? '').trim());
    final playWeb =
        kIsWeb && hosted.isNotEmpty && looksLikeHostedVideoFileUrl(hosted);
    final poster = sanitizeImageUrl(
        (eventNoticiaDisplayVideoThumbnailUrl(p) ?? '').trim());

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: LayoutBuilder(
            builder: (context, c) {
              final screenH = MediaQuery.sizeOf(context).height;
              final wide = c.maxWidth >= 880;
              final radius = BorderRadius.circular(24);
              final mediaSection = _LightboxMediaPager(
                post: p,
                postId: postId,
                memCacheW: memCacheW,
                memCacheH: memCacheH,
                playWeb: playWeb,
                hostedVideoUrl: hosted,
                videoPoster: poster,
              );
              final extVid = eventNoticiaExternalVideoUrl(p);
              final legacyV = (p['videoUrl'] ?? '').toString().trim();
              final showAssistBtn = !playWeb &&
                  (hosted.isNotEmpty ||
                      (extVid != null && extVid.isNotEmpty) ||
                      legacyV.isNotEmpty);
              final textSection = _LightboxTextPanel(
                title: title,
                body: body,
                isEvento: isEvento,
                accent: accent,
                igrejaId: igrejaId,
                postId: postId,
                churchSlug: churchSlug,
                post: p,
                onOpenVideo: () => onOpenHostedVideo(ctx, p, postId),
                showAssistVideoButton: showAssistBtn,
                postsParentCollection:
                    ChurchTenantPostsCollections.segmentFromPostRef(
                        doc.reference),
              );

              final dialogH = (screenH * 0.88).clamp(380.0, 720.0);
              return ClipRRect(
                borderRadius: radius,
                child: Material(
                  color: Colors.white,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1080,
                      maxHeight: dialogH,
                    ),
                    child: SizedBox(
                      height: dialogH,
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 11,
                                  child: mediaSection,
                                ),
                                Expanded(
                                  flex: 9,
                                  child: textSection,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: (dialogH * 0.42).clamp(200.0, 320.0),
                                  width: double.infinity,
                                  child: mediaSection,
                                ),
                                Expanded(
                                  child: textSection,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _LightboxMediaPager extends StatefulWidget {
  final Map<String, dynamic> post;
  final String postId;
  final int memCacheW;
  final int memCacheH;
  final bool playWeb;
  final String hostedVideoUrl;
  final String videoPoster;

  const _LightboxMediaPager({
    required this.post,
    required this.postId,
    required this.memCacheW,
    required this.memCacheH,
    required this.playWeb,
    required this.hostedVideoUrl,
    required this.videoPoster,
  });

  @override
  State<_LightboxMediaPager> createState() => _LightboxMediaPagerState();
}

class _LightboxMediaPagerState extends State<_LightboxMediaPager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final slides = <Widget>[];
    final photos = eventNoticiaPhotoUrls(widget.post);
    for (var i = 0; i < photos.length; i++) {
      final raw = sanitizeImageUrl(photos[i]);
      final path = eventNoticiaPhotoStoragePathAt(widget.post, i);
      slides.add(_gridImageOrStable(
        displayRef: raw,
        path: path,
        memW: (widget.memCacheW * 1.2).round().clamp(200, 1440),
        memH: (widget.memCacheH * 1.2).round().clamp(200, 1440),
      ));
    }
    if (widget.playWeb) {
      slides.insert(
        0,
        Stack(
          fit: StackFit.expand,
          children: [
            if (widget.videoPoster.isNotEmpty &&
                isValidImageUrl(widget.videoPoster))
              SafeNetworkImage(
                imageUrl: widget.videoPoster,
                fit: BoxFit.cover,
                memCacheWidth: widget.memCacheW,
                memCacheHeight: widget.memCacheH,
              ),
            PremiumHtmlFeedVideo(
              videoUrl: widget.hostedVideoUrl,
              visibilityKey: 'lb_${widget.postId}',
              showControls: true,
              posterUrl:
                  widget.videoPoster.isNotEmpty ? widget.videoPoster : null,
              startLoadingImmediately: true,
              videoObjectFitContain: true,
            ),
          ],
        ),
      );
    }
    if (slides.isEmpty) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(
          child: Icon(Icons.perm_media_rounded,
              size: 48, color: Color(0xFF94A3B8)),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView(
          onPageChanged: (i) => setState(() => _page = i),
          children: slides,
        ),
        if (slides.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                slides.length,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _page == i ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LightboxTextPanel extends StatelessWidget {
  final String title;
  final String body;
  final bool isEvento;
  final Color accent;
  final String igrejaId;
  final String postId;
  final String churchSlug;
  final Map<String, dynamic> post;
  final VoidCallback onOpenVideo;
  final bool showAssistVideoButton;
  final String postsParentCollection;

  const _LightboxTextPanel({
    required this.title,
    required this.body,
    required this.isEvento,
    required this.accent,
    required this.igrejaId,
    required this.postId,
    required this.churchSlug,
    required this.post,
    required this.onOpenVideo,
    required this.showAssistVideoButton,
    required this.postsParentCollection,
  });

  Future<void> _copy(BuildContext context) async {
    final url =
        AppConstants.shareNoticiaPublicUrl(churchSlug, postId);
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Link copiado.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body.isEmpty ? 'Sem descrição.' : body,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.45,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.near_me_rounded, size: 18),
                      label: const Text('Copiar link'),
                    ),
                    if (showAssistVideoButton)
                      FilledButton.icon(
                        onPressed: onOpenVideo,
                        icon: const Icon(Icons.play_circle_rounded, size: 18),
                        label: const Text('Assistir vídeo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => shareChurchNoticiaForOgPreview(
                        tenantId: igrejaId,
                        churchSlug: churchSlug,
                        noticiaId: postId,
                        title: title,
                        body: body,
                        postFirestore: post,
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Compartilhar…'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                YahwehSocialPostBar(
                  tenantId: igrejaId,
                  postId: postId,
                  isEvento: isEvento,
                  churchSlug: churchSlug,
                  postsParentCollection: postsParentCollection,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

