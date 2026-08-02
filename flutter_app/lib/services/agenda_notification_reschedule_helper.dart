import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Reagendamento silencioso de notificações da Agenda após gravação.
abstract final class AgendaNotificationRescheduleHelper {
  AgendaNotificationRescheduleHelper._();

  static Future<void> afterReminderSave({
    required String userDocId,
    required DocumentReference<Map<String, dynamic>> reminderRef,
    Map<String, dynamic>? beforeData,
    required DateTime newDate,
    required String newTimeHHmm,
    Map<String, dynamic>? afterPlanSnapshot,
  }) async {}

  static Future<void> afterItemChanged({
    required String userDocId,
    bool queueRebuild = false,
  }) async {}
}
