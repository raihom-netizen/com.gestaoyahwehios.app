import 'dart:async';

import 'package:gestao_yahweh/models/scale_rates.dart';

/// Períodos globais AC4 GO — stub com defaults embutidos.
class ScaleRatesPeriodService {
  ScaleRatesPeriodService._();

  static final ScaleRatesPeriodService _singleton = ScaleRatesPeriodService._();
  factory ScaleRatesPeriodService() => _singleton;

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    _loaded = true;
  }

  ScaleRates currentDisplayRates() => ScaleRates.defaultRates;

  ScaleRates ratesForServiceDay(DateTime serviceDay) => ScaleRates.defaultRates;

  Map<String, double> computeShift({
    required DateTime start,
    required DateTime end,
  }) =>
      ScaleRates.defaultRates.computeShift(start: start, end: end);

  Map<String, double> computeShiftMainEntryLastDayOfMonth({
    required DateTime start,
    required DateTime end,
    required DateTime entryDate,
  }) =>
      ScaleRates.defaultRates.computeShiftMainEntryLastDayOfMonth(
        start: start,
        end: end,
        entryDate: entryDate,
      );

  Stream<void> watchPeriods() => const Stream.empty();

  Future<void> seedBootstrapIfEmpty() async {
    _loaded = true;
  }
}
