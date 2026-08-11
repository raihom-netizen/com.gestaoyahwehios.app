import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/constants/currency_formats.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/finance_line_opening.dart';
import 'package:gestao_yahweh/utils/finance_transaction_datetime.dart';
import 'package:gestao_yahweh/utils/finance_transaction_status_resolver.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/module_write_guard.dart';
import 'package:gestao_yahweh/utils/connectivity_offline.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/finance_lancamento_write_service.dart';
import 'package:gestao_yahweh/services/finance_month_cache.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';
import 'package:gestao_yahweh/services/finance_receipt_upload_service.dart';
import 'logs_service.dart';

/// Deriva os campos que o motor por-igreja usa para manter `contas.saldo`
/// (mesma regra de flutter_app/lib/core/finance_saldo_policy.dart e do
/// script de migração `scripts/migrate_financeiro_pessoal_para_igreja.cjs`).
Map<String, dynamic> _contaEStatusFields({
  required String type,
  required String status,
  required String financeAccountId,
}) {
  final out = <String, dynamic>{};
  if (type == 'income') {
    out['recebimentoConfirmado'] = status != 'pending';
    if (financeAccountId.isNotEmpty) out['contaDestinoId'] = financeAccountId;
  } else {
    out['pagamentoConfirmado'] = status != 'pending';
    if (financeAccountId.isNotEmpty) out['contaOrigemId'] = financeAccountId;
  }
  return out;
}

/// Resultado de [TransactionSaveService.saveFromNovoLancamentoResult] para UI otimista.
class TransactionSaveResult {
  final List<String> docIds;
  const TransactionSaveResult({required this.docIds});
}

/// Persistência de lançamentos (receita/despesa) compartilhada entre Financeiro e atalhos (ex.: Início).
class TransactionSaveService {
  TransactionSaveService._();

  /// [uid] aqui é o `churchId` — Financeiro é por igreja, não por login pessoal.
  static CollectionReference<Map<String, dynamic>> txRef(String uid) =>
      ChurchUiCollections.financeiro(uid.trim());

  /// Evita segundo lançamento de fechamento de Escalas para o mesmo vínculo + período.
  static Future<bool> transactionExistsWithScaleClosureDedupKey(
      String uid, String dedupKey) async {
    final k = dedupKey.trim();
    if (k.isEmpty) return false;
    final q = await txRef(uid)
        .where('scaleClosureDedupKey', isEqualTo: k)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// Uma leitura em lote (chunks de 30 — limite `whereIn` do Firestore) em vez de N queries.
  static Future<Set<String>> existingScaleClosureDedupKeys(
    String uid,
    Iterable<String> dedupKeys,
  ) async {
    final want =
        dedupKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
    if (want.isEmpty) return {};
    final found = <String>{};
    final list = want.toList();
    const chunkSize = 30;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, math.min(i + chunkSize, list.length));
      final snap =
          await txRef(uid).where('scaleClosureDedupKey', whereIn: chunk).get();
      for (final d in snap.docs) {
        final k = d.data()['scaleClosureDedupKey']?.toString().trim();
        if (k != null && k.isNotEmpty) found.add(k);
      }
    }
    return found;
  }

  /// Fechamento Escalas: grava várias receitas com poucos round-trips (batch ≤500 ops cada).
  /// Cada item usa o mesmo formato que [saveFromNovoLancamentoResult] com parcela única e tipo receita.
  static Future<int> saveScaleClosureIncomeBatch({
    required String uid,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return 0;
    final col = txRef(uid);
    var totalWritten = 0;

    for (var start = 0; start < items.length; start += 500) {
      final end = math.min(start + 500, items.length);
      final slice = items.sublist(start, end);
      final batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      for (final data in slice) {
        final rawAmount = data['amount'];
        double amount;
        if (rawAmount is num) {
          amount = rawAmount.toDouble();
        } else if (rawAmount is String) {
          amount = CurrencyFormats.parseBRLInput(rawAmount) ?? 0;
        } else {
          amount = 0;
        }
        if (amount.isNaN || amount.isInfinite || amount <= 0) continue;

        final category = (data['category'] ?? '').toString();
        final description = (data['description'] ?? '').toString();
        final status = (data['status'] ?? 'paid').toString();
        DateTime date = data['date'] is DateTime
            ? data['date'] as DateTime
            : DateTime.now();
        if ((data['source'] ?? '').toString() != 'open_finance') {
          date = FinanceTransactionDatetime.normalizeManualDateTime(date);
        }
        final recurrence = (data['recurrence'] ?? 'none').toString();
        final financeAccountId =
            (data['financeAccountId'] ?? '').toString().trim();

        final ref = col.doc();
        batch.set(ref, {
          'type': 'income',
          'amount': amount,
          'category': category,
          'description': description,
          'status': status,
          'date': Timestamp.fromDate(date),
          'effectiveDate':
              FinanceLineOpening.effectiveTimestampForWrite(date: date),
          'recurrence': recurrence,
          'installmentCount': 1,
          'installmentIndex': 1,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          ..._contaEStatusFields(
            type: 'income',
            status: status,
            financeAccountId: financeAccountId,
          ),
          ..._optionalClosureAndSourceFields(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ops++;
      }
      if (ops > 0) {
        await batch.commit();
        totalWritten += ops;
      }
    }

    if (totalWritten > 0) {
      unawaited(
        LogsService()
            .saveLog(
              modulo: 'Financeiro',
              acao: 'Criou receitas (fechamento Escalas)',
              detalhes: '$totalWritten lançamento(s)',
            )
            .catchError((_) {}),
      );
    }
    return totalWritten;
  }

  static Map<String, dynamic> _optionalClosureAndSourceFields(
      Map<String, dynamic> data) {
    final o = <String, dynamic>{};
    void putStr(String key) {
      final v = data[key];
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      o[key] = s;
    }

    putStr('source');
    putStr('scaleClosureDedupKey');
    putStr('scaleClosureGroupId');
    putStr('scaleClosureEmployerType');
    return o;
  }

  static DateTime addMonths(DateTime d, int months) {
    final year = d.year + ((d.month - 1 + months) ~/ 12);
    final month = ((d.month - 1 + months) % 12) + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = d.day.clamp(1, lastDayOfMonth);
    return DateTime(year, month, day, d.hour, d.minute);
  }

  /// Cordex: validação rigorosa para evitar RangeError (Invalid Value) no Firestore.
  /// Mesma lógica que o módulo Financeiro (Firestore + log + comprovante premium).
  /// [showSuccessSnack]: em gravações em lote (ex.: fechamento de Escalas), use `false` e mostre um único SnackBar no fim.
  static Future<TransactionSaveResult?> saveFromNovoLancamentoResult({
    required String uid,
    required Map<String, dynamic> data,
    required BuildContext context,
    bool showSuccessSnack = true,
  }) async {
    final type = (data['type'] ?? 'expense').toString();
    final rawAmount = data['amount'];
    double amount;
    if (rawAmount is num) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      amount = CurrencyFormats.parseBRLInput(rawAmount) ?? 0;
    } else {
      amount = 0;
    }
    if (amount.isNaN || amount.isInfinite || amount <= 0) return null;

    final category = (data['category'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    DateTime date =
        data['date'] is DateTime ? data['date'] as DateTime : DateTime.now();
    if ((data['source'] ?? '').toString() != 'open_finance') {
      date = FinanceTransactionDatetime.normalizeManualDateTime(date);
    }
    final recurrence = (data['recurrence'] ?? 'none').toString();
    final preferredStatus = (data['status'] ?? 'paid').toString();
    final resolvedStatus = FinanceTransactionStatusResolver.resolveByDateTime(
      date,
      preferredStatus: preferredStatus,
    );
    final paidAt = resolvedStatus == 'paid'
        ? FinanceTransactionStatusResolver.paidAtForAutoPaid(date)
        : null;
    final installments = (data['installments'] is int)
        ? (data['installments'] as int).clamp(1, 999)
        : 1;
    final rawStart = data['installmentStartIndex'];
    final installmentStartIndex = (rawStart is int)
        ? rawStart.clamp(1, installments)
        : (int.tryParse(rawStart?.toString() ?? '') ?? 1)
            .clamp(1, installments);
    final receipt = data['receipt'] as Map<String, dynamic>?;
    final financeAccountId = (data['financeAccountId'] ?? '').toString().trim();
    final addToCalendar = data['addToCalendar'] == true;
    final calendarColorHex = (data['calendarColorHex'] ?? '').toString().trim();
    if (type == 'expense' && financeAccountId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Despesa sem conta. Cadastre e selecione uma conta no lançamento.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return null;
    }

    // ModuleWriteGuard só garante sessão Auth pronta + retry (web/mobile) —
    // o alvo da escrita continua sendo a igreja (`uid` = churchId), nunca o
    // uid pessoal que o guard resolveria internamente.
    return ModuleWriteGuard.run(uid, (_) async {
      final churchId = uid.trim();
      final col = ChurchUiCollections.financeiro(churchId);
      final savedIds = <String>[];
      String? firstDocId;
      if (installments <= 1) {
        final ref = col.doc();
        final payload = {
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
          'status': resolvedStatus,
          'date': Timestamp.fromDate(date),
          'paidAt': ?paidAt,
          'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
            date: date,
            paidAt: paidAt,
          ),
          'recurrence': recurrence,
          'installmentCount': 1,
          'installmentIndex': 1,
          if (financeAccountId.isNotEmpty) 'financeAccountId': financeAccountId,
          'addToCalendar': addToCalendar,
          if (addToCalendar && calendarColorHex.isNotEmpty)
            'calendarColorHex': calendarColorHex,
          ..._contaEStatusFields(
            type: type,
            status: resolvedStatus,
            financeAccountId: financeAccountId,
          ),
          ..._optionalClosureAndSourceFields(data),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        // Web: grava o doc por REST (a transação do SDK trava no cliente
        // envenenado pela assertion). O saldo é COMPUTADO dos lançamentos no
        // painel → recalcula sozinho ao recarregar (leitura REST). Mobile:
        // transação atômica normal (ajusta saldo stored da conta).
        if (kIsWeb) {
          await firestoreRestSetDoc(ref.path, payload);
        } else {
          await FinanceLancamentoWriteService.commitInTransaction(
            churchId: churchId,
            lancamentoRef: ref,
            payload: payload,
            merge: false,
          );
        }
        firstDocId = ref.id;
        savedIds.add(ref.id);
        unawaited(
          LogsService()
              .saveLog(
                modulo: 'Financeiro',
                acao: type == 'income' ? 'Criou receita' : 'Criou despesa',
                detalhes:
                    '${category.isEmpty ? 'Categoria' : category} • ${CurrencyFormats.formatBRL(amount)}',
              )
              .catchError((_) {}),
        );
        if (context.mounted && showSuccessSnack) {
          HapticFeedback.lightImpact();
          final offline =
              isConnectivityOffline(await Connectivity().checkConnectivity());
          final base = type == 'income'
              ? 'Receita registada no Financeiro.'
              : 'Despesa registada no Financeiro.';
          final msg = offline
              ? '$base Guardado no aparelho; sincroniza quando houver internet.'
              : base;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      } else {
        final groupId = col.doc().id;
        final valueIsPerParcel = data['installmentValueIsPerParcel'] == true;
        final amountPerParcel =
            valueIsPerParcel ? amount : amount / installments;
        final parcelCount = installments - installmentStartIndex + 1;
        // Uma transação por parcela (ajusta `contas.saldo` em cada uma) —
        // mesmo padrão de FinanceAccountMigrateService.migrateDocuments.
        for (var k = 0; k < parcelCount; k++) {
          final i = installmentStartIndex + k;
          final d = addMonths(date, k);
          final parcelStatus =
              FinanceTransactionStatusResolver.resolveByDateTime(
            d,
            preferredStatus: preferredStatus,
          );
          final parcelPaidAt = parcelStatus == 'paid'
              ? FinanceTransactionStatusResolver.paidAtForAutoPaid(d)
              : null;
          final ref = col.doc();
          if (k == 0) firstDocId = ref.id;
          savedIds.add(ref.id);
          final payload = {
            'type': type,
            'amount': amountPerParcel,
            'category': category,
            'description': description,
            'status': parcelStatus,
            'date': Timestamp.fromDate(d),
            'paidAt': ?parcelPaidAt,
            'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
              date: d,
              paidAt: parcelPaidAt,
            ),
            'recurrence': recurrence,
            'installmentCount': installments,
            'installmentIndex': i,
            'installmentGroupId': groupId,
            if (financeAccountId.isNotEmpty)
              'financeAccountId': financeAccountId,
            'addToCalendar': addToCalendar,
            if (addToCalendar && calendarColorHex.isNotEmpty)
              'calendarColorHex': calendarColorHex,
            ..._contaEStatusFields(
              type: type,
              status: parcelStatus,
              financeAccountId: financeAccountId,
            ),
            ..._optionalClosureAndSourceFields(data),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          // Web: cada parcela por REST (a transação do SDK trava no cliente
          // envenenado pela assertion). Saldo é computado dos lançamentos →
          // recalcula ao recarregar. Mobile: transação atômica normal.
          if (kIsWeb) {
            await firestoreRestSetDoc(ref.path, payload);
          } else {
            await FinanceLancamentoWriteService.commitInTransaction(
              churchId: churchId,
              lancamentoRef: ref,
              payload: payload,
              merge: false,
            );
          }
        }
        unawaited(
          LogsService()
              .saveLog(
                modulo: 'Financeiro',
                acao: type == 'income'
                    ? 'Criou receita parcelada'
                    : 'Criou despesa parcelada',
                detalhes:
                    '${category.isEmpty ? 'Categoria' : category} • $parcelCount de $installments parcelas • ${valueIsPerParcel ? '${CurrencyFormats.formatBRL(amount)}/parcela' : 'Total ${CurrencyFormats.formatBRL(amount)}'}',
              )
              .catchError((_) {}),
        );
        if (context.mounted && showSuccessSnack) {
          HapticFeedback.lightImpact();
          final offline =
              isConnectivityOffline(await Connectivity().checkConnectivity());
          final base = type == 'income'
              ? 'Receitas parceladas registadas no Financeiro.'
              : 'Despesas parceladas registadas no Financeiro.';
          final msg = offline
              ? '$base Guardado no aparelho; sincroniza quando houver internet.'
              : base;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      }

      if (savedIds.isEmpty) return null;
      final result = TransactionSaveResult(docIds: savedIds);
      // Pendente novo deve pintar no dia da Agenda/Escalas sem esperar cache antigo.
      FinanceMonthCache.clearUid(churchId);
      FinanceTransactionsHub.notifyMutated(
        uid: churchId,
        effectiveDate: date,
      );

      // Comprovante em segundo plano: lista/saldos atualizam na hora (offline → fila local).
      if (receipt != null && firstDocId != null) {
        final bytes = receipt['bytes'] as Uint8List?;
        final name = receipt['name'] as String?;
        final mime = receipt['mime'] as String?;
        if (bytes != null &&
            name != null &&
            mime != null &&
            bytes.lengthInBytes > 0) {
          unawaited(
            FinanceReceiptUploadService.attachToTransaction(
              uid: churchId,
              txDocId: firstDocId,
              bytes: bytes,
              filename: name,
              mimeType: mime,
              context: context.mounted ? context : null,
              showUserFeedback: true,
            ),
          );
        }
      }

      return result;
    });
  }
}
