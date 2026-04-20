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
        looksLikeHostedVideoFileUrl,
        postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show churchMuralCarouselClipHeight;
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
    show saveNoticiaCoverToGallery, shareChurchNoticiaForOgPreview;
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
/// Fundo **opaco** + gradiente alinhado ao site de divulgação Gestão YAHWEH (evita o conteúdo
/// “passar por cima” da faixa quando o fundo era branco semitransparente).
class ChurchPublicPortalNavSliver extends StatelessWidget {
  final Color accent;
  final VoidCallback onInicio;
  final VoidCallback onAvisos;
  final VoidCallback onDestaques;
  final VoidCallback onEventos;
  final VoidCallback onAcessarSistema;

  const ChurchPublicPortalNavSliver({
    super.key,
    required this.accent,
    required this.onInicio,
    required this.onAvisos,
    required this.onDestaques,
    required this.onEventos,
    required this.onAcessarSistema,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final nav = ThemeCleanPremium.navSidebar;
    final mid = Color.lerp(nav, ThemeCleanPremium.primary, 0.38)!;
    final end = Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.22)!;

    final bar = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            nav,
            mid,
            end,
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
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
                      ),
                      _NavChip(
                        label: 'Avisos',
                        onTap: onAvisos,
                      ),
                      _NavChip(
                        label: 'Eventos',
                        onTap: onDestaques,
                      ),
                      _NavChip(
                        label: 'Cultos',
                        onTap: onEventos,
                      ),
                    ],
                  ),
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onAcessarSistema,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1.1,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(accent, Colors.white, 0.16)!,
                            Color.lerp(accent, Colors.white, 0.06)!,
                            Color.lerp(accent, const Color(0xFF0F172A), 0.26)!,
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.36),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                            spreadRadius: -2,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.login_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 9),
                            Text(
                              'Acessar Sistema',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: -0.35,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Acessar sistema',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onAcessarSistema,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.05,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(accent, Colors.white, 0.14)!,
                                Color.lerp(accent, const Color(0xFF0F172A), 0.28)!,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.38),
                                blurRadius: 18,
                                offset: const Offset(0, 7),
                                spreadRadius: -1,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.login_rounded,
                                color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return SliverPersistentHeader(
      pinned: true,
      delegate: _PortalNavDelegate(child: bar),
    );
  }
}

class _NavChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NavChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
            child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1.15,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.34),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.07),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 7),
                  spreadRadius: -1,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.1),
                  blurRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: Colors.white,
                  letterSpacing: -0.35,
                  height: 1.1,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
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
    return Material(
      color: Colors.transparent,
      elevation: overlapsContent ? 14 : 6,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      child: child,
    );
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
  return _SocialGridTile(
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
  int _galleryPage = 0;

  Future<void> _copyLink(BuildContext context) async {
    final url = AppConstants.shareNoticiaSocialPreviewUrl(
        widget.churchSlug, widget.postId, widget.igrejaId);
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Link copiado — cole no WhatsApp.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final galleryUrls = eventNoticiaPhotoUrls(p);
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
    final badgeBg = isEvento
        ? const Color(0xFF0369A1).withValues(alpha: 0.92)
        : const Color(0xFF6D28D9).withValues(alpha: 0.92);

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
                fit: BoxFit.contain,
              )
            else if (displayRef.isNotEmpty)
              _gridImageOrStable(
                displayRef: displayRef,
                path: path,
                memW: widget.memCacheW,
                memH: widget.memCacheH,
                fit: BoxFit.contain,
              )
            else
              Container(color: const Color(0xFFE5E7EB)),
            PremiumHtmlFeedVideo(
              videoUrl: hosted,
              visibilityKey: 'pubgrid_${widget.postId}',
              showControls: false,
              posterUrl: poster.isNotEmpty ? poster : null,
              startLoadingImmediately: true,
              videoObjectFitContain: true,
            ),
          ],
        ),
      );
    } else if (!playWeb && galleryUrls.length > 1) {
      mediaChild = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              itemCount: galleryUrls.length,
              onPageChanged: (i) => setState(() => _galleryPage = i),
              itemBuilder: (ctx, idx) {
                final raw = sanitizeImageUrl(galleryUrls[idx]);
                final pathI = eventNoticiaPhotoStoragePathAt(p, idx);
                return ColoredBox(
                  color: const Color(0xFFF1F5F9),
                  child: _gridImageOrStable(
                    displayRef: raw,
                    path: pathI,
                    memW: widget.memCacheW,
                    memH: widget.memCacheH,
                    fit: BoxFit.contain,
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
                  galleryUrls.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _galleryPage == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _galleryPage == i
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
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
              fit: BoxFit.contain,
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
        child: ColoredBox(
          color: const Color(0xFFF1F5F9),
          child: _gridImageOrStable(
            displayRef: displayRef,
            path: path,
            memW: widget.memCacheW,
            memH: widget.memCacheH,
            fit: BoxFit.contain,
          ),
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
          if (galleryUrls.length > 1) {
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
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AnimatedScale(
                scale: _hover ? 1.012 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _hover ? 1.0 : 0.98,
                  duration: const Duration(milliseconds: 200),
                  child: mediaChild,
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 360.0;
        final ar = postFeedCarouselAspectRatioForIndex(
          p,
          galleryUrls.length > 1 ? _galleryPage : 0,
          galleryUrls.isNotEmpty ? galleryUrls.length : 1,
        );
        final tileH = churchMuralCarouselClipHeight(context, cw, ar);
        return SizedBox(
          height: tileH,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: tile,
          ),
        );
      },
    );
  }
}

Widget _gridImageOrStable({
  required String displayRef,
  required String? path,
  required int memW,
  required int memH,
  BoxFit fit = BoxFit.contain,
}) {
  final url = sanitizeImageUrl(displayRef);
  if (path != null && path.isNotEmpty) {
    return StableStorageImage(
      storagePath: path,
      imageUrl: url.isNotEmpty ? url : null,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
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
      fit: fit,
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
      fit: fit,
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

              final mqSize = MediaQuery.sizeOf(context);
              final dialogH =
                  (screenH * 0.92).clamp(400.0, mqSize.height * 0.94);
              final lbPhotos = eventNoticiaPhotoUrls(p);
              final lbAr = postFeedCarouselAspectRatioForIndex(
                p,
                0,
                lbPhotos.isNotEmpty ? lbPhotos.length : 1,
              );
              final mobileMediaClip =
                  churchMuralCarouselClipHeight(context, c.maxWidth, lbAr);
              final mobileMediaH =
                  mobileMediaClip.clamp(240.0, mqSize.height * 0.62);
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
                                  height: mobileMediaH,
                                  width: double.infinity,
                                  child: ColoredBox(
                                    color: const Color(0xFFF1F5F9),
                                    child: mediaSection,
                                  ),
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
        memW: (widget.memCacheW * 1.5).round().clamp(320, 1600),
        memH: (widget.memCacheH * 1.5).round().clamp(320, 1600),
        fit: BoxFit.contain,
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
                fit: BoxFit.contain,
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
    final url = AppConstants.shareNoticiaSocialPreviewUrl(
        churchSlug, postId, igrejaId);
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
                    if (!kIsWeb)
                      TextButton.icon(
                        onPressed: () =>
                            saveNoticiaCoverToGallery(context, post),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Guardar na galeria'),
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

