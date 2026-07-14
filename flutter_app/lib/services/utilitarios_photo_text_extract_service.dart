import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/services/smart_input_image_ocr_service.dart';
import 'utilitarios_local_service.dart';
import 'utilitarios_photo_service.dart';

/// Parágrafo detectado na foto (preserva estrutura para Word/PDF).
class UtilPhotoTextParagraph {
  const UtilPhotoTextParagraph({
    required this.text,
    this.isHeading = false,
  });

  final String text;
  final bool isHeading;
}

/// Resultado da extração de texto em foto (estilo Lens).
class UtilPhotoTextExtractResult {
  const UtilPhotoTextExtractResult({
    required this.plainText,
    required this.paragraphs,
    required this.sourcePreview,
  });

  final String plainText;
  final List<UtilPhotoTextParagraph> paragraphs;
  final Uint8List sourcePreview;
}

abstract final class UtilitariosPhotoTextExtractService {
  UtilitariosPhotoTextExtractService._();

  static bool get supported {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  /// Melhora a foto e extrai texto estruturado (local + Cloud Vision se logado).
  static Future<UtilPhotoTextExtractResult> extractFromImage(Uint8List raw) async {
    final enhanced = await UtilitariosPhotoService.enhanceQuality(
      raw,
      target: UtilPhotoEnhanceTarget.fullHd,
    );

    var structured = await _extractStructured(enhanced, filePath: null);
    if (structured.plainText.trim().isEmpty) {
      structured = await _extractStructured(raw, filePath: null);
    }
    if (structured.plainText.trim().isEmpty) {
      throw StateError(
        'Nenhum texto encontrado na foto. Tente outro ângulo ou mais luz.',
      );
    }

    return UtilPhotoTextExtractResult(
      plainText: structured.plainText,
      paragraphs: structured.paragraphs,
      sourcePreview: enhanced,
    );
  }

  static Future<({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  })> _extractStructured(
    Uint8List bytes, {
    required String? filePath,
  }) async {
    if (!kIsWeb &&
        SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      final ml = await _extractWithMlKit(bytes);
      if (ml.plainText.trim().isNotEmpty) return ml;
    }

    final flat = await SmartInputImageOcrService.recognizeFromGalleryBytes(
      bytes: bytes,
      filePath: filePath,
    );
    return _paragraphsFromPlainText(flat);
  }

  static Future<({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  })> _extractWithMlKit(Uint8List jpeg) async {
    final tmp = await _writeTempJpeg(jpeg);
    TextRecognizer? rec;
    try {
      rec = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await rec.processImage(
        InputImage.fromFilePath(tmp.path),
      );
      final paragraphs = <UtilPhotoTextParagraph>[];
      final buf = StringBuffer();
      for (final block in recognized.blocks) {
        final lines = block.lines
            .map((l) => l.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (lines.isEmpty) continue;
        final para = lines.join(' ');
        final heading = UtilitariosLocalService.looksLikeDocumentHeading(para);
        paragraphs.add(
          UtilPhotoTextParagraph(text: para, isHeading: heading),
        );
        if (buf.isNotEmpty) buf.writeln();
        buf.write(para);
      }
      return (
        plainText: buf.toString().trim(),
        paragraphs: paragraphs,
      );
    } catch (_) {
      return (
        plainText: '',
        paragraphs: List<UtilPhotoTextParagraph>.empty(),
      );
    } finally {
      try {
        await rec?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  static ({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  }) _paragraphsFromPlainText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return (plainText: '', paragraphs: const []);
    }
    final parts = trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final paragraphs = parts
        .map(
          (p) => UtilPhotoTextParagraph(
            text: p,
            isHeading: UtilitariosLocalService.looksLikeDocumentHeading(p),
          ),
        )
        .toList();
    return (
      plainText: parts.join('\n\n'),
      paragraphs: paragraphs,
    );
  }

  static Future<File> _writeTempJpeg(Uint8List jpeg) async {
    final dir = await getTemporaryDirectory();
    final f = File(
      '${dir.path}/ct_text_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await f.writeAsBytes(jpeg, flush: true);
    return f;
  }

  /// Gera DOCX formatado a partir dos parágrafos editados.
  static Uint8List buildDocx(List<UtilPhotoTextParagraph> paragraphs) {
    return UtilitariosLocalService.buildFormattedDocxFromParagraphs(
      paragraphs
          .where((p) => p.text.trim().isNotEmpty)
          .map((p) => (text: p.text.trim(), isHeading: p.isHeading))
          .toList(),
    );
  }

  /// Gera PDF a partir do texto editado.
  static Future<Uint8List> buildPdf(String plainText) =>
      UtilitariosLocalService.plainTextToPdf(plainText);
}
