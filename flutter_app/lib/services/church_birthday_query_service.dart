import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Aniversariantes sem varrer todos os membros — índice `birthMonth` + limite.
abstract final class ChurchBirthdayQueryService {
  ChurchBirthdayQueryService._();

  static CollectionReference<Map<String, dynamic>> _membros(String tenantId) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
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
}
