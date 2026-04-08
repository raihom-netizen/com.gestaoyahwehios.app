import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme_clean_premium.dart';

/// Cabeçalho discreto de módulo no painel da igreja: cartão claro compacto (menos altura que o gradiente antigo).
class ModuleHeaderPremium extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  /// No mobile, volta ao Painel (índice 0) sem sair do sistema — preenchido pelo [IgrejaCleanShell].
  final VoidCallback? onPainelBack;

  const ModuleHeaderPremium({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onPainelBack,
  });

  static const Color _iconTint = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isPhone = w < ThemeCleanPremium.breakpointMobile; // < 600
    final isVeryNarrow = w < 400;
    final hPad = isVeryNarrow ? 6.0 : (isPhone ? 8.0 : 12.0);
    final vPad = isVeryNarrow ? 4.0 : 5.0;
    final titleSize = isVeryNarrow ? 12.0 : (isPhone ? 13.0 : 14.0);
    final subSize = isVeryNarrow ? 10.5 : 11.5;
    final marginH = isPhone ? 0.0 : ThemeCleanPremium.spaceMd;
    final marginTop = isPhone ? 2.0 : 4.0;
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
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          border: Border.all(color: const Color(0xFFE8EEF4)),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          children: [
            if (onPainelBack != null) ...[
              IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                    color: ThemeCleanPremium.primary.withOpacity(0.9)),
                onPressed: onPainelBack,
                tooltip: 'Voltar ao Painel',
                style: IconButton.styleFrom(
                  minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              SizedBox(width: isVeryNarrow ? 2 : 4),
            ],
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _iconTint, size: isVeryNarrow ? 17 : 19),
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
                              letterSpacing: 0.05,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '·',
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant
                                  .withOpacity(0.7),
                              fontSize: subSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Flexible(
                          flex: 3,
                          child: Text(
                            subtitle!,
                            style: GoogleFonts.inter(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontSize: subSize,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                        letterSpacing: 0.05,
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
