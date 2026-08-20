import 'package:flutter/material.dart';

/// Escolha de período **padrão do app**: abre a digitar, com calendário à mão.
///
/// O `showDateRangePicker` do Flutter abre no calendário e só deixa escrever
/// depois de o utilizador descobrir o lápis no canto. Para quem sabe a data
/// que quer — que é o caso normal em relatórios e extratos — isso são três
/// toques e muito arrastar para trás quando o período é de meses atrás.
/// Aqui abre-se em **modo de digitação** (`dd/mm/aaaa`), e o ícone de
/// calendário continua lá para quem prefere apontar.
///
/// Usar **em todo o lado** onde houver filtro de período, para o comportamento
/// ser o mesmo em Financeiro, Membros, Fornecedores, Relatórios, Visitantes,
/// Certificados, Cartas e Divulgação.
Future<DateTimeRange?> escolherIntervaloDeDatas(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String helpText = 'Escolha o período',
  String confirmText = 'Aplicar',
  String cancelText = 'Cancelar',
  String saveText = 'Aplicar',
  Widget Function(BuildContext, Widget?)? builder,
}) {
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    // Abre a digitar; o botão de calendário fica no diálogo.
    initialEntryMode: DatePickerEntryMode.input,
    locale: const Locale('pt', 'BR'),
    helpText: helpText,
    confirmText: confirmText,
    cancelText: cancelText,
    saveText: saveText,
    fieldStartLabelText: 'Data inicial',
    fieldEndLabelText: 'Data final',
    fieldStartHintText: 'dd/mm/aaaa',
    fieldEndHintText: 'dd/mm/aaaa',
    errorFormatText: 'Use dd/mm/aaaa',
    errorInvalidText: 'Data fora do intervalo permitido',
    errorInvalidRangeText: 'A data final tem de ser depois da inicial',
    switchToCalendarEntryModeIcon: const Icon(Icons.event_rounded),
    switchToInputEntryModeIcon: const Icon(Icons.keyboard_rounded),
    builder: builder,
  );
}
