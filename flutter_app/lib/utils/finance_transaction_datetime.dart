/// Data/hora de lançamentos manuais (Premium): a UI permite dia + hora/minuto.
/// Lançamentos vindos do Open Finance (Premium PRO / [source]/[openFinanceExternalId]) preservam instante da instituição.
abstract final class FinanceTransactionDatetime {
  FinanceTransactionDatetime._();

  static bool isOpenFinanceBacked(Map<String, dynamic> data) {
    final src = (data['source'] ?? '').toString().trim();
    if (src == 'open_finance') return true;
    final ext = (data['openFinanceExternalId'] ?? '').toString().trim();
    return ext.isNotEmpty;
  }

  /// Novo lançamento manual: combina o dia escolhido no calendário com o relógio atual.
  static DateTime mergeCalendarDayWithClockNow(DateTime calendarDay) {
    final n = DateTime.now();
    return DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
      n.hour,
      n.minute,
    );
  }

  /// Normaliza lançamentos manuais para hora/minuto, sem segundos.
  static DateTime withoutSeconds(DateTime d) {
    return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  }

  /// Se a data veio sem horário (00:00), preenche com o relógio atual; se já veio
  /// com horário escolhido, preserva hora/minuto e remove segundos.
  static DateTime normalizeManualDateTime(DateTime d) {
    final hasClock = d.hour != 0 ||
        d.minute != 0 ||
        d.second != 0 ||
        d.millisecond != 0 ||
        d.microsecond != 0;
    return hasClock ? withoutSeconds(d) : mergeCalendarDayWithClockNow(d);
  }

  /// Edição manual: ao mudar só o dia no date picker, mantém hora/minuto do registro anterior.
  static DateTime mergeCalendarDayWithExistingTime(
      DateTime pickedDay, DateTime previous) {
    return DateTime(
      pickedDay.year,
      pickedDay.month,
      pickedDay.day,
      previous.hour,
      previous.minute,
    );
  }

  static DateTime mergeCalendarDayWithTimeOfDay(
      DateTime pickedDay, int hour, int minute) {
    return DateTime(
        pickedDay.year, pickedDay.month, pickedDay.day, hour, minute);
  }
}
