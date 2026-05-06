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

/// Centraliza o filho, limita a largura em telas largas e **amarra a altura** ao viewport
/// do painel quando as constraints são finitas.
///
/// Sem [maxHeight] explícito, filhos com `Column` + `Expanded` ou `ListView` recebiam
/// altura máxima infinita (só `minHeight`), o que travava módulos do painel Master na web/mobile.
/// Com altura fixa à área útil, o conteúdo ocupa o ecrã disponível e a **rolagem fica no módulo**
/// (`ListView`, `SingleChildScrollView`, `CustomScrollView`).
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
        final boundedV =
            c.hasBoundedHeight && c.maxHeight.isFinite && c.maxHeight > 0;
        final h = boundedV ? c.maxHeight : null;

        if (avail < AppTheme.desktopSidebarBreakpoint) {
          if (h != null) {
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: avail,
                height: h,
                child: child,
              ),
            );
          }
          return child;
        }

        final cap = maxWidthOverride ?? AppTheme.maxContentWidthDesktop;
        final useW = avail > cap ? cap : avail;
        if (h != null) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: useW,
              height: h,
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
