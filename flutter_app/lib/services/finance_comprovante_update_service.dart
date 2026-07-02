import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/fornecedor_compromisso_publish_service.dart';

/// Comprovantes — paths canónicos `igrejas/{churchId}/…` via [ChurchRepository.churchId].
abstract final class FinanceComprovanteUpdateService {
  FinanceComprovanteUpdateService._();

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static String financeStoragePathHint({
    required String churchIdHint,
    required String lancamentoId,
    DateTime? referenceDate,
    String ext = 'jpg',
  }) {
    final cid = resolveChurchId(churchIdHint);
    return ChurchStorageLayout.financeComprovantePath(
      tenantId: cid,
      lancamentoId: lancamentoId,
      referenceDate: referenceDate,
      ext: ext,
    );
  }

  static String fornecedorStoragePathHint({
    required String churchIdHint,
    required String fornecedorId,
    required String compromissoId,
    String ext = 'jpg',
  }) {
    final cid = resolveChurchId(churchIdHint);
    return ChurchStorageLayout.fornecedorCompromissoComprovantePath(
      tenantId: cid,
      fornecedorId: fornecedorId,
      compromissoId: compromissoId,
      ext: ext,
    );
  }

  static Future<String> publishFinanceLancamentoStrict({
    required String churchIdHint,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(double progress)? onProgress,
  }) {
    return FinanceComprovantePublishService.uploadComprovanteNow(
      tenantId: resolveChurchId(churchIdHint),
      docRef: docRef,
      rawBytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      referenceDate: referenceDate,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
      onProgress: onProgress,
    );
  }

  static Future<void> removeFinanceLancamentoStrict({
    required String churchIdHint,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
  }) =>
      FinanceComprovantePublishService.removeComprovante(
        tenantId: resolveChurchId(churchIdHint),
        docRef: docRef,
        data: data,
      );

  static Future<void> publishFornecedorCompromissoStrict({
    required String churchIdHint,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) =>
      FornecedorCompromissoPublishService.attachComprovante(
        docRef: docRef,
        churchId: resolveChurchId(churchIdHint),
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        bytes: bytes,
        mimeType: mimeType,
        fileName: fileName,
      );

  static Future<void> removeFornecedorCompromissoStrict({
    required String churchIdHint,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String fornecedorId,
    required String compromissoId,
    required Map<String, dynamic> data,
  }) =>
      FornecedorCompromissoPublishService.removeComprovante(
        docRef: docRef,
        churchId: resolveChurchId(churchIdHint),
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        data: data,
      );

  static Future<FinanceComprovanteAttachment?> pickAttachment(
    BuildContext context, {
    required bool canAdd,
    required bool canChange,
    bool hasExisting = false,
    String title = 'Anexar comprovante',
  }) async {
    if (!canAdd && !canChange) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sem permissão para alterar comprovantes.'),
          ),
        );
      }
      return null;
    }
    return FinanceComprovanteAttachService.showPickSheet(
      context,
      title: hasExisting ? 'Trocar comprovante' : title,
    );
  }
}
