import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/aviso_evento_social_link_button.dart';
import 'package:gestao_yahweh/ui/widgets/church_post_media_carousel.dart';
import 'package:gestao_yahweh/ui/widgets/church_post_rich_text_viewer.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Cartao ÚNICO de publicacao (evento / aviso) — mesmo visual no **modulo
/// Eventos**, no **painel inicial** e no **site publico**.
///
/// Antes cada um destes tres lugares desenhava o post a sua maneira: o painel
/// espremia o carrossel numa caixa de altura calculada por `media_info`
/// (a foto transbordava e a legenda era pintada POR CIMA da imagem) e o site
/// publico mostrava so a capa — quem visitava nunca via o video. Aqui a ordem
/// e sempre a mesma, tipo Instagram:
///
/// 1. cabecalho (selo Evento/Aviso, data, hora)
/// 2. titulo
/// 3. midia — fotos **e** videos no MESMO carrossel
/// 4. legenda ABAIXO da midia, recolhida com «Veja mais»
/// 5. botoes Instagram/YouTube — **so** quando o link existe no post
/// 6. acoes do contexto (participar/comentar/partilhar, ou partilha publica)
class ChurchFeedPostCard extends StatelessWidget {
  const ChurchFeedPostCard({
    super.key,
    required this.data,
    required this.title,
    required this.isEvento,
    this.mediaItems,
    this.dateStr = '',
    this.timeStr = '',
    this.headerTrailing,
    this.leadingHeader,
    this.actions,
    this.footer,
    this.onOpenPost,
    this.onDoubleTapMedia,
    this.emptyMediaPlaceholder,
    this.margin = EdgeInsets.zero,
    this.showCaption = true,
  });

  final Map<String, dynamic> data;
  final String title;
  final bool isEvento;

  /// Itens ja montados. Quando `null`, sai de [churchFeedPostMediaFromData].
  final List<ChurchPostMediaItem>? mediaItems;

  final String dateStr;
  final String timeStr;

  /// Linha acima do selo (avatar + nome da igreja, por exemplo).
  final Widget? leadingHeader;

  /// Canto direito do cabecalho (menu de editar/excluir, partilhar…).
  final Widget? headerTrailing;

  /// Barra de acoes por baixo da legenda.
  final Widget? actions;

  /// Bloco extra no fim (links do evento, «ver comentarios»…).
  final Widget? footer;

  final VoidCallback? onOpenPost;
  final VoidCallback? onDoubleTapMedia;

  /// Desenho usado quando o post nao tem foto nem video.
  final Widget? emptyMediaPlaceholder;

  final EdgeInsets margin;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final items = mediaItems ?? churchFeedPostMediaFromData(data);
    final ig = churchFeedPostInstagramUrl(data);
    final yt = churchFeedPostYoutubeUrl(data);

    Widget media;
    if (items.isNotEmpty) {
      media = ChurchPostMediaCarousel(
        items: items,
        accent: ThemeCleanPremium.primary,
        borderRadius: ThemeCleanPremium.radiusLg,
        aspectRatio: 4 / 5,
        title: title,
      );
      if (onDoubleTapMedia != null) {
        media = GestureDetector(onDoubleTap: onDoubleTapMedia, child: media);
      }
    } else {
      media = emptyMediaPlaceholder ?? const SizedBox.shrink();
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingHeader != null) leadingHeader!,
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChurchFeedPostChips(
                        isEvento: isEvento,
                        dateStr: dateStr,
                        timeStr: timeStr,
                      ),
                      if (title.trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            height: 1.25,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: media,
          ),
          // Legenda SEMPRE por baixo da midia (nunca por cima da foto).
          if (showCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ChurchPostRichTextViewer(
                data: data,
                collapsible: true,
                boxed: false,
                padding: EdgeInsets.zero,
              ),
            ),
          // Instagram / YouTube: so aparecem quando o post tem mesmo o link.
          if (ig.isNotEmpty || yt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: avisoEventoSocialLinksRow(
                instagramUrl: ig,
                youtubeUrl: yt,
              ),
            ),
          if (actions != null) actions!,
          if (footer != null) footer!,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Selo `Evento`/`Aviso` + data + hora — o mesmo em todos os cartoes.
class ChurchFeedPostChips extends StatelessWidget {
  const ChurchFeedPostChips({
    super.key,
    required this.isEvento,
    this.dateStr = '',
    this.timeStr = '',
  });

  final bool isEvento;
  final String dateStr;
  final String timeStr;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isEvento
                ? const Color(0xFFFFF7ED)
                : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isEvento ? 'Evento' : 'Aviso',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isEvento
                  ? const Color(0xFFD97706)
                  : const Color(0xFF2563EB),
            ),
          ),
        ),
        if (dateStr.trim().isNotEmpty)
          _IconChip(icon: Icons.calendar_today_rounded, label: dateStr),
        if (timeStr.trim().isNotEmpty)
          _IconChip(icon: Icons.schedule_rounded, label: timeStr),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// Fotos + video do post num unico carrossel — a MESMA leitura usada pelo
/// modulo Eventos, para o painel e o site publico mostrarem o mesmo conteudo.
List<ChurchPostMediaItem> churchFeedPostMediaFromData(
  Map<String, dynamic> data, {
  List<String>? imageUrlsOverride,
}) {
  final photos = imageUrlsOverride ?? feedPostCarouselPhotoUrls(data);
  final hosted = sanitizeImageUrl(eventNoticiaHostedVideoPlayUrl(data) ?? '');
  final playable =
      hosted.isNotEmpty && eventNoticiaUrlEligibleForHostedInlinePlayer(hosted)
      ? hosted
      : sanitizeImageUrl(eventNoticiaExternalVideoUrl(data) ?? '');
  final thumb = sanitizeImageUrl(
    eventNoticiaDisplayVideoThumbnailUrl(data) ?? '',
  );
  return buildChurchPostMedia(
    imageUrls: photos,
    hostedVideoUrl: playable,
    videoThumbUrl: thumb,
  );
}

/// Link do Instagram do post — vazio quando nao foi preenchido.
/// Delegado a [churchPostInstagramUrl] (core) para o app inteiro usar a MESMA
/// validacao — ver o aviso sobre `Instance of 'Ohb'` la.
String churchFeedPostInstagramUrl(Map<String, dynamic>? data) =>
    churchPostInstagramUrl(data);

/// Link de video externo (YouTube/Vimeo) do post — vazio quando nao existe.
String churchFeedPostYoutubeUrl(Map<String, dynamic>? data) =>
    churchPostExternalVideoLink(data);
