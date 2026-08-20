import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/utils/connectivity_offline.dart';
import 'finance_comprovante_publish_service.dart';
import 'pending_storage_upload_service.dart';
import 'transaction_save_service.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

/// Comprovante financeiro: upload imediato ou fila local (offline) — sync silencioso ao voltar rede.
class FinanceReceiptUploadService {
  FinanceReceiptUploadService._();

  static Future<bool> _isOffline() async {
    try {
      return isConnectivityOffline(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  /// Anexa comprovante ao lançamento. Offline: grava na fila + marca `hasReceipt` localmente.
  static Future<void> attachToTransaction({
    required String uid,
    required String txDocId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    BuildContext? context,
    bool showUserFeedback = true,
  }) async {
    if (uid.isEmpty || txDocId.isEmpty || bytes.isEmpty) return;

    final fsUid = uid.trim();
    final col = TransactionSaveService.txRef(uid);

    final offline = await _isOffline();
    if (!offline) {
      try {
        // Upload direto ao Storage (mesmo motor do comprovante do lançamento
        // novo) — evita o round-trip morto para uma Cloud Function que não
        // está implantada (`ctUploadReceiptToStorage`), que antes falhava
        // sempre e só depois caía na fila local, atrasando todo anexo.
        final result = await FinanceComprovantePublishService
            .uploadComprovanteStorageOnly(
          tenantId: fsUid,
          lancamentoId: txDocId,
          rawBytes: bytes,
          mimeType: mimeType,
          fileName: filename,
        );
        await YahwehDocWrite.update(col.doc(txDocId), {
          ...FinanceComprovantePublishService.comprovanteFieldsPatch(
            url: result.url,
            storagePath: result.storagePath,
            mimeType: result.mimeType,
            fileName: result.fileName,
          ),
          // Compat: telas que ainda leem o formato legado (`receipt`/`hasReceipt`).
          'hasReceipt': true,
          'receipt': {
            'webViewLink': result.url,
            'webContentLink': result.url,
          },
          'receiptPendingUpload': YahwehFv.deleteField,
        });
        if (showUserFeedback && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comprovante enviado e vinculado ao lançamento.'),
            ),
          );
        }
        return;
      } catch (_) {
        // Rede instável — cai na fila local.
      }
    }

    await PendingStorageUploadService.enqueueFinanceReceipt(
      userDocId: fsUid,
      transactionDocId: txDocId,
      bytes: bytes,
      fileName: filename,
      mime: mimeType,
    );
    await YahwehDocWrite.update(col.doc(txDocId), {
      'hasReceipt': true,
      'receiptPendingUpload': true,
      'updatedAt': YahwehFv.serverTimestamp,
    });
    if (showUserFeedback && context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offline
                ? 'Comprovante guardado no aparelho; envia automaticamente quando houver internet.'
                : 'Comprovante na fila local; tentaremos enviar em breve.',
          ),
        ),
      );
    }
  }
}
