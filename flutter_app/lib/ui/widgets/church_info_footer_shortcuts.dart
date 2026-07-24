import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_shell_nav_icon.dart';
import 'package:google_fonts/google_fonts.dart';

/// Atalhos coloridos no rodapé — mesmo padrão 3D do menu lateral / shell mobile.
class ChurchInfoFooterShortcuts extends StatelessWidget {
  const ChurchInfoFooterShortcuts({
    super.key,
    required this.onNavigate,
    this.indices = const [
      ChurchShellIndices.painel,
      ChurchShellIndices.membros,
      ChurchShellIndices.financeiro,
      ChurchShellIndices.muralAvisos,
      ChurchShellIndices.muralEventos,
      ChurchShellIndices.chatIgreja,
    ],
  });

  final ValueChanged<int> onNavigate;
  final List<int> indices;

  static const Map<int, String> _shortLabels = {
    ChurchShellIndices.painel: 'Início',
    ChurchShellIndices.membros: 'Membros',
    ChurchShellIndices.financeiro: 'Financeiro',
    ChurchShellIndices.muralAvisos: 'Avisos',
    ChurchShellIndices.muralEventos: 'Eventos',
    ChurchShellIndices.chatIgreja: 'Yahweh Chat',
    ChurchShellIndices.agenda: 'Agenda',
    ChurchShellIndices.departamentos: 'Deptos',
    ChurchShellIndices.relatorios: 'Relatórios',
    ChurchShellIndices.informacoes: 'Info',
  };

  @override
  Widget build(BuildContext context) {
    final items = indices
        .where((i) => i >= 0 && i < kChurchShellNavEntries.length)
        .map((i) => (index: i, entry: kChurchShellNavEntries[i]))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Color.lerp(Colors.white, const Color(0xFFEFF6FF), 0.55)!,
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Atalhos rápidos',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF475569),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = items.length;
              final slotW = constraints.maxWidth / count;
              final circleSize =
                  (slotW * 0.52).clamp(30.0, 40.0).toDouble();
              final glyphSize =
                  (circleSize * 0.46).clamp(14.0, 18.0).toDouble();
              final labelSize = constraints.maxWidth < 360 ? 8.0 : 9.0;
              return Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _ShortcutChip(
                        label: _shortLabels[item.index] ?? item.entry.label,
                        tooltip: item.entry.label,
                        accent: item.entry.accent,
                        icon: item.entry.icon,
                        circleSize: circleSize,
                        iconSize: glyphSize,
                        labelFontSize: labelSize,
                        onTap: () => onNavigate(item.index),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.label,
    required this.tooltip,
    required this.accent,
    required this.icon,
    required this.circleSize,
    required this.iconSize,
    required this.labelFontSize,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final Color accent;
  final IconData icon;
  final double circleSize;
  final double iconSize;
  final double labelFontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: accent.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChurchShellNavIcon3D(
                  icon: icon,
                  accent: accent,
                  shape: ChurchShellIconShape.circle,
                  size: circleSize,
                  iconSize: iconSize,
                  compact: true,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: labelFontSize,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
