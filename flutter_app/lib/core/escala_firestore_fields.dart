import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Campos de data/título em `igrejas/{id}/escalas` — produção + legado.
abstract final class EscalaFirestoreFields {
  EscalaFirestoreFields._();

  static const List<String> dateKeys = [
    'date',
    'data',
    'dataEscala',
    'dataCompetencia',
    'createdAt',
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
      for (final fmt in ['dd/MM/yyyy', 'dd/MM/yyyy HH:mm', 'yyyy-MM-dd']) {
        try {
          return DateFormat(fmt).parseStrict(s);
        } catch (_) {}
      }
    }
    return null;
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

  static int compareDateDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) =>
      compareDateAsc(b, a);
}
