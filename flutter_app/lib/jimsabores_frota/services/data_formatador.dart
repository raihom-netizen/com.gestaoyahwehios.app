import 'package:intl/intl.dart';

/// Data no padrão DD/MM/AAAA.
String formatarDataBR(DateTime? data) {
  if (data == null) return '';
  return DateFormat('dd/MM/yyyy').format(data);
}

/// Data e hora no padrão DD/MM/AAAA HH:mm.
String formatarDataHoraBR(DateTime? data) {
  if (data == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(data);
}
