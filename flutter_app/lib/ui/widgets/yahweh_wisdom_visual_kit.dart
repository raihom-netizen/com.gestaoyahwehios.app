import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_design_system.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';

/// Primitivos visuais WISDOMAPP — painel igreja, site público e divulgação.
abstract final class YahwehWisdomVisualKit {
  YahwehWisdomVisualKit._();

  static const Color goldLight = YahwehDesignSystem.wisdomGoldLight;
  static const Color gold = YahwehDesignSystem.wisdomGold;
  static const Color goldDeep = Color(0xFFB8941F);
  static const Color navyDeep = YahwehDesignSystem.wisdomNavyDeep;
  static const Color navyMid = YahwehDesignSystem.wisdomNavyMid;
  static const Color tealAccent = YahwehDesignSystem.wisdomTealAccent;

  static LinearGradient get panelBodyGradient =>
      YahwehDesignSystem.panelBodyGradient;

  static LinearGradient get publicPageGradient =>
      YahwehDesignSystem.publicPageGradient;

  /// Corpo de módulo com abas (Financeiro, Patrimônio, Fornecedores).
  static BoxDecoration moduleBodyGradient(Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(accent, Colors.white, 0.68)!,
          const Color(0xFFF8FAFC),
          YahwehDesignSystem.surfaceVariant,
        ],
        stops: const [0.0, 0.28, 1.0],
      ),
    );
  }

  static List<BoxShadow> get softElevatedShadow => YahwehDesignSystem.softCardShadow;

  static BoxDecoration wisdomSectionCard({Color? borderTint}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(YahwehDesignSystem.radiusMd),
      border: Border.all(
        color: borderTint?.withValues(alpha: 0.12) ?? const Color(0xFFE2E8F0),
      ),
      boxShadow: softElevatedShadow,
    );
  }
}

/// Título com gradiente dourado — hero WISDOMAPP.
class YahwehWisdomGoldTitle extends StatelessWidget {
  const YahwehWisdomGoldTitle({
    super.key,
    required this.text,
    this.fontSize,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final double? fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final fs = fontSize ?? (w > 600 ? 34.0 : 28.0);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1E3A8A),
          YahwehWisdomVisualKit.navyMid,
          YahwehWisdomVisualKit.tealAccent,
        ],
      ).createShader(bounds),
      child: Text(
        text,
        textAlign: textAlign,
        style: GoogleFonts.poppins(
          fontSize: fs,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.15,
        ),
      ),
    );
  }
}

/// Navegação por seções (chips) — landing / divulgação WISDOMAPP.
class YahwehWisdomPublicSectionNav extends StatelessWidget {
  const YahwehWisdomPublicSectionNav({
    super.key,
    required this.sections,
    this.selectedIndex = 0,
    this.onSelected,
    this.compact = false,
  });

  final List<({String label, IconData icon})> sections;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < sections.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SectionChip(
                    label: sections[i].label,
                    icon: sections[i].icon,
                    selected: i == selectedIndex,
                    onTap: onSelected == null ? null : () => onSelected!(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeCleanPremium.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: selected ? accent.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? accent : ThemeCleanPremium.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? accent : ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de seção branco — conteúdo em landings e painel.
class YahwehWisdomSectionCard extends StatelessWidget {
  const YahwehWisdomSectionCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderTint,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderTint;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: YahwehWisdomVisualKit.wisdomSectionCard(borderTint: borderTint),
      child: Padding(
        padding: padding ?? ThemeCleanPremium.pagePadding(context),
        child: child,
      ),
    );
  }
}

/// Envolve o corpo de módulo do painel com gradiente WISDOMAPP.
class YahwehWisdomPanelBackdrop extends StatelessWidget {
  const YahwehWisdomPanelBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: YahwehWisdomVisualKit.panelBodyGradient),
      child: child,
    );
  }
}
