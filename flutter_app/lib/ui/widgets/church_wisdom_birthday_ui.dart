import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cor de destaque do módulo Aniversariantes (painel).
const Color kChurchBirthdayAccent = Color(0xFFDB2777);

/// Shell premium WISDOMAPP para o card de aniversariantes no painel.
class ChurchWisdomBirthdayPanelShell extends StatelessWidget {
  const ChurchWisdomBirthdayPanelShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, kChurchBirthdayAccent, 0.06)!,
              Colors.white,
              const Color(0xFFFDF2F8),
            ],
          ),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
          border: Border.all(
            color: kChurchBirthdayAccent.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: kChurchBirthdayAccent.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
            ...ThemeCleanPremium.softUiCardShadow,
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

/// Cabeçalho do card Aniversariantes — WISDOMAPP.
class ChurchWisdomBirthdayPanelHeader extends StatelessWidget {
  const ChurchWisdomBirthdayPanelHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kChurchBirthdayAccent,
                Color.lerp(kChurchBirthdayAccent, Colors.white, 0.25)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: kChurchBirthdayAccent.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.cake_rounded, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aniversariantes',
                style: GoogleFonts.inter(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: const Color(0xFF0F172A),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Celebre com a família da igreja',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Filtros Hoje / Semana / Mês — chips WISDOMAPP.
class ChurchWisdomBirthdayFilterChips extends StatelessWidget {
  const ChurchWisdomBirthdayFilterChips({
    super.key,
    required this.selectedTab,
    required this.onSelected,
    this.accent = kChurchBirthdayAccent,
  });

  final int selectedTab;
  final ValueChanged<int> onSelected;
  final Color accent;

  static const _options = <(int, String, IconData)>[
    (0, 'Hoje', Icons.wb_sunny_outlined),
    (1, 'Semana', Icons.date_range_rounded),
    (2, 'Mês', Icons.calendar_month_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: YahwehWisdomVisualKit.wisdomSectionCard(borderTint: accent),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < _options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _BirthdayTabChip(
                  label: _options[i].$2,
                  icon: _options[i].$3,
                  selected: selectedTab == _options[i].$1,
                  accent: accent,
                  onTap: () => onSelected(_options[i].$1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BirthdayTabChip extends StatelessWidget {
  const _BirthdayTabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: selected ? 1.5 : 0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? accent : const Color(0xFF64748B),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? accent : const Color(0xFF64748B),
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

/// Estado vazio compacto para listas de aniversariantes.
class ChurchWisdomBirthdayEmptyRow extends StatelessWidget {
  const ChurchWisdomBirthdayEmptyRow({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: YahwehWisdomSectionCard(
        borderTint: kChurchBirthdayAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          children: [
            churchWisdomModuleIconLeading(
              icon: Icons.cake_outlined,
              accent: kChurchBirthdayAccent,
              size: 44,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
