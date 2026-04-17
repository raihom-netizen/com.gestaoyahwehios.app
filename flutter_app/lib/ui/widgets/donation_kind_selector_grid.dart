import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Grid 2 colunas — Dízimo vs Oferta (UX Super Premium).
/// [value] é `dizimo` ou `oferta`.
class DonationKindSelectorGrid extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final Color accentColor;

  const DonationKindSelectorGrid({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.toLowerCase().trim();
    final isDizimo = v == 'dizimo' || v == 'dízimo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de contribuição',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Escolha se o valor é dízimo ou oferta — entra no financeiro e no extrato com esse detalhe.',
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey.shade600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: w.clamp(120.0, 400.0),
                  child: _KindCard(
                    selected: isDizimo,
                    accent: accentColor,
                    icon: Icons.church_rounded,
                    title: 'Dízimo',
                    subtitle: 'Fiel à obra',
                    onTap: () => onChanged('dizimo'),
                  ),
                ),
                SizedBox(
                  width: w.clamp(120.0, 400.0),
                  child: _KindCard(
                    selected: !isDizimo,
                    accent: accentColor,
                    icon: Icons.volunteer_activism_rounded,
                    title: 'Oferta',
                    subtitle: 'Oferta voluntária',
                    onTap: () => onChanged('oferta'),
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

class _KindCard extends StatelessWidget {
  final bool selected;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _KindCard({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? Border.all(color: accent, width: 2.2)
        : Border.all(color: const Color(0xFFE2E8F0));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            color: selected
                ? accent.withValues(alpha: 0.09)
                : Colors.white,
            border: border,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? accent : Colors.grey.shade500, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.3,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
