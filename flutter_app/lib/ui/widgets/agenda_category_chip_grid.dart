import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/agenda_visual_palette.dart';
import 'package:gestao_yahweh/ui/widgets/church_agenda_calendar_cells.dart';
import 'package:google_fonts/google_fonts.dart';

/// Grid de categorias (culto, evento social, etc.) — visual WISDOMAPP.
class AgendaCategoryChipGrid extends StatelessWidget {
  const AgendaCategoryChipGrid({
    super.key,
    required this.selectedKey,
    required this.categoryLabels,
    required this.categoryColors,
    required this.onSelected,
    this.customCategoryDocs = const [],
    this.customCategoryKeyBuilder,
  });

  final String selectedKey;
  final Map<String, String> categoryLabels;
  final Map<String, Color> categoryColors;
  final ValueChanged<String> onSelected;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> customCategoryDocs;
  final String Function(String docId)? customCategoryKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final chips = <({String key, String label, Color color})>[
      for (final e in categoryLabels.entries)
        (key: e.key, label: e.value, color: categoryColors[e.key] ?? AgendaVisualPalette.culto),
      for (final c in customCategoryDocs)
        (
          key: customCategoryKeyBuilder?.call(c.id) ?? 'ec_${c.id}',
          label: (c.data()['nome'] ?? 'Categoria').toString(),
          color: c.data()['cor'] is int
              ? Color(c.data()['cor'] as int)
              : ThemeCleanPremium.primary,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo (culto / compromisso)',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            const minW = 108.0;
            final cols =
                (constraints.maxWidth / (minW + spacing)).floor().clamp(2, 4);
            final itemW =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final chip in chips)
                  SizedBox(
                    width: itemW,
                    child: _CategoryChip(
                      label: chip.label,
                      color: chip.color,
                      selected: selectedKey == chip.key,
                      onTap: () => onSelected(chip.key),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1.1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: ThemeCleanPremium.onSurface,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paleta circular de cores — igual editor de compromissos WISDOMAPP.
class AgendaColorPaletteGrid extends StatelessWidget {
  const AgendaColorPaletteGrid({
    super.key,
    required this.selected,
    required this.onSelected,
    this.colors = ChurchAgendaCalendarCells.compromissoPalette,
  });

  final Color selected;
  final ValueChanged<Color> onSelected;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cor no calendário',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in colors)
              InkWell(
                onTap: () => onSelected(c),
                borderRadius: BorderRadius.circular(99),
                child: CircleAvatar(
                  backgroundColor: c,
                  radius: 18,
                  child: selected == c
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
