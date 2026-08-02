import 'package:gestao_yahweh/models/scale_entry.dart';
import 'package:gestao_yahweh/models/scale_rates.dart';
import 'package:gestao_yahweh/models/shift_location.dart';
import 'agenda_reminder_end_of_day.dart';

(int, int) _parseScaleHHmm(String hhmm) {
  final parts = hhmm.trim().split(':');
  final h = int.tryParse(parts.first.trim()) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
  return (h.clamp(0, 23), m.clamp(0, 59));
}

DateTime _clockOnDay(String hhmm, DateTime day) {
  final (h, m) = _parseScaleHHmm(hhmm);
  return DateTime(day.year, day.month, day.day, h, m);
}

/// Fim do turno. Mesmo horário início/fim (ex. 07:00–07:00) = plantão de 24 h.
///
/// **00:00 no fim** = fim do dia civil (23:59:59), não trecho 00h–07h no dia seguinte.
/// Ex.: 08:00–00:00 → até 23:59. Exceção: 00:00–00:00 = 24 horas.
bool scaleEndHHmmIsEndOfDayMidnight(String endHHmm) {
  final (h, m) = _parseScaleHHmm(endHHmm);
  return h == 0 && m == 0;
}

DateTime scaleEntryEndDateTime({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
}) {
  final startDt = _clockOnDay(startHHmm, day);

  if (scaleEndHHmmIsEndOfDayMidnight(endHHmm)) {
    final (sh, sm) = _parseScaleHHmm(startHHmm);
    if (sh == 0 && sm == 0) {
      return startDt.add(const Duration(days: 1));
    }
    return DateTime(day.year, day.month, day.day, 23, 59, 59);
  }

  var endDt = _clockOnDay(endHHmm, day);
  if (!endDt.isAfter(startDt)) {
    endDt = endDt.add(const Duration(days: 1));
  }
  return endDt;
}

/// Início e fim absolutos do plantão (mesma regra em todo o app).
(DateTime start, DateTime end) scaleEntryShiftBounds({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
}) {
  final startDt = _clockOnDay(startHHmm, day);
  final endDt = scaleEntryEndDateTime(
    startHHmm: startHHmm,
    endHHmm: endHHmm,
    day: day,
  );
  return (startDt, endDt);
}

/// True se o turno atravessa para o dia civil seguinte (ex.: 22:00–07:00).
bool scaleShiftCrossesToNextDay({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
}) {
  final (startDt, endDt) = scaleEntryShiftBounds(
    startHHmm: startHHmm,
    endHHmm: endHHmm,
    day: day,
  );
  return startDt.year != endDt.year ||
      startDt.month != endDt.month ||
      startDt.day != endDt.day;
}

/// Horas diurnas/noturnas só pelo relógio (AC4 padrão) — sem valor financeiro.
(double hoursDay, double hoursNight) hoursDayNightFromScaleClock({
  required String startHHmm,
  required String endHHmm,
  DateTime? anchorDay,
}) {
  final day = anchorDay ?? DateTime(2000, 1, 1);
  final startDt = _clockOnDay(startHHmm, day);
  final endDt = scaleEntryEndDateTime(
    startHHmm: startHHmm,
    endHHmm: endHHmm,
    day: day,
  );
  final res = ScaleRates.defaultRates.computeShift(start: startDt, end: endDt);
  return (
    (res['hoursDay'] ?? 0).toDouble(),
    (res['hoursNight'] ?? 0).toDouble(),
  );
}

/// Horas persistidas ou calculadas pelo horário (plantão ordinário sem financeiro).
(double hoursDay, double hoursNight) scaleEntryEffectiveHoursDayNight(
  ScaleEntry e,
) {
  final persisted = e.hoursDay + e.hoursNight;
  if (persisted > 0.009) {
    return (e.hoursDay, e.hoursNight);
  }
  return hoursDayNightFromScaleClock(
    startHHmm: e.start,
    endHHmm: e.end,
    anchorDay: e.date,
  );
}

/// Total de horas do plantão (diurno + noturno), com fallback pelo horário.
double scaleEntryTotalHours(ScaleEntry e) {
  final (hd, hn) = scaleEntryEffectiveHoursDayNight(e);
  return hd + hn;
}

/// Resumo do dia / Controle Estado·Município·Particular / teto do mês:
/// horas e valor só com financeiro ativo (valor > 0 no lançamento).
/// Escala sem financeiro, compromisso e audiência → não entram nesses totais.
bool scaleEntryContaHorasNoResumo(
  ScaleEntry e, {
  List<ShiftLocation> locations = const [],
}) {
  if (e.isCompromissoParticularEfetivo) return false;
  return e.temFinanceiroPainelComLocais(locations);
}

/// Horas exibidas/somadas no resumo (0 quando não entra no financeiro).
double scaleEntryHorasExibicaoResumo(
  ScaleEntry e, {
  List<ShiftLocation> locations = const [],
}) =>
    scaleEntryContaHorasNoResumo(e, locations: locations)
        ? scaleEntryTotalHours(e)
        : 0.0;

/// Par diurno/noturno para PDF e relatórios (0 quando sem financeiro no painel).
(double, double) scaleEntryHoursDayNightResumo(
  ScaleEntry e, {
  List<ShiftLocation> locations = const [],
}) {
  if (!scaleEntryContaHorasNoResumo(e, locations: locations)) {
    return (0.0, 0.0);
  }
  return scaleEntryEffectiveHoursDayNight(e);
}

/// Valor que entra em totais financeiros do resumo / relatório.
double scaleEntryValorResumoFinanceiro(
  ScaleEntry e, {
  List<ShiftLocation> locations = const [],
}) =>
    scaleEntryContaHorasNoResumo(e, locations: locations) ? e.totalValue : 0.0;

/// Soma horas apenas de entradas com financeiro ativo (resumo dia / mês financeiro).
double sumScaleEntriesHoursResumo(
  Iterable<ScaleEntry> entries, {
  List<ShiftLocation> locations = const [],
}) =>
    entries.fold<double>(
      0,
      (s, e) => s + scaleEntryHorasExibicaoResumo(e, locations: locations),
    );

/// Soma horas de várias entradas (O(n) — só dados já em memória).
double sumScaleEntriesHours(Iterable<ScaleEntry> entries) =>
    entries.fold<double>(0, (s, e) => s + scaleEntryTotalHours(e));

String _formatHorasNumero(double hours) {
  if (hours <= 0) return '0';
  if ((hours - hours.roundToDouble()).abs() < 0.05) {
    return hours.round().toString();
  }
  return hours.toStringAsFixed(1).replaceAll('.', ',');
}

/// Cards compactos: "12 h", "120,5 h".
String formatHorasCardUi(double hours) => '${_formatHorasNumero(hours)} h';

/// Resumo do dia — destaque: "12 HORAS".
String formatHorasDestaqueUi(double hours) =>
    '${_formatHorasNumero(hours)} HORAS';

/// Padrão vínculo: quantidade · horas · valor (Estado/Município/Particular/Totalizador).
String formatVinculoContagemHorasValorUi({
  required int quantidade,
  required double horas,
  required String valorFormatado,
  String rotuloQuantidade = 'real.',
}) =>
    '$quantidade $rotuloQuantidade · ${formatHorasCardUi(horas)} · $valorFormatado';

/// Até quando o plantão/compromisso aparece no widget nativo (fim + carência).
DateTime scaleEntryWidgetVisibleUntil({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
  required bool isCompromissoOrMirror,
}) {
  final end = scaleEntryEndDateTime(
    startHHmm: startHHmm,
    endHHmm: endHHmm,
    day: day,
  );
  final grace = isCompromissoOrMirror
      ? kWidgetCompromissoGraceAfterEnd
      : kWidgetPlantaoGraceAfterEnd;
  return end.add(grace);
}

/// Plantão/compromisso ainda visível no widget (2h após fim do plantão; 5h compromisso).
bool scaleEntryVisibleOnWidget({
  required String startHHmm,
  required String endHHmm,
  required DateTime day,
  required DateTime now,
  required bool isCompromissoOrMirror,
}) {
  return now.isBefore(
    scaleEntryWidgetVisibleUntil(
      startHHmm: startHHmm,
      endHHmm: endHHmm,
      day: day,
      isCompromissoOrMirror: isCompromissoOrMirror,
    ),
  );
}
