import 'package:intl/intl.dart';

/// `true` quando o modelo deve gerar/expandir ocorrências na agenda interna,
/// na programação pública e em “Gerar eventos futuros” (predefinição: sim).
bool eventTemplateIncludeInAgenda(Map<String, dynamic> m) =>
    m['includeInAgenda'] != false;

/// Próxima data (sem hora) cujo [weekday] coincide (Dart: seg=1 … dom=7).
DateTime nextWeekdayOnOrAfter(DateTime from, int weekday) {
  var d = DateTime(from.year, from.month, from.day);
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// Lista de ocorrências entre [rangeStart] e [rangeEnd] (inclusive nos dias).
/// [weekday]: 1–7 (seg–dom), como em `event_templates.weekday`.
List<DateTime> expandTemplateOccurrencesInRange({
  required int weekday,
  required String timeHHmm,
  required String recurrence,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final tp = timeHHmm.split(':');
  final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
  final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 30;
  final rec = recurrence.toLowerCase().trim();
  final w = weekday.clamp(1, 7);

  var cursor = nextWeekdayOnOrAfter(rangeStart, w);
  final out = <DateTime>[];
  final endDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);

  while (!cursor.isAfter(endDay)) {
    if (!cursor.isBefore(DateTime(rangeStart.year, rangeStart.month, rangeStart.day))) {
      final dt = DateTime(cursor.year, cursor.month, cursor.day, hh, mm);
      if (!dt.isAfter(rangeEnd)) {
        out.add(dt);
      }
    }
    if (rec == 'biweekly') {
      cursor = cursor.add(const Duration(days: 14));
    } else if (rec == 'monthly') {
      final nm = DateTime(cursor.year, cursor.month + 1, 1);
      cursor = nextWeekdayOnOrAfter(nm, w);
    } else {
      cursor = cursor.add(const Duration(days: 7));
    }
  }
  return out;
}

String formatPublicDatePt(DateTime d) =>
    DateFormat('dd/MM/yyyy', 'pt_BR').format(d);

String weekdayShortPt(DateTime d) {
  const names = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  return names[d.weekday - 1];
}

String weekdayLongPt(DateTime d) =>
    DateFormat('EEEE', 'pt_BR').format(d);

/// Nome do dia em português (ex.: domingo) para [weekday] ISO 1–7 (segunda a domingo), como em [event_templates.weekday].
String weekdayLongNameFromIsoWeekday(int weekday) {
  final w = weekday.clamp(1, 7);
  return DateFormat('EEEE', 'pt_BR').format(DateTime(2024, 1, w));
}
