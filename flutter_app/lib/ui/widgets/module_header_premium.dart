import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/yahweh_design_system.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';
import '../theme_clean_premium.dart';

/// Variante visual do cabeçalho de módulo.
enum ModuleHeaderVariant {
  /// Cartão branco compacto (desktop / módulos leves).
  card,
  /// Barra gradiente WISDOMAPP (mobile shell — padrão).
  wisdomGradient,
}

/// Cabeçalho de módulo no painel da igreja — padrão WISDOMAPP.
class ModuleHeaderPremium extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Color? accent;
  final ModuleHeaderVariant variant;
  /// No mobile, volta ao Painel (índice 0) sem sair do sistema — preenchido pelo [IgrejaCleanShell].
  final VoidCallback? onPainelBack;

  const ModuleHeaderPremium({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.accent,
    this.variant = ModuleHeaderVariant.wisdomGradient,
    this.onPainelBack,
  });

  static const Color _iconTint = Color(0xFF3B82F6);

  Color get _accent => accent ?? ThemeCleanPremium.primary;

  @override
  Widget build(BuildContext context) {
    if (variant == ModuleHeaderVariant.wisdomGradient && onPainelBack != null) {
      return ChurchEmbeddedModuleBar(
        title: title,
        icon: icon,
        accent: _accent,
        onBack: onPainelBack!,
        subtitle: subtitle,
      );
    }
    return _buildCardHeader(context);
  }

  Widget _buildCardHeader(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isPhone = w < ThemeCleanPremium.breakpointMobile;
    final isVeryNarrow = w < 400;
    final hPad = isVeryNarrow ? 6.0 : (isPhone ? 8.0 : 12.0);
    final vPad = isVeryNarrow ? 4.0 : 5.0;
    final titleSize = isVeryNarrow ? 12.0 : (isPhone ? 13.0 : 14.0);
    final subSize = isVeryNarrow ? 10.5 : 11.5;
    final marginH = isPhone ? 0.0 : ThemeCleanPremium.spaceMd;
    final marginTop = isPhone ? 0.0 : 4.0;
    return Semantics(
      header: true,
      label: subtitle != null && subtitle!.isNotEmpty
          ? '$title. $subtitle'
          : title,
      child: Container(
        margin: EdgeInsets.fromLTRB(marginH, marginTop, marginH, 0),
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(YahwehDesignSystem.radiusMd),
          border: Border.all(color: const Color(0xFFE8EEF4)),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          children: [
            if (onPainelBack != null) ...[
              YahwehSuperPremiumBackButton(
                onPressed: onPainelBack,
                tooltip: 'Voltar ao Painel',
                variant: YahwehSuperPremiumBackVariant.onLightSurface,
              ),
              SizedBox(width: isVeryNarrow ? 4 : 6),
            ],
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _accent, size: isVeryNarrow ? 17 : 19),
            ),
            SizedBox(width: isVeryNarrow ? 6 : 8),
            Expanded(
              child: subtitle != null && subtitle!.isNotEmpty
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          flex: 2,
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              color: ThemeCleanPremium.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: titleSize,
                              letterSpacing: -0.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 3,
                          child: Text(
                            subtitle!,
                            style: GoogleFonts.inter(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              fontSize: subSize,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      title,
                      style: GoogleFonts.inter(
                        color: ThemeCleanPremium.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: titleSize,
                        letterSpacing: -0.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
