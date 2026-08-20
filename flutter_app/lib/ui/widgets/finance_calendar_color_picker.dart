import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/widgets/color_palette_tabs_dialog.dart';

/// Seletor de cor para lançamentos financeiros exibidos no calendário
/// Agenda/Escala. Padrão: vermelho para despesas, verde para receitas.
///
/// A escolha em si é o diálogo por abas do Controle Total
/// ([ColorPaletteTabsDialog]) — o mesmo em Financeiro, Agenda, Eventos e
/// Avisos, para o utilizador não encontrar três seletores diferentes conforme
/// a tela. Antes daqui saía uma grelha própria, sem abas, com só as 72
/// primeiras cores da paleta.
abstract final class FinanceCalendarColorPicker {
  static String defaultHexFor(bool isIncome) =>
      isIncome ? '#2E7D32' : '#E53935';

  static Future<String?> show(
    BuildContext context, {
    required bool isIncome,
    String? currentHex,
  }) {
    return mostrarSeletorDeCores(
      context,
      titulo: 'Cor no calendário',
      selecionadaHex: currentHex ?? defaultHexFor(isIncome),
    );
  }
}
