import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

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
