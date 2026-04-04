import 'package:flutter/material.dart';

/// Contrato visual SaaS — grid, largura útil e viewport central.
///
/// Tipografia e [ThemeData] completos: [ThemeCleanPremium] / [YahwehDesignSystem]
/// (`lib/ui/theme_clean_premium.dart`). Este arquivo concentra **layout** e **largura máxima**.
abstract final class AppTheme {
  AppTheme._();

  /// Largura máxima do conteúdo em desktop (evita “site esticado” em monitores largos).
  static const double maxContentWidthDesktop = 1200;

  /// Grid 8pt (margens / paddings padronizados).
  static const double space8 = 8;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  /// Mesmo breakpoint do painel igreja: sidebar fixa vs drawer.
  static const double desktopSidebarBreakpoint = 900;

  /// Raio padrão “SaaS card” (alinha com [YahwehDesignSystem.radiusLg]).
  static const double cardRadiusSaaS = 20;

  /// Borda sutil em cards (surface clara).
  static const Color cardBorderLight = Color(0xFFE8EEF4);
}

/// Centraliza o filho e limita a largura em telas largas (painéis / módulos).
class SaaSContentViewport extends StatelessWidget {
  final Widget child;

  const SaaSContentViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth;
        if (!avail.isFinite || avail <= 0) {
          return child;
        }
        if (avail < AppTheme.desktopSidebarBreakpoint) {
          return child;
        }
        final useW = avail > AppTheme.maxContentWidthDesktop
            ? AppTheme.maxContentWidthDesktop
            : avail;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: useW, child: child),
        );
      },
    );
  }
}
