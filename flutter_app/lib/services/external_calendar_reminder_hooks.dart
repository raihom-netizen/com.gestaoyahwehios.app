import 'dart:async';

/// Hooks para calendários externos (Google etc.) — no-op até integração ativa.
abstract final class ExternalCalendarReminderHooks {
  ExternalCalendarReminderHooks._();

  static Future<void> afterReminderUpsert({
    required String userDocId,
    required String reminderDocId,
    required String title,
    String notes = '',
    required DateTime date,
    required String timeHHmm,
    String endTimeHHmm = '',
    String existingGoogleEventId = '',
  }) async {}
}
