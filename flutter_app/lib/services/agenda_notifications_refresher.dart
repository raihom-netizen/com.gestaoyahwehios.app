/// Stub — AgendaNotificationsRefresher (CT compat).
/// Versão simplificada para YAHWEH: apenas invalida epoch de mutações.
library;

import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';

abstract final class AgendaNotificationsRefresher {
  /// Incrementa o epoch de mutações (compat com CT).
  static Future<void> refreshIncremental([
    String? churchId,
  ]) async {
    if (churchId != null) {
      ChurchFinanceRealtimeService.onFinanceMutation(churchId);
    }
  }

  /// Compat CT — parâmetros ignorados em YAHWEH (no-op).
  static Future<void> refreshIncrementalCompat({
    String? uid,
    Set<String>? reminderIds,
    Set<String>? scaleIds,
    Map<String, Map<String, dynamic>>? cancelReminderBefore,
    Map<String, Map<String, dynamic>>? cancelScaleBefore,
    Set<String>? deletedReminderIds,
    Set<String>? deletedScaleIds,
  }) async {/* no-op */}

  /// Reagendar notificações para um utilizador (no-op em YAHWEH).
  static Future<void> refresh({String? uid}) async {/* no-op */}
}
