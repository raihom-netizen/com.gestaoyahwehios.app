import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Variante visual do botão Voltar Super Premium.
enum YahwehSuperPremiumBackVariant {
  /// Sobre AppBar azul forte — cápsula branca + seta azul.
  onDarkAppBar,
  /// Sobre fundo claro (cartão do módulo, listas) — cápsula azul + seta branca.
  onLightSurface,
}

/// Botão «Voltar» sempre visível — azul forte, sombra e área de toque 48dp.
class YahwehSuperPremiumBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final YahwehSuperPremiumBackVariant variant;

  const YahwehSuperPremiumBackButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Voltar',
    this.variant = YahwehSuperPremiumBackVariant.onLightSurface,
  });

  /// Leading para [AppBar] — `null` se não houver para onde voltar.
  static Widget? appBarLeading(
    BuildContext context, {
    VoidCallback? onPressed,
    YahwehSuperPremiumBackVariant variant =
        YahwehSuperPremiumBackVariant.onDarkAppBar,
    String tooltip = 'Voltar',
  }) {
    final canPop = Navigator.canPop(context);
    if (!canPop && onPressed == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
      child: YahwehSuperPremiumBackButton(
        onPressed: onPressed ?? () => Navigator.maybePop(context),
        variant: variant,
        tooltip: tooltip,
      ),
    );
  }

  static const Color _strongBlue = ThemeCleanPremium.primary;

  @override
  Widget build(BuildContext context) {
    final isOnDark = variant == YahwehSuperPremiumBackVariant.onDarkAppBar;

    final decoration = isOnDark
        ? BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _strongBlue.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          )
        : BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _strongBlue,
                ThemeCleanPremium.primaryLight,
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _strongBlue.withValues(alpha: 0.38),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          );

    final iconColor = isOnDark ? _strongBlue : Colors.white;

    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: decoration,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: iconColor, size: 26),
            onPressed: onPressed,
            tooltip: tooltip,
            style: IconButton.styleFrom(
              minimumSize: const Size(
                ThemeCleanPremium.minTouchTarget,
                ThemeCleanPremium.minTouchTarget,
              ),
              visualDensity: VisualDensity.standard,
            ),
          ),
        ),
      ),
    );
  }
}
