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

/// Receitas fixas (aluguéis, comissões, juros, etc.): o sistema gera lançamentos **pendentes** por mês no período.
/// Mesma lógica de [FixedExpenseService], com `type: income` e coleção `fixed_incomes`.
/// [uid] em todos os métodos é o `churchId` — por igreja, não por login.
class FixedIncomeService {
  // _db saiu: os lotes agora sao YahwehBatch (REST no Web).

  static const int batchLimit = 500;
  static const int maxMonthsAhead = 24;

  CollectionReference<Map<String, dynamic>> _fixedRef(String uid) =>
      ChurchUiCollections.churchDoc(uid.trim()).collection('fixed_incomes');

  CollectionReference<Map<String, dynamic>> _txRef(String uid) =>
      ChurchUiCollections.financeiro(uid.trim());

  Future<List<Map<String, dynamic>>> list(String uid) async {
    // Web: leitura por REST (evita a INTERNAL ASSERTION do SDK 12.17.0 que
    // fazia a tela de Receitas Fixas "não abrir").
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

  static const String modePeriod = 'period';
  static const String modeInstallments = 'installments';

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

    /// Campos de vínculo (membro/fornecedor) prontos para o Firestore — vindos
    /// de `FinanceVinculoSelecao.paraFirestore()`, o mesmo do lançamento avulso.
    Map<String, dynamic>? vinculo,
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
      'createdAt': YahwehFv.serverTimestamp,
      'updatedAt': YahwehFv.serverTimestamp,
      if (vinculo != null) ...vinculo,
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
    Map<String, dynamic>? vinculo,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': YahwehFv.serverTimestamp,
      if (vinculo != null) ...vinculo,
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
        data['totalParcelas'] = YahwehFv.deleteField;
        data['parcelaInicial'] = YahwehFv.deleteField;
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
      data['financeAccountId'] = YahwehFv.deleteField;
    } else if (financeAccountId != null) {
      final accId = financeAccountId.trim();
      if (accId.isEmpty) {
        data['financeAccountId'] = YahwehFv.deleteField;
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
        data['calendarColorHex'] = YahwehFv.deleteField;
      }
    } else if (calendarColorHex != null) {
      if (calendarColorHex.trim().isNotEmpty) {
        data['calendarColorHex'] = calendarColorHex.trim();
      } else {
        data['calendarColorHex'] = YahwehFv.deleteField;
      }
    }
    await YahwehDocWrite.update(_fixedRef(uid).doc(id), data);
    if (vinculo != null) {
      await _updateFuturePendingVinculo(uid, id, vinculo);
    }
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

  /// Propaga banco/caixa para **todos** os lançamentos pendentes desta receita fixa.
  /// Não altera pagos/recebidos (`status != pending`).
  Future<int> _updatePendingAccount(
    String uid,
    String fixedIncomeId,
    String? financeAccountId,
  ) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
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

  /// Propaga o vínculo (membro/fornecedor) aos lançamentos **pendentes
  /// futuros** desta fixa.
  ///
  /// As parcelas já pagas ficam como estão: são histórico, e reescrevê-las
  /// mudaria totais que a tesouraria já fechou.
  Future<void> _updateFuturePendingVinculo(
    String uid,
    String fixedId,
    Map<String, dynamic> vinculo,
  ) async {
    if (vinculo.isEmpty) return;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedId)
          .where('status', isEqualTo: 'pending')
          .get();
      final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in snap.docs) {
        final dateTs = doc.data()['date'];
        if (dateTs is! Timestamp) continue;
        if (dateTs.toDate().isBefore(today)) continue;
        toUpdate.add(doc);
      }
      if (toUpdate.isEmpty) return;
      // `null` no mapa apaga o campo — e assim que o vínculo antigo sai quando
      // se troca de membro para fornecedor (ou se remove).
      final patch = <String, dynamic>{
        for (final e in vinculo.entries)
          e.key: e.value ?? YahwehFv.deleteField,
        'updatedAt': YahwehFv.serverTimestamp,
      };
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final doc in toUpdate.skip(i).take(batchLimit)) {
          batch.update(doc.reference, patch);
        }
        await batch.commit();
      }
    } catch (_) {
      // Best-effort: a fixa ja foi gravada; falhar aqui nao pode desfazer isso.
    }
  }

  Future<void> _updateFuturePendingCalendarFlags(
    String uid,
    String fixedIncomeId,
    bool addToCalendar,
    String? calendarColorHex,
  ) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
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

  Future<int> updateFuturePendingEntries(
      String uid, String fixedIncomeId, int newDayOfMonth) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snap = await _txRef(uid)
        .where('fixedIncomeId', isEqualTo: fixedIncomeId)
        .where('status', isEqualTo: 'pending')
        .get();
    final toUpdate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final dateTs = d['date'];
      if (dateTs is! Timestamp) continue;
      final date = dateTs.toDate();
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
        final date = dateTs.toDate();
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

  /// Remove uma receita fixa e os lançamentos pendentes ligados a ela
  /// (Agenda/calendário + Financeiro). Recebidos permanecem.
  Future<int> delete(String uid, String id) async {
    final removed = await _deletePendingEntriesForFixed(uid, id);
    await YahwehDocWrite.delete(_fixedRef(uid).doc(id));
    FinanceMonthCache.clearUid(uid);
    FinanceTransactionsHub.notifyMutated(uid: uid);
    return removed;
  }

  /// Remove todos os lançamentos **pending** desta receita fixa (qualquer mês).
  Future<int> _deletePendingEntriesForFixed(
      String uid, String fixedIncomeId) async {
    final snap = await _txRef(uid)
        .where('fixedIncomeId', isEqualTo: fixedIncomeId)
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
  /// Limpa dados legados e garante que parcelas passadas de receitas fixas
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

  Future<int> deleteAllParcelas(String uid, String fixedIncomeId) async {
    try {
      final snap = await _txRef(uid)
          .where('fixedIncomeId', isEqualTo: fixedIncomeId)
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
      throw Exception('Erro ao remover parcelas da receita fixa: $e');
    }
  }

  Future<int> ensureMonthlyEntries(String uid, {int monthsAhead = 4}) async {
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

    final existingSnaps = await Future.wait([
      for (final fe in activeItems)
        _txRef(uid)
            .where('fixedIncomeId', isEqualTo: fe['id'].toString())
            .get(),
    ]);

    // Migra lançamentos pendentes com data no passado para "paid". Isso limpa
    // dados antigos que não deveriam estar como pendentes e evita que voltem
    // ao painel de pendentes após serem excluídos.
    await _migratePastPendingEntries(uid, existingSnaps);

    final List<Map<String, dynamic>> toCreate = [];
    for (var i = 0; i < activeItems.length; i++) {
      final fe = activeItems[i];
      final existingSnap = existingSnaps[i];
      final start = (fe['startDate'] as Timestamp).toDate();
      final end = (fe['endDate'] as Timestamp).toDate();
      final dayOfMonth = (fe['dayOfMonth'] as num?)?.toInt() ?? 1;
      final category = (fe['category'] ?? 'Receita').toString();
      final description = (fe['description'] ?? 'Receita fixa').toString();
      final feId = fe['id'].toString();
      final amount = (fe['amount'] as num?)?.toDouble() ?? 0;
      // `== true`, nao `!= false`: campo ausente e DESLIGADO, igual ao
      // formulario. Com `!= false` toda fixa antiga voltava para o calendario.
      final addToCalendar = fe['addToCalendar'] == true;
      // Vinculo da fixa (membro ou fornecedor) — copiado para cada lancamento
      // gerado, senao o total por pessoa ignorava os recorrentes.
      final vinculoFixo = <String, dynamic>{
        for (final k in const [
          'membroId',
          'membroNome',
          'memberId',
          'fornecedorId',
          'fornecedorNome',
          'vinculoMultiplo',
          'vinculos',
        ])
          if (fe[k] != null) k: fe[k],
      };
      final calHex = (fe['calendarColorHex'] ?? '').toString().trim();
      final financeAccountId =
          (fe['financeAccountId'] ?? '').toString().trim();

      // Meses explicitamente excluídos pelo usuário são tratados como "existentes"
      // para não recriar parcelas removidas manualmente.
      final existingMonthKeys = <String>{
        ...List<String>.from(fe['excludedMonths'] ?? const []),
      };
      for (final d in existingSnap.docs) {
        final data = d.data();
        final mk = data['fixedIncomeMonthKey'] as String?;
        if (mk != null && mk.isNotEmpty) {
          existingMonthKeys.add(mk);
          continue;
        }
        final dateTs = data['date'];
        if (dateTs is Timestamp) {
          final dt = dateTs.toDate();
          existingMonthKeys
              .add('${dt.year}-${dt.month.toString().padLeft(2, '0')}');
        }
      }

      final isByInstallments = (fe['mode'] ?? modePeriod) == modeInstallments;
      final totalParcelas = (fe['totalParcelas'] as num?)?.toInt();
      final parcelaInicial = (fe['parcelaInicial'] as num?)?.toInt() ?? 1;
      final installmentCount =
          isByInstallments && totalParcelas != null ? totalParcelas : 1;
      final startMonth = DateTime(start.year, start.month, 1);

      DateTime month = DateTime(start.year, start.month, 1);
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
          'type': 'income',
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
          ...vinculoFixo,
          'fixedIncomeId': feId,
          'fixedIncomeMonthKey': monthKey,
          'addToCalendar': addToCalendar,
          if (!addToCalendar) 'hideFromCalendar': true,
          'recebimentoConfirmado': status != 'pending',
          if (financeAccountId.isNotEmpty) ...{
            'financeAccountId': financeAccountId,
            'contaDestinoId': financeAccountId,
          },
          if (addToCalendar && calHex.isNotEmpty) 'calendarColorHex': calHex,
          'createdAt': YahwehFv.serverTimestamp,
          'updatedAt': YahwehFv.serverTimestamp,
        });
        month = DateTime(month.year, month.month + 1, 1);
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
      throw Exception('Erro ao gerar parcelas de receitas fixas: $e');
    }
  }
}
