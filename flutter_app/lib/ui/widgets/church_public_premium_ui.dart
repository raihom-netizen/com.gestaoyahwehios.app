import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show FreshFirebaseStorageImage, isValidImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show YahwehPremiumFeedShimmer;

/// Normaliza endereço para comparar evento × sede da igreja (evita repetir o mesmo texto em cada card).
bool churchPublicScheduleVenueRedundant(
  String eventLocation,
  String churchDefaultAddress,
) {
  final a = _scheduleAddrKey(eventLocation);
  final b = _scheduleAddrKey(churchDefaultAddress);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length >= 16 && b.length >= 16) {
    if (a.contains(b) || b.contains(a)) return true;
  }
  return false;
}

String _scheduleAddrKey(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'[^a-z0-9áàâãéêíóôõúç]+'), '');
  s = s.replaceAll('cep', '');
  return s;
}

/// Largura máxima do post no site público (desktop) — coluna central tipo Instagram.
const double kChurchPublicFeedCardMaxWidth = 468;

/// Largura máxima do bloco de mídia no feed (1:1 dentro da coluna).
const double kChurchPublicFeedInstagramMaxWidth = kChurchPublicFeedCardMaxWidth;

/// Largura útil do post de foto/vídeo: telefone em tela cheia; desktop limitado (~IG).
double churchPublicFeedInstagramColumnWidth(double parentMaxWidth) {
  if (parentMaxWidth <= kChurchPublicFeedInstagramMaxWidth) {
    return parentMaxWidth;
  }
  return kChurchPublicFeedInstagramMaxWidth;
}

/// Memória de decode 1:1 alinhada ao quadro do feed (mural / site público).
(int, int) churchPublicCoverMemCache(BuildContext context) {
  final mq = MediaQuery.sizeOf(context);
  final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
  final narrow = mq.width < 600;
  final cardGuess = narrow
      ? (mq.width - 52).clamp(260.0, mq.width)
      : kChurchPublicFeedCardMaxWidth;
  final logicalW = churchPublicFeedInstagramColumnWidth(cardGuess);
  // Feed tipo Instagram (~4:5) — mais alto que quadrado para não “achatar” retratos.
  final logicalH = logicalW * 5 / 4;
  final w = (logicalW * dpr).round().clamp(400, 1200);
  final h = (logicalH * dpr).round().clamp(400, 1400);
  return (w, h);
}

/// Altura útil para vídeos institucionais / blocos que não usam o quadro quadrado do feed.
double churchPublicFeedMediaMaxHeight(Size mq) {
  if (mq.width < 600) {
    return (mq.width * 0.52).clamp(200.0, 320.0);
  }
  return (mq.shortestSide * 0.36).clamp(200.0, 280.0);
}

/// Altura do carrossel de fotos no mural (painel / app): evita pôsteres verticais a ocupar o ecrã inteiro.
/// [widthOverHeightAspect] é largura÷altura (ex.: 4/5 = 0,8 para retrato tipo Instagram).
double churchMuralCarouselClipHeight(
  BuildContext context,
  double cardWidth,
  double widthOverHeightAspect,
) {
  if (cardWidth <= 0) return 0;
  final mq = MediaQuery.sizeOf(context);
  final screenH = mq.height;
  final screenW = mq.width;
  final narrow = screenW < 600;
  final ar = widthOverHeightAspect.clamp(0.5, 2.0);
  final idealH = cardWidth / ar;
  // Tectos mais generosos: antes ~320px cortava demais e o cover “esmagava” a composição.
  final capScreen = screenH * (narrow ? 0.52 : 0.46);
  final capAbs = narrow ? 560.0 : 520.0;
  final maxH = math.min(capScreen, capAbs);
  return idealH.clamp(188.0, maxH);
}

/// Faixa de mídia no feed: proporção ~4:5 (estilo Instagram), mais alta que 16:9.
class ChurchPublicConstrainedMedia extends StatelessWidget {
  final Widget child;

  const ChurchPublicConstrainedMedia({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullW = constraints.maxWidth;
        if (fullW <= 0) return const SizedBox.shrink();
        // Área mais alta para pôsteres/eventos: mídia com [BoxFit.contain] no filho.
        final targetH = (fullW * 5 / 4).clamp(200.0, 560.0);
        return SizedBox(
          width: fullW,
          height: targetH,
          child: ColoredBox(
            color: const Color(0xFFF1F5F9),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: fullW,
                height: targetH,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shell de seção editorial — kicker, título, subtítulo, ícone em pastilha com gradiente suave.
class ChurchPublicPremiumSection extends StatelessWidget {
  final String kicker;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  const ChurchPublicPremiumSection({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 18),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: 0.16),
                      accentColor.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kicker.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: accentColor.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

/// Controle de play estilo vidro (overlay em vídeos).
class ChurchPublicPremiumPlayOrb extends StatelessWidget {
  final double diameter;

  const ChurchPublicPremiumPlayOrb({super.key, this.diameter = 58});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: diameter * 0.52,
      ),
    );
  }
}

/// Centraliza e limita a largura de cada item do feed no desktop (cartão + barra social + ações).
class ChurchPublicFeedItemWidth extends StatelessWidget {
  final Widget child;

  const ChurchPublicFeedItemWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return child;
    return Center(
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: kChurchPublicFeedCardMaxWidth),
        child: child,
      ),
    );
  }
}

/// Card de conteúdo do feed (mural) — borda e sombra premium.
class ChurchPublicPremiumFeedCard extends StatelessWidget {
  final Widget child;

  const ChurchPublicPremiumFeedCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Cartão interno para programação fixa / linha de evento.
class ChurchPublicPremiumScheduleTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Color accent;

  const ChurchPublicPremiumScheduleTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: accent, width: 4),
          top: const BorderSide(color: Color(0xFFF1F5F9)),
          right: const BorderSide(color: Color(0xFFF1F5F9)),
          bottom: const BorderSide(color: Color(0xFFF1F5F9)),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Programação pública: layout compacto com thumb lateral.
class ChurchPublicPremiumScheduleEventCard extends StatelessWidget {
  final String title;
  /// Ex.: "Dom" — atalho quando não há [weekdayLongLabel].
  final String weekdayLabel;
  /// Ex.: "domingo" (nome completo) para a pastilha do dia da semana.
  final String weekdayLongLabel;
  /// Ex.: "14/04/2026"
  final String dateShort;
  final String timeLabel;
  final String location;
  /// Endereço principal do cadastro da igreja — se [location] for equivalente, não repete no card.
  final String churchDefaultAddress;
  final String imageUrl;
  final Color accent;
  final VoidCallback? onTap;

  const ChurchPublicPremiumScheduleEventCard({
    super.key,
    required this.title,
    required this.weekdayLabel,
    this.weekdayLongLabel = '',
    required this.dateShort,
    required this.timeLabel,
    required this.location,
    this.churchDefaultAddress = '',
    required this.imageUrl,
    required this.accent,
    this.onTap,
  });

  bool get _hasPhoto =>
      imageUrl.trim().isNotEmpty && isValidImageUrl(imageUrl.trim());

  bool get _showVenueLine {
    final loc = location.trim();
    if (loc.isEmpty) return false;
    final def = churchDefaultAddress.trim();
    if (def.isEmpty) return true;
    return !churchPublicScheduleVenueRedundant(loc, def);
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(22);
    final weekdayLine = weekdayLongLabel.isNotEmpty
        ? weekdayLongLabel
        : weekdayLabel;
    final deep = Color.lerp(accent, const Color(0xFF0F172A), 0.42)!;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Color.lerp(Colors.white, accent, 0.04)!,
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: Color.lerp(const Color(0xFFE2E8F0), accent, 0.12)!,
              width: 1.2,
            ),
            boxShadow: [
              ...ThemeCleanPremium.softUiCardShadow,
              BoxShadow(
                color: accent.withValues(alpha: 0.1),
                blurRadius: 36,
                offset: const Offset(0, 18),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _hasPhoto
                        ? FreshFirebaseStorageImage(
                            imageUrl: imageUrl.trim(),
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            memCacheHeight: 360,
                            placeholder: YahwehPremiumFeedShimmer.mediaCover(),
                            errorWidget: _SchedulePhotoFallback(
                              accent: accent,
                              compact: true,
                            ),
                          )
                        : _SchedulePhotoFallback(accent: accent, compact: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.2,
                          color: deep,
                        ),
                      ),
                      if (dateShort.isNotEmpty ||
                          weekdayLine.isNotEmpty ||
                          timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ScheduleWhenChips(
                          accent: accent,
                          dateShort: dateShort,
                          weekdayLine: weekdayLine,
                          timeLabel: timeLabel,
                          compact: true,
                        ),
                      ],
                      if (_showVenueLine) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_rounded,
                              size: 16,
                              color: accent.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                location.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.8,
                                  height: 1.35,
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 22, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Data / dia / hora em pastilhas separadas (legibilidade + aspecto premium).
class _ScheduleWhenChips extends StatelessWidget {
  final Color accent;
  final String dateShort;
  final String weekdayLine;
  final String timeLabel;
  final bool compact;

  const _ScheduleWhenChips({
    required this.accent,
    required this.dateShort,
    required this.weekdayLine,
    required this.timeLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final deep = Color.lerp(accent, const Color(0xFF0F172A), 0.35)!;

    Widget? chip(IconData icon, String text, {required bool filled}) {
      if (text.isEmpty) return null;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 8,
        ),
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.95),
                    Color.lerp(accent, deep, 0.15)!,
                  ],
                )
              : null,
          color: filled ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled
                ? Colors.transparent
                : accent.withValues(alpha: 0.28),
            width: 1.2,
          ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 13 : 16,
              color: filled ? Colors.white : accent,
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              text,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: filled ? Colors.white : deep,
              ),
            ),
          ],
        ),
      );
    }

    final c1 = chip(Icons.calendar_today_rounded, dateShort, filled: true);
    final c2 = chip(Icons.wb_sunny_rounded, weekdayLine, filled: false);
    final c3 = chip(Icons.schedule_rounded, timeLabel, filled: false);

    final row = <Widget>[];
    if (c1 != null) row.add(c1);
    if (c2 != null) {
      if (row.isNotEmpty) row.add(const SizedBox(width: 8));
      row.add(c2);
    }
    if (c3 != null) {
      if (row.isNotEmpty) row.add(const SizedBox(width: 8));
      row.add(c3);
    }
    if (row.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < (compact ? 280 : 340)) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (c1 != null) c1,
              if (c2 != null) c2,
              if (c3 != null) c3,
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: row),
        );
      },
    );
  }
}

class _SchedulePhotoFallback extends StatelessWidget {
  final Color accent;
  final bool compact;

  const _SchedulePhotoFallback({
    required this.accent,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final h = compact ? 120.0 : 168.0;
    return SizedBox(
      height: h,
      width: double.infinity,
      child: ClipRRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  const Color(0xFFF8FAFC),
                  Color.lerp(const Color(0xFFEFF6FF), accent, 0.06)!,
                ],
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: -24,
            child: Icon(
              Icons.event_repeat_rounded,
              size: compact ? 72 : 120,
              color: accent.withValues(alpha: 0.07),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_available_rounded,
                  size: compact ? 44 : 52,
                  color: accent.withValues(alpha: 0.5),
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Imagem opcional',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent.withValues(alpha: 0.55),
                      letterSpacing: 0.2,
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
