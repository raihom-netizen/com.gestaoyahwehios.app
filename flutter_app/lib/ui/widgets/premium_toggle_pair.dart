import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Alternância de duas opções com **alto contraste** (borda forte + preenchido no ativo).
/// Padrão visual “ultra premium” para PIX/Cartão e similares no painel.
class PremiumTogglePair extends StatelessWidget {
  /// `true` = opção esquerda (A), `false` = direita (B).
  final bool valueIsA;
  final ValueChanged<bool> onChanged;
  final String labelA;
  final String labelB;
  final IconData iconA;
  final IconData iconB;

  const PremiumTogglePair({
    super.key,
    required this.valueIsA,
    required this.onChanged,
    required this.labelA,
    required this.labelB,
    required this.iconA,
    required this.iconB,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    final deep = Color.lerp(primary, const Color(0xFF0F172A), 0.38)!;

    Widget segment({
      required bool selected,
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: selected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primary, deep],
                      )
                    : null,
                color: selected ? null : Colors.white,
                border: Border.all(
                  color: selected
                      ? primary
                      : primary.withValues(alpha: 0.55),
                  width: selected ? 2.2 : 2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.42),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? Colors.white : deep,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: -0.2,
                          color: selected ? Colors.white : deep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
      ),
      child: Row(
        children: [
          segment(
            selected: valueIsA,
            label: labelA,
            icon: iconA,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 10),
          segment(
            selected: !valueIsA,
            label: labelB,
            icon: iconB,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}
