import 'package:intl/intl.dart';

/// Padrão brasileiro: data dd/MM/yyyy e hora 24h (HH:mm).
/// Use em todo o app para exibição e parsing.
class DateTimeFormats {
  DateTimeFormats._();

  static final DateFormat dateBR = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat time24 = DateFormat('HH:mm', 'pt_BR');
  static final DateFormat dateTimeBR = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  static String formatDate(DateTime d) => dateBR.format(d);
  /// Hora no formato 24h (ex: 14:30).
  static String formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
