import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

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
        final targetH = (fullW * 5 / 4).clamp(240.0, 560.0);
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
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
            color: accentColor.withValues(alpha: 0.07),
            blurRadius: 36,
            offset: const Offset(0, 16),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
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
    );
  }
}
