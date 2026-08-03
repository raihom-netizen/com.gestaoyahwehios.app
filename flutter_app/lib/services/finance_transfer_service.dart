import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/constants/currency_formats.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/utils/finance_transaction_datetime.dart';
import 'finance_comprovante_publish_service.dart';
import 'finance_lancamento_write_service.dart';
import 'logs_service.dart';

/// Cria transferência entre contas (Cloud Function com fallback em batch local).
class FinanceTransferService {
  FinanceTransferService._();
  static final FinanceTransferService instance = FinanceTransferService._();

  Future<void> createTransfer({
    required String uid,
    required FinanceAccount fromAcc,
    required FinanceAccount toAcc,
    required double amount,
    required DateTime selectedCalendarDay,
    String note = '',
    String logModulo = 'Financeiro',
    Uint8List? receiptBytes,
    String? receiptName,
    String? receiptMime,
  }) async {
    final fsUid = uid.trim();
    final transferAt = FinanceTransactionDatetime.mergeCalendarDayWithClockNow(selectedCalendarDay);
    final histLine = '${fromAcc.displayName} → ${toAcc.displayName}';

    // A Cloud Function `createFinanceTransfer` opera no espaço pessoal
    // (users/{uid}) e ainda não foi migrada para igrejas/{churchId}/finance —
    // usar sempre o caminho local (já por igreja + saldo atômico) evita
    // gravar a transferência no lugar errado quando a function "funcionar".
    final local = await _createTransferBatchLocal(
      fsUid: fsUid,
      fromId: fromAcc.id,
      toId: toAcc.id,
      fromLabel: fromAcc.displayName,
      toLabel: toAcc.displayName,
      amount: amount,
      transferAt: transferAt,
      note: note,
    );
    final outId = local.outId;
    final inId = local.inId;

    if (receiptBytes != null &&
        receiptBytes.isNotEmpty &&
        (receiptName ?? '').trim().isNotEmpty &&
        (receiptMime ?? '').trim().isNotEmpty) {
      await _attachReceiptToLegs(
        fsUid: fsUid,
        outId: outId,
        inId: inId,
        bytes: receiptBytes,
        name: receiptName!.trim(),
        mime: receiptMime!.trim(),
      );
    }

    await LogsService().saveLog(
      modulo: logModulo,
      acao: 'Transferência entre contas',
      detalhes: '$histLine • ${CurrencyFormats.formatBRL(amount)}',
    );
  }

  Future<void> attachReceiptToTransferLegs({
    required String uid,
    required List<String> docIds,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final fsUid = uid.trim();
    final ids = docIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return;
    // Mesmo comprovante em ambas as pernas — uma única imagem, uploads em
    // paralelo (antes: Cloud Function não implantada, falhava sempre).
    await Future.wait(
      ids.map((id) => _uploadComprovanteAndPatch(fsUid: fsUid, txId: id, bytes: bytes, name: name, mime: mime)),
    );
  }

  Future<void> _uploadComprovanteAndPatch({
    required String fsUid,
    required String txId,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final result = await FinanceComprovantePublishService.uploadComprovanteStorageOnly(
      tenantId: fsUid,
      lancamentoId: txId,
      rawBytes: bytes,
      mimeType: mime,
      fileName: name,
    );
    await ChurchUiCollections.financeiro(fsUid).doc(txId).update({
      ...FinanceComprovantePublishService.comprovanteFieldsPatch(
        url: result.url,
        storagePath: result.storagePath,
        mimeType: result.mimeType,
        fileName: result.fileName,
      ),
      'hasReceipt': true,
      'receipt': {'webViewLink': result.url, 'webContentLink': result.url},
    });
  }

  Future<void> removeReceiptFromTransferLegs({
    required String uid,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return;
    final fsUid = uid.trim();
    final col = ChurchUiCollections.financeiro(fsUid);
    final batch = FirebaseFirestore.instance.batch();
    for (final id in docIds) {
      if (id.trim().isEmpty) continue;
      batch.update(col.doc(id), {
        'receipt': FieldValue.delete(),
        'hasReceipt': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _attachReceiptToLegs({
    required String fsUid,
    required String? outId,
    required String? inId,
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    final ids = [outId, inId].whereType<String>().where((id) => id.trim().isNotEmpty);
    await Future.wait(
      ids.map((id) => _uploadComprovanteAndPatch(fsUid: fsUid, txId: id, bytes: bytes, name: name, mime: mime)),
    );
  }

  Future<({String pairId, String outId, String inId})> _createTransferBatchLocal({
    required String fsUid,
    required String fromId,
    required String toId,
    required String fromLabel,
    required String toLabel,
    required double amount,
    required DateTime transferAt,
    required String note,
  }) async {
    final pairId = 'tr_${DateTime.now().microsecondsSinceEpoch}';
    final notePart = note.trim().isEmpty ? '' : ' • ${note.trim()}';
    final histLine = '$fromLabel → $toLabel';
    final descOut = 'Saída • Transferência • $histLine$notePart';
    final descIn = 'Entrada • Transferência • $histLine$notePart';
    final transferTs = Timestamp.fromDate(transferAt);

    final col = ChurchUiCollections.financeiro(fsUid);
    final outRef = col.doc();
    final inRef = col.doc();
    // Uma transação por perna (ajusta `contas.saldo` de origem e destino).
    await FinanceLancamentoWriteService.commitInTransaction(
      churchId: fsUid,
      lancamentoRef: outRef,
      merge: false,
      payload: {
        'type': 'expense',
        'amount': amount,
        'category': 'Transferência',
        'description': descOut,
        'status': 'paid',
        'date': transferTs,
        'paidAt': transferTs,
        'effectiveDate': transferTs,
        'financeAccountId': fromId,
        'contaOrigemId': fromId,
        'pagamentoConfirmado': true,
        'transferPairId': pairId,
        'transferDirection': 'out',
        'transferCounterpartyAccountId': toId,
        'transferCounterpartyLabel': toLabel,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    await FinanceLancamentoWriteService.commitInTransaction(
      churchId: fsUid,
      lancamentoRef: inRef,
      merge: false,
      payload: {
        'type': 'income',
        'amount': amount,
        'category': 'Transferência',
        'description': descIn,
        'status': 'paid',
        'date': transferTs,
        'paidAt': transferTs,
        'effectiveDate': transferTs,
        'financeAccountId': toId,
        'contaDestinoId': toId,
        'recebimentoConfirmado': true,
        'transferPairId': pairId,
        'transferDirection': 'in',
        'transferCounterpartyAccountId': fromId,
        'transferCounterpartyLabel': fromLabel,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    return (pairId: pairId, outId: outRef.id, inId: inRef.id);
  }
}
