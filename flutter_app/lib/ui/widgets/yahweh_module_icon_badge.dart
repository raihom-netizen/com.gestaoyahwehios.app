import 'package:flutter/material.dart';
import 'package:gestao_yahweh/constants/yahweh_module_icon_assets.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Badge PNG de módulo — padrão Controle Total (cartão + emblema YAHWEH).
class YahwehModuleIconBadge extends StatelessWidget {
  const YahwehModuleIconBadge({
    super.key,
    required this.moduleKey,
    this.size = 44,
    this.accent,
    this.fallbackToMaterial = true,
  });

  final String? moduleKey;
  final double size;
  final Color? accent;
  final bool fallbackToMaterial;

  @override
  Widget build(BuildContext context) {
    final asset = YahwehModuleIconAssets.forModuleKey(moduleKey);
    final a = accent ?? ThemeCleanPremium.primary;

    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.27),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: fallbackToMaterial
                ? (_, __, ___) => _MaterialFallback(
                      moduleKey: moduleKey,
                      size: size,
                      accent: a,
                    )
                : null,
          ),
        ),
      );
    }

    return _MaterialFallback(moduleKey: moduleKey, size: size, accent: a);
  }
}

class _MaterialFallback extends StatelessWidget {
  const _MaterialFallback({
    required this.moduleKey,
    required this.size,
    required this.accent,
  });

  final String? moduleKey;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          YahwehModuleIconAssets.materialFallback(moduleKey),
          color: accent,
          size: size * 0.48,
        ),
      ),
    );
  }
}

/// Ícone avisos sem fundo — emblema YAHWEH transparente.
class YahwehAvisosEmblemIcon extends StatelessWidget {
  const YahwehAvisosEmblemIcon({
    super.key,
    this.size = 48,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      YahwehModuleIconAssets.avisos,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
