import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipos visuais canónicos da agenda (calendário + lista + PDF).
enum AgendaVisualKind {
  evento,
  culto,
  curso,
  escala,
  pendencia,
  feriado,
}

/// Paleta unificada — escalas, eventos, cursos e pendências.
abstract final class AgendaVisualPalette {
  AgendaVisualPalette._();

  static const Color evento = Color(0xFF7C3AED);
  static const Color culto = Color(0xFF2563EB);
  static const Color curso = Color(0xFF16A34A);
  static const Color escala = Color(0xFF0D9488);
  static const Color pendencia = Color(0xFFEA580C);
  static const Color eventoSocial = Color(0xFFE11D48);
  static const Color lideranca = Color(0xFF7C3AED);
  static const Color agendaInterna = Color(0xFF3B82F6);
  static const Color feedEvento = Color(0xFFDB2777);
  static const Color feriado = Color(0xFFE11D48);

  static const Map<String, Color> categoryColors = {
    'culto': culto,
    'evento_social': eventoSocial,
    'lideranca': lideranca,
    'ensino_ebd': curso,
  };

  static const Map<String, String> categoryLabels = {
    'culto': 'Cultos',
    'evento_social': 'Eventos sociais',
    'lideranca': 'Liderança',
    'ensino_ebd': 'Cursos / EBD',
  };

  static const Map<String, Color> legacyTypeColors = {
    'Culto': culto,
    'Evento': evento,
    'Célula': curso,
    'Reunião': lideranca,
  };

  static Color? hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceFirst('#', '').trim();
    if (h.length != 6) return null;
    final r = int.tryParse(h.substring(0, 2), radix: 16);
    final g = int.tryParse(h.substring(2, 4), radix: 16);
    final b = int.tryParse(h.substring(4, 6), radix: 16);
    if (r == null || g == null || b == null) return null;
    return Color(0xFF000000 | (r << 16) | (g << 8) | b);
  }

  static String colorToHex(Color c) {
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '$r$g$b';
  }

  static AgendaVisualKind kindFor({
    required String source,
    String? categoryKey,
    String? type,
    bool hasConflict = false,
    bool generatedFromTemplate = false,
  }) {
    if (hasConflict || generatedFromTemplate) {
      return AgendaVisualKind.pendencia;
    }
    final ck = (categoryKey ?? '').trim();
    if (ck == 'ensino_ebd') return AgendaVisualKind.curso;
    if (ck == 'culto' || source == 'cultos') return AgendaVisualKind.culto;
    if (source == 'agenda') return AgendaVisualKind.evento;
    if (source == 'noticias') return AgendaVisualKind.evento;
    final t = (type ?? '').toLowerCase();
    if (t.contains('ebd') ||
        t.contains('ensino') ||
        t.contains('curso') ||
        t.contains('célula') ||
        t.contains('celula')) {
      return AgendaVisualKind.curso;
    }
    if (t.contains('culto')) return AgendaVisualKind.culto;
    return AgendaVisualKind.evento;
  }

  static Color colorFor({
    required String source,
    String? categoryKey,
    String? type,
    String? eventColorHex,
    bool hasConflict = false,
    bool generatedFromTemplate = false,
  }) {
    final custom = hexToColor(eventColorHex);
    if (custom != null) return custom;

    final ck = (categoryKey ?? '').trim();
    if (ck.isNotEmpty && categoryColors.containsKey(ck)) {
      return categoryColors[ck]!;
    }

    if (source == 'cultos') return culto;
    if (source == 'agenda') return agendaInterna;
    if (source == 'noticias') return feedEvento;

    final normalized = (type ?? '').trim();
    if (legacyTypeColors.containsKey(normalized)) {
      return legacyTypeColors[normalized]!;
    }

    return switch (kindFor(
      source: source,
      categoryKey: categoryKey,
      type: type,
      hasConflict: hasConflict,
      generatedFromTemplate: generatedFromTemplate,
    )) {
      AgendaVisualKind.culto => culto,
      AgendaVisualKind.curso => curso,
      AgendaVisualKind.pendencia => pendencia,
      AgendaVisualKind.feriado => feriado,
      AgendaVisualKind.escala => escala,
      AgendaVisualKind.evento => evento,
    };
  }

  static Color chipBackground(Color accent) =>
      accent.withValues(alpha: 0.12);

  static Color chipForeground(Color accent) {
    final lum = accent.computeLuminance();
    return lum > 0.55
        ? Color.lerp(accent, const Color(0xFF0F172A), 0.72)!
        : accent;
  }

  static IconData iconForKind(AgendaVisualKind kind) {
    switch (kind) {
      case AgendaVisualKind.evento:
        return Icons.event_rounded;
      case AgendaVisualKind.culto:
        return Icons.church_rounded;
      case AgendaVisualKind.curso:
        return Icons.menu_book_rounded;
      case AgendaVisualKind.escala:
        return Icons.calendar_month_rounded;
      case AgendaVisualKind.pendencia:
        return Icons.warning_amber_rounded;
      case AgendaVisualKind.feriado:
        return Icons.flag_rounded;
    }
  }
}

/// Legenda fixa — código de cores da agenda.
class AgendaColorLegend extends StatelessWidget {
  const AgendaColorLegend({
    super.key,
    this.compact = false,
  });

  final bool compact;

  static const _items = <({String label, Color color, IconData icon})>[
    (label: 'Eventos', color: AgendaVisualPalette.evento, icon: Icons.event_rounded),
    (label: 'Cursos / EBD', color: AgendaVisualPalette.curso, icon: Icons.menu_book_rounded),
    (label: 'Cultos', color: AgendaVisualPalette.culto, icon: Icons.church_rounded),
    (label: 'Escalas', color: AgendaVisualPalette.escala, icon: Icons.groups_rounded),
    (label: 'Pendências', color: AgendaVisualPalette.pendencia, icon: Icons.warning_amber_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Código de cores',
            style: GoogleFonts.poppins(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Wrap(
            spacing: compact ? 8 : 10,
            runSpacing: compact ? 6 : 8,
            children: [
              for (final item in _items)
                _LegendChip(
                  label: item.label,
                  color: item.color,
                  icon: item.icon,
                  compact: compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.compact,
  });

  final String label;
  final Color color;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 18 : 20,
          height: compact ? 18 : 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
          ),
          child: Icon(icon, size: compact ? 11 : 12, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: compact ? 10.5 : 11.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF334155),
          ),
        ),
      ],
    );
  }
}

/// Indicador compacto no canto da célula do calendário.
class AgendaDayCornerBadge extends StatelessWidget {
  const AgendaDayCornerBadge({
    super.key,
    required this.color,
    this.icon,
    this.tooltip,
  });

  final Color color;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: icon != null ? 14 : 8,
      height: icon != null ? 14 : 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: icon == null
          ? null
          : Icon(icon, size: 9, color: Colors.white),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}
