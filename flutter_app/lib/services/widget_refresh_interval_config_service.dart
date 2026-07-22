import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Horários fixos da sincronização local do widget (app_config/widget_local_refresh).
class WidgetRefreshIntervalConfigService {
  WidgetRefreshIntervalConfigService._();

  static const docPath = 'app_config/widget_local_refresh';

  /// Duas sincronizações por dia: meia-noite e meio-dia (horário local do aparelho).
  static const List<int> syncHours = <int>[0, 12];

  static const String syncModeTwiceDaily = 'twice_daily';

  static List<int>? _cachedHours;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static final List<VoidCallback> _listeners = <VoidCallback>[];

  static List<int> get effectiveSyncHours => _cachedHours ?? syncHours;

  static String get scheduleKey => effectiveSyncHours.join(',');

  static String get scheduleLabel => effectiveSyncHours
      .map((h) => h == 0 ? '00:00' : '${h.toString().padLeft(2, '0')}:00')
      .join(' e ');

  static void _applyFromMap(Map<String, dynamic>? data) {
    final raw = data?['syncHours'];
    if (raw is List && raw.isNotEmpty) {
      final parsed = raw
          .map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? -1)
          .where((h) => h >= 0 && h < 24)
          .toList()
        ..sort();
      if (parsed.isNotEmpty) {
        _cachedHours = parsed;
        return;
      }
    }
    _cachedHours = List<int>.from(syncHours);
  }

  /// Próximo horário de sincronização após [from] (relógio local).
  static DateTime nextScheduledSyncAfter(DateTime from) {
    final hours = effectiveSyncHours;
    for (var dayOffset = 0; dayOffset < 4; dayOffset++) {
      final base = DateTime(from.year, from.month, from.day)
          .add(Duration(days: dayOffset));
      for (final hour in hours) {
        final slot = DateTime(base.year, base.month, base.day, hour);
        if (slot.isAfter(from)) return slot;
      }
    }
    return from.add(const Duration(hours: 12));
  }

  static Duration delayUntilNextSync([DateTime? from]) {
    final now = from ?? DateTime.now();
    return nextScheduledSyncAfter(now).difference(now);
  }

  static void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  static Future<void> warmUp() async {
    try {
      final snap = await FirebaseFirestore.instance.doc(docPath).get(
            const GetOptions(source: Source.serverAndCache),
          );
      _applyFromMap(snap.data());
    } catch (e, st) {
      debugPrint('WidgetRefreshIntervalConfigService.warmUp: $e\n$st');
      _cachedHours = List<int>.from(syncHours);
    }
  }

  static void startListening() {
    if (_sub != null) return;
    _sub = FirebaseFirestore.instance.doc(docPath).snapshots().listen(
      (snap) {
        final prev = scheduleKey;
        _applyFromMap(snap.data());
        if (prev != scheduleKey) {
          _notifyListeners();
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('WidgetRefreshIntervalConfigService.listen: $e\n$st');
      },
    );
  }

  static void stopListening() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
