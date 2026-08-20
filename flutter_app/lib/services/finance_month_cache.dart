import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'finance_calendar_bridge.dart';

/// Dados financeiros de um mês civil já processados para o calendário.
class MonthFinanceData {
  final List<CalendarFinanceEntry> entries;
  final Map<DateTime, List<CalendarFinanceEntry>> byDay;
  final Set<DateTime> days;
  final int pendingExpenseCount;
  final double pendingExpenseTotal;
  final int pendingIncomeCount;
  final double pendingIncomeTotal;

  const MonthFinanceData({
    required this.entries,
    required this.byDay,
    required this.days,
    required this.pendingExpenseCount,
    required this.pendingExpenseTotal,
    required this.pendingIncomeCount,
    required this.pendingIncomeTotal,
  });

  factory MonthFinanceData.fromEntries(List<CalendarFinanceEntry> entries) {
    final byDay = FinanceCalendarBridge.groupByDay(entries);
    int expCount = 0;
    double expTotal = 0;
    int incCount = 0;
    double incTotal = 0;
    for (final e in entries) {
      if (e.isExpense) {
        expCount++;
        expTotal += e.amount;
      } else if (e.isIncome) {
        incCount++;
        incTotal += e.amount;
      }
    }
    return MonthFinanceData(
      entries: entries,
      byDay: byDay,
      days: byDay.keys.toSet(),
      pendingExpenseCount: expCount,
      pendingExpenseTotal: expTotal,
      pendingIncomeCount: incCount,
      pendingIncomeTotal: incTotal,
    );
  }

  static const MonthFinanceData empty = MonthFinanceData(
    entries: [],
    byDay: {},
    days: {},
    pendingExpenseCount: 0,
    pendingExpenseTotal: 0,
    pendingIncomeCount: 0,
    pendingIncomeTotal: 0,
  );
}

/// Cache em memória + cache-first do Firestore para dados financeiros no calendário.
///
/// Stale-while-revalidate + dedupe de requests — paint instantâneo ao abrir
/// Agenda/Escalas/Financeiro (paridade Controle Total).
class FinanceMonthCache {
  FinanceMonthCache._();

  static final Map<String, MonthFinanceData> _dataByKey = {};
  static final Map<String, Future<MonthFinanceData>> _inflight = {};
  static final Set<String> _serverRefreshQueued = {};

  static String monthKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}';

  static String _cacheKey(String uid, DateTime day) {
    final fsUid = uid.trim();
    return '$fsUid|${monthKey(day)}';
  }

  static MonthFinanceData? peek(String uid, DateTime focusedDay) {
    return _dataByKey[_cacheKey(uid, focusedDay)];
  }

  static void remember(String uid, DateTime focusedDay, MonthFinanceData data) {
    _dataByKey[_cacheKey(uid, focusedDay)] = data;
  }

  static void invalidateMonth(String uid, DateTime day) {
    final key = _cacheKey(uid, day);
    _dataByKey.remove(key);
    _serverRefreshQueued.remove(key);
  }

  /// Esvazia o cache em RAM quando o operador global troca de igreja.
  ///
  /// Chamado por [ChurchTenantSwitchPurge]. Sem isto o painel mudava de
  /// igreja e continuava a servir o que ja estava em memoria.
  static void purgarNaTrocaDeIgreja() {
    _dataByKey.clear();
    _inflight.clear();
    _serverRefreshQueued.clear();
  }

  static void clearUid(String uid) {
    final fsUid = uid.trim();
    if (fsUid.isEmpty) return;
    final prefix = '$fsUid|';
    _dataByKey.removeWhere((k, _) => k.startsWith(prefix));
    _serverRefreshQueued.removeWhere((k) => k.startsWith(prefix));
  }

  static (DateTime start, DateTime end) _monthBounds(DateTime day) {
    final monthStart = DateTime(day.year, day.month, 1);
    final monthEnd = DateTime(day.year, day.month + 1, 0, 23, 59, 59);
    return (monthStart, monthEnd);
  }

  /// Retorna dados do mês: memória ? cache Firestore ? servidor.
  /// Com cache em memória: devolve na hora e sincroniza servidor em background.
  static Future<MonthFinanceData> fetchMonth(
    String uid,
    DateTime ref, {
    bool forceServer = false,
  }) async {
    final key = _cacheKey(uid, ref);

    final mem = _dataByKey[key];
    if (!forceServer && mem != null) {
      _queueServerRefresh(uid, ref, key);
      return mem;
    }

    final existing = _inflight[key];
    if (existing != null && !forceServer) {
      return existing;
    }

    final future = _fetchMonthImpl(uid, ref, forceServer: forceServer);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight[key], future)) {
        _inflight.remove(key);
      }
    }
  }

  static void _queueServerRefresh(String uid, DateTime ref, String key) {
    if (_serverRefreshQueued.contains(key)) return;
    _serverRefreshQueued.add(key);
    unawaited(() async {
      try {
        await _fetchFromServer(uid, ref);
      } finally {
        _serverRefreshQueued.remove(key);
      }
    }());
  }

  static Future<MonthFinanceData> _fetchMonthImpl(
    String uid,
    DateTime ref, {
    required bool forceServer,
  }) async {
    final (monthStart, _) = _monthBounds(ref);

    if (!forceServer) {
      try {
        final cacheEntries = await FinanceCalendarBridge.fetchPendingForMonth(
          uid,
          monthStart,
          source: Source.cache,
        );
        // Mês vazio também é resultado válido (evita skeleton eterno).
        final data = MonthFinanceData.fromEntries(cacheEntries);
        remember(uid, ref, data);
        if (cacheEntries.isNotEmpty) {
          _queueServerRefresh(uid, ref, _cacheKey(uid, ref));
          return data;
        }
      } catch (_) {}
    }

    return _fetchFromServer(uid, ref);
  }

  static Future<MonthFinanceData> _fetchFromServer(
    String uid,
    DateTime ref,
  ) async {
    final (monthStart, _) = _monthBounds(ref);
    try {
      final entries = await FinanceCalendarBridge.fetchPendingForMonth(
        uid,
        monthStart,
        source: Source.server,
      );
      final data = MonthFinanceData.fromEntries(entries);
      remember(uid, ref, data);
      return data;
    } catch (e, st) {
      debugPrint('FinanceMonthCache.fetchMonth: $e\n$st');
    }
    return peek(uid, ref) ?? MonthFinanceData.empty;
  }

  /// Pré-carrega mês atual (cache Firestore primeiro — sem bloquear UI).
  static Future<void> prefetchCurrentMonth(String uid, [DateTime? ref]) =>
      prefetchMonth(uid, ref ?? DateTime.now());

  /// Pré-carrega um mês civil específico.
  static Future<void> prefetchMonth(String uid, DateTime ref) async {
    final key = _cacheKey(uid, ref);
    if (_dataByKey.containsKey(key)) {
      _queueServerRefresh(uid, ref, key);
      return;
    }
    await fetchMonth(uid, ref);
  }

  /// Mês anterior + seguinte — navegação no calendário sem espera.
  static Future<void> prefetchAdjacentMonths(
      String uid, DateTime focused) async {
    final prev = DateTime(focused.year, focused.month - 1, 1);
    final next = DateTime(focused.year, focused.month + 1, 1);
    await Future.wait([
      prefetchMonth(uid, prev),
      prefetchMonth(uid, next),
    ]);
  }
}
