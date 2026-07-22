import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show compute, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:home_widget/home_widget.dart';

import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/escala_firestore_fields.dart';
import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_schedules_load_service.dart';
import 'package:gestao_yahweh/services/widget_android_alarm_sync.dart';
import 'package:gestao_yahweh/services/widget_last_sync_prefs.dart';
import 'package:gestao_yahweh/services/widget_native_payload_builder.dart';
import 'package:gestao_yahweh/services/widget_native_payload_cache.dart';
import 'package:gestao_yahweh/services/widget_native_platform_sync.dart';

/// Ponte Flutter → widget nativo (paridade Controle Total): agenda/escalas igreja → JSON v2.
class WidgetUpdateService {
  WidgetUpdateService._();

  static const String androidName = 'GestaoYahwehWidgetProvider';
  static const String androidSmallName = 'GestaoYahwehWidgetSmallProvider';
  static const String androidMediumName = 'GestaoYahwehWidgetMediumProvider';
  static const String iosName = 'GestaoYahwehWidget';
  static const String appGroupId = 'group.com.gestaoyahwehios.app.widget';
  static const String jsonKey = 'widget_events_json';

  static const int _horizonDays = 5;
  static const int _queryLimit = 80;

  static Future<void>? _updateFuture;
  static DateTime? _lastUpdateAt;
  static bool _appGroupConfigured = false;
  static String? _lastJsonPayload;
  static Timer? _debounce;

  static bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> ensureAppGroup() async {
    if (!_isMobileNative || _appGroupConfigured) return;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      _appGroupConfigured = true;
    } catch (_) {}
  }

  static Future<void> syncOpenModuleIndex(int moduleIndex) async {
    if (!_isMobileNative) return;
    await ensureAppGroup();
    try {
      await HomeWidget.saveWidgetData<int>('widget_open_module', moduleIndex);
    } catch (_) {}
  }

  /// Agenda refresh após login / foreground / reconexão.
  static void scheduleWidgetRefresh([String? churchId]) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(updateWidgetData(churchId));
    });
  }

  static Future<void> refreshWidgetIfStale([String? churchId]) async {
    final last = _lastUpdateAt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 8)) {
      return;
    }
    await updateWidgetData(churchId);
  }

  static Future<void> updateWidgetData([String? churchIdHint]) async {
    if (!_isMobileNative) return;
    if (_updateFuture != null) return _updateFuture!;
    _updateFuture = _updateWidgetDataImpl(churchIdHint);
    try {
      await _updateFuture;
    } finally {
      _updateFuture = null;
    }
  }

  static Future<void> _updateWidgetDataImpl(String? churchIdHint) async {
    await ensureAppGroup();
    final due = await WidgetAndroidAlarmSync.consumeNativeSyncDue();
    final churchId = (churchIdHint ?? ChurchContextService.currentChurchId ?? '')
        .trim();
    if (churchId.isEmpty) {
      await _persistEmptyHint('Faça login e abra o painel da igreja');
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final horizonEnd = todayStart.add(Duration(days: _horizonDays));

    final events = <Map<String, dynamic>>[];

    try {
      final agenda = await ChurchAgendaLoadService.loadAll(
        seedTenantId: churchId,
        limit: _queryLimit,
      );
      for (final doc in agenda.docs) {
        final data = doc.data();
        final when = AgendaFirestoreFields.parseDate(data);
        if (when == null) continue;
        final day = DateTime(when.year, when.month, when.day);
        if (day.isBefore(todayStart) || !day.isBefore(horizonEnd)) continue;
        final title = AgendaFirestoreFields.displayTitle(data, docId: doc.id);
        final timeRange = _formatTimeRange(when, data);
        final endOfDay = day.add(const Duration(hours: 23, minutes: 59));
        events.add({
          'dayMs': day.millisecondsSinceEpoch.toString(),
          'sortMs': when.millisecondsSinceEpoch.toString(),
          'type': 'compromisso',
          'title': title,
          'timeRange': timeRange,
          'symbol': '',
          'visibleUntilMs': endOfDay.millisecondsSinceEpoch.toString(),
        });
      }
    } catch (_) {}

    try {
      final escalas = await ChurchSchedulesLoadService.loadEscalas(
        seedTenantId: churchId,
        limit: _queryLimit,
      );
      for (final doc in escalas.docs) {
        final data = doc.data();
        final when = EscalaFirestoreFields.parseDate(data);
        if (when == null) continue;
        final day = DateTime(when.year, when.month, when.day);
        if (day.isBefore(todayStart) || !day.isBefore(horizonEnd)) continue;
        final title = _escalaTitle(data, doc.id);
        final timeRange = _formatTimeRange(when, data);
        final visibleUntil = day
            .add(const Duration(hours: 26))
            .millisecondsSinceEpoch; // fim do dia + 2h
        events.add({
          'dayMs': day.millisecondsSinceEpoch.toString(),
          'sortMs': when.millisecondsSinceEpoch.toString(),
          'type': 'scale',
          'title': title,
          'timeRange': timeRange,
          'symbol': '',
          'visibleUntilMs': visibleUntil.toString(),
        });
      }
    } catch (_) {}

    final input = <String, dynamic>{
      'nowMs': now.millisecondsSinceEpoch,
      'financeRaw': '',
      'events': events,
    };

    String jsonStr;
    try {
      jsonStr = await compute(encodeNativeWidgetPayload, input);
    } catch (_) {
      jsonStr = jsonEncode(buildNativeWidgetPayload(input));
    }

    if (jsonStr.isEmpty) return;
    if (!due && jsonStr == _lastJsonPayload) {
      _lastUpdateAt = now;
      return;
    }

    await _persistJson(jsonStr);
    _lastJsonPayload = jsonStr;
    _lastUpdateAt = now;
    await WidgetLastSyncPrefs.saveNow();
    await WidgetNativePayloadCache.save(churchId, jsonStr);
    unawaited(WidgetAndroidAlarmSync.scheduleAlarmsIfNeeded());
    unawaited(syncOpenModuleIndex(ChurchShellIndices.agenda));
  }

  static Future<void> _persistEmptyHint(String hint) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final payload = buildNativeWidgetPayload({
      'nowMs': now.millisecondsSinceEpoch,
      'financeRaw': '',
      'events': <Map<String, dynamic>>[],
    });
    payload['hint'] = hint.toUpperCase();
    payload['horizonStartMs'] = todayStart.millisecondsSinceEpoch;
    await _persistJson(jsonEncode(payload));
  }

  static Future<void> _persistJson(String jsonStr) async {
    try {
      await HomeWidget.saveWidgetData<String>(jsonKey, jsonStr);
    } catch (_) {}
    await WidgetNativePlatformSync.afterWidgetJsonSaved(jsonStr);
    try {
      await HomeWidget.updateWidget(
        name: androidName,
        androidName: androidName,
        iOSName: iosName,
        qualifiedAndroidName: 'com.gestaoyahweh.app.$androidName',
      );
      await HomeWidget.updateWidget(
        name: androidSmallName,
        androidName: androidSmallName,
        iOSName: iosName,
        qualifiedAndroidName: 'com.gestaoyahweh.app.$androidSmallName',
      );
      await HomeWidget.updateWidget(
        name: androidMediumName,
        androidName: androidMediumName,
        iOSName: iosName,
        qualifiedAndroidName: 'com.gestaoyahweh.app.$androidMediumName',
      );
    } catch (_) {
      await WidgetNativePlatformSync.forceWidgetRedraw();
    }
  }

  static String _escalaTitle(Map<String, dynamic> data, String docId) {
    for (final key in ['titulo', 'title', 'nome', 'name', 'setor', 'ministerio']) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return docId.isNotEmpty ? 'Escala' : 'Escala';
  }

  static String _formatTimeRange(DateTime when, Map<String, dynamic> data) {
    final start = (data['horaInicio'] ?? data['hora'] ?? data['startTime'] ?? '')
        .toString()
        .trim();
    final end = (data['horaFim'] ?? data['endTime'] ?? '').toString().trim();
    if (start.isNotEmpty && end.isNotEmpty) return '$start – $end';
    if (start.isNotEmpty) return start;
    if (when.hour == 0 && when.minute == 0) return 'DIA TODO';
    final hh = when.hour.toString().padLeft(2, '0');
    final mi = when.minute.toString().padLeft(2, '0');
    return '$hh:$mi';
  }
}

typedef WidgetDataService = WidgetUpdateService;
