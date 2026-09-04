import 'dart:async' show unawaited;
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show warmNoticiaShareMediaBundle;
import 'package:gestao_yahweh/core/event_gallery_archive.dart'
    show eventArchiveBaseDate;
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaPhotoUrls,
        eventNoticiaUrlEligibleForHostedInlinePlayer,
        postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/widgets/church_feed_post_card.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/aviso_evento_social_link_button.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show churchMuralCarouselClipHeight, kChurchPublicSiteMobileFrameWidth;
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show
        YahwehPremiumFeedShimmer,
        saveNoticiaCoverToGallery,
        shareChurchNoticiaForOgPreview;
import 'package:gestao_yahweh/ui/widgets/yahweh_social_post_bar.dart';

/// Skeleton enquanto `publishState == uploading` (fotos a subir em background).
Widget _churchPublicProcessingMediaPlaceholder(Color accent) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          YahwehPremiumFeedShimmer.mediaCover(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              color: Colors.black.withValues(alpha: 0.42),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Carregando mídia...',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Miniatura rápida quando o post tem [media_info] (mural Instagram).
/// Aceita https **ou** path Storage (publicação path-only sem getDownloadURL).
String? churchPublicPostThumbUrl(Map<String, dynamic> p) {
  final mi = p['media_info'];
  if (mi is Map) {
    for (final k in ['url_thumb', 'urlThumb', 'url_original', 'urlOriginal']) {
      final u = sanitizeImageUrl((mi[k] ?? '').toString());
      if (u.isNotEmpty &&
          (isValidImageUrl(u) || firebaseStorageMediaUrlLooksLike(u))) {
        return u;
      }
    }
  }
  final img = sanitizeImageUrl(
      (p['imageUrl'] ?? p['imagemUrl'] ?? p['defaultImageUrl'] ?? '')
          .toString());
  if (img.isNotEmpty &&
      (isValidImageUrl(img) || firebaseStorageMediaUrlLooksLike(img))) {
    return img;
  }
  final cover = eventNoticiaFeedCoverHintUrl(p);
  if (cover.isNotEmpty) return cover;
  final path = eventNoticiaImageStoragePath(p);
  if (path != null && path.isNotEmpty) return path;
  return null;
}

String _formatArchiveEventDatePt(DateTime? d) {
  if (d == null) return 'Data a confirmar';
  const w = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  final wd = w[d.weekday - 1];
  return '$wd · ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Barra de navegação fixa (abaixo da AppBar): âncoras da página.
/// Fundo **opaco** + gradiente alinhado ao site de divulgação Gestão YAHWEH (evita o conteúdo
/// «passar por cima» da faixa quando o fundo era branco semitransparente).
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
    final isWide = !kIsWeb && MediaQuery.sizeOf(context).width >= 720;
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
          constraints: BoxConstraints(
            maxWidth: kIsWeb
                ? kChurchPublicSiteMobileFrameWidth
                : 1100,
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _NavChip(
                        label: 'Início',
                        icon: Icons.home_rounded,
                        onTap: onInicio,
                      ),
                      _NavChip(
                        label: 'Avisos',
                        icon: Icons.campaign_rounded,
                        onTap: onAvisos,
                      ),
                      _NavChip(
                        label: 'Eventos',
                        icon: Icons.event_rounded,
                        onTap: onDestaques,
                      ),
                      _NavChip(
                        label: 'Cultos',
                        icon: Icons.auto_awesome_rounded,
                        onTap: onEventos,
                      ),
                    ],
                  ),
                ),
              ),
              if (!kIsWeb)
                if (isWide)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Material(
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
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.login_rounded,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 9),
                                Text(
                                  'Acessar Sistema',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: 'Acessar sistema',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onAcessarSistema,
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
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
                  ),
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

  /// Ícone da secção — a barra era só texto e lia-se como uma lista de
  /// palavras; com o ícone fica alinhada com as pastilhas do hero.
  final IconData? icon;

  const _NavChip({
    required this.label,
    required this.onTap,
    this.icon,
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
              padding: EdgeInsets.symmetric(
                horizontal: icon == null ? 18 : 15,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 7),
                  ],
                  Text(
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
                ],
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
      separatorBuilder: (_, _) => const SizedBox(height: 14),
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
Widget churchPublicSocialFeedTileFromMap({
  required BuildContext context,
  required String postId,
  required Map<String, dynamic> post,
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
  bool galleryArchivePremiumLayout = false,
}) {
  return _SocialGridTile(
    postId: postId,
    post: post,
    igrejaId: igrejaId,
    churchSlug: churchSlug,
    accent: accent,
    memCacheW: memCacheW,
    memCacheH: memCacheH,
    galleryArchivePremiumLayout: galleryArchivePremiumLayout,
    onOpenHostedVideo: onOpenHostedVideo,
    onOpenDetail: () {},
    onOpenGalleryFocus: null,
  );
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
  bool galleryArchivePremiumLayout = false,
}) {
  return _SocialGridTile(
    postId: doc.id,
    post: doc.data(),
    igrejaId: igrejaId,
    churchSlug: churchSlug,
    accent: accent,
    memCacheW: memCacheW,
    memCacheH: memCacheH,
    galleryArchivePremiumLayout: galleryArchivePremiumLayout,
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
          mediaFocus: ChurchPublicPostLightboxMediaFocus.start,
        )),
    onOpenGalleryFocus: () => unawaited(ChurchPublicPostLightbox.show(
          context,
          doc: doc,
          igrejaId: igrejaId,
          churchSlug: churchSlug,
          accent: accent,
          memCacheW: memCacheW,
          memCacheH: memCacheH,
          onOpenHostedVideo: onOpenHostedVideo,
          mediaFocus: ChurchPublicPostLightboxMediaFocus.firstPhoto,
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
  /// Card em quadrado premium (arquivo da galeria): título, data, “Ver detalhes” / “Mais fotos”.
  final bool galleryArchivePremiumLayout;
  final VoidCallback onOpenDetail;
  /// Abre o lightbox com foco na primeira foto (pula vídeo web). Se null, «Mais fotos» usa [onOpenDetail].
  final VoidCallback? onOpenGalleryFocus;
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
    this.galleryArchivePremiumLayout = false,
    required this.onOpenDetail,
    this.onOpenGalleryFocus,
    required this.onOpenHostedVideo,
  });

  @override
  State<_SocialGridTile> createState() => _SocialGridTileState();
}

class _SocialGridTileState extends State<_SocialGridTile> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    // Pré-aquece foto/vídeo assim que o card aparece no mural público — o
    // toque em "Compartilhar" lê do cache em vez de baixar mídia na hora.
    warmNoticiaShareMediaBundle(
      widget.post,
      tenantId: widget.igrejaId,
      postId: widget.postId,
      collection: (widget.post['type'] ?? 'eventos').toString(),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = AppConstants.shareNoticiaSocialPreviewUrl(
        widget.churchSlug, widget.postId, widget.igrejaId);
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Link copiado ? cole no WhatsApp.'),
    );
  }

  /// Compartilhamento nativo direto do card do mural público — sem exigir login,
  /// já leva foto/vídeo (via [shareChurchNoticiaForOgPreview]) igual à área do membro.
  void _share(BuildContext context) {
    final p = widget.post;
    unawaited(shareChurchNoticiaForOgPreview(
      tenantId: widget.igrejaId,
      churchSlug: widget.churchSlug,
      noticiaId: widget.postId,
      title: (p['title'] ?? '').toString(),
      body: (p['body'] ?? p['text'] ?? '').toString(),
      postFirestore: p,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.galleryArchivePremiumLayout) {
      return _buildGalleryArchivePremiumLayout(context);
    }

    final p = widget.post;
    final type = (p['type'] ?? 'aviso').toString();
    final isEvento = type == 'evento';
    final title = (p['title'] ?? '').toString().trim();
    final publishState = (p['publishState'] ?? '').toString();
    final mediaUploading =
        publishState == MuralFastPublishService.stateUploading;

    // MESMA leitura de mídia do módulo Eventos e do painel inicial: fotos e
    // vídeo no mesmo carrossel. O site público mostrava só a capa (ou só o
    // vídeo, nunca os dois) — quem visitava não via o vídeo publicado.
    final items = churchFeedPostMediaFromData(p);

    DateTime? dt;
    final startAt = p['startAt'];
    if (startAt is Timestamp) {
      dt = startAt.toDate();
    } else {
      final createdAt = p['createdAt'];
      if (createdAt is Timestamp) dt = createdAt.toDate();
    }
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}'
        : '';
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    return ChurchFeedPostCard(
      data: p,
      title: title.isEmpty ? 'Publicação' : title,
      isEvento: isEvento,
      mediaItems: items,
      dateStr: dateStr,
      timeStr: timeStr,
      onOpenPost: widget.onOpenDetail,
      emptyMediaPlaceholder: mediaUploading
          ? AspectRatio(
              aspectRatio: 4 / 5,
              child: _churchPublicProcessingMediaPlaceholder(widget.accent),
            )
          : null,
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copiar link',
            icon: Icon(Icons.near_me_rounded, size: 20, color: widget.accent),
            onPressed: () => _copyLink(context),
          ),
          IconButton(
            tooltip: 'Compartilhar',
            icon: Icon(Icons.share_rounded, size: 20, color: widget.accent),
            onPressed: () => _share(context),
          ),
        ],
      ),
      actions: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: widget.onOpenDetail,
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Ver publicação'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent.withValues(alpha: 0.10),
                  foregroundColor: widget.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Compartilhar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A).withValues(alpha: 0.10),
                foregroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cartão “super premium” em quadrado (mídia 1:1 + título, data, ações).
  Widget _buildGalleryArchivePremiumLayout(BuildContext context) {
    final p = widget.post;
    final galleryUrls = eventNoticiaPhotoUrls(p);
    final type = (p['type'] ?? 'aviso').toString();
    final isEvento = type == 'evento';
    final rawTitle = (p['title'] ?? '').toString().trim();
    final displayTitle = rawTitle.isEmpty ? 'Evento' : rawTitle;
    final hosted =
        sanitizeImageUrl((eventNoticiaHostedVideoPlayUrl(p) ?? '').trim());
    final ext = eventNoticiaExternalVideoUrl(p);
    final legacy = (p['videoUrl'] ?? '').toString().trim();
    final hasVideo = hosted.isNotEmpty ||
        (ext != null && ext.isNotEmpty) ||
        legacy.isNotEmpty;
    final playWeb = kIsWeb &&
        hosted.isNotEmpty &&
        eventNoticiaUrlEligibleForHostedInlinePlayer(hosted);
    final thumb = churchPublicPostThumbUrl(p);
    final cover = eventNoticiaFeedCoverHintUrl(p);
    var displayRef =
        ((thumb != null && thumb.isNotEmpty) ? thumb : cover).trim();
    final pathFirst = eventNoticiaPhotoStoragePathAt(p, 0) ??
        eventNoticiaImageStoragePath(p);
    final poster = sanitizeImageUrl(
        (eventNoticiaDisplayVideoThumbnailUrl(p) ?? '').trim());
    final badge = isEvento ? 'Evento' : 'Aviso';
    final badgeBg = isEvento
        ? const Color(0xFF0C4A6E).withValues(alpha: 0.94)
        : const Color(0xFF6D28D9).withValues(alpha: 0.94);

    DateTime? eventDay = eventArchiveBaseDate(p);
    if (eventDay == null) {
      final c = p['createdAt'];
      if (c is Timestamp) eventDay = c.toDate();
    }
    final dateLabel = _formatArchiveEventDatePt(eventDay);
    final photoAlbumCount = galleryUrls.length;

    late final Widget heroInner;
    if (galleryUrls.isNotEmpty) {
      final raw = sanitizeImageUrl(galleryUrls.first);
      final path0 = eventNoticiaPhotoStoragePathAt(p, 0);
      heroInner = _gridImageOrStable(
        displayRef: raw,
        path: path0,
        memW: widget.memCacheW,
        memH: widget.memCacheH,
        fit: BoxFit.cover,
      );
    } else if (poster.isNotEmpty &&
        (isValidImageUrl(poster) ||
            isFirebaseStorageHttpUrl(poster) ||
            firebaseStorageMediaUrlLooksLike(poster))) {
      heroInner = _gridImageOrStable(
        displayRef: poster,
        path: null,
        memW: widget.memCacheW,
        memH: widget.memCacheH,
        fit: BoxFit.cover,
      );
    } else if (displayRef.isNotEmpty ||
        (pathFirst != null && pathFirst.isNotEmpty)) {
      heroInner = _gridImageOrStable(
        displayRef: displayRef,
        path: pathFirst,
        memW: widget.memCacheW,
        memH: widget.memCacheH,
        fit: BoxFit.cover,
      );
    } else {
      heroInner = ColoredBox(
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: Icon(
            Icons.photo_library_rounded,
            size: 52,
            color: widget.accent.withValues(alpha: 0.28),
          ),
        ),
      );
    }

    final Widget hero = Stack(
      fit: StackFit.expand,
      children: [
        heroInner,
        if (hasVideo && !playWeb)
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 54, color: Colors.white),
            ),
          ),
        if (hasVideo && playWeb)
          IgnorePointer(
            child: Container(
              alignment: Alignment.center,
              color: Colors.black.withValues(alpha: 0.22),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
          ),
      ],
    );

    final radius = BorderRadius.circular(24);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.006 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.14),
                blurRadius: 36,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
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
                          behavior: HitTestBehavior.opaque,
                          child: hero,
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(11),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              badge,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.35,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Column(
                            children: [
                              Material(
                                color: Colors.white.withValues(alpha: 0.95),
                                elevation: 3,
                                shadowColor: Colors.black26,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: IconButton(
                                  tooltip: 'Copiar link',
                                  icon: Icon(Icons.near_me_rounded,
                                      size: 20, color: widget.accent),
                                  onPressed: () => _copyLink(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Material(
                                color: Colors.white.withValues(alpha: 0.95),
                                elevation: 3,
                                shadowColor: Colors.black26,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: IconButton(
                                  tooltip: 'Compartilhar',
                                  icon: Icon(Icons.share_rounded,
                                      size: 20, color: widget.accent),
                                  onPressed: () => _share(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.22,
                            letterSpacing: -0.4,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: widget.accent.withValues(alpha: 0.92),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (photoAlbumCount > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '$photoAlbumCount ${photoAlbumCount == 1 ? 'foto no álbum' : 'fotos no álbum'}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    widget.onOpenGalleryFocus ??
                                        widget.onOpenDetail,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: widget.accent,
                                  side: BorderSide(
                                    color:
                                        widget.accent.withValues(alpha: 0.55),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Mais fotos',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: widget.onOpenDetail,
                                style: FilledButton.styleFrom(
                                  backgroundColor: widget.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Ver detalhes',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
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

/// Foco da área de mídia ao abrir [ChurchPublicPostLightbox].
enum ChurchPublicPostLightboxMediaFocus {
  /// Primeiro slide (vídeo web no índice 0, quando existir).
  start,
  /// Primeira **foto** do álbum: pula o slide do vídeo web quando há fotos (botão «Mais fotos»).
  firstPhoto,
}

int _lightboxMediaSlideCount(Map<String, dynamic> p, bool playWeb) {
  final n = eventNoticiaPhotoUrls(p).length;
  if (playWeb) {
    return n == 0 ? 1 : n + 1;
  }
  return n;
}

/// Índice inicial do [PageView] do lightbox (alinhado à ordem dos slides em [_LightboxMediaPager]).
int lightboxInitialMediaPage(
  Map<String, dynamic> p,
  bool playWeb,
  ChurchPublicPostLightboxMediaFocus focus,
) {
  final count = _lightboxMediaSlideCount(p, playWeb);
  if (count <= 0) return 0;
  int idx;
  if (focus == ChurchPublicPostLightboxMediaFocus.start) {
    idx = 0;
  } else {
    final photos = eventNoticiaPhotoUrls(p);
    if (photos.isEmpty) {
      idx = 0;
    } else if (playWeb) {
      idx = 1;
    } else {
      idx = 0;
    }
  }
  return idx.clamp(0, count - 1);
}

/// Limites no **web** — modal mais compacto e legível (evita mídia “fullscreen”).
const double _kPublicLightboxMaxWidthWeb = 720;
const double _kPublicLightboxMaxHeightWeb = 520;

/// Modal estilo Instagram (desktop: mídia à esquerda, texto à direita).
class ChurchPublicPostLightbox {
  ChurchPublicPostLightbox._();

  static Future<void> show(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String igrejaId,
    required String churchSlug,
    String churchName = '',
    required Color accent,
    required int memCacheW,
    required int memCacheH,
    required Future<void> Function(
      BuildContext context,
      Map<String, dynamic> post,
      String postId,
    ) onOpenHostedVideo,
    ChurchPublicPostLightboxMediaFocus mediaFocus =
        ChurchPublicPostLightboxMediaFocus.start,
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
        kIsWeb && hosted.isNotEmpty && eventNoticiaUrlEligibleForHostedInlinePlayer(hosted);
    final poster = sanitizeImageUrl(
        (eventNoticiaDisplayVideoThumbnailUrl(p) ?? '').trim());

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: kIsWeb ? 0.45 : 0.55),
      builder: (ctx) {
        final insetWeb = const EdgeInsets.symmetric(horizontal: 28, vertical: 40);
        final insetMo = const EdgeInsets.symmetric(horizontal: 14, vertical: 22);
        return Dialog(
          insetPadding: kIsWeb ? insetWeb : insetMo,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: LayoutBuilder(
            builder: (context, c) {
              final screenH = MediaQuery.sizeOf(context).height;
              final wide = c.maxWidth >= 840;
              final radius = BorderRadius.circular(26);
              final initialPage = lightboxInitialMediaPage(p, playWeb, mediaFocus);
              final mediaSection = _LightboxMediaPager(
                post: p,
                postId: postId,
                memCacheW: memCacheW,
                memCacheH: memCacheH,
                playWeb: playWeb,
                hostedVideoUrl: hosted,
                videoPoster: poster,
                initialPage: initialPage,
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
                churchName: churchName,
                post: p,
                onOpenVideo: () => onOpenHostedVideo(ctx, p, postId),
                showAssistVideoButton: showAssistBtn,
                postsParentCollection:
                    ChurchTenantPostsCollections.segmentFromPostRef(
                        doc.reference),
              );

              final mqSize = MediaQuery.sizeOf(context);
              final dialogH = kIsWeb
                  ? min(
                      min(screenH * 0.74, _kPublicLightboxMaxHeightWeb),
                      mqSize.height * 0.88,
                    ).clamp(320.0, mqSize.height * 0.9)
                  : (screenH * 0.92).clamp(400.0, mqSize.height * 0.94);
              final maxDialogW = kIsWeb
                  ? min(_kPublicLightboxMaxWidthWeb, c.maxWidth)
                  : min(1080.0, c.maxWidth);
              final lbPhotos = eventNoticiaPhotoUrls(p);
              final lbAr = postFeedCarouselAspectRatioForIndex(
                p,
                0,
                lbPhotos.isNotEmpty ? lbPhotos.length : 1,
              );
              final mobileMediaClip =
                  churchMuralCarouselClipHeight(context, c.maxWidth, lbAr);
              final mobileMediaH = mobileMediaClip.clamp(
                220.0,
                mqSize.height * (kIsWeb ? 0.50 : 0.62),
              );
              final mediaFlex = kIsWeb ? 10 : 11;
              final textFlex = kIsWeb ? 10 : 9;
              final shell = Material(
                color: Colors.white,
                elevation: 0,
                shadowColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxDialogW,
                    maxHeight: dialogH,
                  ),
                  child: SizedBox(
                    height: dialogH,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: mediaFlex,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    border: Border(
                                      right: BorderSide(
                                        color: Colors.black.withValues(
                                            alpha: kIsWeb ? 0.06 : 0.05),
                                      ),
                                    ),
                                  ),
                                  child: mediaSection,
                                ),
                              ),
                              Expanded(
                                flex: textFlex,
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
              );
              return Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                          alpha: kIsWeb ? 0.20 : 0.14),
                      blurRadius: kIsWeb ? 44 : 28,
                      offset: const Offset(0, 22),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: shell,
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
  /// Índice inicial do carrossel (ex.: primeira foto após vídeo web).
  final int initialPage;

  const _LightboxMediaPager({
    required this.post,
    required this.postId,
    required this.memCacheW,
    required this.memCacheH,
    required this.playWeb,
    required this.hostedVideoUrl,
    required this.videoPoster,
    this.initialPage = 0,
  });

  @override
  State<_LightboxMediaPager> createState() => _LightboxMediaPagerState();
}

class _LightboxMediaPagerState extends State<_LightboxMediaPager> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    final count =
        _lightboxMediaSlideCount(widget.post, widget.playWeb);
    final maxIdx = count > 0 ? count - 1 : 0;
    final safe = widget.initialPage.clamp(0, maxIdx);
    _page = safe;
    _controller = PageController(initialPage: safe);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
          controller: _controller,
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
  final String churchName;
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
    this.churchName = '',
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
                if ((post['instagramUrl'] ?? '').toString().trim().isNotEmpty ||
                    (eventNoticiaExternalVideoUrl(post) ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  avisoEventoSocialLinksRow(
                    instagramUrl: (post['instagramUrl'] ?? '').toString(),
                    youtubeUrl: eventNoticiaExternalVideoUrl(post),
                  ),
                ],
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
                      label: const Text('Compartilhar?'),
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
                  churchName: churchName,
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

