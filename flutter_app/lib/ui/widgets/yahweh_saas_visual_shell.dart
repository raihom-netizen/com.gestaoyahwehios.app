import 'package:flutter/material.dart';
import 'package:gestao_yahweh/constants/yahweh_module_icon_assets.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_login_ui.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_yahweh_brand_logo.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

export 'package:gestao_yahweh/ui/widgets/church_wisdom_login_ui.dart'
    show
        ChurchWisdomLoginBackdrop,
        ChurchWisdomLoginAppBar,
        ChurchWisdomLoginHeroCard,
        ChurchWisdomLoginFormCard,
        ChurchWisdomAuthCenter,
        ChurchWisdomCardBrandHeader,
        ChurchWisdomLoginScriptureFooter,
        authCompactFieldDecoration,
        kAuthScreenMaxWidth,
        kChurchWisdomLoginGold,
        kChurchWisdomLoginNavy,
        kChurchWisdomLoginTeal;

/// Shell visual unificado — login, planos, licença, checkout e bloqueios.
abstract final class YahwehSaasVisualShell {
  YahwehSaasVisualShell._();

  static Widget brandEmblem({
    double size = 88,
    bool glow = true,
  }) {
    return GestaoYahwehBrandLogo(
      height: size,
      width: size,
      showHeroGlow: glow,
      heroGlowColor: kChurchWisdomLoginGold,
    );
  }

  static Widget transparentEmblem({double size = 88}) {
    return Image.asset(
      YahwehModuleIconAssets.emblemaTransparent,
      height: size,
      width: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => brandEmblem(size: size),
    );
  }

  static Widget hero({
    required String title,
    String? subtitle,
    double logoSize = 96,
    bool transparentLogo = false,
  }) {
    return ChurchWisdomLoginHeroCard(
      logo: transparentLogo
          ? transparentEmblem(size: logoSize)
          : brandEmblem(size: logoSize),
      greeting: title,
      subtitle: subtitle,
    );
  }

  static Widget surfaceCard({required Widget child, EdgeInsets? padding}) {
    return ChurchWisdomLoginFormCard(
      child: padding != null
          ? Padding(padding: padding, child: child)
          : child,
    );
  }

  static Widget securityFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded,
            size: 14, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(
          'Conexão segura · Pagamento via Mercado Pago',
          style: GoogleFonts.inter(
            color: Colors.grey.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static Widget primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: ThemeCleanPremium.minTouchTarget,
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon ?? Icons.arrow_forward_rounded),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: ThemeCleanPremium.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          ),
        ),
      ),
    );
  }

  static Widget outlinedButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      height: ThemeCleanPremium.minTouchTarget,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.open_in_new_rounded),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: ThemeCleanPremium.primary,
          side: BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          ),
        ),
      ),
    );
  }
}

/// Estado de licença / bloqueio — visual premium unificado.
class YahwehSaasLicenseStatePage extends StatelessWidget {
  const YahwehSaasLicenseStatePage({
    super.key,
    required this.title,
    required this.message,
    this.churchName,
    this.logoUrl,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
    this.showBackButton = false,
    this.icon = Icons.lock_clock_rounded,
    this.accent = ThemeCleanPremium.error,
  });

  final String title;
  final String message;
  final String? churchName;
  final String? logoUrl;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;
  final bool showBackButton;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final canPop = showBackButton && Navigator.of(context).canPop();
    return ChurchWisdomLoginBackdrop(
      appBar: canPop
          ? ChurchWisdomLoginAppBar(onBack: () => Navigator.of(context).pop())
          : null,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ThemeCleanPremium.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  YahwehSaasVisualShell.hero(
                    title: title,
                    subtitle: (churchName ?? '').trim().isNotEmpty
                        ? churchName!.trim()
                        : 'Gestão YAHWEH',
                    logoSize: 92,
                  ),
                  const SizedBox(height: 16),
                  YahwehSaasVisualShell.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            border: Border.all(color: accent.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, color: accent, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  message,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (primaryLabel != null && onPrimary != null) ...[
                          const SizedBox(height: 16),
                          YahwehSaasVisualShell.primaryButton(
                            label: primaryLabel!,
                            onPressed: onPrimary,
                            icon: Icons.workspace_premium_rounded,
                          ),
                        ],
                        if (secondaryLabel != null && onSecondary != null) ...[
                          const SizedBox(height: 10),
                          YahwehSaasVisualShell.outlinedButton(
                            label: secondaryLabel!,
                            onPressed: onSecondary,
                            icon: Icons.support_agent_rounded,
                          ),
                        ],
                        if (tertiaryLabel != null && onTertiary != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: onTertiary,
                            child: Text(tertiaryLabel!),
                          ),
                        ],
                        const SizedBox(height: 14),
                        YahwehSaasVisualShell.securityFooter(),
                      ],
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
}

/// Hero de pricing / planos — topo das páginas `/planos` e checkout.
class YahwehSaasPricingHeroBanner extends StatelessWidget {
  const YahwehSaasPricingHeroBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.badge = 'Planos oficiais · Mercado Pago',
  });

  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kChurchWisdomLoginNavy,
            Color(0xFF1D4ED8),
            kChurchWisdomLoginTeal,
          ],
        ),
        boxShadow: YahwehWisdomVisualKit.softElevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              YahwehSaasVisualShell.brandEmblem(size: 56, glow: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded,
                    color: kChurchWisdomLoginGold, size: 16),
                const SizedBox(width: 6),
                Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
