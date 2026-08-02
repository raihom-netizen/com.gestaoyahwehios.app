import 'dart:async';

import 'agenda_notifications_refresher.dart';
import 'widget_update_service.dart';

/// Trabalho pesado pós-salvar (notificações locais + widget) **fora** do caminho
/// crítico do botão Salvar — timers separados evitam rajadas de GET Firestore.
class PostSaveBackgroundCoordinator {
  PostSaveBackgroundCoordinator._();

  /// Widget nativo: confirmação leve só se o refresh imediato não concluiu.
  static const Duration _widgetDebounce = Duration(milliseconds: 700);

  /// Notificações locais: agrupa saves seguidos sem bloquear UI.
  static const Duration _notifDebounce = Duration(milliseconds: 5000);

  /// Acima disso → refresh completo (lote / geração automática).
  static const int _incrementalMaxDocs = 12;

  static Timer? _notifTimer;
  static Timer? _widgetTimer;

  static String? _pendingUid;
  static bool _forceFullRefresh = false;
  static String? _widgetUid;

  static final Set<String> _reminderIds = {};
  static final Set<String> _scaleIds = {};
  static final Map<String, Map<String, dynamic>> _beforeReminder = {};
  static final Map<String, Map<String, dynamic>> _beforeScale = {};
  static final Set<String> _deletedReminderIds = {};
  static final Set<String> _deletedScaleIds = {};

  /// Agenda sync em background. Várias gravações seguidas → um único refresh.
  static void schedule(
    String userDocId, {
    bool notifications = false,
    bool widget = false,
    bool fullNotificationRefresh = false,
    String? reminderDocId,
    String? scaleDocId,
    List<String>? reminderDocIds,
    List<String>? scaleDocIds,
    Map<String, dynamic>? beforeReminderData,
    Map<String, dynamic>? beforeScaleData,
    bool reminderDeleted = false,
    bool scaleDeleted = false,
  }) {
    if (userDocId.isEmpty) return;
    _pendingUid = userDocId;
    if (notifications) {
      _forceFullRefresh = _forceFullRefresh || fullNotificationRefresh;
    }
    if (widget) {
      _widgetUid = userDocId;
      // Sync imediato via cache local; confirmação só se ainda pendente (~700 ms).
      WidgetUpdateService.scheduleWidgetRefresh(userDocId);
    }

    for (final id in reminderDocIds ?? const <String>[]) {
      if (id.isEmpty) continue;
      if (reminderDeleted) {
        _deletedReminderIds.add(id);
      } else {
        _reminderIds.add(id);
      }
    }
    for (final id in scaleDocIds ?? const <String>[]) {
      if (id.isEmpty) continue;
      if (scaleDeleted) {
        _deletedScaleIds.add(id);
      } else {
        _scaleIds.add(id);
      }
    }

    if (reminderDocId != null && reminderDocId.isNotEmpty) {
      if (reminderDeleted) {
        _deletedReminderIds.add(reminderDocId);
        if (beforeReminderData != null) {
          _beforeReminder[reminderDocId] = beforeReminderData;
        }
      } else {
        _reminderIds.add(reminderDocId);
        if (beforeReminderData != null) {
          _beforeReminder[reminderDocId] = beforeReminderData;
        }
      }
    }
    if (scaleDocId != null && scaleDocId.isNotEmpty) {
      if (scaleDeleted) {
        _deletedScaleIds.add(scaleDocId);
        if (beforeScaleData != null) {
          _beforeScale[scaleDocId] = beforeScaleData;
        }
      } else {
        _scaleIds.add(scaleDocId);
        if (beforeScaleData != null) {
          _beforeScale[scaleDocId] = beforeScaleData;
        }
      }
    }

    if (notifications) {
      _notifTimer?.cancel();
      _notifTimer = Timer(_notifDebounce, _flushNotifications);
    }
    if (widget) {
      _widgetTimer?.cancel();
      _widgetTimer = Timer(_widgetDebounce, _flushWidget);
    }
  }

  /// Financeiro / meta: só widget (sem notificações locais de agenda).
  static void scheduleFinanceWidget(String userDocId) {
    if (userDocId.isEmpty) return;
    _widgetUid = userDocId;
    WidgetUpdateService.scheduleWidgetRefresh(userDocId);
    _widgetTimer?.cancel();
    _widgetTimer = Timer(_widgetDebounce, _flushWidget);
  }

  static void _flushNotifications() {
    final uid = _pendingUid;
    final full = _forceFullRefresh;
    final reminderIds = Set<String>.from(_reminderIds);
    final scaleIds = Set<String>.from(_scaleIds);
    final beforeReminder = Map<String, Map<String, dynamic>>.from(_beforeReminder);
    final beforeScale = Map<String, Map<String, dynamic>>.from(_beforeScale);
    final deletedReminders = Set<String>.from(_deletedReminderIds);
    final deletedScales = Set<String>.from(_deletedScaleIds);

    _forceFullRefresh = false;
    _reminderIds.clear();
    _scaleIds.clear();
    _beforeReminder.clear();
    _beforeScale.clear();
    _deletedReminderIds.clear();
    _deletedScaleIds.clear();
    _notifTimer = null;

    if (uid == null || uid.isEmpty) return;

    final changeCount = reminderIds.length +
        scaleIds.length +
        deletedReminders.length +
        deletedScales.length;
    if (!full && changeCount > 0 && changeCount <= _incrementalMaxDocs) {
      unawaited(
        AgendaNotificationsRefresher.refreshIncrementalCompat(
          uid: uid,
          reminderIds: reminderIds,
          scaleIds: scaleIds,
          cancelReminderBefore: beforeReminder,
          cancelScaleBefore: beforeScale,
          deletedReminderIds: deletedReminders,
          deletedScaleIds: deletedScales,
        ),
      );
    } else {
      unawaited(AgendaNotificationsRefresher.refresh(uid: uid));
    }
  }

  static void _flushWidget() {
    final uid = _widgetUid;
    _widgetUid = null;
    _widgetTimer = null;
    if (uid == null || uid.isEmpty) return;
    unawaited(WidgetUpdateService.refreshWidgetIfStale(uid));
  }
}
