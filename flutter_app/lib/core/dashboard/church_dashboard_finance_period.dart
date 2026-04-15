import 'package:flutter/material.dart';

/// Presets do filtro financeiro no painel da igreja (dashboard).
enum ChurchDashboardFinancePreset {
  previousMonth,
  currentMonth,
  weekly,
  yearly,
  custom,
}

/// Resolve o intervalo [DateTimeRange] em horário local e rótulos para a UI.
class ChurchDashboardFinancePeriod {
  ChurchDashboardFinancePeriod._();

  static DateTimeRange resolve({
    required ChurchDashboardFinancePreset preset,
    DateTimeRange? custom,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    switch (preset) {
      case ChurchDashboardFinancePreset.previousMonth:
        final first = DateTime(n.year, n.month - 1, 1);
        final lastDay = DateTime(n.year, n.month, 0);
        return DateTimeRange(
          start: DateTime(first.year, first.month, first.day),
          end: DateTime(
            lastDay.year,
            lastDay.month,
            lastDay.day,
            23,
            59,
            59,
            999,
          ),
        );
      case ChurchDashboardFinancePreset.currentMonth:
        final lastDay = DateTime(n.year, n.month + 1, 0);
        return DateTimeRange(
          start: DateTime(n.year, n.month, 1),
          end: DateTime(
            lastDay.year,
            lastDay.month,
            lastDay.day,
            23,
            59,
            59,
            999,
          ),
        );
      case ChurchDashboardFinancePreset.weekly:
        final endDay = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
        final startDay = endDay.subtract(const Duration(days: 6));
        return DateTimeRange(
          start: DateTime(
            startDay.year,
            startDay.month,
            startDay.day,
          ),
          end: endDay,
        );
      case ChurchDashboardFinancePreset.yearly:
        return DateTimeRange(
          start: DateTime(n.year, 1, 1),
          end: DateTime(n.year, 12, 31, 23, 59, 59, 999),
        );
      case ChurchDashboardFinancePreset.custom:
        final c = custom;
        if (c == null) {
          return resolve(
            preset: ChurchDashboardFinancePreset.currentMonth,
            now: n,
          );
        }
        return DateTimeRange(
          start: DateTime(c.start.year, c.start.month, c.start.day),
          end: DateTime(
            c.end.year,
            c.end.month,
            c.end.day,
            23,
            59,
            59,
            999,
          ),
        );
    }
  }

  static String presetLabel(ChurchDashboardFinancePreset p) {
    switch (p) {
      case ChurchDashboardFinancePreset.previousMonth:
        return 'Mês anterior';
      case ChurchDashboardFinancePreset.currentMonth:
        return 'Mês atual';
      case ChurchDashboardFinancePreset.weekly:
        return 'Semanal';
      case ChurchDashboardFinancePreset.yearly:
        return 'Anual';
      case ChurchDashboardFinancePreset.custom:
        return 'Período';
    }
  }

  /// Meses “equivalentes” para médias tipo / mês (projeção).
  static double equivalentMonths(DateTimeRange range) {
    final days = range.end.difference(range.start).inDays + 1;
    if (days < 1) return 1 / 30.4;
    return (days / 30.4).clamp(1 / 30.4, 120.0);
  }

  static bool sameRange(DateTimeRange? a, DateTimeRange? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.start == b.start && a.end == b.end;
  }
}
