import 'package:gestao_yahweh/models/scale_rates.dart';

/// Períodos personalizados de taxa por usuário (stub — usa padrão AC4).
class UserScaleRatesPeriodService {
  UserScaleRatesPeriodService._();

  static final UserScaleRatesPeriodService _singleton =
      UserScaleRatesPeriodService._();
  factory UserScaleRatesPeriodService() => _singleton;

  Future<List<Map<String, dynamic>>> getPeriods(String uid) async => const [];

  ScaleRates ratesForServiceDay(String uid, DateTime serviceDay) =>
      ScaleRates.defaultRates;
}
