import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

enum MarketingButtonStyle { store, primary, outline }

/// Botão unificado — Google Play, TestFlight, planos, login (mesma altura e alinhamento).
class MarketingNavButton extends StatelessWidget {
  const MarketingNavButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.style = MarketingButtonStyle.outline,
    this.storeGradient,
    this.compact = false,
    this.onDarkSurface = false,
    this.enabled = true,
  });

  static const double kHeight = 48;
  static const double kCompactHeight = 38;
  static const double kMinWidth = 156;

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final MarketingButtonStyle style;
  final List<Color>? storeGradient;
  final bool compact;
  final bool onDarkSurface;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final h = compact ? kCompactHeight : kHeight;
    final radius = compact ? 12.0 : 14.0;
    final iconSize = compact ? 18.0 : 22.0;
    final labelSize = compact ? 11.0 : 12.5;
    final subtitleSize = compact ? 9.5 : 10.5;

    final bool filled = style != MarketingButtonStyle.outline || onDarkSurface;
    final List<Color> gradient = switch (style) {
      MarketingButtonStyle.store =>
        storeGradient ?? const [Color(0xFF01875F), Color(0xFF00A86B)],
      MarketingButtonStyle.primary when onDarkSurface => [
          Colors.white.withValues(alpha: 0.96),
          Colors.white.withValues(alpha: 0.88),
        ],
      MarketingButtonStyle.primary => [
          ThemeCleanPremium.primary,
          ThemeCleanPremium.primaryLight,
        ],
      MarketingButtonStyle.outline when onDarkSurface => [
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.08),
        ],
      MarketingButtonStyle.outline => [Colors.white, Colors.white],
    };

    final Color fg = switch (style) {
      MarketingButtonStyle.store => Colors.white,
      MarketingButtonStyle.primary when onDarkSurface => ThemeCleanPremium.primary,
      MarketingButtonStyle.primary => Colors.white,
      MarketingButtonStyle.outline when onDarkSurface => Colors.white,
      MarketingButtonStyle.outline => ThemeCleanPremium.primary,
    };
    final colors = enabled
        ? gradient
        : [Colors.grey.shade400, Colors.grey.shade500];

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: compact ? 120 : kMinWidth, minHeight: h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: (filled || onDarkSurface)
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    )
                  : null,
              color: (filled || onDarkSurface) ? null : Colors.white,
              border: Border.all(
                color: switch (style) {
                  MarketingButtonStyle.outline when onDarkSurface =>
                    Colors.white.withValues(alpha: 0.42),
                  MarketingButtonStyle.outline =>
                    ThemeCleanPremium.primary.withValues(alpha: 0.32),
                  _ => Colors.transparent,
                },
                width: 1.4,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: (filled ? colors.first : ThemeCleanPremium.primary)
                            .withValues(alpha: filled ? 0.28 : 0.1),
                        blurRadius: compact ? 8 : 14,
                        offset: Offset(0, compact ? 3 : 6),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: iconSize),
                  SizedBox(width: compact ? 7 : 10),
                  Flexible(
                    child: subtitle != null && subtitle!.trim().isNotEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg.withValues(alpha: 0.88),
                                  fontSize: subtitleSize,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: labelSize + 1.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: labelSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
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
}

/// Alias legado — delega para [MarketingNavButton].
class ModernStoreDownloadButton extends StatelessWidget {
  const ModernStoreDownloadButton({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MarketingNavButton(
      label: label,
      subtitle: subtitle,
      icon: icon,
      style: MarketingButtonStyle.store,
      storeGradient: gradient,
      onTap: onTap,
      enabled: enabled,
    );
  }
}
