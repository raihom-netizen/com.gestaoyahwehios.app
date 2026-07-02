import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';

/// Botão de ação largura total — estilo Super Premium (web, iOS, Android).
class YahwehSuperPremiumActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final String label;
  final LinearGradient? gradient;
  final Color? backgroundColor;
  final Color foregroundColor;
  final bool compact;
  final double? minHeight;

  const YahwehSuperPremiumActionButton({
    super.key,
    required this.onPressed,
    this.icon,
    this.leading,
    required this.label,
    this.gradient,
    this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.compact = false,
    this.minHeight,
  });

  factory YahwehSuperPremiumActionButton.chat({
    Key? key,
    required VoidCallback? onPressed,
    String label = YahwehContactButtonLabels.yahwehChat,
    bool compact = false,
  }) {
    return YahwehSuperPremiumActionButton(
      key: key,
      onPressed: onPressed,
      icon: Icons.forum_rounded,
      label: label,
      gradient: churchChatWhatsPremiumLinearGradient,
      compact: compact,
    );
  }

  factory YahwehSuperPremiumActionButton.whatsapp({
    Key? key,
    required VoidCallback? onPressed,
    String label = YahwehContactButtonLabels.whatsApp,
    bool compact = false,
  }) {
    return YahwehSuperPremiumActionButton(
      key: key,
      onPressed: onPressed,
      leading: WhatsappBrandIcon(size: compact ? 15 : 20, color: Colors.white),
      label: label,
      backgroundColor: const Color(0xFF16A34A),
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 22.0 : 16.0;
    final vPad = compact ? 8.0 : 16.0;
    final hPad = compact ? 10.0 : 16.0;
    final iconSize = compact ? 15.0 : 22.0;
    final fontSize = compact ? 11.0 : 16.0;
    final height = minHeight ??
        (compact ? 36.0 : ThemeCleanPremium.minTouchTarget);

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            color: gradient == null ? backgroundColor : null,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: (gradient != null
                              ? const Color(0xFF2563EB)
                              : (backgroundColor ?? Colors.green))
                          .withValues(alpha: compact ? 0.22 : 0.32),
                      blurRadius: compact ? 8 : 14,
                      offset: Offset(0, compact ? 3 : 6),
                    ),
                  ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                leading ??
                    Icon(icon ?? Icons.circle, size: iconSize, color: foregroundColor),
                SizedBox(width: compact ? 5 : 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: fontSize,
                      letterSpacing: compact ? -0.1 : 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (compact) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: child,
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: child,
      ),
    );
  }
}
