import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/member_schedule_availability_service.dart';

/// Validações de inteligência do módulo de escalas (conflito + indisponibilidade).
abstract final class ScheduleIntelValidators {
  ScheduleIntelValidators._();

  static String ymdKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// CPFs (11 dígitos) já ocupados em **outro** departamento no mesmo dia com horário sobreposto.
  static Future<Set<String>> otherDeptBusyNormCpfs({
    required CollectionReference<Map<String, dynamic>> instancesCol,
    required DateTime calendarDay,
    required String slotTime,
    required String currentDepartmentId,
    String excludeEscalaDocId = '',
  }) async {
    final hints = await MemberScheduleAvailability.crossDeptConflictHintsByNormCpf(
      instancesCol: instancesCol,
      excludeEscalaDocId: excludeEscalaDocId,
      calendarDay: calendarDay,
      slotTime: slotTime,
      currentDepartmentId: currentDepartmentId,
    );
    return hints.keys.toSet();
  }
}
