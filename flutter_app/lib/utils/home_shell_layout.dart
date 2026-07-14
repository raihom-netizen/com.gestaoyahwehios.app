import 'package:flutter/material.dart';

/// Módulo aberto dentro do [HomeShell] (rodapé fixo: ícones + versículo).
bool isHomeShellEmbeddedModule({
  ScrollController? shellScrollController,
  Object? onNavigateTo,
}) =>
    shellScrollController != null || onNavigateTo != null;

/// [SafeArea] inferior: no shell o rodapé já reserva o inset do dispositivo.
bool homeShellSafeAreaBottom({required bool embeddedInHomeShell}) =>
    !embeddedInHomeShell;

/// Padding inferior de scroll/lista — **não** somar [MediaQuery.padding.bottom] no shell.
double homeShellScrollBottomPadding(
  BuildContext context, {
  required bool embeddedInHomeShell,
  double tail = 8,
}) {
  if (embeddedInHomeShell) return tail;
  return tail + MediaQuery.paddingOf(context).bottom;
}

/// Espaço para FAB acima do rodapé do shell (sem safe area duplicada).
double homeShellFabScrollTail(
  BuildContext context, {
  required bool embeddedInHomeShell,
  double fabClearance = 72,
}) {
  if (embeddedInHomeShell) return fabClearance;
  return fabClearance + MediaQuery.paddingOf(context).bottom;
}

/// Altura visual do rodapé — mesma fórmula em Web, iOS e Android.
double homeShellFooterBarHeight(
  BuildContext context, {
  bool heroCentered = true,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final isUltraNarrow = width < 360;
  final isNarrow = width < 480;
  final isWide = width >= 720;
  final pillSize =
      isUltraNarrow ? 32.0 : (isNarrow ? 34.0 : (isWide ? 40.0 : 36.0));
  final labelSize =
      isUltraNarrow ? 9.5 : (isNarrow ? 10.0 : (isWide ? 11.0 : 10.5));
  final heroBoost = heroCentered ? 6.0 : 0.0;
  return pillSize + labelSize + (isUltraNarrow ? 10.0 : 14.0) + heroBoost;
}

/// Offset inferior do botão «voltar ao topo» — acima do rodapé + versículo.
double homeShellScrollToTopFabBottom(
  BuildContext context, {
  bool heroCentered = true,
}) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  const verseBlock = 22.0;
  const gap = 10.0;
  return bottomInset +
      homeShellFooterBarHeight(context, heroCentered: heroCentered) +
      verseBlock +
      gap;
}
