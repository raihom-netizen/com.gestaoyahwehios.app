import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';

/// Utilitários centralizados para comprovantes — espelho WISDOMAPP ReceiptAttachmentUtils.
abstract final class FinanceComprovanteUtils {
  FinanceComprovanteUtils._();

  static const int maxBytes = FinanceComprovanteAttachService.maxBytes;
  static const allowedExtensions = FinanceComprovanteAttachService.allowedExtensions;

  static bool hasViewableComprovante(Map<String, dynamic>? data) =>
      data != null && FinanceComprovanteAttachService.hasComprovanteReady(data);

  static String viewUrl(Map<String, dynamic>? data) {
    if (data == null) return '';
    return (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '').toString().trim();
  }

  static String storagePath(Map<String, dynamic>? data) {
    if (data == null) return '';
    return (data['comprovanteStoragePath'] ?? '').toString().trim();
  }

  static String fileName(Map<String, dynamic>? data) =>
      FinanceComprovanteAttachService.displayNameFromDoc(data ?? {});

  static String mimeType(Map<String, dynamic>? data) =>
      FinanceComprovanteAttachService.mimeFromDoc(data ?? {});

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
