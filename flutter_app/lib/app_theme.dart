import 'package:flutter/material.dart';

/// Contrato visual SaaS — grid, largura útil e viewport central.
///
/// Tipografia e [ThemeData] completos: [ThemeCleanPremium] / [YahwehDesignSystem]
/// (`lib/ui/theme_clean_premium.dart`). Este arquivo concentra **layout** e **largura máxima**.
abstract final class AppTheme {
  AppTheme._();

  /// Largura máxima do conteúdo em desktop (evita “site esticado” em monitores largos).
  static const double maxContentWidthDesktop = 1200;

  /// Feed tipo Instagram (Mural de Eventos / Mural de Avisos) na web — evita vídeo 16:9 e cards largos demais.
  static const double maxSocialFeedWidthWeb = 520;

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

  /// Em desktop, substitui o teto [AppTheme.maxContentWidthDesktop] (ex.: feed social mais estreito).
  final double? maxWidthOverride;

  const SaaSContentViewport({super.key, required this.child, this.maxWidthOverride});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth;
        if (!avail.isFinite || avail <= 0) {
          return child;
        }
        // Tablet/mobile no navegador: mesma altura mínima do viewport que no desktop.
        if (avail < AppTheme.desktopSidebarBreakpoint) {
          if (c.hasBoundedHeight && c.maxHeight.isFinite && c.maxHeight > 0) {
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: child,
            );
          }
          return child;
        }
        final cap = maxWidthOverride ?? AppTheme.maxContentWidthDesktop;
        final useW = avail > cap ? cap : avail;
        // Altura mínima = viewport: evita filhos com Column+Expanded sem altura definida na web
        // e melhora rolagem quando o módulo usa um único scroll (CustomScrollView).
        if (c.hasBoundedHeight && c.maxHeight.isFinite && c.maxHeight > 0) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: useW,
                minHeight: c.maxHeight,
              ),
              child: child,
            ),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: useW, child: child),
        );
      },
    );
  }
}
