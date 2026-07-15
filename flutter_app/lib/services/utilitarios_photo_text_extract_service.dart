import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/utils/ocr_description_sanity.dart';
import 'package:gestao_yahweh/utils/smart_input_ocr_recognized_postprocess.dart';
import 'package:gestao_yahweh/services/smart_input_image_ocr_service.dart';
import 'utilitarios_local_service.dart';
import 'utilitarios_photo_service.dart';

/// Parágrafo detectado na foto (preserva estrutura para Word/PDF).
class UtilPhotoTextParagraph {
  const UtilPhotoTextParagraph({
    required this.text,
    this.isHeading = false,
    this.isBold = false,
    this.isBullet = false,
  });

  final String text;
  final bool isHeading;
  final bool isBold;
  final bool isBullet;

  UtilPhotoTextParagraph copyWith({
    String? text,
    bool? isHeading,
    bool? isBold,
    bool? isBullet,
  }) {
    return UtilPhotoTextParagraph(
      text: text ?? this.text,
      isHeading: isHeading ?? this.isHeading,
      isBold: isBold ?? this.isBold,
      isBullet: isBullet ?? this.isBullet,
    );
  }
}

/// Resultado da extração de texto em foto — Controletotalapp.
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

  /// ML Kit reutilizado (estilo Lens — não reabrir a cada foto).
  static TextRecognizer? _latinRec;
  static Future<TextRecognizer>? _latinWarmup;

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

  /// Pré-aquece o ML Kit ao abrir a tela (carrega modelo + 1 frame dummy).
  static Future<void> warmUp() {
    if (kIsWeb || !SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      return Future<void>.value();
    }
    return _ensureLatinRecognizer().then((rec) async {
      try {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/ct_ocr_warmup.jpg');
        if (!await f.exists()) {
          // JPEG 1x1 branco — só para forçar o modelo nativo na memória.
          await f.writeAsBytes(const <int>[
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
            0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB,
            0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07,
            0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B,
            0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E,
            0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C,
            0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34,
            0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34,
            0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01,
            0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x03, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00,
            0x3F, 0x00, 0x7F, 0xFF, 0xD9,
          ], flush: false);
        }
        await rec.processImage(InputImage.fromFilePath(f.path));
      } catch (_) {}
    });
  }

  static Future<TextRecognizer> _ensureLatinRecognizer() {
    final existing = _latinRec;
    if (existing != null) return Future.value(existing);
    return _latinWarmup ??= () async {
      final rec = TextRecognizer(script: TextRecognitionScript.latin);
      _latinRec = rec;
      return rec;
    }();
  }

  /// OCR estilo Google Lens (Android/iOS = on-device ML Kit).
  ///
  /// Prioridade: **arquivo nativo da câmera** → ML Kit imediato (sem reencode).
  /// Fallback: resize leve só se não houver path.
  static Future<UtilPhotoTextExtractResult> extractFromImage(
    Uint8List raw, {
    String? filePath,
  }) async {
    if (!kIsWeb && SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      // 1) Path nativo — caminho Lens (sem decode/encode Flutter).
      if (filePath != null &&
          filePath.isNotEmpty &&
          await File(filePath).exists()) {
        final ml = await _runMlKitOnPath(filePath);
        if (ml.plainText.trim().isNotEmpty) {
          return UtilPhotoTextExtractResult(
            plainText: ml.plainText,
            paragraphs: ml.paragraphs,
            // Preview leve: reutiliza bytes se já vieram; senão não bloqueia.
            sourcePreview: raw.isNotEmpty ? raw : Uint8List(0),
          );
        }
      }

      // 2) Fallback: jpeg leve + ML Kit (só se path falhou / vazio).
      late final Uint8List input;
      if (raw.isNotEmpty) {
        input = raw;
      } else if (filePath != null &&
          filePath.isNotEmpty &&
          await File(filePath).exists()) {
        input = await File(filePath).readAsBytes();
      } else {
        input = Uint8List(0);
      }
      if (input.isEmpty) {
        throw StateError('Imagem vazia.');
      }
      final fast = await UtilitariosPhotoService.normalizeForOcrFast(input);
      final ml2 = await _runMlKitOnBytes(fast);
      if (ml2.plainText.trim().isNotEmpty) {
        return UtilPhotoTextExtractResult(
          plainText: ml2.plainText,
          paragraphs: ml2.paragraphs,
          sourcePreview: fast,
        );
      }
      throw StateError(
        'Nenhum texto encontrado na foto. Tente outro ângulo ou mais luz.',
      );
    }

    // Web / desktop.
    late final Uint8List input;
    if (raw.isNotEmpty) {
      input = raw;
    } else if (!kIsWeb &&
        filePath != null &&
        filePath.isNotEmpty &&
        await File(filePath).exists()) {
      input = await File(filePath).readAsBytes();
    } else {
      input = Uint8List(0);
    }
    if (input.isEmpty) throw StateError('Imagem vazia.');
    final normalized = await UtilitariosPhotoService.normalizeForOcrFast(input);
    final flat = await SmartInputImageOcrService.recognizeFromGalleryBytes(
      bytes: normalized,
      filePath: filePath,
    );
    final structured = _paragraphsFromPlainText(flat);
    if (structured.plainText.trim().isEmpty) {
      throw StateError(
        'Nenhum texto encontrado na foto. Tente outro ângulo ou mais luz.',
      );
    }
    return UtilPhotoTextExtractResult(
      plainText: structured.plainText,
      paragraphs: structured.paragraphs,
      sourcePreview: normalized,
    );
  }

  static Future<({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  })> _runMlKitOnPath(String path) async {
    final rec = await _ensureLatinRecognizer();
    try {
      final recognized = await rec.processImage(
        InputImage.fromFilePath(path),
      );
      return _structureFromRecognized(recognized);
    } catch (_) {
      return (
        plainText: '',
        paragraphs: List<UtilPhotoTextParagraph>.empty(),
      );
    }
  }

  static Future<({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  })> _runMlKitOnBytes(Uint8List jpeg) async {
    final rec = await _ensureLatinRecognizer();
    final tmp = await _writeTempJpegFast(jpeg);
    try {
      final recognized = await rec.processImage(
        InputImage.fromFilePath(tmp.path),
      );
      return _structureFromRecognized(recognized);
    } catch (_) {
      return (
        plainText: '',
        paragraphs: List<UtilPhotoTextParagraph>.empty(),
      );
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  static ({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  }) _structureFromRecognized(RecognizedText recognized) {
    final cleaned = _cleanDocumentOcrText(
      SmartInputOcrRecognizedPostprocess.apply(recognized.text),
    );
    if (cleaned.isEmpty) {
      return (
        plainText: '',
        paragraphs: List<UtilPhotoTextParagraph>.empty(),
      );
    }

    final blocks = recognized.blocks.toList()
      ..sort((a, b) {
        final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
        if (dy != 0) return dy;
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });

    final paragraphs = <UtilPhotoTextParagraph>[];
    final buf = StringBuffer();
    for (final block in blocks) {
      final lines = block.lines.toList()
        ..sort((a, b) {
          final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
          if (dy != 0) return dy;
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        });
      final lineTexts = lines
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty && !OcrDescriptionSanity.looksLikeOcrNoise(t))
          .toList();
      if (lineTexts.isEmpty) continue;
      final para = lineTexts.join(' ');
      if (OcrDescriptionSanity.looksLikeOcrNoise(para)) continue;
      final heading = UtilitariosLocalService.looksLikeDocumentHeading(para);
      paragraphs.add(
        UtilPhotoTextParagraph(text: para, isHeading: heading),
      );
      if (buf.isNotEmpty) buf.writeln();
      buf.write(para);
    }

    final plain = buf.toString().trim();
    if (plain.isNotEmpty) {
      return (plainText: plain, paragraphs: paragraphs);
    }
    return _paragraphsFromPlainText(cleaned);
  }

  static String _cleanDocumentOcrText(String text) {
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (t.isEmpty) return t;
    t = t.replaceAll(RegExp(r'[|¦‖]{2,}'), ' ');
    t = t.replaceAll(RegExp(r'[=+\-]{4,}'), '\n');
    t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  static ({
    String plainText,
    List<UtilPhotoTextParagraph> paragraphs,
  }) _paragraphsFromPlainText(String text) {
    final trimmed = _cleanDocumentOcrText(text);
    if (trimmed.isEmpty) {
      return (plainText: '', paragraphs: const []);
    }
    final parts = trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim())
        .where((p) => p.isNotEmpty && !OcrDescriptionSanity.looksLikeOcrNoise(p))
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

  /// Preview leve depois do OCR (não entra no hot path).
  static Future<Uint8List?> loadPreviewBytes(String path) async {
    if (kIsWeb || path.isEmpty) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<File> _writeTempJpegFast(Uint8List jpeg) async {
    final dir = await getTemporaryDirectory();
    final f = File(
      '${dir.path}/ct_text_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await f.writeAsBytes(jpeg, flush: false);
    return f;
  }

  static Uint8List buildDocx(List<UtilPhotoTextParagraph> paragraphs) {
    return UtilitariosLocalService.buildFormattedDocxFromParagraphs(
      paragraphs
          .where((p) => p.text.trim().isNotEmpty)
          .map(
            (p) => (
              text: p.isBullet ? '• ${p.text.trim()}' : p.text.trim(),
              isHeading: p.isHeading,
              isBold: p.isBold && !p.isHeading,
            ),
          )
          .toList(),
    );
  }

  static Future<Uint8List> buildPdf(List<UtilPhotoTextParagraph> paragraphs) =>
      UtilitariosLocalService.plainTextToFormattedPdf(
        paragraphs
            .where((p) => p.text.trim().isNotEmpty)
            .map(
              (p) => (
                text: p.isBullet ? '• ${p.text.trim()}' : p.text.trim(),
                isHeading: p.isHeading,
                isBold: p.isBold && !p.isHeading,
              ),
            )
            .toList(),
      );

  static Future<Uint8List> buildPdfPlain(String plainText) =>
      UtilitariosLocalService.plainTextToPdf(plainText);
}
