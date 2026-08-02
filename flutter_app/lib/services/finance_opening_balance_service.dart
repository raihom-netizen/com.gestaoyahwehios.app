import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/utils/finance_account_balance_utils.dart';
import 'package:gestao_yahweh/utils/finance_transactions_realtime.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/firestore_query_batched_collect.dart';
import 'package:gestao_yahweh/utils/firestore_user_doc_id.dart';

/// Saldo de abertura: total via [finance_month_buckets]; por conta via
/// [finance_account_month_buckets] (servidor) + sÃ³ o mÃªs parcial em transactions.
class FinanceOpeningBalanceService {
  FinanceOpeningBalanceService._();

  static const int _openingBucketsVersionExpected = 3;

  static final Map<String,
      ({double total, Map<String, double> byAccount, DateTime at})> _cache = {};

  static String _cacheKey(String uid, DateTime periodStart, bool withAccounts) {
    final id = firestoreUserDocIdForAppShell(uid);
    final d = DateTime(periodStart.year, periodStart.month, periodStart.day);
    return '$id|${d.toIso8601String().substring(0, 10)}|acc:$withAccounts';
  }

  static void invalidateForUser(String uid) {
    final id = firestoreUserDocIdForAppShell(uid);
    _cache.removeWhere((k, _) => k.startsWith('$id|'));
  }

  /// Leitura sÃ­ncrona do cache em memÃ³ria â€” evita FutureBuilder piscar no painel/Financeiro.
  static ({double total, Map<String, double> byAccount})? peekCached({
    required String uid,
    required DateTime periodStart,
    bool loadAccounts = false,
    Duration maxAge = const Duration(minutes: 30),
  }) {
    if (uid.isEmpty) return null;
    final start =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    final key = _cacheKey(uid, start, loadAccounts);
    final hit = _cache[key];
    if (hit == null || DateTime.now().difference(hit.at) > maxAge) return null;
    return (
      total: hit.total,
      byAccount: Map<String, double>.from(hit.byAccount),
    );
  }

  static void invalidateIfBefore(String uid, DateTime effectiveDate) {
    final id = firestoreUserDocIdForAppShell(uid);
    for (final k in _cache.keys.toList()) {
      if (!k.startsWith('$id|')) continue;
      final datePart = k.split('|');
      if (datePart.length < 2) continue;
      final start = DateTime.tryParse(datePart[1]);
      if (start != null && effectiveDate.isBefore(start)) {
        _cache.remove(k);
      }
    }
  }

  /// Restaura accountId a partir da chave sanitizada gravada pelo servidor.
  static String _restoreAccountFieldKey(String fieldKey) {
    return fieldKey.replaceAll('\uFF0E', '.');
  }

  static void _mergeNetByAccountMap(
      Map<String, double> target, Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return;
    raw.forEach((fieldKey, value) {
      if (value is! num) return;
      final aid = _restoreAccountFieldKey(fieldKey);
      if (aid.isEmpty) return;
      target[aid] = (target[aid] ?? 0) + value.toDouble();
    });
  }

  /// SÃ³ o total (buckets) â€” exibe saldos/KPI na hora.
  static Future<double> loadTotalFast({
    required String uid,
    required DateTime periodStart,
    Duration cacheTtl = const Duration(minutes: 5),
  }) async {
    final r = await load(
      uid: uid,
      periodStart: periodStart,
      loadAccounts: false,
      cacheTtl: cacheTtl,
    );
    return r.total;
  }

  /// Total (buckets + mÃªs parcial). [loadAccounts]: mapa por conta via buckets servidor.
  static Future<({double total, Map<String, double> byAccount})> load({
    required String uid,
    required DateTime periodStart,
    bool loadAccounts = true,
    Duration cacheTtl = const Duration(minutes: 5),
    Set<String> creditCardIds = const {},
  }) async {
    if (uid.isEmpty) {
      return (total: 0.0, byAccount: const <String, double>{});
    }
    final start =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    final key = _cacheKey(uid, start, loadAccounts);
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < cacheTtl) {
      return (
        total: hit.total,
        byAccount: Map<String, double>.from(hit.byAccount)
      );
    }

    final fsId = firestoreUserDocIdForAppShell(uid);
    final partialKey = FinanceLineOpening.monthKeySaoPaulo(start);
    final monthStart = FinanceLineOpening.startOfMonthWallLocal(start);

    var prefix = 0.0;
    try {
      final buckets = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsId)
          .collection('finance_month_buckets')
          .orderBy(FieldPath.documentId)
          .where(FieldPath.documentId, isLessThan: partialKey)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
      for (final doc in buckets.docs) {
        prefix += (doc.data()['netPaid'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}

    final seen = <String>{};
    var partial = 0.0;
    final byAcc = <String, double>{};

    void absorb(Map<String, dynamic> d, String docId) {
      if (seen.contains(docId)) return;
      seen.add(docId);
      final c = FinanceLineOpening.openingContribution(d);
      if (c == 0) return;
      partial += c;
      if (loadAccounts) {
        final slice =
            FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps(
          items: [d],
          periodStart: start,
          creditCardIds: creditCardIds,
        );
        slice.forEach((k, v) => byAcc[k] = (byAcc[k] ?? 0) + v);
      }
    }

    if (loadAccounts) {
      try {
        final accBuckets = await FirebaseFirestore.instance
            .collection('users')
            .doc(fsId)
            .collection('finance_account_month_buckets')
            .orderBy(FieldPath.documentId)
            .where(FieldPath.documentId, isLessThan: partialKey)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
        for (final doc in accBuckets.docs) {
          final data = doc.data();
          _mergeNetByAccountMap(
              byAcc, data['netByAccount'] as Map<String, dynamic>?);
        }
      } catch (_) {}
    }

    try {
      final partialDocs = await financePeriodMergedDocumentsCollect(
        uid: fsId,
        from: monthStart,
        to: start.subtract(const Duration(seconds: 1)),
        statusFilter: 'paid',
        maxDocuments: 12000,
      ).timeout(const Duration(seconds: 20));
      for (final doc in partialDocs) {
        absorb(doc.data(), doc.id);
      }
    } catch (_) {}

    if (loadAccounts) {
      try {
        final monthDocs = await firestoreQueryCollectDocumentsBatched(
          FirebaseFirestore.instance
              .collection('users')
              .doc(fsId)
              .collection('transactions')
              .where('date',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
              .where('date', isLessThan: Timestamp.fromDate(start))
              .orderBy('date', descending: false),
          pageSize: 400,
          maxDocuments: 2500,
        ).timeout(const Duration(seconds: 12));
        for (final doc in monthDocs) {
          final d = doc.data();
          if (d['effectiveDate'] != null) continue;
          final ts = d['date'];
          if (ts is! Timestamp) continue;
          final date = ts.toDate();
          if (!date.isBefore(start)) continue;
          absorb(d, doc.id);
        }
      } catch (_) {}
    }

    var total = prefix + partial;

    if (loadAccounts) {
      final sumAssigned = byAcc.values.fold<double>(0, (a, b) => a + b);
      if ((total - sumAssigned).abs() > 0.05) {
        try {
          final beforeDocs = await financePeriodMergedDocumentsCollect(
            uid: fsId,
            from: DateTime(2020, 1, 1),
            to: start.subtract(const Duration(seconds: 1)),
            statusFilter: 'paid',
            maxDocuments: 20000,
          ).timeout(const Duration(seconds: 25));
          final recomputed =
              FinanceAccountBalanceUtils.openingPaidByAccountFromDocMaps(
            items: beforeDocs.map((d) => d.data()),
            periodStart: start,
            creditCardIds: creditCardIds,
          );
          byAcc
            ..clear()
            ..addAll(recomputed);
        } catch (_) {}
      }

      // CartÃµes de crÃ©dito nÃ£o movimentam saldo bancÃ¡rio: removemos do mapa
      // por conta para que a visÃ£o consolidada use a mesma base da conta individual.
      byAcc.removeWhere((accountId, _) => creditCardIds.contains(accountId));

      // Fonte Ãºnica de verdade: o saldo consolidado Ã© a soma das contas bancÃ¡rias.
      // Isso evita divergÃªncia entre o total dos buckets (que pode incluir cartÃµes
      // e lanÃ§amentos sem conta) e o somatÃ³rio por conta exibido em cada banco.
      total = byAcc.values.fold<double>(0, (acc, value) => acc + value);
    }

    final result = (total: total, byAccount: byAcc);
    _cache[key] = (
      total: total,
      byAccount: Map.unmodifiable(Map<String, double>.from(byAcc)),
      at: DateTime.now(),
    );

    // Sincroniza o cache "sÃ³ total" com o mesmo valor bancÃ¡rio, evitando que
    // uma carga rÃ¡pida anterior (que incluÃ­a cartÃµes) pisque na tela antes da
    // carga completa com as contas.
    if (loadAccounts) {
      final fastKey = _cacheKey(uid, start, false);
      _cache[fastKey] = (
        total: total,
        byAccount: const <String, double>{},
        at: DateTime.now(),
      );
    }

    return result;
  }

  /// VersÃ£o esperada dos agregados (contas por mÃªs no servidor).
  static int get openingBucketsVersionExpected =>
      _openingBucketsVersionExpected;

  /// Uma vez por sessÃ£o: reconstrÃ³i buckets mensais + por conta no servidor (migraÃ§Ã£o v2).
  static bool _rebuildAsked = false;

  static Future<void> ensureServerBucketsRebuildIfNeeded(String uid) async {
    if (_rebuildAsked || uid.isEmpty) return;
    _rebuildAsked = true;
    try {
      final fsId = firestoreUserDocIdForAppShell(uid);
      final meta = await FirebaseFirestore.instance
          .doc('users/$fsId/finance_stats/meta')
          .get();
      if (meta.exists &&
          (meta.data()?['openingBucketsVersion'] as num? ?? 0) >=
              _openingBucketsVersionExpected) {
        return;
      }
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ctFinanceRebuildOpeningBuckets')
          .call()
          .timeout(const Duration(seconds: 180));
      invalidateForUser(uid);
    } catch (_) {}
  }
}
