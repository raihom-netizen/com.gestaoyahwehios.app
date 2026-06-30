import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/yahweh_design_system.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

export 'package:gestao_yahweh/core/yahweh_design_system.dart' show YahwehDesignSystem;
export 'package:gestao_yahweh/ui/theme_clean_premium.dart' show ThemeCleanPremium;

/// **Design System — entrada única** do Gestão YAHWEH.
///
/// Use em `MaterialApp`:
/// ```dart
/// theme: AppTheme.light,
/// darkTheme: AppTheme.dark,
/// ```
///
/// Tokens (cores, raios, sombras): [AppColors], [AppSpacing], [AppRadius].
/// Componentes prontos: [AppComponentStyles].
///
/// Legado: [ThemeCleanPremium] e [YahwehDesignSystem] continuam válidos;
/// novos ecrãs devem importar só este ficheiro.
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeCleanPremium.themeData;

  static ThemeData get dark => ThemeCleanPremium.themeDataDark;

  static void hapticLight() => ThemeCleanPremium.hapticAction();
}

/// Cores da marca — delegadas a [YahwehDesignSystem].
abstract final class AppColors {
  AppColors._();

  static const primary = YahwehDesignSystem.brandPrimary;
  static const primaryLight = YahwehDesignSystem.brandPrimaryLight;
  static const gold = YahwehDesignSystem.brandGold;
  static const surface = YahwehDesignSystem.surface;
  static const onSurface = YahwehDesignSystem.onSurface;
  static const onSurfaceMuted = YahwehDesignSystem.onSurfaceVariant;
  static const card = YahwehDesignSystem.cardBackground;
  static const error = YahwehDesignSystem.error;
  static const success = YahwehDesignSystem.success;
  static const navSidebar = YahwehDesignSystem.navSidebar;
}

/// Espaçamento consistente em todos os módulos (Financeiro, Chat, Membros…).
abstract final class AppSpacing {
  AppSpacing._();

  static const xs = ThemeCleanPremium.spaceXs;
  static const sm = ThemeCleanPremium.spaceSm;
  static const md = ThemeCleanPremium.spaceMd;
  static const lg = ThemeCleanPremium.spaceLg;
  static const xl = ThemeCleanPremium.spaceXl;
  static const xxl = ThemeCleanPremium.spaceXxl;
}

/// Raios de borda — cards 16–20, modais 20–24.
abstract final class AppRadius {
  AppRadius._();

  static const sm = YahwehDesignSystem.radiusSm;
  static const md = YahwehDesignSystem.radiusMd;
  static const lg = YahwehDesignSystem.radiusLg;
  static const xl = YahwehDesignSystem.radiusXl;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get field => BorderRadius.circular(md);
  static BorderRadius get chip => BorderRadius.circular(sm);
}

/// Estilos reutilizáveis — evita duplicar BoxDecoration em cada módulo.
abstract final class AppComponentStyles {
  AppComponentStyles._();

  static const double minTouch = 48;

  /// Card padrão (Financeiro, Património, Cadastro, Dashboard).
  static BoxDecoration card({Color? background}) => BoxDecoration(
        color: background ?? AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: YahwehDesignSystem.softCardShadow,
      );

  /// AppBar gradiente (Novo Aviso, Novo Evento, formulários premium).
  static LinearGradient get appBarGradient => LinearGradient(
        colors: [AppColors.primary, AppColors.primaryLight],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  /// Botão primário «Publicar / Salvar».
  static ButtonStyle get primaryFilled => FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, minTouch),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.field),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.2,
        ),
      );

  /// Botão secundário «Cancelar».
  static ButtonStyle get secondaryOutlined => OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, minTouch),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.field),
      );

  /// Diálogo / modal (erros amigáveis — preferir SnackBar; modais só para progresso).
  static ShapeBorder get dialogShape => RoundedRectangleBorder(
        borderRadius: AppRadius.dialog,
      );

  /// SnackBar de erro (substitui pop-ups técnicos `core/no-app` na UI).
  static SnackBar errorSnack(String message, {VoidCallback? onRetry}) {
    return SnackBar(
      content: Text(message),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: 'Tentar novamente',
              textColor: Colors.white,
              onPressed: onRetry,
            ),
    );
  }

  static SnackBar successSnack(String message) =>
      ThemeCleanPremium.successSnackBar(message);
}
