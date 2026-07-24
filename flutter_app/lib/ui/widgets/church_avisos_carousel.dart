import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_feed_photo_slide.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show
        churchMuralCarouselClipHeight,
        churchPublicFeedInstagramColumnWidth,
        kChurchPublicSiteMobileFrameWidth;
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart'
    show showYahwehOriginalMedia;
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_social_post_bar.dart';

/// Carrossel premium de avisos — painel e site público (proporção Instagram).
class ChurchAvisosCarousel extends StatefulWidget {
  const ChurchAvisosCarousel({
    super.key,
    required this.churchIdHint,
    this.onManageTap,
    this.compact = false,
    this.forPublicSite = false,
    this.churchSlug = '',
    this.churchName = '',
  });

  final String churchIdHint;
  final VoidCallback? onManageTap;
  final bool compact;
  final bool forPublicSite;
  final String churchSlug;
  final String churchName;

  @override
  State<ChurchAvisosCarousel> createState() => _ChurchAvisosCarouselState();
}

class _ChurchAvisosCarouselState extends State<ChurchAvisosCarousel> {
  final PageController _pageCtrl = PageController();
  int _page = 0;
  final Map<String, int> _photoPageByAviso = {};

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  double _mediaHeight(BuildContext context, Map<String, dynamic> postData, int nPhotos) {
    final mq = MediaQuery.sizeOf(context);
    final cardW = widget.forPublicSite
        ? churchPublicFeedInstagramColumnWidth(
            (mq.width - 32).clamp(260.0, kChurchPublicSiteMobileFrameWidth),
          )
        : mq.width > 900
            ? 420.0
            : (mq.width - (widget.compact ? 56 : 48)).clamp(260.0, mq.width);
    final ar = postFeedCarouselAspectRatioForIndex(
      postData,
      0,
      nPhotos > 0 ? nPhotos : 1,
    );
    final ideal = churchMuralCarouselClipHeight(context, cardW, ar);
    // +80% adicional nos clamps do carrossel (painel / avisos / site).
    if (widget.forPublicSite) return ideal.clamp(356.0, 680.0);
    if (widget.compact) return ideal.clamp(454.0, 760.0);
    if (kIsWeb) return ideal.clamp(520.0, 860.0);
    return ideal.clamp(580.0, 900.0);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChurchAvisoItem>>(
      stream: ChurchAvisosLoadService.watchActive(
        churchIdHint: widget.churchIdHint,
      ),
      builder: (context, snap) {
        final items = (snap.data ?? const <ChurchAvisoItem>[])
            .where((a) => a.hasImages || a.mediaRefs().isNotEmpty)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          decoration: YahwehWisdomVisualKit.wisdomSectionCard(
            borderTint: const Color(0xFF6366F1),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.campaign_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Avisos da igreja',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (widget.onManageTap != null)
                    TextButton.icon(
                      onPressed: widget.onManageTap,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Gerir'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: _mediaHeight(
                  context,
                  items[_page.clamp(0, items.length - 1)].rawData,
                  items[_page.clamp(0, items.length - 1)].mediaRefs().length,
                ),
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) {
                    final aviso = items[index];
                    final refs = aviso.mediaRefs();
                    if (refs.isEmpty) return const SizedBox.shrink();
                    final photoIdx = _photoPageByAviso[aviso.id] ?? 0;
                    final mediaH = _mediaHeight(context, aviso.rawData, refs.length);
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    final memW = (MediaQuery.sizeOf(context).width * dpr)
                        .round()
                        .clamp(400, 1200);

                    Widget photoAt(int pi) {
                      // Toque na foto → ampliar imagem inteira (padrão CT).
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showYahwehOriginalMedia(
                          context,
                          urlOrPath: refs[pi],
                        ),
                        child: ChurchFeedPhotoSlide(
                          mediaRef: refs[pi],
                          postData: aviso.rawData,
                          docId: aviso.id,
                          churchId: widget.churchIdHint,
                          width: double.infinity,
                          height: mediaH,
                          fit: BoxFit.contain,
                          memCacheWidth: memW,
                          skipFreshDisplayUrl: true,
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            child: refs.length <= 1
                                ? photoAt(0)
                                : Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      PageView.builder(
                                        key: ValueKey('aviso_photos_${aviso.id}'),
                                        itemCount: refs.length,
                                        onPageChanged: (pi) => setState(
                                          () => _photoPageByAviso[aviso.id] = pi,
                                        ),
                                        itemBuilder: (_, pi) => photoAt(pi),
                                      ),
                                      if (refs.length > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: List.generate(
                                              refs.length,
                                              (pi) => Container(
                                                width: photoIdx == pi ? 18 : 7,
                                                height: 7,
                                                margin: const EdgeInsets.symmetric(
                                                  horizontal: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: photoIdx == pi
                                                      ? Colors.white
                                                      : Colors.white54,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          aviso.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (aviso.body.isNotEmpty)
                          Text(
                            aviso.body,
                            maxLines: widget.compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (items.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    items.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _page == i ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _page == i
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              Builder(
                builder: (context) {
                  final current =
                      items[_page.clamp(0, items.length - 1)];
                  final ctxData =
                      ChurchContextService.currentChurchData ?? const {};
                  final slug = widget.churchSlug.trim().isNotEmpty
                      ? widget.churchSlug.trim()
                      : (ctxData['slug'] ??
                              ctxData['publicSlug'] ??
                              '')
                          .toString()
                          .trim();
                  final name = widget.churchName.trim().isNotEmpty
                      ? widget.churchName.trim()
                      : (ctxData['nome'] ??
                              ctxData['name'] ??
                              ctxData['nomeIgreja'] ??
                              '')
                          .toString()
                          .trim();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: YahwehSocialPostBar(
                      key: ValueKey('aviso_engage_${current.id}'),
                      tenantId: widget.churchIdHint,
                      postId: current.id,
                      isEvento: false,
                      churchSlug: slug,
                      churchName: name,
                      postsParentCollection:
                          ChurchTenantPostsCollections.avisos,
                      allowGuestCommentView: widget.forPublicSite,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
