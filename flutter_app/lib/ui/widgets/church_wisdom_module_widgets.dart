import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card horizontal flutuante — listas de módulos (Membros, Cargos, Visitantes, etc.).
class ChurchWisdomModuleListCard extends StatelessWidget {
  const ChurchWisdomModuleListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.accent,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? ThemeCleanPremium.primary;
    final borderRadius = BorderRadius.circular(ThemeCleanPremium.radiusLg);
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white,
                  Color.lerp(Colors.white, a, 0.05)!,
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: YahwehWisdomVisualKit.softElevatedShadow,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 12 : 14,
                vertical: dense ? 10 : 12,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    SizedBox(width: dense ? 10 : 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: dense ? 14 : 15,
                            letterSpacing: -0.2,
                            height: 1.25,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    trailing!
                  else if (onTap != null)
                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Estado vazio premium — módulos do painel.
class ChurchWisdomModuleEmptyState extends StatelessWidget {
  const ChurchWisdomModuleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? ThemeCleanPremium.primary;
    return Center(
      child: Padding(
        padding: ThemeCleanPremium.pagePadding(context),
        child: YahwehWisdomSectionCard(
          borderTint: a,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: a.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: a),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    backgroundColor: a,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Leading quadrado com ícone — listas de módulos.
Widget churchWisdomModuleIconLeading({
  required IconData icon,
  required Color accent,
  double size = 48,
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withValues(alpha: 0.2)),
      color: accent.withValues(alpha: 0.1),
    ),
    child: SizedBox(
      width: size,
      height: size,
      child: Icon(icon, color: accent, size: size * 0.46),
    ),
  );
}
