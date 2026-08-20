import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:gestao_yahweh/utils/firestore_session_guard.dart';
import 'package:gestao_yahweh/ui/widgets/home_start_module_picker.dart';
import 'app_session_cache.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

/// Campo em `users/{uid}/settings/planning` — início da semana no calendário.
const String kCalendarWeekStartsOnSundayField = 'calendarWeekStartsOnSunday';

/// Início da semana no calendário do módulo Escalas — preferência por usuário.
/// Usada em **todo** calendário do app (Escalas, lançamento expresso, compromisso, etc.).
///
/// Persistência: local (`SharedPreferences`) + nuvem (`settings/planning`).
/// Após update de versão: preserva a escolha local e sincroniza com a nuvem.
class ScalesCalendarWeekStartPrefs {
  ScalesCalendarWeekStartPrefs._();

  static const _kUid = 'scales_cal_week_uid_v1';
  static const _kSunday = 'scales_cal_week_sunday_v1';

  static const _weekLabelsMondayFirst = [
    'SEG',
    'TER',
    'QUA',
    'QUI',
    'SEX',
    'SAB',
    'DOM',
  ];

  static const _weekLabelsSundayFirst = [
    'DOM',
    'SEG',
    'TER',
    'QUA',
    'QUI',
    'SEX',
    'SAB',
  ];

  static bool? _memorySunday;
  static String? _memoryUid;

  /// Padrão global do app: semana começa no domingo.
  static const StartingDayOfWeek defaultWeekStart = StartingDayOfWeek.sunday;

  static StartingDayOfWeek _weekStartFromSunday(bool startsOnSunday) =>
      startsOnSunday ? StartingDayOfWeek.sunday : StartingDayOfWeek.monday;

  /// Resolve UID para calendários quando o caller não passa explicitamente.
  static String? resolveUidForCalendar(String? uid) {
    final clean = (uid ?? '').trim();
    if (clean.isNotEmpty) return clean;
    return AppSessionCache.cachedUidSync();
  }

  /// Cabeçalhos da grade (SEG…DOM ou DOM…SAB).
  static List<String> weekLabels(StartingDayOfWeek start) =>
      start == StartingDayOfWeek.sunday
          ? _weekLabelsSundayFirst
          : _weekLabelsMondayFirst;

  /// Rótulo curto do dia civil (1=seg … 7=dom) — independente da ordem das colunas.
  static String weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'SEG';
      case DateTime.tuesday:
        return 'TER';
      case DateTime.wednesday:
        return 'QUA';
      case DateTime.thursday:
        return 'QUI';
      case DateTime.friday:
        return 'SEX';
      case DateTime.saturday:
        return 'SAB';
      case DateTime.sunday:
        return 'DOM';
      default:
        return '';
    }
  }

  /// Início da semana para calendários (síncrono + padrão domingo).
  static StartingDayOfWeek resolveWeekStart(String? uid) {
    final resolved = resolveUidForCalendar(uid);
    if (resolved == null) return defaultWeekStart;
    return weekStartSync(resolved);
  }

  /// Células vazias antes do dia 1 na grade mensal.
  static int leadingBlanksForMonth(
    int year,
    int month,
    StartingDayOfWeek start,
  ) {
    final weekday = DateTime(year, month, 1).weekday;
    if (start == StartingDayOfWeek.sunday) {
      return weekday % 7;
    }
    return weekday - 1;
  }

  /// Coluna de cabeçalho é fim de semana (sáb/dom).
  static bool isWeekendHeaderColumn(int columnIndex, StartingDayOfWeek start) {
    if (start == StartingDayOfWeek.sunday) {
      return columnIndex == 0 || columnIndex == 6;
    }
    return columnIndex >= 5;
  }

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    // Preserva valor mesmo se uid estiver vazio (migração / update).
    if (!prefs.containsKey(_kSunday)) {
      _memorySunday = true;
      _memoryUid = null;
      return;
    }
    final uid = (prefs.getString(_kUid) ?? '').trim();
    _memoryUid = uid.isEmpty ? null : uid;
    _memorySunday = prefs.getBool(_kSunday) ?? true;
  }

  /// Leitura síncrona após [warmUp] — evita flash segunda→domingo no 1º paint.
  static StartingDayOfWeek weekStartSync(String uid) {
    final clean = uid.trim();
    if (_memorySunday == null) return defaultWeekStart;
    if (clean.isNotEmpty &&
        _memoryUid != null &&
        _memoryUid!.isNotEmpty &&
        _memoryUid != clean) {
      return defaultWeekStart;
    }
    return _weekStartFromSunday(_memorySunday!);
  }

  static Future<StartingDayOfWeek> load(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return defaultWeekStart;

    // 1) Nuvem (fonte entre aparelhos).
    final remote = await _readRemote(clean);
    if (remote != null) {
      await _saveLocal(clean, startsOnSunday: remote);
      return _weekStartFromSunday(remote);
    }

    // 2) Local do mesmo usuário (ou migração se uid local vazio) —
    //    preserva após update de versão; não mistura contas.
    final prefs = await SharedPreferences.getInstance();
    final storedUid = (prefs.getString(_kUid) ?? '').trim();
    if (prefs.containsKey(_kSunday) &&
        (storedUid.isEmpty || storedUid == clean)) {
      final sunday = prefs.getBool(_kSunday) ?? true;
      await _saveLocal(clean, startsOnSunday: sunday);
      await _writeRemote(clean, startsOnSunday: sunday);
      return _weekStartFromSunday(sunday);
    }

    if (_memorySunday != null &&
        (_memoryUid == null ||
            _memoryUid!.isEmpty ||
            _memoryUid == clean)) {
      final sunday = _memorySunday!;
      await _saveLocal(clean, startsOnSunday: sunday);
      await _writeRemote(clean, startsOnSunday: sunday);
      return _weekStartFromSunday(sunday);
    }

    _memoryUid = clean;
    _memorySunday = true;
    await _saveLocal(clean, startsOnSunday: true);
    await _writeRemote(clean, startsOnSunday: true);
    return defaultWeekStart;
  }

  static Future<void> save(String uid, {required bool startsOnSunday}) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    await _saveLocal(clean, startsOnSunday: startsOnSunday);
    await _writeRemote(clean, startsOnSunday: startsOnSunday);
  }

  static Future<void> prefetch(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    try {
      await load(clean);
    } catch (e, st) {
      debugPrint('ScalesCalendarWeekStartPrefs.prefetch: $e\n$st');
    }
  }

  static Future<void> clear() async {
    _memorySunday = null;
    _memoryUid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kSunday);
  }

  static Future<void> _saveLocal(
    String uid, {
    required bool startsOnSunday,
  }) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    _memoryUid = clean;
    _memorySunday = startsOnSunday;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, clean);
    await prefs.setBool(_kSunday, startsOnSunday);
  }

  static Future<bool?> _readRemote(String uid) async {
    try {
      final snap = await homePlanningRef(uid).get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null || !data.containsKey(kCalendarWeekStartsOnSundayField)) {
        return null;
      }
      final raw = data[kCalendarWeekStartsOnSundayField];
      if (raw is bool) return raw;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeRemote(
    String uid, {
    required bool startsOnSunday,
  }) async {
    try {
      await FirestoreSessionGuard.runWithAuthRetry(() async {
        await YahwehDocWrite.set(homePlanningRef(uid), {
          kCalendarWeekStartsOnSundayField: startsOnSunday,
          'updatedAt': YahwehFv.serverTimestamp,
        });
      });
    } catch (e, st) {
      debugPrint('ScalesCalendarWeekStartPrefs.save: $e\n$st');
    }
  }
}
