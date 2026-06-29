import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_login_ui.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card premium WISDOMAPP — site público / cadastro membro / status.
class ChurchWisdomPublicSurfaceCard extends StatelessWidget {
  const ChurchWisdomPublicSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final a = accent ?? kChurchWisdomLoginTeal;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color.lerp(Colors.white, a, 0.04)!,
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: YahwehWisdomVisualKit.softElevatedShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Estado de carregamento — site público / acompanhar cadastro.
class ChurchWisdomPublicLoading extends StatelessWidget {
  const ChurchWisdomPublicLoading({
    super.key,
    this.message = 'Carregando…',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ChurchWisdomPublicSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: kChurchWisdomLoginTeal,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge de status do cadastro público.
class ChurchWisdomPublicStatusBadge extends StatelessWidget {
  const ChurchWisdomPublicStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
