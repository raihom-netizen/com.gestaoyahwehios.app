import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Aniversariantes sem varrer todos os membros — índice `birthMonth` + limite.
abstract final class ChurchBirthdayQueryService {
  ChurchBirthdayQueryService._();

  static CollectionReference<Map<String, dynamic>> _membros(String tenantId) {
    return         ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('membros');
  }

  /// Membros com aniversário no mês corrente (máx. [limit]).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchCurrentMonthBirthdays({
    required String tenantId,
    int? limit,
    int? month,
  }) async {
    final m = month ?? DateTime.now().month;
    final cap = limit ?? YahwehPerformanceV4.birthdayQueryLimit;
    try {
      final snap = await _membros(tenantId)
          .where(YahwehPerformanceV4.memberBirthMonthField, isEqualTo: m)
          .limit(cap)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs;
    } catch (_) {}
    return const [];
  }

  /// Aniversariantes de hoje (`birthMonth` + `birthDay`).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchTodayBirthdays({
    required String tenantId,
    int? limit,
  }) async {
    final now = DateTime.now();
    final cap = limit ?? YahwehPerformanceV4.birthdayQueryLimit;
    try {
      final snap = await _membros(tenantId)
          .where(YahwehPerformanceV4.memberBirthMonthField, isEqualTo: now.month)
          .where(YahwehPerformanceV4.memberBirthDayField, isEqualTo: now.day)
          .limit(cap)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs;
    } catch (_) {}
    final monthDocs = await fetchCurrentMonthBirthdays(
      tenantId: tenantId,
      limit: cap * 2,
      month: now.month,
    );
    return monthDocs.where((d) {
      final day = d.data()[YahwehPerformanceV4.memberBirthDayField];
      final n = day is num ? day.toInt() : int.tryParse('$day');
      return n == now.day;
    }).take(cap).toList();
  }

  static Set<(int, int)> weekMonthDaySet([DateTime? anchor]) {
    final now = anchor ?? DateTime.now();
    final set = <(int, int)>{};
    for (var i = 0; i < 7; i++) {
      final d = now.add(Duration(days: i));
      set.add((d.month, d.day));
    }
    return set;
  }

  /// Próximos 7 dias (inclui hoje), via índice `birthMonth` (suporta virada de mês).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchWeekBirthdays({
    required String tenantId,
    int? limit,
    DateTime? anchor,
  }) async {
    final now = anchor ?? DateTime.now();
    final cap = limit ?? YahwehPerformanceV4.birthdayQueryLimit;
    final weekSet = weekMonthDaySet(now);
    final months = weekSet.map((e) => e.$1).toSet();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};
    for (final mo in months) {
      final monthDocs = await fetchCurrentMonthBirthdays(
        tenantId: tenantId,
        limit: cap * 2,
        month: mo,
      );
      for (final d in monthDocs) {
        if (!seen.add(d.id)) continue;
        final day = d.data()[YahwehPerformanceV4.memberBirthDayField];
        final n = day is num ? day.toInt() : int.tryParse('$day');
        if (n == null) continue;
        if (weekSet.contains((mo, n))) {
          out.add(d);
        }
      }
    }
    out.sort((a, b) {
      final da = a.data()[YahwehPerformanceV4.memberBirthDayField];
      final db = b.data()[YahwehPerformanceV4.memberBirthDayField];
      final na = da is num ? da.toInt() : int.tryParse('$da') ?? 0;
      final nb = db is num ? db.toInt() : int.tryParse('$db') ?? 0;
      return na.compareTo(nb);
    });
    return out.take(cap).toList();
  }

  /// Todos os aniversariantes de um mês (índice `birthMonth`).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchMonthBirthdays({
    required String tenantId,
    required int month,
    int? limit,
  }) async {
    final docs = await fetchCurrentMonthBirthdays(
      tenantId: tenantId,
      month: month,
      limit: limit ?? YahwehPerformanceV4.birthdayQueryLimit,
    );
    docs.sort((a, b) {
      final da = a.data()[YahwehPerformanceV4.memberBirthDayField];
      final db = b.data()[YahwehPerformanceV4.memberBirthDayField];
      final na = da is num ? da.toInt() : int.tryParse('$da') ?? 0;
      final nb = db is num ? db.toInt() : int.tryParse('$db') ?? 0;
      return na.compareTo(nb);
    });
    return docs;
  }

  /// Carrega os 12 meses (para página «Ano todo»).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchYearAllMonths({
    required String tenantId,
    int? perMonthLimit,
  }) async {
    final cap = perMonthLimit ?? YahwehPerformanceV4.birthdayQueryLimit;
    final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};
    for (var m = 1; m <= 12; m++) {
      final docs = await fetchMonthBirthdays(
        tenantId: tenantId,
        month: m,
        limit: cap,
      );
      for (final d in docs) {
        if (seen.add(d.id)) all.add(d);
      }
    }
    return all;
  }
}
