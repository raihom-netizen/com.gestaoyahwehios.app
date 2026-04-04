import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/core/yahweh_design_system.dart';

export 'package:gestao_yahweh/core/yahweh_design_system.dart' show YahwehDesignSystem;

/// Padrão visual Clean Premium — Gestão YAHWEH (Soft UI / Super Premium).
/// Cores, raios e sombras vêm de [YahwehDesignSystem] (única fonte para Master, Igreja e sites).
/// Uso: MaterialApp(theme: ThemeCleanPremium.themeData, ...)
class ThemeCleanPremium {
  ThemeCleanPremium._();

  /// Feedback háptico leve em ações principais (Salvar, Excluir, Confirmar) — mobile.
  static void hapticAction() => HapticFeedback.lightImpact();

  // Cores principais (delegadas ao design system)
  static const Color primary = YahwehDesignSystem.brandPrimary;
  static const Color primaryLight = YahwehDesignSystem.brandPrimaryLight;
  static const Color primaryLighter = YahwehDesignSystem.brandPrimaryLighter;
  static const Color surface = YahwehDesignSystem.surface;
  static const Color surfaceVariant = YahwehDesignSystem.surfaceVariant;
  static const Color onSurface = YahwehDesignSystem.onSurface;
  static const Color onSurfaceVariant = YahwehDesignSystem.onSurfaceVariant;
  static const Color cardBackground = YahwehDesignSystem.cardBackground;
  static const Color error = YahwehDesignSystem.error;
  static const Color success = YahwehDesignSystem.success;

  /// Menu lateral esquerdo azul escuro (Painel Igreja)
  static const Color navSidebar = YahwehDesignSystem.navSidebar;
  static const Color navSidebarHover = YahwehDesignSystem.navSidebarHover;
  static const Color navSidebarAccent = YahwehDesignSystem.navSidebarAccent;

  // Espaçamento (Clean Premium: generoso)
  static const double spaceXs = 6;
  static const double spaceSm = 12;
  static const double spaceMd = 18;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // Raios (bordas arredondadas elegantes — super premium)
  static const double radiusSm = YahwehDesignSystem.radiusSm;
  static const double radiusMd = YahwehDesignSystem.radiusMd;
  static const double radiusLg = YahwehDesignSystem.radiusLg;
  static const double radiusXl = YahwehDesignSystem.radiusXl;
  static const double radiusXxl = YahwehDesignSystem.radiusXxl;

  /// Sombras Soft UI (super premium): 0 10px 30px rgba(0,0,0,0.04)
  static List<BoxShadow> get softUiCardShadow => YahwehDesignSystem.softCardShadow;
  /// Sombras premium (cards e overlays) — fallback
  static List<BoxShadow> get cardShadow => softUiCardShadow;
  static List<BoxShadow> get cardShadowHover => [
    BoxShadow(
      color: primary.withOpacity(0.12),
      blurRadius: 24,
      offset: const Offset(0, 12),
      spreadRadius: 0,
    ),
    ...cardShadow,
  ];

  /// Cores para modo escuro
  static const Color surfaceDark = YahwehDesignSystem.surfaceDark;
  static const Color surfaceVariantDark = YahwehDesignSystem.surfaceVariantDark;
  static const Color onSurfaceDark = YahwehDesignSystem.onSurfaceDark;
  static const Color onSurfaceVariantDark = YahwehDesignSystem.onSurfaceVariantDark;
  static const Color cardBackgroundDark = YahwehDesignSystem.cardBackgroundDark;

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: primaryLight,
        surface: surface,
        error: error,
        brightness: Brightness.light,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: surfaceVariant,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 20,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: Color(0xFFE8EEF4), width: 1),
        ),
        color: cardBackground,
        margin: const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
        clipBehavior: Clip.antiAlias,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),
      textTheme: YahwehDesignSystem.textThemeInter(ThemeData.light().textTheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: const TextStyle(color: onSurfaceVariant),
        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceSm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceSm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceSm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: spaceSm, vertical: spaceXs),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceXs),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        tileColor: Colors.white,
        iconColor: onSurfaceVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primary.withOpacity(0.12),
        side: BorderSide(color: Colors.grey.shade200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: onSurface,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 15,
          color: onSurfaceVariant,
          height: 1.4,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceVariant,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      drawerTheme: DrawerThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(radiusLg)),
        ),
        backgroundColor: cardBackground,
        elevation: 4,
      ),
    );
  }

  static ThemeData get themeDataDark {
    return ThemeData(
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryLighter,
        secondary: primaryLight,
        surface: surfaceDark,
        error: error,
        onPrimary: surfaceDark,
        onSecondary: surfaceDark,
        onSurface: onSurfaceDark,
        onSurfaceVariant: onSurfaceVariantDark,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: surfaceVariantDark,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBackgroundDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBackgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusSm)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primaryLighter, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF334155)),
    );
  }

  /// SnackBar padrão painel: fundo verde, texto branco (sucesso, erro de rede, gravações — mesmo visual).
  /// Ao exibir, dispara feedback háptico leve no mobile ([_HapticSnackSuccessContent]).
  static SnackBar successSnackBar(String message) {
    return SnackBar(
      content: _HapticSnackSuccessContent(message: message),
      backgroundColor: success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
    );
  }

  /// Alias para mensagens de erro/aviso com o mesmo visual verde + branco.
  static SnackBar feedbackSnackBar(String message) => successSnackBar(message);

  /// Breakpoints para responsividade (Android, iPhone, tablet, web)
  static const double breakpointMobile = 600;
  static const double breakpointTablet = 900;
  static const double breakpointDesktop = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointTablet;
  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointMobile;
  /// Celular (< 600): padding reduzido para aproveitar tela
  static EdgeInsets pagePadding(BuildContext context) =>
      EdgeInsets.symmetric(
        horizontal: isNarrow(context) ? spaceSm : spaceLg,
        vertical: isNarrow(context) ? spaceMd : spaceLg,
      );
  /// Área de toque mínima recomendada (Android/iOS): 48px
  static const double minTouchTarget = 48;

  /// Rota com transição suave (fade + slide leve) para navegação entre telas do painel.
  /// Card branco padrão (listas vazias, destaques) — raio 16px + sombra soft.
  static BoxDecoration get premiumSurfaceCard => BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: const Color(0xFFE8EDF3)),
        boxShadow: softUiCardShadow,
      );

  /// Estado vazio reutilizável (módulos eventos, listas, etc.).
  /// [iconColor] opcional — ex.: estado de erro com [error].
  static Widget premiumEmptyState({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
    Color? iconColor,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(spaceLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: spaceXl, vertical: spaceXxl),
            decoration: premiumSurfaceCard,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: iconColor ?? primary.withOpacity(0.38)),
                const SizedBox(height: spaceMd),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: spaceSm),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: onSurfaceVariant,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: spaceMd),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Estado de falha de rede / carregamento com ação **Tentar novamente** (mesmo cartão do empty).
  static Widget premiumErrorState({
    required String title,
    String? subtitle,
    VoidCallback? onRetry,
    String retryLabel = 'Tentar novamente',
  }) {
    return premiumEmptyState(
      icon: Icons.wifi_off_rounded,
      title: title,
      subtitle: subtitle ??
          'Verifique sua conexão e tente de novo.',
      iconColor: error.withValues(alpha: 0.72),
      action: onRetry != null
          ? FilledButton.icon(
              onPressed: () {
                hapticAction();
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(retryLabel),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: spaceLg, vertical: spaceSm),
                minimumSize: const Size(minTouchTarget, minTouchTarget),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusMd)),
              ),
            )
          : null,
    );
  }

  /// SnackBar flutuante para erro com ação opcional de retry (listas, Firestore, APIs).
  static SnackBar errorSnackBarWithRetry(
    String message, {
    VoidCallback? onRetry,
    String retryLabel = 'Tentar novamente',
  }) {
    return SnackBar(
      content: Text(
        message,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      backgroundColor: const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd)),
      action: onRetry != null
          ? SnackBarAction(
              label: retryLabel,
              textColor: primaryLighter,
              onPressed: onRetry,
            )
          : null,
    );
  }

  static void showErrorSnackBarWithRetry(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    String retryLabel = 'Tentar novamente',
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      errorSnackBarWithRetry(
        message,
        onRetry: onRetry,
        retryLabel: retryLabel,
      ),
    );
  }

  static PageRoute<T> fadeSlideRoute<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeOutCubic;
        final fade = CurvedAnimation(parent: animation, curve: curve);
        final slide = Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: curve),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }
}

/// Feedback háptico uma vez quando o SnackBar de sucesso entra na árvore (iOS/Android).
class _HapticSnackSuccessContent extends StatefulWidget {
  const _HapticSnackSuccessContent({required this.message});

  final String message;

  @override
  State<_HapticSnackSuccessContent> createState() =>
      _HapticSnackSuccessContentState();
}

class _HapticSnackSuccessContentState extends State<_HapticSnackSuccessContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) HapticFeedback.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.message,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
