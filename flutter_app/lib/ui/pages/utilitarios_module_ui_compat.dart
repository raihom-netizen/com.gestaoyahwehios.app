import 'package:flutter/material.dart';

/// Compatibilidade Visual CT → Gestão Yahweh para o módulo Utilitários.
abstract final class ModernModuleUI {
  ModernModuleUI._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffoldBgOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color cardBg(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF1E293B)
          : Theme.of(context).colorScheme.surface;

  static Color onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color onSurfaceMuted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Widget bodyWithGradient({
    required BuildContext context,
    required Widget child,
  }) {
    final dark = isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0B1220), Color(0xFF111827), Color(0xFF0F172A)]
              : const [Color(0xFFF8FAFC), Color(0xFFEFF6FF), Color(0xFFF1F5F9)],
        ),
      ),
      child: child,
    );
  }

  static BoxDecoration previewSheetDecoration(
    BuildContext context, {
    double radius = 22,
  }) {
    if (isDark(context)) {
      return BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );
    }
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static BoxDecoration moduleCardDecoration(
    BuildContext context, {
    double radius = 18,
    Color? borderAccent,
  }) {
    final accent = borderAccent ?? const Color(0xFF6366F1);
    return BoxDecoration(
      color: isDark(context) ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: 0.35)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static TextStyle moduleTitleStyle(
    BuildContext context, {
    double fontSize = 16,
    FontWeight weight = FontWeight.w900,
  }) =>
      TextStyle(
        fontWeight: weight,
        fontSize: fontSize,
        color: onSurface(context),
        letterSpacing: -0.2,
      );

  static TextStyle moduleSubtitleStyle(
    BuildContext context, {
    double fontSize = 12.5,
  }) =>
      TextStyle(
        fontSize: fontSize,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: onSurfaceMuted(context),
      );

  static Widget sectionTitle(
    BuildContext context,
    String title, {
    Color? accent,
    double fontSize = 13,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: fontSize > 14 ? 20 : 16,
            decoration: BoxDecoration(
              color: accent ?? const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: onSurface(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget iconBadge({
    required IconData icon,
    required List<Color> gradient,
    double size = 44,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }

  static Widget gradientActionCard({
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.38),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 11 : 14,
          ),
          child: Row(
            children: [
              iconBadge(icon: icon, gradient: gradient, size: compact ? 36 : 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget centeredPickButton({
    required List<Color> gradient,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool secondary = false,
    double minWidth = 280,
  }) {
    if (secondary) {
      return ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, minHeight: 48),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20, color: gradient.first),
          label: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: gradient.first)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            side: BorderSide(color: gradient.first.withValues(alpha: 0.55)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth, minHeight: 52),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget emptyPickState({
    required BuildContext context,
    required List<Color> gradient,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
    IconData buttonIcon = Icons.folder_open_rounded,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconBadge(icon: icon, gradient: gradient, size: 64),
            const SizedBox(height: 20),
            Text(title,
                style: moduleTitleStyle(context), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: moduleSubtitleStyle(context)),
            const SizedBox(height: 24),
            centeredPickButton(
              gradient: gradient,
              icon: buttonIcon,
              label: buttonLabel,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }

  static Widget infoBanner({
    required BuildContext context,
    required IconData icon,
    required List<Color> iconGradient,
    required String text,
  }) {
    final dark = isDark(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [
                  const Color(0xFF6366F1).withValues(alpha: 0.22),
                  iconGradient.last.withValues(alpha: 0.16),
                ]
              : [
                  const Color(0xFF6366F1).withValues(alpha: 0.1),
                  iconGradient.last.withValues(alpha: 0.08),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: iconGradient.first.withValues(alpha: dark ? 0.35 : 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: iconGradient),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.38,
                fontWeight: FontWeight.w600,
                color: onSurfaceMuted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cores de tema usadas pelos fluxos Utilitários (espelho CT theme_context).
extension UtilitariosThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get appInputFill =>
      isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

  Color get appTextPrimary =>
      isDarkMode ? const Color(0xFFFFFFFF) : const Color(0xFF1E293B);

  Color get appTextSecondary =>
      isDarkMode ? const Color(0xFFB3B3B3) : const Color(0xFF64748B);

  Color get appTextMuted =>
      isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);

  Color get appDarkModuleSurface =>
      isDarkMode ? const Color(0xFF1A1F2E) : Theme.of(this).colorScheme.surface;
}
