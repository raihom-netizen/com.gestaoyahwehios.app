import 'package:flutter/material.dart' as material;

import '../services/scales_calendar_week_start_prefs.dart';
import '../widgets/multi_date_month_picker_dialog.dart';

/// Ponto único de calendário do app — respeita início da semana (domingo/segunda)
/// definido no módulo Escalas ([ScalesCalendarWeekStartPrefs]).
///
/// Substitui o `showDatePicker` do Material por nosso calendário premium
/// (feriados/fins de semana em destaque, mesma grade em todo o sistema).
Future<DateTime?> showDatePicker({
  required material.BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  material.DatePickerEntryMode initialEntryMode =
      material.DatePickerEntryMode.calendar,
  material.SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  material.Locale? locale,
  bool useRootNavigator = true,
  material.RouteSettings? routeSettings,
  material.TextDirection? textDirection,
  material.TransitionBuilder? builder,
  material.DatePickerMode initialDatePickerMode = material.DatePickerMode.day,
  String? errorFormatText,
  String? errorInvalidText,
  String? fieldHintText,
  String? fieldLabelText,
  material.TextInputType? keyboardType,
  material.Offset? anchorPoint,
  material.ValueChanged<material.DatePickerEntryMode>? onDatePickerModeChange,
  material.Icon? switchToInputEntryModeIcon,
  material.Icon? switchToCalendarEntryModeIcon,
  /// UID do usuário — alinha início da semana com Escalas.
  String? uid,
}) {
  return pickSingleDateWithHolidayCalendar(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    uid: ScalesCalendarWeekStartPrefs.resolveUidForCalendar(uid),
  );
}
