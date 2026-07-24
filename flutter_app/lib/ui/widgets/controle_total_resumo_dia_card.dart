import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// «Resumo do dia» — visual idêntico ao módulo Escalas do Controle Total.
///
/// Barra gradiente no topo, título em negrito, data `EEEE, dd/MM/yyyy`,
/// dica de toque e lista de itens; opcionalmente rodapé «Total do dia».
class ControleTotalResumoDiaCard extends StatelessWidget {
  const ControleTotalResumoDiaCard({
    super.key,
    required this.day,
    required this.children,
    this.showTapHint = true,
    this.tapHint =
        'Toque novamente no dia no calendário para incluir, trocar ou editar.',
    this.footer,
    this.emptyMessage = 'Nenhum compromisso neste dia.',
  });

  final DateTime day;
  final List<Widget> children;
  final bool showTapHint;
  final String tapHint;
  final Widget? footer;
  final String emptyMessage;

  static const List<Color> _logoGradient = [
    Color(0xFF0C3B8A),
    Color(0xFF0E7490),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final fsHeader = isMobile ? 15.0 : 15.5;
    final fsDate = isMobile ? 12.0 : 12.5;
    final fsHint = isMobile ? 11.0 : 11.5;
    final raw = DateFormat("EEEE, dd/MM/yyyy", 'pt_BR').format(day);
    final dateLabel =
        raw.isEmpty ? raw : '${raw[0].toUpperCase()}${raw.substring(1)}';

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: _logoGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Resumo do dia',
                  style: GoogleFonts.poppins(
                    fontSize: fsHeader,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.35,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: GoogleFonts.poppins(
                    fontSize: fsDate,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                ),
                if (showTapHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    tapHint,
                    style: GoogleFonts.poppins(
                      fontSize: fsHint,
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (children.isEmpty)
                  Text(
                    emptyMessage,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  )
                else
                  ...children,
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  footer!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha de item no resumo — barra colorida + ícone + título (padrão Escalas CT).
class ControleTotalResumoDiaItem extends StatelessWidget {
  const ControleTotalResumoDiaItem({
    super.key,
    required this.accent,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.onTap,
    this.below,
  });

  final Color accent;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final titleFs = isMobile ? 15.5 : 16.5;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 5,
              height: 42,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: titleFs,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.primary,
                      height: 1.3,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(height: 4),
                  trailing!,
                ],
                if (below != null) ...[
                  const SizedBox(height: 4),
                  below!,
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: row,
      ),
    );
  }
}
