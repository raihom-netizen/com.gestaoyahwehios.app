import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Campos de data/título em `igrejas/{id}/agenda` — produção + legado.
abstract final class AgendaFirestoreFields {
  AgendaFirestoreFields._();

  static const List<String> dateKeys = [
    'startTime',
    'startAt',
    'dataEvento',
    'data',
    'date',
    'dataCompetencia',
    'dataExibicao',
    'createdAt',
  ];

  static const List<String> titleKeys = [
    'title',
    'titulo',
    'evento',
    'nome',
    'name',
  ];

  static DateTime? parseDate(Map<String, dynamic> data) {
    for (final key in dateKeys) {
      final raw = data[key];
      if (raw == null) continue;
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is Map) {
        final sec = raw['seconds'] ?? raw['_seconds'];
        if (sec != null) {
          final n = sec is num ? sec.toInt() : int.tryParse(sec.toString());
          if (n != null) {
            return DateTime.fromMillisecondsSinceEpoch(n * 1000);
          }
        }
      }
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      final iso = DateTime.tryParse(s);
      if (iso != null) return iso;
      for (final fmt in [
        'dd/MM/yyyy',
        'dd/MM/yyyy HH:mm',
        'yyyy-MM-dd',
        'yyyy-MM-dd HH:mm',
      ]) {
        try {
          return DateFormat(fmt).parseStrict(s);
        } catch (_) {}
      }
    }
    return null;
  }

  static Timestamp? parseTimestamp(Map<String, dynamic> data) {
    final dt = parseDate(data);
    return dt == null ? null : Timestamp.fromDate(dt);
  }

  static String displayTitle(Map<String, dynamic> data, {String? docId}) {
    for (final key in titleKeys) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final id = (docId ?? data['id'] ?? '').toString().trim();
    return id.isNotEmpty ? id : 'Compromisso';
  }

  static int compareDateAsc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final da = parseDate(a.data());
    final db = parseDate(b.data());
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }
}
