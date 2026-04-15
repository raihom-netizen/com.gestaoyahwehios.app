import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _tzInitialized = false;

/// Garante base de fusos para [formatDataEmissaoAmericaSaoPaulo] (chamar cedo no app é opcional).
void ensureBrasiliaTimeZoneInitialized() {
  if (_tzInitialized) return;
  tzdata.initializeTimeZones();
  _tzInitialized = true;
}

/// Formata instante do Firestore sempre em **America/Sao_Paulo** (horário de Brasília).
String formatDataEmissaoAmericaSaoPaulo(dynamic ts) {
  if (ts is! Timestamp) return '—';
  ensureBrasiliaTimeZoneInitialized();
  final loc = tz.getLocation('America/Sao_Paulo');
  final utc = DateTime.fromMillisecondsSinceEpoch(
    ts.millisecondsSinceEpoch,
    isUtc: true,
  );
  final br = tz.TZDateTime.from(utc, loc);
  return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(br);
}

/// Data civil (sem hora) em **America/Sao_Paulo** — filtros e agregações do histórico.
DateTime? emissionCalendarDateBr(dynamic ts) {
  if (ts is! Timestamp) return null;
  ensureBrasiliaTimeZoneInitialized();
  final loc = tz.getLocation('America/Sao_Paulo');
  final utc = DateTime.fromMillisecondsSinceEpoch(
    ts.millisecondsSinceEpoch,
    isUtc: true,
  );
  final br = tz.TZDateTime.from(utc, loc);
  return DateTime(br.year, br.month, br.day);
}
