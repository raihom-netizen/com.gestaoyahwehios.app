import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

import 'package:gestao_yahweh/constants/app_business_rules.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/finance_transaction_status_resolver.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';
import 'finance_month_cache.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Despesas fixas: todo mês o sistema cria um lançamento automaticamente no período definido pelo usuário.
/// [uid] em todos os métodos é o `churchId` — por igreja, não por login.
class FixedExpenseService {
  // _db saiu: os lotes passaram a ser YahwehBatch (REST no Web) e já não há
  // nenhuma escrita direta pelo SDK neste serviço.

  /// Limite do Firestore por WriteBatch (não alterar sem conferir documentação).
  static const int batchLimit = 500;

  /// Tetos para [monthsAhead]: geração de parcelas até este número de meses à frente (evita explosão de lançamentos).
  static const int maxMonthsAhead = 24;

  /// Guarda contra chamadas concorrentes de [ensureMonthlyEntries] (race condition → duplicação).
  static Future<int>? _ensureRunning;

  CollectionReference<Map<String, dynamic>> _fixedRef(String uid) =>
      ChurchUiCollections.churchDoc(uid.trim()).collection('fixed_expenses');

  CollectionReference<Map<String, dynamic>> _txRef(String uid) =>
      ChurchUiCollections.financeiro(uid.trim());

  /// Lista todas as despesas fixas ativas do usuário.
  Future<List<Map<String, dynamic>>> list(String uid) async {
    // Web: leitura por REST (evita a INTERNAL ASSERTION do SDK 12.17.0).
    if (kIsWeb) {
      final docs = await firestoreRestCollect(
        collectionPath: _fixedRef(uid).path,
        orderByField: 'createdAt',
        descending: true,
      );
      return docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
    }
    final snap =
        await _fixedRef(uid).orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      return m;
    }).toList();
  }

  /// Modo da despesa fixa: por período (datas) ou por parcelas (financiamento/empréstimo).
  static const String modePeriod = 'period';
  static const String modeInstallments = 'installments';

  /// Cria uma despesa fixa.
  /// [dayOfMonth] 1–31 (dia do mês em que o lançamento será criado).
  /// [endDate] null = sem data fim (por período) ou calculado (por parcelas).
  /// [mode] 'period' = por período (start/end); 'installments' = por parcelas (totalParcelas, parcelaInicial).
  /// [parcelaInicial] quando por parcelas: a partir de qual parcela está (ex.: 4 em 10 = começou a controlar na 4ª).
  Future<String> add({
    required String uid,
    required String description,
    required String category,
    required double amount,
    required int dayOfMonth,
    required DateTime startDate,
    DateTime? endDate,
    String mode = modePeriod,
    int? totalParcelas,
    int? parcelaInicial,
    bool addToCalendar = false,
    String? calendarColorHex,
    String? financeAccountId,
  }) async {
    final day = dayOfMonth.clamp(1, 31);
    DateTime end;
    int? effTotalParcelas;
    if (mode == modeInstallments &&
        totalParcelas != null &&
        totalParcelas >= 1) {
      effTotalParcelas =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      final ini = (parcelaInicial ?? 1).clamp(1, effTotalParcelas);
      final meses = effTotalParcelas - ini + 1;
      end = DateTime(start.year, start.month + meses - 1, start.day);
    } else {
      effTotalParcelas = null;
      end = endDate ??
          DateTime(startDate.year + 10, startDate.month, startDate.day);
    }
    final accId = (financeAccountId ?? '').trim();
    final data = <String, dynamic>{
      'description': description,
      'category': category,
      'amount': amount,
      'dayOfMonth': day,
      'startDate': Timestamp.fromDate(
          DateTime(startDate.year, startDate.month, startDate.day)),
      'endDate': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
      'active': true,
      'addToCalendar': addToCalendar,
      if (accId.isNotEmpty) 'financeAccountId': accId,
      if (addToCalendar &&
          calendarColorHex != null &&
          calendarColorHex.trim().isNotEmpty)
        'calendarColorHex': calendarColorHex.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (mode == modeInstallments && effTotalParcelas != null) {
      data['mode'] = modeInstallments;
      data['totalParcelas'] = effTotalParcelas;
      data['parcelaInicial'] = (parcelaInicial ?? 1).clamp(1, effTotalParcelas);
    } else {
      data['mode'] = modePeriod;
    }
    final ref = await _fixedRef(uid).add(data);
    return ref.id;
  }

  /// Atualiza uma despesa fixa.
  /// Se [dayOfMonth] for alterado, as parcelas futuras (pendentes) são atualizadas para o novo dia.
  /// Retorna o número de parcelas futuras que foram ajustadas (0 se não alterou o dia).
  Future<int> update({
    required String uid,
    required String id,
    String? description,
    String? category,
    double? amount,
    int? dayOfMonth,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
    String? mode,
    int? totalParcelas,
    int? parcelaInicial,
    bool? addToCalendar,
    String? calendarColorHex,
    String? financeAccountId,
    bool clearFinanceAccount = false,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (description != null) data['description'] = description;
    if (category != null) data['category'] = category;
    if (amount != null) data['amount'] = amount;
    if (dayOfMonth != null) data['dayOfMonth'] = dayOfMonth.clamp(1, 31);
    if (startDate != null) {
      data['startDate'] = Timestamp.fromDate(
          DateTime(startDate.year, startDate.month, startDate.day));
    }
    if (endDate != null) {
      data['endDate'] = Timestamp.fromDate(
          DateTime(endDate.year, endDate.month, endDate.day));
    }
    if (active != null) data['active'] = active;
    if (mode != null) {
      data['mode'] = mode;
      if (mode == modePeriod) {
        data['totalParcelas'] = FieldValue.delete();
        data['parcelaInicial'] = FieldValue.delete();
      }
    }
    if (totalParcelas != null) {
      data['totalParcelas'] =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
    }
    if (parcelaInicial != null && totalParcelas != null) {
      final cap =
          totalParcelas.clamp(1, AppBusinessRules.maxFixedFlowInstallments);
      data['parcelaInicial'] = parcelaInicial.clamp(1, cap);
    }
    if (clearFinanceAccount) {
      data['financeAccountId'] = FieldValue.delete();
    } else if (financeAccountId != null) {
      final accId = financeAccountId.trim();
      if (accId.isEmpty) {
        data['financeAccountId'] = FieldValue.delete();
      } else {
        data['financeAccountId'] = accId;
      }
    }
    if (addToCalendar != null) {
      data['addToCalendar'] = addToCalendar;
      if (addToCalendar &&
          calendarColorHex != null &&
          calendarColorHex.trim().isNotEmpty) {
        data['calendarColorHex'] = calendarColorHex.trim();
      } else {
        data['calendarColorHex'] = FieldValue.delete();
      }
    } else if (calendarColorHex != null) {
      if (calendarColorHex.trim().isNotEmpty) {
        data['calendarColorHex'] = calendarColorHex.trim();
      } else {
        data['calendarColorHex'] = FieldValue.delete();
      }
    }
    await YahwehDocWrite.update(_fixedRef(uid).doc(id), data);
    if (addToCalendar != null || calendarColorHex != null) {
      await _updateFuturePendingCalendarFlags(
        uid,
        id,
        // `?? true` ligava o calendario nos pendentes futuros quando so a COR
        // tinha sido alterada. Desligado por defeito, como no formulario.
        addToCalendar ?? false,
        calendarColorHex,
      );
    }
    if (clearFinanceAccount || financeAccountId != null) {
      await _updatePendingAccount(
        uid,
        id,
        clearFinanceAccount ? null : financeAccountId,
      );
    }
    if (dayOfMonth != null) {
      return updateFuturePendingEntries(uid, id, dayOfMonth.clamp(1, 31));
    }
    return 0;
  }

  /// Propaga banco/caixa para **todos** os lançamentos pendentes desta despesa fixa.
  /// Não altera pagos/recebidos (`status != pending`).
  Future<int> _updatePendingAccount(
    String uid,
    String fixedExpenseId,
    String? financeAccountId,
  ) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedExpenseId', isEqualTo: fixedExpenseId)
          .where('status', isEqualTo: 'pending')
          .get();
      if (snap.docs.isEmpty) return 0;
      final accId = (financeAccountId ?? '').trim();
      var updated = 0;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final doc in snap.docs.skip(i).take(batchLimit)) {
          batch.update(doc.reference, {
            if (accId.isNotEmpty)
              'financeAccountId': accId
            else
              'financeAccountId': YahwehFv.deleteField,
            'updatedAt': YahwehFv.serverTimestamp,
          });
          updated++;
        }
        await batch.commit();
      }
      return updated;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _updateFuturePendingCalendarFlags(
    String uid,
    String fixedExpenseId,
    bool addToCalendar,
    String? calendarColorHex,
  ) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final snap = await _txRef(uid)
          .where('fixedExpenseId', isEqualTo: fixedExpenseId)
          .where('status', isEqualTo: 'pending')
          .get();
      final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs is! Timestamp) continue;
        final date = dateTs.toDate();
        if (date.isBefore(today)) continue;
        toUpdate.add(doc);
      }
      if (toUpdate.isEmpty) return;
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final doc in toUpdate.skip(i).take(batchLimit)) {
          batch.update(doc.reference, {
            'addToCalendar': addToCalendar,
            if (addToCalendar)
              'hideFromCalendar': YahwehFv.deleteField
            else
              'hideFromCalendar': true,
            if (addToCalendar &&
                calendarColorHex != null &&
                calendarColorHex.trim().isNotEmpty)
              'calendarColorHex': calendarColorHex.trim()
            else
              'calendarColorHex': YahwehFv.deleteField,
            'updatedAt': YahwehFv.serverTimestamp,
          });
        }
        await batch.commit();
      }
    } catch (_) {}
  }

  /// Atualiza a data (dia do mês) das parcelas futuras pendentes desta despesa fixa.
  /// Ex.: usuário editou de dia 16 para 08 — as contas pendentes dos próximos meses passam a vencer no dia 08.
  /// Usa WriteBatch (até [batchLimit] por commit) para menos round-trips.
  Future<int> updateFuturePendingEntries(
      String uid, String fixedExpenseId, int newDayOfMonth) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snap = await _txRef(uid)
        .where('fixedExpenseId', isEqualTo: fixedExpenseId)
        .where('status', isEqualTo: 'pending')
        .get();
    final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final dateTs = d['date'];
      if (dateTs is! Timestamp) continue;
      final date = (dateTs).toDate();
      if (date.isBefore(today)) continue;
      int lastDay = 28;
      try {
        lastDay = DateTime(date.year, date.month + 1, 0).day;
      } catch (_) {}
      final day = newDayOfMonth.clamp(1, lastDay);
      final newDate = DateTime(date.year, date.month, day);
      if (newDate == date) continue;
      toUpdate.add(doc);
    }
    int updated = 0;
    for (var i = 0; i < toUpdate.length; i += batchLimit) {
      final batch = YahwehBatch();
      for (final doc in toUpdate.skip(i).take(batchLimit)) {
        final d = doc.data();
        final dateTs = d['date'];
        if (dateTs is! Timestamp) continue;
        final date = (dateTs).toDate();
        int lastDay = 28;
        try {
          lastDay = DateTime(date.year, date.month + 1, 0).day;
        } catch (_) {}
        final day = newDayOfMonth.clamp(1, lastDay);
        final newDate = DateTime(date.year, date.month, day);
        batch.update(doc.reference, {
          'date': Timestamp.fromDate(newDate),
          'updatedAt': YahwehFv.serverTimestamp,
        });
        updated++;
      }
      await batch.commit();
    }
    return updated;
  }

  /// Remove uma despesa fixa e os lançamentos pendentes ligados a ela
  /// (Agenda/calendário + Financeiro). Pagos permanecem.
  Future<int> delete(String uid, String id) async {
    final removed = await _deletePendingEntriesForFixed(uid, id);
    await YahwehDocWrite.delete(_fixedRef(uid).doc(id));
    // Agenda + Escalas + listas financeiras atualizam na hora.
    FinanceMonthCache.clearUid(uid);
    FinanceTransactionsHub.notifyMutated(uid: uid);
    return removed;
  }

  /// Remove todos os lançamentos **pending** desta despesa fixa (qualquer mês).
  /// Assim somem da Agenda e do calendário de Escalas de imediato.
  /// Query só por `fixedExpenseId` (sem filtro composto) — evita falha por índice.
  Future<int> _deletePendingEntriesForFixed(
      String uid, String fixedExpenseId) async {
    final snap = await _txRef(uid)
        .where('fixedExpenseId', isEqualTo: fixedExpenseId)
        .get();
    final toDelete = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final status = (doc.data()['status'] ?? '').toString().toLowerCase();
      if (status != 'pending') continue;
      toDelete.add(doc);
    }
    if (toDelete.isEmpty) return 0;
    for (var i = 0; i < toDelete.length; i += batchLimit) {
      final batch = YahwehBatch();
      for (final doc in toDelete.skip(i).take(batchLimit)) {
        batch.deleteDoc(doc.reference);
      }
      await batch.commit();
    }
    return toDelete.length;
  }

  /// Migra lançamentos pendentes com data anterior a hoje para "paid".
  /// Limpa dados legados e garante que parcelas passadas de despesas fixas
  /// não fiquem eternamente como pendentes.
  Future<void> _migratePastPendingEntries(
    String uid,
    List<QuerySnapshot<Map<String, dynamic>>> snaps,
  ) async {
    try {
      final startOfToday = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final d = doc.data();
          if ((d['status'] ?? '').toString() != 'pending') continue;
          final dateTs = d['date'];
          if (dateTs is! Timestamp) continue;
          final date = dateTs.toDate();
          if (!date.isBefore(startOfToday)) continue;
          toUpdate.add(doc);
        }
      }
      if (toUpdate.isEmpty) return;
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final doc in toUpdate.skip(i).take(batchLimit)) {
          final dateTs = doc.data()['date'];
          final date = dateTs is Timestamp ? dateTs.toDate() : DateTime.now();
          final paidAt =
              FinanceTransactionStatusResolver.paidAtForAutoPaid(date);
          batch.update(doc.reference, {
            'status': 'paid',
            'paidAt': paidAt,
            'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
              date: date,
              paidAt: paidAt,
            ),
            'updatedAt': YahwehFv.serverTimestamp,
          });
        }
        await batch.commit();
      }
    } catch (_) {
      // Falha silenciosa: não impede a geração das parcelas futuras.
    }
  }

  /// Remove todas as parcelas (lançamentos) criadas por esta despesa fixa no Financeiro.
  /// Retorna a quantidade de lançamentos excluídos. Usa WriteBatch ([batchLimit] por vez) — sem await por doc.
  Future<int> deleteAllParcelas(String uid, String fixedExpenseId) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedExpenseId', isEqualTo: fixedExpenseId)
          .get();
      if (snap.docs.isEmpty) return 0;
      int deleted = 0;
      for (var i = 0; i < snap.docs.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final doc in snap.docs.skip(i).take(batchLimit)) {
          batch.deleteDoc(doc.reference);
          deleted++;
        }
        await batch.commit();
      }
      return deleted;
    } catch (e) {
      throw Exception('Erro ao remover parcelas da despesa fixa: $e');
    }
  }

  /// Garante que, para cada despesa fixa ativa, exista um lançamento em cada mês do período (startDate..endDate).
  /// Respeita a data final (endDate) cadastrada na despesa — gera parcelas até o último mês do período.
  /// [monthsAhead] não limita mais a geração; é usado apenas em preferências de exibição (painel pendentes).
  Future<int> ensureMonthlyEntries(String uid, {int monthsAhead = 4}) async {
    // Evita chamadas concorrentes (race condition → duplicação de parcelas).
    if (_ensureRunning != null) return _ensureRunning!;
    _ensureRunning = _ensureMonthlyEntriesImpl(uid, monthsAhead: monthsAhead);
    try {
      return await _ensureRunning!;
    } finally {
      _ensureRunning = null;
    }
  }

  Future<int> _ensureMonthlyEntriesImpl(String uid,
      {int monthsAhead = 4}) async {
    final items = await list(uid);
    final activeItems = <Map<String, dynamic>>[];
    for (final fe in items) {
      if (fe['active'] != true) continue;
      final startTs = fe['startDate'];
      final endTs = fe['endDate'];
      if (startTs is! Timestamp || endTs is! Timestamp) continue;
      final feId = (fe['id'] ?? '').toString();
      if (feId.isEmpty) continue;
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      activeItems.add(fe);
    }
    if (activeItems.isEmpty) return 0;

    // Queries em paralelo: uma por despesa fixa (monthKeys já existentes)
    final existingSnaps = await Future.wait([
      for (final fe in activeItems)
        _txRef(uid)
            .where('fixedExpenseId', isEqualTo: fe['id'].toString())
            .get(),
    ]);

    // Migra lançamentos pendentes com data no passado para "paid". Isso limpa
    // dados antigos que não deveriam estar como pendentes e evita que voltem
    // ao painel de pendentes após serem excluídos.
    await _migratePastPendingEntries(uid, existingSnaps);

    final List<Map<String, dynamic>> toCreate = [];
    // Docs duplicados (mesma despesa fixa + mesmo mês) → limpar do Firestore.
    final docsToDelete = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < activeItems.length; i++) {
      final fe = activeItems[i];
      final existingSnap = existingSnaps[i];
      final start = (fe['startDate'] as Timestamp).toDate();
      final end = (fe['endDate'] as Timestamp).toDate();
      final dayOfMonth = (fe['dayOfMonth'] as num?)?.toInt() ?? 1;
      final category = (fe['category'] ?? 'Despesa').toString();
      final description = (fe['description'] ?? 'Despesa fixa').toString();
      final feId = fe['id'].toString();
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;
      // Toggle «Mostrar no calendário»: só aparece na Agenda se explicitamente true
      // (ou legado sem campo — trata como ligado).
      final addToCalendar = fe['addToCalendar'] != false;
      final calHex = (fe['calendarColorHex'] ?? '').toString().trim();
      final financeAccountId =
          (fe['financeAccountId'] ?? '').toString().trim();

      // Inclui monthKey explícito OU deriva do campo date (pagas/legado sem fixedExpenseMonthKey),
      // senão o sistema recriava parcela "Pendente" do mesmo mês ao rodar ensure de novo.
      // Meses explicitamente excluídos pelo usuário também são tratados como "existentes"
      // para não recriar parcelas removidas manualmente.
      final existingMonthKeys = <String>{
        ...List<String>.from(fe['excludedMonths'] ?? const []),
      };
      for (final d in existingSnap.docs) {
        final data = d.data();
        String mk;
        final explicitMk = data['fixedExpenseMonthKey'] as String?;
        if (explicitMk != null && explicitMk.isNotEmpty) {
          mk = explicitMk;
        } else {
          final dateTs = data['date'];
          if (dateTs is Timestamp) {
            final dt = dateTs.toDate();
            mk = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          } else {
            continue;
          }
        }
        if (!existingMonthKeys.add(mk)) {
          // Duplicado: mesma despesa fixa + mesmo mês → marcar para exclusão.
          docsToDelete.add(d);
        }
      }

      final isByInstallments = (fe['mode'] ?? modePeriod) == modeInstallments;
      final totalParcelas = (fe['totalParcelas'] as num?)?.toInt();
      final parcelaInicial = (fe['parcelaInicial'] as num?)?.toInt() ?? 1;
      final installmentCount =
          isByInstallments && totalParcelas != null ? totalParcelas : 1;
      final startMonth = DateTime(start.year, start.month, 1);

      DateTime month = DateTime(start.year, start.month, 1);
      // Respeitar a data final da despesa fixa: gerar parcelas até o mês de end (inclusive).
      final limitEnd = DateTime(end.year, end.month, 1);

      while (!month.isAfter(limitEnd)) {
        if (month.isBefore(startMonth)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        final monthKey =
            '${month.year}-${month.month.toString().padLeft(2, '0')}';
        if (existingMonthKeys.contains(monthKey)) {
          month = DateTime(month.year, month.month + 1, 1);
          continue;
        }
        // Índice da parcela: primeiro mês = parcelaInicial, segundo = parcelaInicial+1, etc.
        int parcelIndex = 1;
        if (isByInstallments && totalParcelas != null) {
          final monthsFromStart =
              (month.year - start.year) * 12 + (month.month - start.month);
          parcelIndex =
              (parcelaInicial + monthsFromStart).clamp(1, totalParcelas);
          if (parcelIndex > totalParcelas) {
            month = DateTime(month.year, month.month + 1, 1);
            continue;
          }
        }
        existingMonthKeys.add(monthKey);
        int lastDay = 31;
        try {
          lastDay = DateTime(month.year, month.month + 1, 0).day;
        } catch (_) {}
        final dayClamped = dayOfMonth.clamp(1, lastDay);
        final date = DateTime(month.year, month.month, dayClamped);
        final descOut =
            isByInstallments && totalParcelas != null && totalParcelas > 1
                ? '$description · $parcelIndex/$totalParcelas'
                : description;
        final dateTs = Timestamp.fromDate(date);
        final status = FinanceTransactionStatusResolver.resolveByDate(date);
        final paidAt = status == 'paid'
            ? FinanceTransactionStatusResolver.paidAtForAutoPaid(date)
            : null;
        toCreate.add({
          'type': 'expense',
          'amount': amount,
          'category': category,
          'description': descOut,
          'status': status,
          'date': dateTs,
          'paidAt': ?paidAt,
          'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
            date: date,
            paidAt: paidAt,
          ),
          'recurrence': 'fixed',
          'installmentCount': installmentCount,
          'installmentIndex': parcelIndex,
          'fixedExpenseId': feId,
          'fixedExpenseMonthKey': monthKey,
          'addToCalendar': addToCalendar,
          if (!addToCalendar) 'hideFromCalendar': true,
          'pagamentoConfirmado': status != 'pending',
          if (financeAccountId.isNotEmpty) ...{
            'financeAccountId': financeAccountId,
            'contaOrigemId': financeAccountId,
          },
          if (addToCalendar && calHex.isNotEmpty) 'calendarColorHex': calHex,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        month = DateTime(month.year, month.month + 1, 1);
      }
    }

    // Limpa duplicados existentes (mesma despesa fixa + mesmo mês).
    if (docsToDelete.isNotEmpty) {
      try {
        for (var j = 0; j < docsToDelete.length; j += batchLimit) {
          final batch = YahwehBatch();
          for (final doc in docsToDelete.skip(j).take(batchLimit)) {
            batch.deleteDoc(doc.reference);
          }
          await batch.commit();
        }
      } catch (_) {
        // Falha na limpeza não impede geração de novas parcelas.
      }
    }

    int created = 0;
    try {
      for (var j = 0; j < toCreate.length; j += batchLimit) {
        final batch = YahwehBatch();
        for (final data in toCreate.skip(j).take(batchLimit)) {
          batch.set(_txRef(uid).doc(), data);
          created++;
        }
        await batch.commit();
      }
      return created;
    } catch (e) {
      throw Exception('Erro ao gerar parcelas de despesas fixas: $e');
    }
  }
}
