import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/utils/utf8_mojibake_fix.dart';

/// Leitura tolerante de campos Firestore — UPPERCASE, camelCase, legado.
///
/// O banco **não** muda; o Flutter adapta-se a qualquer chave ou valor nulo.
abstract final class FirestoreMapFields {
  FirestoreMapFields._();

  static String pickString(
    Map<String, dynamic>? map,
    List<String> keys, {
    String fallback = '',
  }) {
    if (map == null || map.isEmpty) return fallback;
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = Utf8MojibakeFix.repair(v.toString().trim());
      if (s.isNotEmpty) return s;
    }
    return fallback;
  }

  static int pickInt(
    Map<String, dynamic>? map,
    List<String> keys, {
    int fallback = 0,
  }) {
    if (map == null || map.isEmpty) return fallback;
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse(v.toString().trim());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static double pickDouble(
    Map<String, dynamic>? map,
    List<String> keys, {
    double fallback = 0,
  }) {
    if (map == null || map.isEmpty) return fallback;
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      final raw = v.toString().trim().replaceAll(',', '.');
      final parsed = double.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static bool pickBool(
    Map<String, dynamic>? map,
    List<String> keys, {
    bool fallback = false,
  }) {
    if (map == null || map.isEmpty) return fallback;
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      if (v is bool) return v;
      final s = v.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'sim' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'nao' || s == 'não' || s == 'no') {
        return false;
      }
    }
    return fallback;
  }

  static Timestamp? pickTimestamp(Map<String, dynamic>? map, List<String> keys) {
    if (map == null || map.isEmpty) return null;
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      if (v is Timestamp) return v;
      if (v is DateTime) return Timestamp.fromDate(v);
      if (v is Map) {
        final sec = v['seconds'] ?? v['_seconds'];
        if (sec != null) {
          final n = sec is num ? sec.toInt() : int.tryParse(sec.toString());
          if (n != null) return Timestamp.fromMillisecondsSinceEpoch(n * 1000);
        }
      }
      final parsed = DateTime.tryParse(v.toString());
      if (parsed != null) return Timestamp.fromDate(parsed);
    }
    return null;
  }

  static DateTime? pickDate(Map<String, dynamic>? map, List<String> keys) {
    final ts = pickTimestamp(map, keys);
    if (ts != null) return ts.toDate();
    if (map == null || map.isEmpty) return null;
    for (final k in keys) {
      final v = map[k];
      if (v is DateTime) return v;
    }
    return null;
  }

  static List<String> pickStringList(
    Map<String, dynamic>? map,
    List<String> keys, {
    List<String> fallback = const [],
  }) {
    if (map == null || map.isEmpty) return fallback;
    for (final k in keys) {
      final v = map[k];
      if (v is! List) continue;
      final out = v
          .map((e) => Utf8MojibakeFix.repair(e.toString().trim()))
          .where((s) => s.isNotEmpty)
          .toList();
      if (out.isNotEmpty) return out;
    }
    return fallback;
  }

  static String pickCpfDigits(Map<String, dynamic>? map) {
    final raw = pickString(map, const ['CPF', 'cpf', 'Cpf']);
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length == 11 ? digits : '';
  }
}
