import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Aniversariantes — índice `birthMonth`/`birthDay` com fallback por `DATA_NASCIMENTO`.
abstract final class ChurchBirthdayQueryService {
  ChurchBirthdayQueryService._();

  static const int yearViewPerMonthLimit = 80;
  static const int yearScanMemberLimit = 600;

  static CollectionReference<Map<String, dynamic>> _membros(String tenantId) {
    return ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('membros');
  }

  static Future<String> _resolveTenantId(String tenantId) async {
    final bound = ChurchContext.currentChurchId?.trim() ?? '';
    if (bound.isNotEmpty) return bound;
    final panel = ChurchContextService.panelChurchId(tenantId);
    return panel.isNotEmpty ? panel : tenantId.trim();
  }

  static Future<List<String>> _clusterIds(String tid) async {
    final ids = <String>{tid.trim()};
    try {
      for (final s in await TenantResolverService.getAllRelatedIgrejaDocIds(tid)) {
        final t = s.trim();
        if (t.isNotEmpty) ids.add(t);
      }
    } catch (_) {}
    return ids.toList();
  }

  static int? _birthDayFromData(Map<String, dynamic> data) {
    final raw = data[YahwehPerformanceV4.memberBirthDayField];
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  static int? _birthMonthFromData(Map<String, dynamic> data) {
    final raw = data[YahwehPerformanceV4.memberBirthMonthField];
    if (raw is num) return raw.toInt();
    final parsed = int.tryParse('$raw');
    if (parsed != null && parsed >= 1 && parsed <= 12) return parsed;
    return birthDateFromMemberData(data)?.month;
  }

  /// Membros com aniversário no mês (índice `birthMonth` + cluster BPC).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchCurrentMonthBirthdays({
    required String tenantId,
    int? limit,
    int? month,
  }) async {
    final tid = await _resolveTenantId(tenantId);
    if (tid.isEmpty) return const [];
    final m = month ?? DateTime.now().month;
    final cap = limit ?? YahwehPerformanceV4.birthdayQueryLimit;
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};

    await ChurchTenantResilientReads.preparePanelRead();

    for (final id in await _clusterIds(tid)) {
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => _membros(id)
              .where(YahwehPerformanceV4.memberBirthMonthField, isEqualTo: m)
              .limit(cap)
              .get(),
        );
        for (final d in snap.docs) {
          if (seen.add(d.id)) out.add(d);
        }
        if (out.length >= cap) break;
      } catch (_) {}
    }

    if (out.isNotEmpty) return out.take(cap).toList();

    try {
      final scan = await ChurchTenantResilientReads.membrosRecent(
        tid,
        limit: yearScanMemberLimit,
      );
      for (final d in scan.docs) {
        if (!seen.add(d.id)) continue;
        if (_birthMonthFromData(d.data()) == m) out.add(d);
        if (out.length >= cap) break;
      }
    } catch (_) {}

    return out;
  }

  /// Aniversariantes de hoje (`birthMonth` + `birthDay`).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchTodayBirthdays({
    required String tenantId,
    int? limit,
  }) async {
    final now = DateTime.now();
    final cap = limit ?? YahwehPerformanceV4.birthdayQueryLimit;
    final tid = await _resolveTenantId(tenantId);
    if (tid.isEmpty) return const [];

    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};

    await ChurchTenantResilientReads.preparePanelRead();

    for (final id in await _clusterIds(tid)) {
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => _membros(id)
              .where(YahwehPerformanceV4.memberBirthMonthField,
                  isEqualTo: now.month)
              .where(YahwehPerformanceV4.memberBirthDayField, isEqualTo: now.day)
              .limit(cap)
              .get(),
        );
        for (final d in snap.docs) {
          if (seen.add(d.id)) out.add(d);
        }
        if (out.length >= cap) break;
      } catch (_) {}
    }

    if (out.isNotEmpty) return out.take(cap).toList();

    final monthDocs = await fetchCurrentMonthBirthdays(
      tenantId: tid,
      limit: cap * 2,
      month: now.month,
    );
    return monthDocs.where((d) => _birthDayFromData(d.data()) == now.day).take(cap).toList();
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

  /// Próximos 7 dias (inclui hoje).
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
        final day = _birthDayFromData(d.data());
        if (day == null) continue;
        if (weekSet.contains((mo, day))) out.add(d);
      }
    }
    out.sort((a, b) {
      final da = _birthDayFromData(a.data()) ?? 0;
      final db = _birthDayFromData(b.data()) ?? 0;
      return da.compareTo(db);
    });
    return out.take(cap).toList();
  }

  /// Todos os aniversariantes de um mês.
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
      final da = _birthDayFromData(a.data()) ?? 0;
      final db = _birthDayFromData(b.data()) ?? 0;
      return da.compareTo(db);
    });
    return docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchYearViaMembrosScan(String tid) async {
    try {
      await ChurchTenantResilientReads.preparePanelRead();
      final snap = await ChurchTenantResilientReads.membrosRecent(
        tid,
        limit: yearScanMemberLimit,
      );
      final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        if (birthDateFromMemberData(d.data()) != null) out.add(d);
      }
      out.sort((a, b) {
        final da = birthDateFromMemberData(a.data());
        final db = birthDateFromMemberData(b.data());
        if (da == null || db == null) return 0;
        final c = da.month.compareTo(db.month);
        return c != 0 ? c : da.day.compareTo(db.day);
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Carrega os 12 meses (página «Ano todo») — nunca lança excepção.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchYearAllMonths({
    required String tenantId,
    int? perMonthLimit,
  }) async {
    final tid = await _resolveTenantId(tenantId);
    if (tid.isEmpty) return const [];

    final cap = perMonthLimit ?? yearViewPerMonthLimit;
    final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seen = <String>{};

    try {
      await ChurchTenantResilientReads.preparePanelRead();
      for (var m = 1; m <= 12; m++) {
        final docs = await fetchMonthBirthdays(
          tenantId: tid,
          month: m,
          limit: cap,
        );
        for (final d in docs) {
          if (seen.add(d.id)) all.add(d);
        }
      }
      if (all.isNotEmpty) return all;
    } catch (_) {}

    return _fetchYearViaMembrosScan(tid);
  }
}
