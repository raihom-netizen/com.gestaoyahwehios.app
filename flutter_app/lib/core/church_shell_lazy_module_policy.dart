import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';

/// Política de módulos do painel — carregar sob demanda (menos RAM / arranque rápido).
///
/// **Mobile:** só o atalho **ativo** do rodapé fica montado — liberta RAM e streams
/// dos outros módulos (teclado fluido em Eventos/Avisos/Chat).
/// Módulos só do menu lateral desmontam ao sair.
///
/// **Desktop:** [IndexedStack] mantém só páginas já visitadas (cache por índice).
abstract final class ChurchShellLazyModulePolicy {
  ChurchShellLazyModulePolicy._();

  /// Índice do dashboard no shell.
  static const int dashboardIndex = ChurchShellIndices.painel;

  /// Atalhos do rodapé mobile — sempre em cache após primeira visita.
  static const Set<int> mobileFooterIndices = {
    ChurchShellIndices.painel,
    ChurchShellIndices.membros,
    ChurchShellIndices.muralAvisos,
    ChurchShellIndices.muralEventos,
    ChurchShellIndices.chatIgreja,
  };

  /// Módulos pesados fora do rodapé — não pré-montar no arranque.
  static const Set<int> heavyModuleIndices = {
    ChurchShellIndices.departamentos,
    ChurchShellIndices.financeiro,
    ChurchShellIndices.patrimonio,
    ChurchShellIndices.fornecedores,
  };

  static bool shouldPrefetchOnHover(int index) =>
      !kIsWeb && heavyModuleIndices.contains(index);

  static bool keepMountedOnMobile(int index) => false;

  static bool isMobileFooterTab(int index) =>
      mobileFooterIndices.contains(index);
}
