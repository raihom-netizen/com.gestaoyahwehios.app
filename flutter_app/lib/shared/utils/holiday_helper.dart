// Feriados nacionais brasileiros (lei federal): fixos + móveis a partir da Páscoa.
// Sem API externa — válido para qualquer ano gregoriano.

/// Um feriado nacional no calendário.
class NationalHoliday {
  const NationalHoliday({required this.date, required this.name});

  final DateTime date;
  final String name;
}

/// Utilitário perpétuo para planejamento na Agenda.
abstract final class HolidayHelper {
  HolidayHelper._();

  /// Páscoa (domingo) — algoritmo de Meeus/Jones/Butcher (calendário gregoriano).
  static DateTime easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Lista ordenada (inclui Consciência Negra 20/11 e feriados móveis).
  static List<NationalHoliday> nationalHolidays(int year) {
    final e = easterSunday(year);
    final out = <NationalHoliday>[
      NationalHoliday(date: DateTime(year, 1, 1), name: 'Confraternização Universal'),
      NationalHoliday(
          date: e.subtract(const Duration(days: 48)),
          name: 'Carnaval (ponto facultativo)'),
      NationalHoliday(
          date: e.subtract(const Duration(days: 47)), name: 'Carnaval'),
      NationalHoliday(
          date: e.subtract(const Duration(days: 2)), name: 'Paixão de Cristo'),
      NationalHoliday(date: DateTime(year, 4, 21), name: 'Tiradentes'),
      NationalHoliday(date: DateTime(year, 5, 1), name: 'Dia do Trabalho'),
      NationalHoliday(
          date: e.add(const Duration(days: 60)), name: 'Corpus Christi'),
      NationalHoliday(date: DateTime(year, 9, 7), name: 'Independência do Brasil'),
      NationalHoliday(
          date: DateTime(year, 10, 12), name: 'Nossa Senhora Aparecida'),
      NationalHoliday(date: DateTime(year, 11, 2), name: 'Finados'),
      NationalHoliday(
          date: DateTime(year, 11, 15), name: 'Proclamação da República'),
      NationalHoliday(date: DateTime(year, 11, 20), name: 'Consciência Negra'),
      NationalHoliday(date: DateTime(year, 12, 25), name: 'Natal'),
    ];
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Feriados nacionais que caem em [month] de [year] (ordenados).
  static List<NationalHoliday> nationalHolidaysInMonth(int year, int month) {
    final m = month.clamp(1, 12);
    return nationalHolidays(year)
        .where((h) => h.date.year == year && h.date.month == m)
        .toList();
  }

  /// Chaves `yyyy-MM-dd` para marcar dias no calendário.
  static Set<String> nationalHolidayKeys(int year) {
    final y = year;
    return nationalHolidays(y)
        .map((h) =>
            '${h.date.year.toString().padLeft(4, '0')}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')}')
        .toSet();
  }

  /// Nome do feriado na data (só dia civil; ignora hora).
  static String? holidayNameOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    for (final h in nationalHolidays(day.year)) {
      final x = DateTime(h.date.year, h.date.month, h.date.day);
      if (x == d) return h.name;
    }
    return null;
  }
}
