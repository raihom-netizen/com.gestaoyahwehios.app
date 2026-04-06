import 'package:cloud_firestore/cloud_firestore.dart';

/// Dias em que o voluntário marcou indisponibilidade (viagem etc.) para o líder respeitar na escala.
/// Armazenado em `membros/{id}` no campo [fieldYmds] (lista de strings `yyyy-MM-dd`).
abstract final class MemberScheduleAvailability {
  MemberScheduleAvailability._();

  static const String fieldYmds = 'escalaIndisponivelYmds';
  static const String fieldUpdatedAt = 'escalaIndisponivelUpdatedAt';

  static String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<String> parseYmdList(dynamic raw) {
    if (raw is! List) return [];
    final out = <String>[];
    for (final e in raw) {
      final s = e.toString().trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) && !out.contains(s)) {
        out.add(s);
      }
    }
    out.sort();
    return out;
  }

  static bool isUnavailableOn(List<String> ymds, DateTime day) {
    return ymds.contains(ymd(day));
  }

  /// Minutos desde meia-noite; null se não der para interpretar.
  static int? timeToMinutes(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!) ?? 0;
    final min = int.tryParse(m.group(2)!) ?? 0;
    return h.clamp(0, 47) * 60 + min.clamp(0, 59);
  }

  /// Mesmo dia + sobreposição de horário (margem em minutos entre inícios).
  static bool timesOverlapRough(
    String timeA,
    String timeB, {
    int marginMinutes = 90,
  }) {
    final a = timeToMinutes(timeA);
    final b = timeToMinutes(timeB);
    if (a == null || b == null) return true;
    return (a - b).abs() < marginMinutes;
  }

  static Future<void> saveYmds({
    required DocumentReference<Map<String, dynamic>> memberRef,
    required List<String> sortedYmds,
  }) async {
    await memberRef.set(
      {
        fieldYmds: sortedYmds,
        fieldUpdatedAt: FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// CPF normalizado → aviso se já está em outra escala no mesmo dia com horário sobreposto.
  static Future<Map<String, String>> crossDeptConflictHintsByNormCpf({
    required CollectionReference<Map<String, dynamic>> instancesCol,
    required String excludeEscalaDocId,
    required DateTime calendarDay,
    required String slotTime,
    required String currentDepartmentId,
  }) async {
    String norm(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
    final start = DateTime(calendarDay.year, calendarDay.month, calendarDay.day);
    final end = DateTime(calendarDay.year, calendarDay.month, calendarDay.day, 23, 59, 59, 999);
    final hints = <String, String>{};
    try {
      final q = await instancesCol
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .limit(80)
          .get();
      for (final esc in q.docs) {
        if (esc.id == excludeEscalaDocId) continue;
        final od = esc.data();
        if ((od['departmentId'] ?? '').toString() == currentDepartmentId) {
          continue;
        }
        final escTime = (od['time'] ?? '').toString();
        if (!timesOverlapRough(slotTime, escTime)) continue;
        final dn = (od['departmentName'] ?? '').toString().trim();
        final label = dn.isNotEmpty ? dn : 'outro departamento';
        final mems =
            ((od['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
        for (final c in mems) {
          final n = norm(c);
          if (n.isEmpty) continue;
          hints[n] = 'Já escalado em $label às $escTime';
        }
      }
    } catch (_) {}
    return hints;
  }
}
