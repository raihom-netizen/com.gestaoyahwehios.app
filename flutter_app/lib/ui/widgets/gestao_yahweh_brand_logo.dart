import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/default_church_logo_asset.dart';

/// Escudo Gestão YAHWEH — renderização nítida (Retina / 4K) para divulgação, login e painéis.
class GestaoYahwehBrandLogo extends StatelessWidget {
  const GestaoYahwehBrandLogo({
    super.key,
    required this.height,
    this.width,
    this.maxWidth,
    this.fit = BoxFit.contain,
    this.showHeroGlow = false,
    this.heroGlowColor,
    this.borderRadius,
    this.fallbackIconColor,
  });

  final double height;
  final double? width;
  final double? maxWidth;
  final BoxFit fit;
  /// Halo suave no hero da landing / divulgação.
  final bool showHeroGlow;
  final Color? heroGlowColor;
  final BorderRadius? borderRadius;
  final Color? fallbackIconColor;

  static const String _primaryAsset = kDefaultChurchLogoAssetPath;
  static const String _syncedAliasAsset = kGestaoYahwehBrandLogoAsset;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    final logicalSide = width ?? height;
    final cachePx = (logicalSide * dpr).round().clamp(256, 4096);

    Widget img = Image.asset(
      _primaryAsset,
      height: height,
      width: width,
      fit: fit,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      cacheHeight: cachePx,
      cacheWidth: width != null ? cachePx : null,
      errorBuilder: (_, __, ___) => Image.asset(
        _syncedAliasAsset,
        height: height,
        width: width,
        fit: fit,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
        cacheHeight: cachePx,
        cacheWidth: width != null ? cachePx : null,
        errorBuilder: (_, __, ___) => Icon(
          Icons.shield_rounded,
          size: height * 0.82,
          color: fallbackIconColor ?? ThemeCleanPremium.primary,
        ),
      ),
    );

    if (maxWidth != null) {
      img = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: img,
      );
    }

    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }

    if (!showHeroGlow) return img;

    final glow = heroGlowColor ?? ThemeCleanPremium.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: kIsWeb ? 0.28 : 0.22),
            blurRadius: 42,
            spreadRadius: 2,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: img,
    );
  }
}

/// Marca tipográfica quando o PNG não carrega.
class GestaoYahwehBrandTextMark extends StatelessWidget {
  const GestaoYahwehBrandTextMark({
    super.key,
    required this.maxSide,
    this.color,
  });

  final double maxSide;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeCleanPremium.primary;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxSide,
        maxWidth: maxSide * 1.35,
        minHeight: 72,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, size: maxSide * 0.22, color: c),
            const SizedBox(height: 8),
            Text(
              'Gestão',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.05,
              ),
            ),
            Text(
              'YAHWEH',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                height: 1.05,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
