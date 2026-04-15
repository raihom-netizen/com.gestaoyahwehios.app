import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';

/// Ícone por canal — **só Material** (FA Brands falha na web / tree-shake).
Widget _socialTileLeadingIcon(ChurchPublicSocialTileData data, double size) {
  switch (data.channel) {
    case 'youtube':
      return Icon(
        Icons.play_circle_rounded,
        color: Colors.white,
        size: size,
      );
    case 'instagram':
      return Icon(
        Icons.photo_camera_rounded,
        color: Colors.white,
        size: size,
      );
    case 'facebook':
      return Icon(
        Icons.facebook_rounded,
        color: Colors.white,
        size: size,
      );
    case 'whatsapp':
      return WhatsappChannelIcon(size: size);
    default:
      return Icon(
        Icons.link_rounded,
        color: Colors.white,
        size: size,
      );
  }
}

/// Cartões tocáveis para Instagram, YouTube, Facebook e WhatsApp no site público.
class ChurchPublicSocialGallery extends StatelessWidget {
  final bool compact;
  final List<ChurchPublicSocialTileData> tiles;

  const ChurchPublicSocialGallery({
    super.key,
    required this.tiles,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // Celular web: cartões em grade ficam “pesados”; usar faixa horizontal compacta.
        if (w < 520) {
          return _SocialChannelsHorizontalStrip(tiles: tiles);
        }
        final minTile = compact ? 92.0 : 112.0;
        final cross = (w / minTile).floor().clamp(2, 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: compact ? 8 : 10,
            crossAxisSpacing: compact ? 8 : 10,
            childAspectRatio: compact ? 1.75 : 1.55,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, i) => _SocialTile(data: tiles[i], compact: compact),
        );
      },
    );
  }
}

/// Faixa rolável: ícones menores, altura fixa — visual alinhado ao painel premium.
class _SocialChannelsHorizontalStrip extends StatelessWidget {
  final List<ChurchPublicSocialTileData> tiles;

  const _SocialChannelsHorizontalStrip({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _SocialTileStripChip(data: tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _SocialTileStripChip extends StatelessWidget {
  final ChurchPublicSocialTileData data;

  const _SocialTileStripChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final g = data.gradient;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: g,
            ),
            boxShadow: [
              BoxShadow(
                color: g.last.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _socialTileLeadingIcon(data, 16),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChurchPublicSocialTileData {
  final String channel;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  final VoidCallback onTap;

  const ChurchPublicSocialTileData({
    required this.channel,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.onTap,
  });
}

class _SocialTile extends StatelessWidget {
  final ChurchPublicSocialTileData data;
  final bool compact;

  const _SocialTile({required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    final g = data.gradient;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: g,
            ),
            boxShadow: [
              BoxShadow(
                color: g.last.withValues(alpha: 0.28),
                blurRadius: compact ? 10 : 14,
                offset: Offset(0, compact ? 4 : 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 9 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 6 : 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _socialTileLeadingIcon(
                    data,
                    compact ? 17 : 19,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 12 : 13,
                        letterSpacing: -0.2,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Título + subtítulo + galeria (seção “ultra premium” em contatos).
class ChurchPublicSocialGallerySection extends StatelessWidget {
  final Color accent;
  final List<ChurchPublicSocialTileData> tiles;
  final bool compact;

  const ChurchPublicSocialGallerySection({
    super.key,
    required this.accent,
    required this.tiles,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final effectiveCompact = compact || c.maxWidth < 640;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.2),
                        accent.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(Icons.hub_rounded,
                      color: accent, size: effectiveCompact ? 18 : 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Redes e WhatsApp',
                        style: TextStyle(
                          fontSize: effectiveCompact ? 14.5 : 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.35,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Toque para abrir no app ou no navegador',
                        style: TextStyle(
                          fontSize: effectiveCompact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: effectiveCompact ? 12 : 16),
            ChurchPublicSocialGallery(
                tiles: tiles, compact: effectiveCompact),
          ],
        );
      },
    );
  }
}

/// Gradientes e ícones padrão por canal (Material — compatível com web).
class ChurchPublicSocialPresets {
  static const instagramG = [
    Color(0xFFF58529),
    Color(0xFFDD2A7B),
    Color(0xFF8134AF),
  ];
  static const youtubeG = [Color(0xFFFF0000), Color(0xFFB20710)];
  static const facebookG = [Color(0xFF1877F2), Color(0xFF0C63D4)];
  static const whatsappG = [Color(0xFF25D366), Color(0xFF128C7E)];

  static const IconData iconInstagram = Icons.photo_camera_rounded;
  static const IconData iconYoutube = Icons.play_circle_rounded;
  static const IconData iconFacebook = Icons.facebook_rounded;
  static const IconData iconWhatsapp = Icons.chat_rounded;
}

/// Monta a lista de cartões a partir das URLs do cadastro + [whatsappUri] já resolvido.
class ChurchPublicSocialGalleryBuilder {
  ChurchPublicSocialGalleryBuilder._();

  static List<ChurchPublicSocialTileData> fromUrls({
    required void Function(String channel) onBeforeOpen,
    required void Function(Uri uri) launchUri,
    required String instagramUrl,
    required String facebookUrl,
    required String youtubeUrl,
    Uri? whatsappUri,
  }) {
    Uri? norm(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      final s =
          t.startsWith(RegExp(r'https?://', caseSensitive: false)) ? t : 'https://$t';
      return Uri.tryParse(s);
    }

    final tiles = <ChurchPublicSocialTileData>[];
    final iu = norm(instagramUrl);
    if (iu != null) {
      tiles.add(ChurchPublicSocialTileData(
        channel: 'instagram',
        title: 'Instagram',
        subtitle: 'Feed e comunidade',
        gradient: ChurchPublicSocialPresets.instagramG,
        icon: ChurchPublicSocialPresets.iconInstagram,
        onTap: () {
          onBeforeOpen('instagram');
          launchUri(iu);
        },
      ));
    }
    final yu = norm(youtubeUrl);
    if (yu != null) {
      tiles.add(ChurchPublicSocialTileData(
        channel: 'youtube',
        title: 'YouTube',
        subtitle: 'Vídeos e cultos',
        gradient: ChurchPublicSocialPresets.youtubeG,
        icon: ChurchPublicSocialPresets.iconYoutube,
        onTap: () {
          onBeforeOpen('youtube');
          launchUri(yu);
        },
      ));
    }
    final fu = norm(facebookUrl);
    if (fu != null) {
      tiles.add(ChurchPublicSocialTileData(
        channel: 'facebook',
        title: 'Facebook',
        subtitle: 'Página oficial',
        gradient: ChurchPublicSocialPresets.facebookG,
        icon: ChurchPublicSocialPresets.iconFacebook,
        onTap: () {
          onBeforeOpen('facebook');
          launchUri(fu);
        },
      ));
    }
    if (whatsappUri != null) {
      tiles.add(ChurchPublicSocialTileData(
        channel: 'whatsapp',
        title: 'WhatsApp',
        subtitle: 'Fale com a igreja',
        gradient: ChurchPublicSocialPresets.whatsappG,
        icon: ChurchPublicSocialPresets.iconWhatsapp,
        onTap: () {
          onBeforeOpen('whatsapp');
          launchUri(whatsappUri);
        },
      ));
    }
    return tiles;
  }
}
