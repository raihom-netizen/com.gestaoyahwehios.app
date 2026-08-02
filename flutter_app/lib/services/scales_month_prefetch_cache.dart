import 'dart:async';

/// Pré-carrega mês de Escalas em background (stub leve — cache opcional).
abstract final class ScalesMonthPrefetchCache {
  ScalesMonthPrefetchCache._();

  static void invalidateMonth(String uid, DateTime month) {}

  static Future<void> prefetchMonth(String uid, DateTime month) async {}
}
