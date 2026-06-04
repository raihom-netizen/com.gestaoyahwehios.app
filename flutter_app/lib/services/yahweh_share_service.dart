import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Partilha nativa (WhatsApp, Telegram, etc.) — ponto único §19 prompt mestre.
abstract final class YahwehShareService {
  YahwehShareService._();

  static const String whatsAppHint =
      'Escolha WhatsApp na folha de partilha para enviar a um membro ou grupo.';

  static Future<void> sharePdfBytes({
    required Uint8List bytes,
    required String fileName,
    String? message,
    String? subject,
    Rect? sharePositionOrigin,
  }) =>
      shareBytes(
        bytes: bytes,
        fileName: fileName.endsWith('.pdf') ? fileName : '$fileName.pdf',
        mimeType: 'application/pdf',
        message: message ?? whatsAppHint,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );

  static Future<void> shareCsvBytes({
    required Uint8List bytes,
    required String fileName,
    String? subject,
  }) =>
      shareBytes(
        bytes: bytes,
        fileName: fileName.endsWith('.csv') ? fileName : '$fileName.csv',
        mimeType: 'text/csv',
        subject: subject ?? 'Exportação CSV',
        message: whatsAppHint,
      );

  /// Bytes genéricos (PDF, CSV, ZIP, imagem…).
  static Future<void> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? message,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    if (bytes.isEmpty) return;
    if (kIsWeb) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        text: message,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, name: fileName, mimeType: mimeType)],
      text: message,
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Ficheiro já em disco (ex. PDF gerado localmente).
  static Future<void> shareFile({
    required String path,
    String? mimeType,
    String? message,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    await Share.shareXFiles(
      [XFile(path, mimeType: mimeType)],
      text: message ?? whatsAppHint,
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Folha nativa — texto (avisos, links).
  static Future<void> shareText(
    String text, {
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await Share.share(
      t,
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
