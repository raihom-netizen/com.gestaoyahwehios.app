import 'package:flutter/foundation.dart';

/// Política de módulos do painel — carregar sob demanda (menos RAM / arranque rápido).
///
/// **Mobile:** só o Dashboard (índice 0) permanece montado; ao sair do módulo o widget
/// é destruído (`igreja_clean_shell.dart`).
///
/// **Desktop:** [IndexedStack] mantém só páginas já visitadas (cache por índice).
abstract final class ChurchShellLazyModulePolicy {
  ChurchShellLazyModulePolicy._();

  /// Índice do dashboard no shell.
  static const int dashboardIndex = 0;

  /// Módulos pesados — não pré-montar no arranque.
  static const Set<int> heavyModuleIndices = {
    1, // mural/avisos
    2, // membros
    3, // departamentos
    4, // eventos
    5, // financeiro
    20, // chat
    21,
    24,
  };

  static bool shouldPrefetchOnHover(int index) =>
      !kIsWeb && heavyModuleIndices.contains(index);

  static bool keepMountedOnMobile(int index) => index == dashboardIndex;
}
