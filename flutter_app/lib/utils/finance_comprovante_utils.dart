import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';

/// Utilitários centralizados para comprovantes — espelho WISDOMAPP ReceiptAttachmentUtils.
abstract final class FinanceComprovanteUtils {
  FinanceComprovanteUtils._();

  static const int maxBytes = FinanceComprovanteAttachService.maxBytes;
  static const allowedExtensions = FinanceComprovanteAttachService.allowedExtensions;

  static bool hasViewableComprovante(Map<String, dynamic>? data) =>
      ChurchCanonicalMediaContract.hasViewableFinanceComprovante(data);

  static String viewUrl(Map<String, dynamic>? data) =>
      ChurchCanonicalMediaContract.financeComprovanteViewUrl(data);

  static String storagePath(Map<String, dynamic>? data) =>
      ChurchCanonicalMediaContract.financeComprovanteStoragePath(data);

  static String fileName(Map<String, dynamic>? data) {
    if (data == null) return 'Comprovante';
    return ChurchCanonicalMediaContract.resolveFinanceComprovante(data).fileName;
  }

  static String mimeType(Map<String, dynamic>? data) {
    if (data == null) return 'image/jpeg';
    final mime =
        ChurchCanonicalMediaContract.resolveFinanceComprovante(data).mimeType;
    return mime.isNotEmpty ? mime : FinanceComprovanteAttachService.mimeFromDoc(data);
  }

  static bool isImageComprovante(Map<String, dynamic>? data) {
    final mime = mimeType(data);
    return mime.startsWith('image/');
  }

  static bool isPdfComprovante(Map<String, dynamic>? data) {
    final mime = mimeType(data);
    return mime.contains('pdf') || fileName(data).toLowerCase().endsWith('.pdf');
  }

  static Future<FinanceComprovanteAttachment?> pickValidated(
    BuildContext context, {
    bool showSnack = true,
  }) =>
      FinanceComprovanteAttachService.showPickSheet(context);
}
