import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// **Single source of truth** — identidade visual Gestão YAHWEH em todas as frentes
/// (Painel Master, Painel Igreja, site de divulgação, site público da igreja).
///
/// [ThemeCleanPremium] consome estes tokens para [ThemeData]. Para alterar azul/ouro/raios globalmente,
/// edite aqui e mantenha os componentes a usar [ThemeCleanPremium] ou importar [YahwehDesignSystem].
abstract final class YahwehDesignSystem {
  YahwehDesignSystem._();

  // ——— Marca: Azul + Ouro + branco ———
  static const Color brandPrimary = Color(0xFF0052CC);
  static const Color brandPrimaryLight = Color(0xFF2B6FE0);
  static const Color brandPrimaryLighter = Color(0xFF5E93EC);

  /// Destaques (sidebar, CTAs secundários) — “ouro” suave alinhado ao painel igreja.
  static const Color brandGold = Color(0xFFFFE082);
  static const Color brandWhite = Color(0xFFFFFFFF);

  static const Color surface = Color(0xFFF4F5F7);
  static const Color surfaceVariant = Color(0xFFF4F5F7);
  static const Color onSurface = Color(0xFF1A1A2E);
  static const Color onSurfaceVariant = Color(0xFF64748B);
  static const Color cardBackground = Colors.white;
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);

  static const Color navSidebar = Color(0xFF0A3D91);
  static const Color navSidebarHover = Color(0xFF1565C0);
  static const Color navSidebarAccent = brandGold;

  static const Color surfaceDark = Color(0xFF1A1A2E);
  static const Color surfaceVariantDark = Color(0xFF0F172A);
  static const Color onSurfaceDark = Color(0xFFF8FAFC);
  static const Color onSurfaceVariantDark = Color(0xFF94A3B8);
  static const Color cardBackgroundDark = Color(0xFF1E293B);

  // ——— Raios (cards 16, modais 20) ———
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusXxl = 28;

  /// Sombra suave unificada (Soft UI).
  static List<BoxShadow> get softCardShadow => [
        BoxShadow(
          color: const Color(0x0A000000),
          blurRadius: 30,
          offset: const Offset(0, 10),
          spreadRadius: 0,
        ),
      ];

  /// Tipografia **Inter** (padrão app / painéis).
  static TextTheme textThemeInter(TextTheme base) =>
      GoogleFonts.interTextTheme(base).copyWith(
        headlineMedium:
            GoogleFonts.inter(fontWeight: FontWeight.w600, letterSpacing: 0.3),
        titleLarge:
            GoogleFonts.inter(fontWeight: FontWeight.w600, letterSpacing: 0.25),
        titleMedium:
            GoogleFonts.inter(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.normal),
        bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.normal),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
      );

  /// Tipografia **Poppins** (alternativa para landings / títulos de marca).
  static TextTheme textThemePoppins(TextTheme base) =>
      GoogleFonts.poppinsTextTheme(base).copyWith(
        headlineMedium: GoogleFonts.poppins(
            fontWeight: FontWeight.w600, letterSpacing: 0.2),
        titleLarge: GoogleFonts.poppins(
            fontWeight: FontWeight.w600, letterSpacing: 0.15),
        titleMedium: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.poppins(fontWeight: FontWeight.normal),
        bodyMedium: GoogleFonts.poppins(fontWeight: FontWeight.normal),
        labelLarge: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      );
}
