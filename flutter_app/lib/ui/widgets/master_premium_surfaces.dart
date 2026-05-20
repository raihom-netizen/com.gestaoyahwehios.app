import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';

/// Superfície de card unificada para módulos do Painel Master (Soft UI, borda e sombra).
class MasterPremiumCard extends StatelessWidget {
  const MasterPremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.expandWidth = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool expandWidth;

  static const EdgeInsetsGeometry _defaultPadding =
      EdgeInsets.all(ThemeCleanPremium.spaceMd);

  @override
  Widget build(BuildContext context) {
    Widget inner = Container(
      width: expandWidth ? double.infinity : null,
      padding: padding ?? _defaultPadding,
      decoration: ThemeCleanPremium.premiumSurfaceCard,
      child: child,
    );
    if (margin != null) {
      inner = Padding(padding: margin!, child: inner);
    }
    return inner;
  }
}

/// Gradiente do menu lateral master (Super Premium SaaS).
const BoxDecoration masterSidebarGradientDecoration = BoxDecoration(
  gradient: churchChatWhatsPremiumLinearGradient,
);

/// KPI do Command Center.
class MasterKpiCard extends StatelessWidget {
  const MasterKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.onTap,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: MasterPremiumCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.9),
                      Color.lerp(accent, const Color(0xFF7C3AED), 0.35)!,
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saúde da igreja (licença / pagamento).
enum MasterChurchHealth { ok, warning, critical, free }

class MasterHealthChip extends StatelessWidget {
  const MasterHealthChip({super.key, required this.health, this.compact = false});

  final MasterChurchHealth health;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (health) {
      MasterChurchHealth.ok => ('Ativa', const Color(0xFF16A34A)),
      MasterChurchHealth.warning => ('Atenção', const Color(0xFFD97706)),
      MasterChurchHealth.critical => ('Bloqueada', const Color(0xFFDC2626)),
      MasterChurchHealth.free => ('FREE', const Color(0xFF2563EB)),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Título de seção com hierarquia tipográfica e [trailing] responsivo.
class MasterModuleSectionTitle extends StatelessWidget {
  const MasterModuleSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: ThemeCleanPremium.isNarrow(context) ? 17 : 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.15,
      color: ThemeCleanPremium.onSurface,
      height: 1.2,
    );
    final subStyle = TextStyle(
      fontSize: 13,
      height: 1.45,
      color: ThemeCleanPremium.onSurfaceVariant,
    );

    if (trailing == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: subStyle),
          ],
        ],
      );
    }

    if (ThemeCleanPremium.isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: titleStyle),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: subStyle),
          ],
          const SizedBox(height: 10),
          trailing!,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: subStyle),
              ],
            ],
          ),
        ),
        trailing!,
      ],
    );
  }
}
