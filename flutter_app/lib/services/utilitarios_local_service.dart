import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' hide PdfDocument, PdfRect;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'package:gestao_yahweh/services/relatorio_service.dart';
import 'package:gestao_yahweh/services/smart_input_image_ocr_service.dart';
import 'package:gestao_yahweh/constants/utilitarios_export_page_format.dart';

/// Anotação no editor PDF (exportada achatada no PDF final).
class UtilPdfPageAnnotation {
  const UtilPdfPageAnnotation({
    required this.id,
    required this.type,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
    this.text = '',
    this.argb = 0xFFFFF59D,
    this.textArgb = 0xFF1E293B,
    this.fontScale = 1.0,
    this.fontBold = false,
    this.seamless = false,
  });

  /// `text` | `highlight` | `check` | `whiteout`
  final String id;
  final String type;
  final double nx;
  final double ny;
  final double nw;
  final double nh;
  final String text;
  final int argb;
  final int textArgb;
  final double fontScale;
  final bool fontBold;

  /// Exportação integrada ao fundo (sem caixa branca visível).
  final bool seamless;

  UtilPdfPageAnnotation copyWith({
    String? id,
    String? type,
    double? nx,
    double? ny,
    double? nw,
    double? nh,
    String? text,
    int? argb,
    int? textArgb,
    double? fontScale,
    bool? fontBold,
    bool? seamless,
  }) {
    return UtilPdfPageAnnotation(
      id: id ?? this.id,
      type: type ?? this.type,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      nw: nw ?? this.nw,
      nh: nh ?? this.nh,
      text: text ?? this.text,
      argb: argb ?? this.argb,
      textArgb: textArgb ?? this.textArgb,
      fontScale: fontScale ?? this.fontScale,
      fontBold: fontBold ?? this.fontBold,
      seamless: seamless ?? this.seamless,
    );
  }
}

/// Campo de texto detectado no documento (PDF embutido ou OCR).
class UtilPdfTextField {
  const UtilPdfTextField({
    required this.id,
    required this.text,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
    this.source = 'pdf',
    this.textArgb = 0xFF1E293B,
    this.fontBold = false,
  });

  final String id;
  final String text;
  final double nx;
  final double ny;
  final double nw;
  final double nh;

  /// `pdf` (texto selecionável) ou `ocr` (scan).
  final String source;

  /// Cor detectada no documento original (ARGB).
  final int textArgb;

  /// Negrito detectado no documento original.
  final bool fontBold;

  UtilPdfTextField copyWith({
    String? id,
    String? text,
    double? nx,
    double? ny,
    double? nw,
    double? nh,
    String? source,
    int? textArgb,
    bool? fontBold,
  }) {
    return UtilPdfTextField(
      id: id ?? this.id,
      text: text ?? this.text,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      nw: nw ?? this.nw,
      nh: nh ?? this.nh,
      source: source ?? this.source,
      textArgb: textArgb ?? this.textArgb,
      fontBold: fontBold ?? this.fontBold,
    );
  }
}

/// Nível de compressão Smart — Baixa / Média / Alta (perceptual, não só qualidade baixa).
enum UtilitariosCompressLevel {
  /// Quase original — leve redução.
  baixa,

  /// Smart equilíbrio — metade do tamanho típico.
  media,

  /// Ultra Smart — máxima redução mantendo nitidez perceptual.
  alta,
}

extension UtilitariosCompressLevelX on UtilitariosCompressLevel {
  String get label => switch (this) {
        UtilitariosCompressLevel.baixa => 'Baixa',
        UtilitariosCompressLevel.media => 'Média',
        UtilitariosCompressLevel.alta => 'Alta',
      };

  String get subtitle => switch (this) {
        UtilitariosCompressLevel.baixa =>
          'Quase original · ~15–25% menor (imagem, PDF, MP4)',
        UtilitariosCompressLevel.media =>
          'Smart Compress · ~40–55% menor · recomendado',
        UtilitariosCompressLevel.alta =>
          'Ultra Smart · até ~80% menor · nitidez recuperada',
      };

  /// Resumo técnico exibido na UI do compressor.
  String get techSummary => switch (this) {
        UtilitariosCompressLevel.baixa =>
          'Imagem até 2K · PDF legível · vídeo até 1080p',
        UtilitariosCompressLevel.media =>
          'Resize + sharpen Smart · PDF otimizado · vídeo 900p',
        UtilitariosCompressLevel.alta =>
          'Máxima redução · sharpen forte · vídeo 720p preset slow',
      };

  /// Faixa estimada de redução (UI).
  String get reductionBadge => switch (this) {
        UtilitariosCompressLevel.baixa => 'Leve',
        UtilitariosCompressLevel.media => 'Smart',
        UtilitariosCompressLevel.alta => 'Ultra',
      };

  /// JPEG 1–100 — Alta usa qualidade moderada + resize + nitidez (não “bloco”).
  int get jpegQuality => switch (this) {
        UtilitariosCompressLevel.baixa => 84,
        UtilitariosCompressLevel.media => 72,
        UtilitariosCompressLevel.alta => 58,
      };

  /// JPEG dedicado para páginas PDF (texto legível mesmo em Alta).
  int get pdfPageJpegQuality => switch (this) {
        UtilitariosCompressLevel.baixa => 82,
        UtilitariosCompressLevel.media => 70,
        UtilitariosCompressLevel.alta => 60,
      };

  int get maxSide => switch (this) {
        UtilitariosCompressLevel.baixa => 2048,
        UtilitariosCompressLevel.media => 1440,
        UtilitariosCompressLevel.alta => 960,
      };

  /// Largura de render do PDF — Alta mais agressiva, com JPEG + sharpen compensando.
  double get pdfRenderWidth => switch (this) {
        UtilitariosCompressLevel.baixa => 1100,
        UtilitariosCompressLevel.media => 820,
        UtilitariosCompressLevel.alta => 580,
      };

  /// Nitidez perceptual pós-redimensionamento (0–1).
  double get sharpenStrength => switch (this) {
        UtilitariosCompressLevel.baixa => 0.12,
        UtilitariosCompressLevel.media => 0.34,
        UtilitariosCompressLevel.alta => 0.55,
      };

  String get fileSuffix => switch (this) {
        UtilitariosCompressLevel.baixa => 'baixa',
        UtilitariosCompressLevel.media => 'media',
        UtilitariosCompressLevel.alta => 'alta',
      };
}

/// Formato de compactação de arquivos (ZIP local; RAR = ZIP ultra no celular).
enum UtilitariosArchiveFormat {
  zip,
  zipMax,
  rar,
}

extension UtilitariosArchiveFormatX on UtilitariosArchiveFormat {
  String get label => switch (this) {
        UtilitariosArchiveFormat.zip => 'ZIP',
        UtilitariosArchiveFormat.zipMax => 'ZIP máximo',
        UtilitariosArchiveFormat.rar => 'RAR',
      };

  String get subtitle => switch (this) {
        UtilitariosArchiveFormat.zip =>
          'Rápido · compatível com tudo',
        UtilitariosArchiveFormat.zipMax =>
          'Menor tamanho · extensão .zip',
        UtilitariosArchiveFormat.rar =>
          'Ultra-compacto · .zip no celular (padrão universal)',
      };

  String get fileExtension => 'zip';

  String get mimeType => 'application/zip';
}

/// Conversões e compressão **100% locais** (sem upload / Firebase Storage).
///
/// Trabalho pesado de imagem/ZIP/DOCX roda em [compute] (isolate) para não
/// travar a UI. PDF (pdfrx) fica no isolate principal com yields entre páginas.
abstract final class UtilitariosLocalService {
  UtilitariosLocalService._();

  static bool _pdfrxReady = false;

  /// Limites defensivos — evita OOM / travamento em PDFs/fotos grandes.
  static const int kMaxPdfPagesRender = 15;
  static const int kMaxPdfPagesCompress = 20;
  /// Dividir / juntar / editor PDF — até 100 páginas (miniaturas progressivas).
  static const int kMaxPdfPagesTools = 100;
  static const int kMaxPdfPagesText = 30;
  static const int kMaxImagesPerPdf = 20;
  static const int kMaxInputBytes = 28 * 1024 * 1024; // 28 MB
  /// Total ao compactar vários arquivos em ZIP/RAR (local).
  static const int kMaxArchiveTotalBytes = 96 * 1024 * 1024; // 96 MB
  static const int kMaxArchiveFileCount = 40;
  /// Vídeos MP4/MOV — leitura por path (sem carregar tudo na RAM).
  static const int kMaxVideoInputBytes = 500 * 1024 * 1024; // 500 MB
  static const double kPdfRenderWidth = 900;
  static const double kPdfCompressWidth = 780;

  /// Scanner — preview rápido na UI; export final em A4 (~2800 px, rápido e nítido).
  static const int kScanPreviewMaxSide = 1100;
  static const int kScanThumbMaxSide = 900;
  static const int kScanWorkMaxSide = 2000;
  static const int kScanExportMaxSide = 2800;
  static const int kScanPreviewJpegQuality = 82;
  static const int kScanWorkJpegQuality = 86;
  static const int kScanExportJpegQuality = 92;

  static Future<void> _ensurePdfrx() async {
    if (_pdfrxReady) return;
    await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
    _pdfrxReady = true;
  }

  static void ensureWithinSize(Uint8List bytes, {String label = 'Arquivo'}) {
    if (bytes.lengthInBytes > kMaxInputBytes) {
      throw StateError(
        '$label muito grande (máx. ~28 MB). Comprima antes ou use menos páginas.',
      );
    }
  }

  static Future<void> ensureVideoFileWithinSize(
    String path, {
    String label = 'Vídeo',
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('$label não encontrado.');
    }
    final size = await file.length();
    if (size > kMaxVideoInputBytes) {
      throw StateError(
        '$label muito grande (máx. ~500 MB). Use um arquivo menor.',
      );
    }
  }

  static Future<void> _yieldUi() => Future<void>.delayed(Duration.zero);

  /// JPEG/PNG → PDF (1 página por imagem) — encode em isolate.
  /// [level] controla qualidade/tamanho. Conversões usam [baixa]; compressor passa Média/Alta.
  static Future<Uint8List> imagesToPdf(
    List<Uint8List> images, {
    UtilitariosCompressLevel level = UtilitariosCompressLevel.baixa,
  }) async {
    if (images.isEmpty) throw StateError('Selecione ao menos uma imagem.');
    if (images.length > kMaxImagesPerPdf) {
      throw StateError(
        'No máximo $kMaxImagesPerPdf imagens por vez (mais rápido e estável).',
      );
    }
    for (final raw in images) {
      ensureWithinSize(raw, label: 'Imagem');
    }
    return compute(
      _imagesToPdfIsolate,
      _ImagesToPdfArgs(images: images, level: level),
    );
  }

  /// Compressor de imagem (JPEG mais leve) — isolate.
  /// Use [level] (Baixa/Média/Alta) ou [quality]/[maxSide] manuais.
  static Future<Uint8List> compressImage(
    Uint8List raw, {
    UtilitariosCompressLevel level = UtilitariosCompressLevel.media,
    int? quality,
    int? maxSide,
    double? sharpenStrength,
  }) async {
    ensureWithinSize(raw, label: 'Imagem');
    return compute(
      _compressImageIsolate,
      _CompressImageArgs(
        raw: raw,
        quality: quality ?? level.jpegQuality,
        maxSide: maxSide ?? level.maxSide,
        sharpenStrength: sharpenStrength ?? level.sharpenStrength,
      ),
    );
  }

  /// Modo de tratamento da página do scanner (CamScanner).
  static const String scanModeDocument = 'document';
  static const String scanModeColor = 'color';
  static const String scanModeOriginal = 'original';
  /// Cores vivas + limpeza de sombra (papel amassado/sujo) — padrão do scanner.
  static const String scanModeVivid = 'vivid';

  /// Scanner estilo CamScanner: enquadra + limpa (documento) ou coloriza.
  /// 100% local, em isolate — não trava a UI.
  /// [skipAutoCrop]: use `true` quando o recorte manual já foi aplicado.
  /// [exportQuality]: monta A4 limpo em alta resolução (~4K) ao confirmar página.
  static Future<Uint8List> enhanceScanPage(
    Uint8List raw, {
    String mode = scanModeDocument,
    bool skipAutoCrop = false,
    int? maxSide,
    int? jpegQuality,
    bool exportQuality = false,
    bool previewOnly = false,
  }) async {
    ensureWithinSize(raw, label: 'Foto do scanner');
    final side = maxSide ??
        (exportQuality ? kScanExportMaxSide : kScanPreviewMaxSide);
    final quality = jpegQuality ??
        (exportQuality ? kScanExportJpegQuality : kScanPreviewJpegQuality);
    return compute(
      _enhanceScanPageIsolate,
      _EnhanceScanArgs(
        raw: raw,
        mode: mode,
        skipAutoCrop: skipAutoCrop,
        maxSide: side,
        jpegQuality: quality,
        exportA4: exportQuality,
        previewOnly: previewOnly,
      ),
    );
  }

  /// Detecta enquadramento automático (normalizado 0–1 sobre a foto).
  static Future<({double nx, double ny, double nw, double nh})> detectScanCropRect(
    Uint8List raw,
  ) async {
    ensureWithinSize(raw, label: 'Foto do scanner');
    final r = await compute(_detectScanCropNormIsolate, raw);
    return (nx: r[0], ny: r[1], nw: r[2], nh: r[3]);
  }

  /// Recorta a foto pelo retângulo normalizado (0–1).
  static Future<Uint8List> cropScanImageNormalized(
    Uint8List raw, {
    required double nx,
    required double ny,
    required double nw,
    required double nh,
  }) async {
    ensureWithinSize(raw, label: 'Foto do scanner');
    return compute(
      _cropScanNormIsolate,
      _CropScanNormArgs(nx: nx, ny: ny, nw: nw, nh: nh, raw: raw),
    );
  }

  /// Captura scanner em um único isolate: prepara original + crop + preview limpo (rápido).
  static Future<
      ({
        Uint8List original,
        double nx,
        double ny,
        double nw,
        double nh,
        Uint8List preview,
      })> prepareScanCapture(
    Uint8List raw, {
    String mode = scanModeDocument,
  }) async {
    ensureWithinSize(raw, label: 'Foto do scanner');
    final r = await compute(
      _prepareScanCaptureIsolate,
      _PrepareScanCaptureArgs(raw: raw, mode: mode),
    );
    return (
      original: r.original,
      nx: r.crop[0],
      ny: r.crop[1],
      nw: r.crop[2],
      nh: r.crop[3],
      preview: r.preview,
    );
  }

  /// Fase 1 ultra-rápida: enquadramento imediato (sem limpeza pesada) — estilo CamScanner.
  static Future<
      ({
        Uint8List original,
        double nx,
        double ny,
        double nw,
        double nh,
        Uint8List thumb,
      })> prepareScanFrame(Uint8List raw) async {
    ensureWithinSize(raw, label: 'Foto do scanner');
    final r = await compute(_prepareScanFrameIsolate, raw);
    return (
      original: r.original,
      nx: r.crop[0],
      ny: r.crop[1],
      nw: r.crop[2],
      nh: r.crop[3],
      thumb: r.thumb,
    );
  }

  /// Recorte + preview em um isolate (troca de modo / enquadramento).
  static Future<Uint8List> rebuildScanPreview(
    Uint8List original, {
    required double nx,
    required double ny,
    required double nw,
    required double nh,
    String mode = scanModeDocument,
  }) async {
    ensureWithinSize(original, label: 'Foto do scanner');
    return compute(
      _rebuildScanPreviewIsolate,
      _RebuildScanPreviewArgs(
        original: original,
        nx: nx,
        ny: ny,
        nw: nw,
        nh: nh,
        mode: mode,
      ),
    );
  }

  /// Export final da página (A4) em um isolate.
  static Future<Uint8List> buildScanExport(
    Uint8List original, {
    required double nx,
    required double ny,
    required double nw,
    required double nh,
    String mode = scanModeDocument,
  }) async {
    ensureWithinSize(original, label: 'Foto do scanner');
    return compute(
      _buildScanExportIsolate,
      _RebuildScanPreviewArgs(
        original: original,
        nx: nx,
        ny: ny,
        nw: nw,
        nh: nh,
        mode: mode,
        exportQuality: true,
      ),
    );
  }

  /// Várias páginas do scanner — processa uma a uma com yield na UI.
  static Future<List<Uint8List>> enhanceScanPages(
    List<Uint8List> pages, {
    String mode = scanModeDocument,
  }) async {
    if (pages.isEmpty) return const [];
    final out = <Uint8List>[];
    for (final page in pages) {
      await _yieldUi();
      out.add(await enhanceScanPage(page, mode: mode));
    }
    return out;
  }

  /// Formato de imagem na exportação PDF → imagem.
  static const String imageFormatJpeg = 'jpeg';
  static const String imageFormatPng = 'png';

  /// PDF → imagens (JPEG ou PNG), até [maxPages] páginas.
  static Future<List<Uint8List>> pdfToImages(
    Uint8List pdfBytes, {
    int maxPages = kMaxPdfPagesRender,
    double fullWidth = kPdfRenderWidth,
    String format = imageFormatJpeg,
  }) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    final asPng = format == imageFormatPng;
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      final total = doc.pages.length;
      final n = total > maxPages ? maxPages : total;
      if (n <= 0) throw StateError('PDF sem páginas.');
      final out = <Uint8List>[];
      for (var i = 0; i < n; i++) {
        await _yieldUi();
        final page = doc.pages[i];
        final loaded =
            await page.waitForLoaded(timeout: const Duration(seconds: 12));
        final p = loaded ?? page;
        final pageImg = await p.render(fullWidth: fullWidth);
        if (pageImg == null) continue;
        try {
          final encoded = await compute(
            _encodePageIsolate,
            _EncodePageArgs(
              width: pageImg.width,
              height: pageImg.height,
              pixels: Uint8List.fromList(pageImg.pixels),
              asPng: asPng,
              jpegQuality: asPng ? 100 : 82,
            ),
          );
          out.add(encoded);
        } finally {
          pageImg.dispose();
        }
      }
      if (out.isEmpty) throw StateError('Não foi possível renderizar o PDF.');
      return out;
    } finally {
      await doc.dispose();
    }
  }

  /// PDF → JPEG (atalho).
  static Future<List<Uint8List>> pdfToJpegs(
    Uint8List pdfBytes, {
    int maxPages = kMaxPdfPagesRender,
    double fullWidth = kPdfRenderWidth,
  }) =>
      pdfToImages(
        pdfBytes,
        maxPages: maxPages,
        fullWidth: fullWidth,
        format: imageFormatJpeg,
      );

  /// PDF → PNG (atalho).
  static Future<List<Uint8List>> pdfToPngs(
    Uint8List pdfBytes, {
    int maxPages = kMaxPdfPagesRender,
    double fullWidth = kPdfRenderWidth,
  }) =>
      pdfToImages(
        pdfBytes,
        maxPages: maxPages,
        fullWidth: fullWidth,
        format: imageFormatPng,
      );

  /// Extrai texto do PDF (local) para gerar Word editável.
  static Future<String> pdfExtractText(Uint8List pdfBytes) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      final buf = StringBuffer();
      final total = doc.pages.length;
      final n = total > kMaxPdfPagesText ? kMaxPdfPagesText : total;
      for (var i = 0; i < n; i++) {
        await _yieldUi();
        final page = doc.pages[i];
        final loaded =
            await page.waitForLoaded(timeout: const Duration(seconds: 10));
        final p = loaded ?? page;
        final text = await p.loadText();
        final full = text?.fullText.trim() ?? '';
        if (full.isNotEmpty) {
          buf.writeln(full);
          buf.writeln();
        }
      }
      final s = buf.toString().trim();
      if (s.isEmpty) {
        return 'Documento convertido no GestÃ£o Yahweh.\n'
            'Este PDF não possui texto selecionável (pode ser imagem/scan).\n'
            'Use «PDF → JPEG» ou «PDF → PNG» para obter as páginas em imagem.';
      }
      return s;
    } finally {
      await doc.dispose();
    }
  }

  /// PDF → DOCX com parágrafos, títulos e tabelas preservados (layout local).
  static Future<Uint8List> pdfToDocx(Uint8List pdfBytes) async {
    final doc = await _pdfExtractStructuredDocument(pdfBytes);
    return compute(_buildFormattedDocxIsolate, doc);
  }

  /// PDF → Excel (XLSX): linhas/colunas e tabelas alinhadas ao documento.
  static Future<Uint8List> pdfToXlsx(Uint8List pdfBytes) async {
    final doc = await _pdfExtractStructuredDocument(pdfBytes);
    return compute(_buildFormattedXlsxIsolate, doc);
  }

  /// PDF → PowerPoint (PPTX): cada página do PDF vira um slide (imagem).
  static Future<Uint8List> pdfToPptx(Uint8List pdfBytes) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    // Largura moderada = rápido na web e JPEG estável no PowerPoint.
    final pages = await pdfToJpegs(
      pdfBytes,
      maxPages: kMaxPdfPagesRender,
      fullWidth: kIsWeb ? 900 : 1100,
    );
    if (pages.isEmpty) {
      throw StateError('PDF sem páginas para gerar PowerPoint.');
    }
    // Garante JPEG real (PowerPoint rejeita PNG renomeado / bytes vazios).
    final safe = <Uint8List>[];
    for (final p in pages) {
      if (p.length < 32) continue;
      if (p[0] == 0xFF && p[1] == 0xD8) {
        safe.add(p);
        continue;
      }
      // Reencode se não for JPEG.
      final decoded = img.decodeImage(p);
      if (decoded == null) continue;
      safe.add(Uint8List.fromList(img.encodeJpg(decoded, quality: 85)));
    }
    if (safe.isEmpty) {
      throw StateError(
        'Não foi possível renderizar as páginas do PDF para PowerPoint.',
      );
    }
    return compute(_buildMinimalPptxFromImagesIsolate, safe);
  }

  /// Excel (XLSX/CSV) → PDF (tabela local).
  static Future<Uint8List> excelToPdf(
    Uint8List bytes,
    String fileName,
  ) async {
    ensureWithinSize(bytes, label: 'Planilha');
    final lower = fileName.toLowerCase();
    final rows = await compute(
      _excelRowsIsolate,
      _DocumentTextArgs(bytes: bytes, fileName: lower),
    );
    final theme = await RelatorioService.latinPdfThemeForExport();
    return _rowsToPdfWithTheme(rows, theme);
  }

  /// DOCX/TXT/RTF → PDF (texto local, fonte Noto com acentos pt-BR).
  static Future<Uint8List> documentToPdf(
    Uint8List bytes,
    String fileName,
  ) async {
    ensureWithinSize(bytes, label: 'Documento');
    final lower = fileName.toLowerCase();
    final text = await compute(
      _documentTextIsolate,
      _DocumentTextArgs(bytes: bytes, fileName: lower),
    );
    // Tema Noto no isolate principal (fonte não serializa bem no compute).
    final theme = await RelatorioService.latinPdfThemeForExport();
    return _textToPdfWithTheme(text, theme);
  }

  static String extractTextFromDocx(Uint8List bytes) =>
      _extractTextFromDocxSync(bytes);

  /// DOCX OOXML mínimo válido (abre no Word / Google Docs / LibreOffice).
  static Uint8List buildMinimalDocx(String plainText) =>
      _buildMinimalDocxIsolate(plainText);

  /// Parágrafos com títulos/negrito → DOCX formatado (exportação Controletotalapp).
  static Uint8List buildFormattedDocxFromParagraphs(
    List<({String text, bool isHeading, bool isBold})> paragraphs,
  ) {
    final blocks = paragraphs
        .where((p) => p.text.trim().isNotEmpty)
        .map(
          (p) => _PdfExportBlock(
            kind: p.isHeading ? 'heading' : 'paragraph',
            text: p.text.trim(),
            bold: p.isBold,
          ),
        )
        .toList();
    return _buildFormattedDocxIsolate(
      _PdfExportDocument(
        blocks: blocks,
        plainFallback: paragraphs.map((p) => p.text).join('\n\n'),
      ),
    );
  }

  /// Texto com parágrafos formatados → PDF A4.
  static Future<Uint8List> plainTextToFormattedPdf(
    List<({String text, bool isHeading, bool isBold})> paragraphs,
  ) async {
    final theme = await RelatorioService.latinPdfThemeForExport();
    return _formattedParagraphsToPdf(paragraphs, theme);
  }

  /// Texto puro → PDF A4 com fonte Noto (acentos pt-BR).
  static Future<Uint8List> plainTextToPdf(String plainText) async {
    final theme = await RelatorioService.latinPdfThemeForExport();
    return _textToPdfWithTheme(plainText, theme);
  }

  /// Detecta linha curta em caixa alta como possível título.
  static bool looksLikeDocumentHeading(String text) => _pdfLooksLikeHeading(text);

  /// Empacota várias páginas de imagem em ZIP (local) — isolate.
  static Future<Uint8List> zipImages(
    List<Uint8List> pages,
    String stem, {
    String extension = 'jpg',
  }) {
    return compute(
      _zipImagesIsolate,
      _ZipImagesArgs(pages: pages, stem: stem, extension: extension),
    );
  }

  /// Atalho legado — ZIP de JPEGs.
  static Future<Uint8List> zipJpegs(List<Uint8List> pages, String stem) =>
      zipImages(pages, stem, extension: 'jpg');

  /// Compacta um ou vários arquivos em ZIP (rápido, máximo ou estilo RAR=ZIP max).
  static Future<Uint8List> archivePlatformFiles(
    List<({String name, Uint8List bytes})> files, {
    UtilitariosArchiveFormat format = UtilitariosArchiveFormat.zip,
  }) async {
    if (files.isEmpty) {
      throw StateError('Selecione ao menos um arquivo.');
    }
    if (files.length > kMaxArchiveFileCount) {
      throw StateError('Máximo de $kMaxArchiveFileCount arquivos por vez.');
    }
    var total = 0;
    for (final f in files) {
      ensureWithinSize(f.bytes, label: f.name);
      total += f.bytes.lengthInBytes;
      if (total > kMaxArchiveTotalBytes) {
        throw StateError(
          'Total muito grande (máx. ~96 MB). Remova alguns arquivos.',
        );
      }
    }
    return compute(
      _archiveFilesIsolate,
      _ArchiveFilesArgs(files: files, format: format),
    );
  }

  /// Comprime PDF re-renderizando páginas (local) — [level]: Baixa / Média / Alta.
  /// Média/Alta reduzem de verdade (render menor + JPEG forte + PDF final alinhado).
  static Future<Uint8List> compressPdf(
    Uint8List pdfBytes, {
    UtilitariosCompressLevel level = UtilitariosCompressLevel.media,
  }) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    final pages = await pdfToJpegs(
      pdfBytes,
      maxPages: kMaxPdfPagesCompress,
      fullWidth: level.pdfRenderWidth,
    );
    final compressed = <Uint8List>[];
    for (final page in pages) {
      await _yieldUi();
      compressed.add(
        await compressImage(
          page,
          quality: level.pdfPageJpegQuality,
          maxSide: level.maxSide,
          sharpenStrength: level.sharpenStrength,
        ),
      );
    }
    // Mesmo nível no PDF final — evita re-encode “gordo” que desfaz a compressão.
    return imagesToPdf(compressed, level: level);
  }

  /// Conta páginas do PDF (local).
  static Future<int> pdfPageCount(Uint8List pdfBytes) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  /// Renderiza várias páginas reutilizando o mesmo documento (bem mais rápido).
  static Future<Map<int, Uint8List>> renderPdfPagesAt(
    Uint8List pdfBytes,
    Iterable<int> pageIndices, {
    double fullWidth = kPdfRenderWidth,
    int jpegQuality = 82,
  }) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    final out = <int, Uint8List>{};
    try {
      await doc.loadPagesProgressively();
      final len = doc.pages.length;
      for (final pageIndex in pageIndices) {
        if (pageIndex < 0 || pageIndex >= len) continue;
        await _yieldUi();
        final page = doc.pages[pageIndex];
        final loaded =
            await page.waitForLoaded(timeout: const Duration(seconds: 12));
        final p = loaded ?? page;
        final pageImg = await p.render(fullWidth: fullWidth);
        if (pageImg == null) continue;
        try {
          out[pageIndex] = await compute(
            _encodePageIsolate,
            _EncodePageArgs(
              width: pageImg.width,
              height: pageImg.height,
              pixels: Uint8List.fromList(pageImg.pixels),
              asPng: false,
              jpegQuality: jpegQuality,
            ),
          );
        } finally {
          pageImg.dispose();
        }
      }
    } finally {
      await doc.dispose();
    }
    return out;
  }

  /// Renderiza uma página do PDF (índice 0-based).
  static Future<Uint8List> renderPdfPageAt(
    Uint8List pdfBytes,
    int pageIndex, {
    double fullWidth = kPdfRenderWidth,
  }) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      if (pageIndex < 0 || pageIndex >= doc.pages.length) {
        throw StateError('Página ${pageIndex + 1} não existe no PDF.');
      }
      final page = doc.pages[pageIndex];
      final loaded =
          await page.waitForLoaded(timeout: const Duration(seconds: 12));
      final p = loaded ?? page;
      final pageImg = await p.render(fullWidth: fullWidth);
      if (pageImg == null) {
        throw StateError('Não foi possível renderizar a página ${pageIndex + 1}.');
      }
      try {
        return await compute(
          _encodePageIsolate,
          _EncodePageArgs(
            width: pageImg.width,
            height: pageImg.height,
            pixels: Uint8List.fromList(pageImg.pixels),
            asPng: false,
            jpegQuality: 86,
          ),
        );
      } finally {
        pageImg.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }

  /// Miniaturas de todas as páginas (UI de merge/split/editor).
  static Future<List<Uint8List>> pdfPageThumbnails(
    Uint8List pdfBytes, {
    int maxPages = kMaxPdfPagesCompress,
    double fullWidth = 520,
  }) =>
      pdfToImages(
        pdfBytes,
        maxPages: maxPages,
        fullWidth: fullWidth,
        format: imageFormatJpeg,
      );

  /// Une páginas na ordem escolhida (vários PDFs → 1 PDF).
  static Future<Uint8List> mergeOrderedPdfPages(
    List<({Uint8List pdf, int pageIndex})> order,
  ) async {
    if (order.isEmpty) throw StateError('Selecione ao menos uma página.');
    if (order.length > kMaxPdfPagesTools) {
      throw StateError(
        'Máximo de $kMaxPdfPagesTools páginas por união (limite local).',
      );
    }
    final images = <Uint8List>[];
    for (final item in order) {
      await _yieldUi();
      images.add(
        await renderPdfPageAt(item.pdf, item.pageIndex),
      );
    }
    return imagesToPdf(images);
  }

  /// Divide PDF: páginas selecionadas → 1 PDF ou ZIP (1 PDF por página).
  static Future<({Uint8List bytes, String fileName, String mime})> splitPdfPages(
    Uint8List pdfBytes,
    List<int> pageIndices, {
    required bool onePdfPerPage,
  }) async {
    if (pageIndices.isEmpty) {
      throw StateError('Selecione ao menos uma página para dividir.');
    }
    if (pageIndices.length > kMaxPdfPagesTools) {
      throw StateError(
        'Máximo de $kMaxPdfPagesTools páginas por divisão.',
      );
    }
    final ordered = <int>[];
    for (final i in pageIndices) {
      if (i < 0) continue;
      if (!ordered.contains(i)) ordered.add(i);
    }
    if (ordered.isEmpty) {
      throw StateError('Selecione ao menos uma página para dividir.');
    }
    if (onePdfPerPage && ordered.length > 1) {
      final rendered = await renderPdfPagesAt(pdfBytes, ordered);
      final pdfs = <Uint8List>[];
      for (final i in ordered) {
        final img = rendered[i];
        if (img == null) {
          throw StateError('Não foi possível renderizar a página ${i + 1}.');
        }
        pdfs.add(await imagesToPdf([img]));
      }
      final zip = await zipImages(pdfs, 'pagina', extension: 'pdf');
      return (
        bytes: zip,
        fileName: 'pdf_dividido_controle_total.zip',
        mime: 'application/zip',
      );
    }
    final rendered = await renderPdfPagesAt(pdfBytes, ordered);
    final images = <Uint8List>[];
    for (final i in ordered) {
      final img = rendered[i];
      if (img == null) {
        throw StateError('Não foi possível renderizar a página ${i + 1}.');
      }
      images.add(img);
    }
    return (
      bytes: await imagesToPdf(images),
      fileName: 'pdf_dividido_controle_total.pdf',
      mime: 'application/pdf',
    );
  }

  /// Aplica anotações (texto, destaque, check) sobre a página e devolve JPEG.
  static Future<Uint8List> flattenPdfPageWithAnnotations(
    Uint8List pageJpeg,
    List<UtilPdfPageAnnotation> annotations,
  ) async {
    if (annotations.isEmpty) return pageJpeg;
    return compute(
      _flattenPdfAnnotationsIsolate,
      _FlattenAnnotationsArgs(page: pageJpeg, items: annotations),
    );
  }

  /// Exporta páginas editadas (JPEG) para um PDF único.
  static Future<Uint8List> exportEditedPdfPages(
    List<Uint8List> pageJpegs,
  ) =>
      imagesToPdf(pageJpegs);

  /// Tamanho em pixels da página renderizada (mesma largura de [renderPdfPageAt]).
  static Future<({int width, int height})> pdfPageRenderPixelSize(
    Uint8List pdfBytes,
    int pageIndex, {
    double fullWidth = kPdfRenderWidth,
  }) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      if (pageIndex < 0 || pageIndex >= doc.pages.length) {
        throw StateError('Página ${pageIndex + 1} não existe no PDF.');
      }
      final page = doc.pages[pageIndex];
      final loaded =
          await page.waitForLoaded(timeout: const Duration(seconds: 12));
      final p = loaded ?? page;
      final w = fullWidth.round();
      final h = (fullWidth * p.height / p.width).round();
      return (width: w, height: h);
    } finally {
      await doc.dispose();
    }
  }

  /// Detecta campos editáveis na página (texto PDF + OCR em scan).
  static Future<List<UtilPdfTextField>> detectPdfPageTextFields(
    Uint8List pdfBytes,
    int pageIndex, {
    Uint8List? pageJpeg,
  }) async {
    final embedded = await _detectEmbeddedPdfTextFields(pdfBytes, pageIndex);
    List<UtilPdfTextField> fields;
    if (embedded.length >= 2) {
      fields = embedded;
    } else if (pageJpeg != null && pageJpeg.isNotEmpty) {
      final ocr = await _detectOcrTextFieldsFromJpeg(pageJpeg);
      fields = ocr.isNotEmpty ? ocr : embedded;
    } else {
      fields = embedded;
    }
    if (pageJpeg != null && pageJpeg.isNotEmpty && fields.isNotEmpty) {
      fields = enrichPdfTextFieldsWithVisualStyle(pageJpeg, fields);
    }
    return fields;
  }

  /// Amostra cor e negrito de cada campo a partir da página renderizada.
  static List<UtilPdfTextField> enrichPdfTextFieldsWithVisualStyle(
    Uint8List pageJpeg,
    List<UtilPdfTextField> fields,
  ) {
    final decoded = img.decodeImage(pageJpeg);
    if (decoded == null) return fields;
    return fields
        .map((f) {
          final style = _sampleFieldTextStyle(
            decoded,
            f.nx,
            f.ny,
            f.nw,
            f.nh,
            fontBoldHint: f.fontBold,
          );
          return f.copyWith(
            textArgb: style.textArgb,
            fontBold: style.fontBold,
          );
        })
        .toList();
  }

  static Future<List<UtilPdfTextField>> _detectEmbeddedPdfTextFields(
    Uint8List pdfBytes,
    int pageIndex,
  ) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    try {
      await doc.loadPagesProgressively();
      if (pageIndex < 0 || pageIndex >= doc.pages.length) return const [];
      final page = doc.pages[pageIndex];
      final loaded =
          await page.waitForLoaded(timeout: const Duration(seconds: 12));
      final p = loaded ?? page;
      final structured = await p.loadStructuredText();
      if (structured.fullText.trim().isEmpty) return const [];
      return _groupPdfFragmentsIntoFields(structured, p.width, p.height);
    } finally {
      await doc.dispose();
    }
  }

  static List<UtilPdfTextField> _groupPdfFragmentsIntoFields(
    PdfPageText pageText,
    double pageW,
    double pageH,
  ) {
    if (pageW <= 0 || pageH <= 0) return const [];
    final frags = pageText.fragments
        .where((f) => f.text.trim().length >= 2)
        .toList();
    if (frags.isEmpty) return const [];

    frags.sort((a, b) => b.bounds.top.compareTo(a.bounds.top));
    final lineThreshold = pageH * 0.018;
    final lines = <List<PdfPageTextFragment>>[];

    for (final f in frags) {
      var placed = false;
      for (final line in lines) {
        final ref = line.first;
        if ((f.bounds.bottom - ref.bounds.bottom).abs() <= lineThreshold) {
          line.add(f);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([f]);
    }

    final out = <UtilPdfTextField>[];
    var idx = 0;
    final lineHeights = <double>[];
    for (final line in lines) {
      line.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      PdfRect? merged;
      final sb = StringBuffer();
      for (final f in line) {
        merged = merged == null ? f.bounds : merged.merge(f.bounds);
        if (sb.isNotEmpty) sb.write(' ');
        sb.write(f.text.trim());
      }
      final text = sb.toString().trim();
      if (text.length < 2 || merged == null || merged.isEmpty) continue;
      final padX = pageW * 0.006;
      final padY = pageH * 0.004;
      final left = (merged.left - padX).clamp(0.0, pageW);
      final right = (merged.right + padX).clamp(0.0, pageW);
      final bottom = (merged.bottom - padY).clamp(0.0, pageH);
      final top = (merged.top + padY).clamp(0.0, pageH);
      final w = right - left;
      final h = top - bottom;
      if (w <= 0 || h <= 0) continue;
      lineHeights.add(h);
      out.add(
        UtilPdfTextField(
          id: 'pdf_$idx',
          text: text,
          nx: left / pageW,
          ny: (pageH - top) / pageH,
          nw: w / pageW,
          nh: h / pageH,
          source: 'pdf',
        ),
      );
      idx++;
    }
    if (out.isEmpty || lineHeights.isEmpty) return out;
    lineHeights.sort();
    final medianH = lineHeights[lineHeights.length ~/ 2];
    return out
        .map((f) {
          final pxH = f.nh * pageH;
          final bold = pxH >= medianH * 1.18;
          return f.copyWith(fontBold: bold);
        })
        .toList();
  }

  static Future<List<UtilPdfTextField>> _detectOcrTextFieldsFromJpeg(
    Uint8List jpeg,
  ) async {
    if (kIsWeb || !SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      return const [];
    }
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return const [];

    final tmp = File(
      'D:\\TEMPORARIOS\\util_pdf_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    TextRecognizer? rec;
    try {
      await tmp.parent.create(recursive: true);
      await tmp.writeAsBytes(jpeg, flush: true);
      rec = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await rec.processImage(InputImage.fromFilePath(tmp.path));
      final out = <UtilPdfTextField>[];
      var idx = 0;
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.length < 2) continue;
          final box = line.boundingBox;
          if (box.width <= 0 || box.height <= 0) continue;
          final pad = 4.0;
          final left = (box.left - pad).clamp(0.0, decoded.width.toDouble());
          final top = (box.top - pad).clamp(0.0, decoded.height.toDouble());
          final right =
              (box.right + pad).clamp(0.0, decoded.width.toDouble());
          final bottom =
              (box.bottom + pad).clamp(0.0, decoded.height.toDouble());
          final w = right - left;
          final h = bottom - top;
          if (w <= 0 || h <= 0) continue;
          out.add(
            UtilPdfTextField(
              id: 'ocr_$idx',
              text: t,
              nx: left / decoded.width,
              ny: top / decoded.height,
              nw: w / decoded.width,
              nh: h / decoded.height,
              source: 'ocr',
            ),
          );
          idx++;
        }
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      try {
        await rec?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Extrai documento estruturado (parágrafos, títulos, tabelas) do PDF.
  static Future<_PdfExportDocument> _pdfExtractStructuredDocument(
    Uint8List pdfBytes,
  ) async {
    ensureWithinSize(pdfBytes, label: 'PDF');
    await _ensurePdfrx();
    final doc = await PdfDocument.openData(pdfBytes, sourceName: 'util.pdf');
    final blocks = <_PdfExportBlock>[];
    final plainBuf = StringBuffer();
    try {
      await doc.loadPagesProgressively();
      final total = doc.pages.length;
      final n = total > kMaxPdfPagesText ? kMaxPdfPagesText : total;
      for (var pi = 0; pi < n; pi++) {
        await _yieldUi();
        if (pi > 0) {
          blocks.add(const _PdfExportBlock(kind: 'pageBreak'));
        }
        final page = doc.pages[pi];
        final loaded =
            await page.waitForLoaded(timeout: const Duration(seconds: 10));
        final p = loaded ?? page;
        final structured = await p.loadStructuredText();
        if (structured.fullText.trim().isNotEmpty) {
          plainBuf.writeln(structured.fullText.trim());
          plainBuf.writeln();
        }
        if (structured.fragments.isNotEmpty) {
          blocks.addAll(_structuredPageToBlocks(structured, p.width, p.height));
          continue;
        }
        final plain = await p.loadText();
        final full = plain?.fullText.trim() ?? '';
        if (full.isNotEmpty) {
          plainBuf.writeln(full);
          plainBuf.writeln();
          for (final line in full.split('\n')) {
            final t = line.trim();
            if (t.isEmpty) continue;
            blocks.add(
              _PdfExportBlock(
                kind: _looksLikeHeading(t) ? 'heading' : 'paragraph',
                text: t,
              ),
            );
          }
        }
      }
    } finally {
      await doc.dispose();
    }

    final plain = plainBuf.toString().trim();
    if (blocks.isEmpty) {
      if (plain.isEmpty) {
        return _PdfExportDocument(
          blocks: const [],
          plainFallback:
              'Documento convertido no GestÃ£o Yahweh.\n'
              'Este PDF não possui texto selecionável (pode ser imagem/scan).\n'
              'Use «PDF → JPEG» ou «PDF → PNG» para obter as páginas em imagem.',
        );
      }
      final fallbackBlocks = plain
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map(
            (t) => _PdfExportBlock(
              kind: _looksLikeHeading(t) ? 'heading' : 'paragraph',
              text: t,
            ),
          )
          .toList();
      return _PdfExportDocument(blocks: fallbackBlocks, plainFallback: plain);
    }
    return _PdfExportDocument(blocks: blocks, plainFallback: plain);
  }

  static List<_PdfExportBlock> _structuredPageToBlocks(
    PdfPageText pageText,
    double pageW,
    double pageH,
  ) {
    if (pageW <= 0 || pageH <= 0) return const [];
    final frags = pageText.fragments
        .where((f) => f.text.trim().isNotEmpty)
        .toList();
    if (frags.isEmpty) return const [];

    frags.sort((a, b) => b.bounds.top.compareTo(a.bounds.top));
    final lineThreshold = pageH * 0.018;
    final lines = <List<PdfPageTextFragment>>[];

    for (final f in frags) {
      var placed = false;
      for (final line in lines) {
        final ref = line.first;
        if ((f.bounds.bottom - ref.bounds.bottom).abs() <= lineThreshold) {
          line.add(f);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([f]);
    }

    final rowCells = <List<String>>[];
    for (final line in lines) {
      line.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      rowCells.add(_fragmentsToCells(line, pageW));
    }
    return _rowCellsToBlocks(rowCells);
  }

  static List<String> _fragmentsToCells(
    List<PdfPageTextFragment> line,
    double pageW,
  ) {
    if (line.isEmpty) return const [];
    final gapThreshold = pageW * 0.022;
    final cells = <String>[];
    final sb = StringBuffer();
    PdfRect? prev;
    for (final f in line) {
      if (prev != null && (f.bounds.left - prev.right) > gapThreshold) {
        final t = sb.toString().trim();
        if (t.isNotEmpty) cells.add(t);
        sb.clear();
      }
      if (sb.isNotEmpty) sb.write(' ');
      sb.write(f.text.trim());
      prev = f.bounds;
    }
    final tail = sb.toString().trim();
    if (tail.isNotEmpty) cells.add(tail);
    return cells;
  }

  static List<_PdfExportBlock> _rowCellsToBlocks(List<List<String>> rowCells) {
    final blocks = <_PdfExportBlock>[];
    var i = 0;
    while (i < rowCells.length) {
      final cells = rowCells[i];
      if (cells.isEmpty) {
        i++;
        continue;
      }
      if (cells.length >= 2) {
        var j = i + 1;
        while (j < rowCells.length) {
          final next = rowCells[j];
          if (next.isEmpty) break;
          if (next.length < 2) break;
          if ((next.length - cells.length).abs() > 1) break;
          j++;
        }
        if (j - i >= 2) {
          blocks.add(
            _PdfExportBlock(
              kind: 'table',
              rows: _normalizeTableRows(rowCells.sublist(i, j)),
            ),
          );
          i = j;
          continue;
        }
      }
      final text = cells.join(cells.length > 1 ? ' · ' : ' ').trim();
      if (text.isNotEmpty) {
        blocks.add(
          _PdfExportBlock(
            kind: _looksLikeHeading(text) ? 'heading' : 'paragraph',
            text: text,
          ),
        );
      }
      i++;
    }
    return blocks;
  }

  static List<List<String>> _normalizeTableRows(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final maxCols = rows.map((r) => r.length).fold<int>(0, math.max);
    return rows
        .map((r) {
          final copy = List<String>.from(r);
          while (copy.length < maxCols) {
            copy.add('');
          }
          return copy;
        })
        .toList();
  }

  static bool _looksLikeHeading(String text) => _pdfLooksLikeHeading(text);
}

// ─── Isolates (funções top-level / estáticas serializáveis) ─────────────────

bool _pdfLooksLikeHeading(String text) {
  final s = text.trim();
  if (s.isEmpty || s.length > 90) return false;
  if (RegExp(r'^\d+[\.\)]\s').hasMatch(s)) return true;
  final letters = s.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (letters.length >= 4 && letters == letters.toUpperCase()) return true;
  return false;
}

class _CompressImageArgs {
  const _CompressImageArgs({
    required this.raw,
    required this.quality,
    required this.maxSide,
    this.sharpenStrength = 0,
  });
  final Uint8List raw;
  final int quality;
  final int maxSide;
  final double sharpenStrength;
}

Uint8List _compressImageIsolate(_CompressImageArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  var work = decoded;
  if (work.numChannels == 4) {
    final flat = img.Image(width: work.width, height: work.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, work);
    work = flat;
  }
  final maxDim = work.width > work.height ? work.width : work.height;
  if (maxDim > a.maxSide) {
    work = img.copyResize(
      work,
      width: work.width >= work.height ? a.maxSide : null,
      height: work.height > work.width ? a.maxSide : null,
      interpolation: img.Interpolation.cubic,
    );
  }
  if (a.sharpenStrength > 0.01) {
    work = _sharpenMild(work, strength: a.sharpenStrength);
  }
  return Uint8List.fromList(img.encodeJpg(work, quality: a.quality));
}

/// Pipeline CamScanner local: enquadrar + limpar / colorir / original.
class _EnhanceScanArgs {
  const _EnhanceScanArgs({
    required this.raw,
    required this.mode,
    this.skipAutoCrop = false,
    this.maxSide = UtilitariosLocalService.kScanPreviewMaxSide,
    this.jpegQuality = UtilitariosLocalService.kScanPreviewJpegQuality,
    this.exportA4 = false,
    this.previewOnly = false,
  });
  final Uint8List raw;
  final String mode;
  final bool skipAutoCrop;
  final int maxSide;
  final int jpegQuality;
  final bool exportA4;
  final bool previewOnly;
}

class _CropScanNormArgs {
  const _CropScanNormArgs({
    required this.raw,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });
  final Uint8List raw;
  final double nx;
  final double ny;
  final double nw;
  final double nh;
}

class _PrepareScanCaptureArgs {
  const _PrepareScanCaptureArgs({required this.raw, required this.mode});
  final Uint8List raw;
  final String mode;
}

class _PrepareScanCaptureResult {
  const _PrepareScanCaptureResult({
    required this.original,
    required this.crop,
    required this.preview,
  });
  final Uint8List original;
  final List<double> crop;
  final Uint8List preview;
}

class _PrepareScanFrameResult {
  const _PrepareScanFrameResult({
    required this.original,
    required this.crop,
    required this.thumb,
  });
  final Uint8List original;
  final List<double> crop;
  final Uint8List thumb;
}

class _RebuildScanPreviewArgs {
  const _RebuildScanPreviewArgs({
    required this.original,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
    required this.mode,
    this.exportQuality = false,
  });
  final Uint8List original;
  final double nx;
  final double ny;
  final double nw;
  final double nh;
  final String mode;
  final bool exportQuality;
}

List<double> _detectScanCropNormFromImage(img.Image decoded) {
  final w = decoded.width;
  final h = decoded.height;
  final box = _detectDocumentBoundsCombined(decoded);
  if (box == null) return const [0.04, 0.04, 0.92, 0.92];
  var minX = box.minX;
  var minY = box.minY;
  var maxX = box.maxX;
  var maxY = box.maxY;
  final padX = (w * 0.012).round().clamp(4, 18);
  final padY = (h * 0.012).round().clamp(4, 18);
  minX = (minX - padX).clamp(0, w - 1);
  minY = (minY - padY).clamp(0, h - 1);
  maxX = (maxX + padX).clamp(0, w - 1);
  maxY = (maxY + padY).clamp(0, h - 1);
  final cropW = maxX - minX + 1;
  final cropH = maxY - minY + 1;
  if (cropW < w * 0.28 || cropH < h * 0.28) {
    return const [0.04, 0.04, 0.92, 0.92];
  }
  return [
    minX / w,
    minY / h,
    cropW / w,
    cropH / h,
  ];
}

List<double> _detectScanCropNormIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return const [0.04, 0.04, 0.92, 0.92];
  return _detectScanCropNormFromImage(decoded);
}

Uint8List _cropScanNormIsolate(_CropScanNormArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  final x = (a.nx * decoded.width).round().clamp(0, decoded.width - 1);
  final y = (a.ny * decoded.height).round().clamp(0, decoded.height - 1);
  final w = (a.nw * decoded.width).round().clamp(1, decoded.width - x);
  final h = (a.nh * decoded.height).round().clamp(1, decoded.height - y);
  return Uint8List.fromList(
    img.encodeJpg(img.copyCrop(decoded, x: x, y: y, width: w, height: h), quality: 92),
  );
}

img.Image _resizeScanLongEdge(img.Image work, int maxSide) {
  final maxDim = work.width > work.height ? work.width : work.height;
  if (maxDim <= maxSide) return work;
  return img.copyResize(
    work,
    width: work.width >= work.height ? maxSide : null,
    height: work.height > work.width ? maxSide : null,
    interpolation: img.Interpolation.linear,
  );
}

img.Image _cropScanNormImage(img.Image decoded, double nx, double ny, double nw, double nh) {
  final x = (nx * decoded.width).round().clamp(0, decoded.width - 1);
  final y = (ny * decoded.height).round().clamp(0, decoded.height - 1);
  final w = (nw * decoded.width).round().clamp(1, decoded.width - x);
  final h = (nh * decoded.height).round().clamp(1, decoded.height - y);
  return img.copyCrop(decoded, x: x, y: y, width: w, height: h);
}

img.Image _enhanceScanImage(
  img.Image work, {
  required String mode,
  required bool previewOnly,
  required bool exportA4,
  required int maxSide,
}) {
  if (mode == UtilitariosLocalService.scanModeOriginal) {
    work = _resizeScanLongEdge(work, maxSide);
    if (exportA4) work = _fitScanExportA4(work, maxSide);
    return work;
  }
  if (mode == UtilitariosLocalService.scanModeColor) {
    work = _reduceShadowsMild(work);
    work = img.adjustColor(
      work,
      brightness: 1.06,
      contrast: 1.18,
      saturation: 1.2,
    );
    if (exportA4) work = _fitScanExportA4(work, maxSide);
    return work;
  }
  if (mode == UtilitariosLocalService.scanModeVivid) {
    work = _flattenCrumpledDocument(work, vivid: true, preview: previewOnly);
    if (exportA4) work = _fitScanExportA4(work, maxSide);
    return work;
  }
  work = _flattenCrumpledDocument(work, preview: previewOnly);
  if (exportA4) work = _fitScanExportA4(work, maxSide);
  return work;
}

_PrepareScanFrameResult _prepareScanFrameIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  final work = _resizeScanLongEdge(
    decoded,
    UtilitariosLocalService.kScanWorkMaxSide,
  );
  final original = Uint8List.fromList(
    img.encodeJpg(
      work,
      quality: UtilitariosLocalService.kScanWorkJpegQuality,
    ),
  );
  final crop = _detectScanCropNormFromImage(work);
  final cropped = _cropScanNormImage(
    work,
    crop[0],
    crop[1],
    crop[2],
    crop[3],
  );
  final thumb = Uint8List.fromList(
    img.encodeJpg(
      _resizeScanLongEdge(cropped, UtilitariosLocalService.kScanThumbMaxSide),
      quality: 78,
    ),
  );
  return _PrepareScanFrameResult(original: original, crop: crop, thumb: thumb);
}

_PrepareScanCaptureResult _prepareScanCaptureIsolate(_PrepareScanCaptureArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  final work = _resizeScanLongEdge(
    decoded,
    UtilitariosLocalService.kScanWorkMaxSide,
  );
  final original = Uint8List.fromList(
    img.encodeJpg(
      work,
      quality: UtilitariosLocalService.kScanWorkJpegQuality,
    ),
  );
  final crop = _detectScanCropNormFromImage(work);
  final cropped = _cropScanNormImage(
    work,
    crop[0],
    crop[1],
    crop[2],
    crop[3],
  );
  final previewImg = _enhanceScanImage(
    cropped,
    mode: a.mode,
    previewOnly: true,
    exportA4: false,
    maxSide: UtilitariosLocalService.kScanPreviewMaxSide,
  );
  final preview = Uint8List.fromList(
    img.encodeJpg(
      _resizeScanLongEdge(
        previewImg,
        UtilitariosLocalService.kScanPreviewMaxSide,
      ),
      quality: UtilitariosLocalService.kScanPreviewJpegQuality,
    ),
  );
  return _PrepareScanCaptureResult(original: original, crop: crop, preview: preview);
}

Uint8List _rebuildScanPreviewIsolate(_RebuildScanPreviewArgs a) {
  final decoded = img.decodeImage(a.original);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  final cropped = _cropScanNormImage(decoded, a.nx, a.ny, a.nw, a.nh);
  final out = _enhanceScanImage(
    cropped,
    mode: a.mode,
    previewOnly: true,
    exportA4: false,
    maxSide: UtilitariosLocalService.kScanPreviewMaxSide,
  );
  return Uint8List.fromList(
    img.encodeJpg(
      _resizeScanLongEdge(out, UtilitariosLocalService.kScanPreviewMaxSide),
      quality: UtilitariosLocalService.kScanPreviewJpegQuality,
    ),
  );
}

Uint8List _buildScanExportIsolate(_RebuildScanPreviewArgs a) {
  final decoded = img.decodeImage(a.original);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  final cropped = _cropScanNormImage(decoded, a.nx, a.ny, a.nw, a.nh);
  final out = _enhanceScanImage(
    cropped,
    mode: a.mode,
    previewOnly: false,
    exportA4: true,
    maxSide: UtilitariosLocalService.kScanExportMaxSide,
  );
  return Uint8List.fromList(
    img.encodeJpg(out, quality: UtilitariosLocalService.kScanExportJpegQuality),
  );
}

Uint8List _enhanceScanPageIsolate(_EnhanceScanArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Foto inválida para o scanner.');
  var work = decoded;

  final maxSide = a.maxSide;
  final maxDim = work.width > work.height ? work.width : work.height;
  if (maxDim > maxSide) {
    work = img.copyResize(
      work,
      width: work.width >= work.height ? maxSide : null,
      height: work.height > work.width ? maxSide : null,
      interpolation: img.Interpolation.linear,
    );
  }

  // 1) Enquadra o documento (corta fundo / mesa) — rápido.
  if (!a.skipAutoCrop) {
    work = _autoCropDocument(work);
  }

  final mode = a.mode;
  if (mode == 'original') {
    work = _finalizeScanExport(work, a);
    return Uint8List.fromList(img.encodeJpg(work, quality: a.jpegQuality));
  }

  if (mode == 'color') {
    work = _reduceShadowsMild(work);
    work = img.adjustColor(
      work,
      brightness: 1.06,
      contrast: 1.18,
      saturation: 1.2,
    );
    work = _finalizeScanExport(work, a);
    return Uint8List.fromList(img.encodeJpg(work, quality: a.jpegQuality));
  }

  if (mode == 'vivid') {
    work = _flattenCrumpledDocument(
      work,
      vivid: true,
      preview: a.previewOnly,
    );
    work = _finalizeScanExport(work, a);
    return Uint8List.fromList(img.encodeJpg(work, quality: a.jpegQuality));
  }

  // Documento: achata amassados/sombras e monta folha A4 limpa.
  work = _flattenCrumpledDocument(work, preview: a.previewOnly);
  work = _finalizeScanExport(work, a);
  return Uint8List.fromList(img.encodeJpg(work, quality: a.jpegQuality));
}

img.Image _finalizeScanExport(img.Image work, _EnhanceScanArgs a) {
  if (!a.exportA4) return work;
  return _fitScanExportA4(work, a.maxSide);
}

/// Enquadra o documento (estilo CamScanner) — borda por contraste + papel.
img.Image _autoCropDocument(img.Image src) {
  final w = src.width;
  final h = src.height;
  if (w < 80 || h < 80) return src;

  final box = _detectDocumentBoundsCombined(src);
  if (box == null) return src;

  var minX = box.minX;
  var minY = box.minY;
  var maxX = box.maxX;
  var maxY = box.maxY;
  if (maxX <= minX || maxY <= minY) return src;

  final padX = (w * 0.012).round().clamp(4, 18);
  final padY = (h * 0.012).round().clamp(4, 18);
  minX = (minX - padX).clamp(0, w - 1);
  minY = (minY - padY).clamp(0, h - 1);
  maxX = (maxX + padX).clamp(0, w - 1);
  maxY = (maxY + padY).clamp(0, h - 1);

  final cropW = maxX - minX + 1;
  final cropH = maxY - minY + 1;
  if (cropW < w * 0.28 || cropH < h * 0.28) return src;
  if (cropW >= w * 0.985 && cropH >= h * 0.985) return src;

  return img.copyCrop(src, x: minX, y: minY, width: cropW, height: cropH);
}

({int minX, int minY, int maxX, int maxY})? _detectDocumentBoundsCombined(
  img.Image src,
) {
  final byEdge = _detectDocumentBoundsByEdge(src);
  final byContent = _detectDocumentBoundsByContent(src);
  var box = byEdge ?? byContent;
  if (box == null && byEdge != null && byContent != null) {
    box = (
      minX: byEdge.minX > byContent.minX ? byEdge.minX : byContent.minX,
      minY: byEdge.minY > byContent.minY ? byEdge.minY : byContent.minY,
      maxX: byEdge.maxX < byContent.maxX ? byEdge.maxX : byContent.maxX,
      maxY: byEdge.maxY < byContent.maxY ? byEdge.maxY : byContent.maxY,
    );
  }
  return box ?? byEdge ?? byContent;
}

({int minX, int minY, int maxX, int maxY})? _detectDocumentBoundsByEdge(
  img.Image src,
) {
  final w = src.width;
  final h = src.height;
  final step = w > 1200 || h > 1200 ? 3 : 2;

  int colEnergy(int x) {
    var e = 0;
    for (var y = step; y < h - step; y += step) {
      final a = _lumaAt(src, x, y);
      final b = _lumaAt(src, (x + step).clamp(0, w - 1), y);
      e += (a - b).abs();
    }
    return e;
  }

  int rowEnergy(int y) {
    var e = 0;
    for (var x = step; x < w - step; x += step) {
      final a = _lumaAt(src, x, y);
      final b = _lumaAt(src, x, (y + step).clamp(0, h - 1));
      e += (a - b).abs();
    }
    return e;
  }

  // Energia média das bordas externas (mesa).
  var edgeSamples = 0;
  var edgeSum = 0;
  for (final x in [step, w - 1 - step]) {
    edgeSum += colEnergy(x);
    edgeSamples++;
  }
  for (final y in [step, h - 1 - step]) {
    edgeSum += rowEnergy(y);
    edgeSamples++;
  }
  final edgeAvg = edgeSamples == 0 ? 0 : edgeSum ~/ edgeSamples;
  final trigger = (edgeAvg * 1.55).round().clamp(1200, 28000);

  int findLeft() {
    for (var x = step; x < w ~/ 2; x += step) {
      if (colEnergy(x) >= trigger) return x;
    }
    return 0;
  }

  int findRight() {
    for (var x = w - 1 - step; x > w ~/ 2; x -= step) {
      if (colEnergy(x) >= trigger) return x;
    }
    return w - 1;
  }

  int findTop() {
    for (var y = step; y < h ~/ 2; y += step) {
      if (rowEnergy(y) >= trigger) return y;
    }
    return 0;
  }

  int findBottom() {
    for (var y = h - 1 - step; y > h ~/ 2; y -= step) {
      if (rowEnergy(y) >= trigger) return y;
    }
    return h - 1;
  }

  final minX = findLeft();
  final maxX = findRight();
  final minY = findTop();
  final maxY = findBottom();
  if (maxX - minX < w * 0.35 || maxY - minY < h * 0.35) return null;
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

({int minX, int minY, int maxX, int maxY})? _detectDocumentBoundsByContent(
  img.Image src,
) {
  final w = src.width;
  final h = src.height;

  // Mesa = mediana dos cantos.
  final samples = <int>[
    _lumaAt(src, 3, 3),
    _lumaAt(src, w - 4, 3),
    _lumaAt(src, 3, h - 4),
    _lumaAt(src, w - 4, h - 4),
    _lumaAt(src, w ~/ 10, h ~/ 10),
    _lumaAt(src, w - w ~/ 10, h ~/ 10),
    _lumaAt(src, w ~/ 10, h - h ~/ 10),
    _lumaAt(src, w - w ~/ 10, h - h ~/ 10),
  ]..sort();
  final bg = samples[samples.length ~/ 2];

  var minX = w;
  var minY = h;
  var maxX = 0;
  var maxY = 0;
  var hits = 0;
  const step = 2;

  for (var y = 0; y < h; y += step) {
    for (var x = 0; x < w; x += step) {
      final p = src.getPixel(x, y);
      final l = ((0.299 * p.r) + (0.587 * p.g) + (0.114 * p.b)).round();
      final sat = () {
        final mx = p.r > p.g ? (p.r > p.b ? p.r : p.b) : (p.g > p.b ? p.g : p.b);
        final mn = p.r < p.g ? (p.r < p.b ? p.r : p.b) : (p.g < p.b ? p.g : p.b);
        return (mx - mn).toInt();
      }();
      // Papel / conteúdo: difere da mesa OU tem cor viva (desenhos).
      final isDoc = (l - bg).abs() >= 22 || sat >= 38 || l >= 200;
      if (!isDoc) continue;
      hits++;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (hits < 120 || maxX <= minX || maxY <= minY) return null;
  if (maxX - minX < w * 0.32 || maxY - minY < h * 0.32) return null;
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

int _lumaAt(img.Image src, int x, int y) {
  final p = src.getPixel(x, y);
  return ((0.299 * p.r) + (0.587 * p.g) + (0.114 * p.b)).round();
}

/// Estima iluminação de fundo (campo suave) — ignora vincos finos do papel amassado.
img.Image _estimateScanBackground(img.Image src) {
  final sw = (src.width / 14).round().clamp(32, 200);
  final sh = (src.height / 14).round().clamp(32, 200);
  var small = img.copyResize(
    src,
    width: sw,
    height: sh,
    interpolation: img.Interpolation.average,
  );
  small = img.gaussianBlur(small, radius: 3);
  small = img.copyResize(
    small,
    width: (sw / 2).round().clamp(16, sw),
    height: (sh / 2).round().clamp(16, sh),
    interpolation: img.Interpolation.average,
  );
  small = img.gaussianBlur(small, radius: 2);
  return img.copyResize(
    small,
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
}

double _illuminationFactor(double sample, double background, double target) {
  final bg = background.clamp(96.0, 252.0);
  return (target / bg).clamp(0.78, 1.32);
}

/// Normaliza iluminação — remove vincos/sombras locais mantendo texto.
img.Image _normalizeIllumination(img.Image src) {
  final bg = _estimateScanBackground(src);
  final out = img.Image.from(src);
  const target = 232.0;
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final sp = src.getPixel(x, y);
      final bp = bg.getPixel(x, y);
      final fr = _illuminationFactor(sp.r.toDouble(), bp.r.toDouble(), target);
      final fg = _illuminationFactor(sp.g.toDouble(), bp.g.toDouble(), target);
      final fb = _illuminationFactor(sp.b.toDouble(), bp.b.toDouble(), target);
      final nr = (sp.r * fr).round().clamp(0, 255);
      final ng = (sp.g * fg).round().clamp(0, 255);
      final nb = (sp.b * fb).round().clamp(0, 255);
      out.setPixelRgba(x, y, nr, ng, nb, sp.a.toInt());
    }
  }
  return out;
}

/// Preview na UI — correção leve sem ruído/halftone em papel amassado.
img.Image _normalizeIlluminationPreview(img.Image src) {
  final bg = _estimateScanBackground(src);
  final out = img.Image.from(src);
  const target = 226.0;
  const blend = 0.52;
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final sp = src.getPixel(x, y);
      final bp = bg.getPixel(x, y);
      final fr = _illuminationFactor(sp.r.toDouble(), bp.r.toDouble(), target);
      final fg = _illuminationFactor(sp.g.toDouble(), bp.g.toDouble(), target);
      final fb = _illuminationFactor(sp.b.toDouble(), bp.b.toDouble(), target);
      final cr = (sp.r * fr).round().clamp(0, 255);
      final cg = (sp.g * fg).round().clamp(0, 255);
      final cb = (sp.b * fb).round().clamp(0, 255);
      final nr = (sp.r * (1 - blend) + cr * blend).round().clamp(0, 255);
      final ng = (sp.g * (1 - blend) + cg * blend).round().clamp(0, 255);
      final nb = (sp.b * (1 - blend) + cb * blend).round().clamp(0, 255);
      out.setPixelRgba(x, y, nr, ng, nb, sp.a.toInt());
    }
  }
  return out;
}

img.Image _reduceShadowsStrong(img.Image src) {
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final l = _lumaAt(out, x, y);
      if (l < 198) {
        final lift = 1.0 + ((198 - l) / 340).clamp(0.0, 0.3);
        p.r = (p.r * lift).round().clamp(0, 255);
        p.g = (p.g * lift).round().clamp(0, 255);
        p.b = (p.b * lift).round().clamp(0, 255);
        out.setPixel(x, y, p);
      }
    }
  }
  return out;
}

/// Suaviza vincos no papel claro sem borrar letras escuras.
img.Image _smoothPaperWrinkles(img.Image src) {
  final smallW = (src.width / 3).round().clamp(1, src.width);
  final smallH = (src.height / 3).round().clamp(1, src.height);
  final blurred = img.copyResize(
    img.gaussianBlur(
      img.copyResize(
        src,
        width: smallW,
        height: smallH,
        interpolation: img.Interpolation.average,
      ),
      radius: 2,
    ),
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final sp = src.getPixel(x, y);
      final bp = blurred.getPixel(x, y);
      final l = _lumaAt(src, x, y);
      if (l > 138) {
        final t = ((l - 138) / 78).clamp(0.0, 0.62);
        final nr = (sp.r * (1 - t) + bp.r * t).round();
        final ng = (sp.g * (1 - t) + bp.g * t).round();
        final nb = (sp.b * (1 - t) + bp.b * t).round();
        out.setPixelRgba(x, y, nr, ng, nb, sp.a.toInt());
      }
    }
  }
  return out;
}

/// Remove reflexos/claros de vinco (linhas brancas) em papel amassado.
img.Image _suppressCreaseHighlights(img.Image src) {
  final smallW = (src.width / 5).round().clamp(1, src.width);
  final smallH = (src.height / 5).round().clamp(1, src.height);
  final blurred = img.copyResize(
    img.gaussianBlur(
      img.copyResize(
        src,
        width: smallW,
        height: smallH,
        interpolation: img.Interpolation.average,
      ),
      radius: 2,
    ),
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final sp = src.getPixel(x, y);
      final bp = blurred.getPixel(x, y);
      final l = _lumaAt(src, x, y);
      final bl = _lumaAt(blurred, x, y);
      if (l > 168 && l < 248 && (l - bl) > 22) {
        final t = ((l - bl) / 48).clamp(0.0, 0.82);
        final nr = (sp.r * (1 - t) + bp.r * t).round().clamp(0, 255);
        final ng = (sp.g * (1 - t) + bp.g * t).round().clamp(0, 255);
        final nb = (sp.b * (1 - t) + bp.b * t).round().clamp(0, 255);
        out.setPixelRgba(x, y, nr, ng, nb, sp.a.toInt());
      }
    }
  }
  return out;
}

/// Papel amassado → folha limpa com texto/cores preservados.
img.Image _flattenCrumpledDocument(
  img.Image src, {
  bool vivid = false,
  bool preview = false,
}) {
  if (preview) {
    var work = _reduceShadowsMild(src);
    if (!vivid) {
      work = img.adjustColor(
        work,
        brightness: 1.04,
        contrast: 1.06,
        saturation: 0.98,
      );
      return work;
    }
    work = _normalizeIlluminationPreview(work);
    work = _smoothPaperWrinkles(work);
    work = _suppressCreaseHighlights(work);
    work = img.adjustColor(
      work,
      brightness: 1.03,
      contrast: 1.06,
      saturation: 1.08,
    );
    return work;
  }

  var work = _reduceShadowsStrong(src);
  work = _normalizeIllumination(work);
  work = _smoothPaperWrinkles(work);
  work = _suppressCreaseHighlights(work);
  work = _smoothPaperWrinkles(work);
  work = _whitenPaper(work);
  if (vivid) {
    work = img.adjustColor(
      work,
      brightness: 1.03,
      contrast: 1.1,
      saturation: 1.1,
    );
  } else {
    work = img.adjustColor(
      work,
      brightness: 1.04,
      contrast: 1.14,
      saturation: 0.94,
    );
  }
  return _sharpenMild(work, strength: vivid ? 0.35 : 0.2);
}

/// Monta canvas A4 branco em alta resolução e centraliza o documento.
img.Image _fitScanExportA4(img.Image work, int longEdge) {
  const a4Ratio = 210.0 / 297.0; // largura / altura (retrato)
  final portrait = work.height >= work.width;
  final tw = portrait ? (longEdge * a4Ratio).round() : longEdge;
  final th = portrait ? longEdge : (longEdge / a4Ratio).round();

  final contentAspect = work.width / work.height;
  final canvasAspect = tw / th;
  img.Image scaled;
  if (contentAspect > canvasAspect) {
    scaled = img.copyResize(
      work,
      width: tw,
      interpolation: img.Interpolation.cubic,
    );
  } else {
    scaled = img.copyResize(
      work,
      height: th,
      interpolation: img.Interpolation.cubic,
    );
  }

  final canvas = img.Image(width: tw, height: th);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final ox = ((tw - scaled.width) / 2).round();
  final oy = ((th - scaled.height) / 2).round();
  img.compositeImage(canvas, scaled, dstX: ox, dstY: oy);
  return canvas;
}

/// Empurra pixels claros para branco (papel) sem matar o texto.
img.Image _whitenPaper(img.Image src) {
  final out = img.Image.from(src);
  for (final p in out) {
    final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
    if (l > 184) {
      final t = ((l - 184) / 68).clamp(0.0, 1.0);
      final mix = 0.22 + (0.48 * t);
      p.r = (p.r + (255 - p.r) * mix).round().clamp(0, 255);
      p.g = (p.g + (255 - p.g) * mix).round().clamp(0, 255);
      p.b = (p.b + (255 - p.b) * mix).round().clamp(0, 255);
    } else if (l < 108) {
      p.r = (p.r * 0.9).round().clamp(0, 255);
      p.g = (p.g * 0.9).round().clamp(0, 255);
      p.b = (p.b * 0.9).round().clamp(0, 255);
    }
  }
  return out;
}

img.Image _reduceShadowsMild(img.Image src) {
  final out = img.Image.from(src);
  for (var y = 0; y < out.height; y++) {
    for (var x = 0; x < out.width; x++) {
      final p = out.getPixel(x, y);
      final l = _lumaAt(out, x, y);
      if (l < 150) {
        final lift = 1.0 + ((150 - l) / 500).clamp(0.0, 0.2);
        p.r = (p.r * lift).round().clamp(0, 255);
        p.g = (p.g * lift).round().clamp(0, 255);
        p.b = (p.b * lift).round().clamp(0, 255);
        out.setPixel(x, y, p);
      }
    }
  }
  return out;
}

img.Image _sharpenMild(img.Image src, {double strength = 1.0}) {
  final s = strength.clamp(0.0, 1.0);
  if (s <= 0.01) return src;
  final k = 0.45 * s;
  final c = 1.0 + (1.8 * s);
  return img.convolution(
    src,
    filter: [
      0, -k, 0,
      -k, c, -k,
      0, -k, 0,
    ],
  );
}

class _FlattenAnnotationsArgs {
  const _FlattenAnnotationsArgs({required this.page, required this.items});
  final Uint8List page;
  final List<UtilPdfPageAnnotation> items;
}

img.ColorRgb8 _medianPaperColorAround(
  img.Image work,
  int x,
  int y,
  int rw,
  int rh, {
  int ring = 4,
}) {
  final rs = <int>[];
  final gs = <int>[];
  final bs = <int>[];
  final w = work.width;
  final h = work.height;
  final x2 = (x + rw).clamp(0, w);
  final y2 = (y + rh).clamp(0, h);

  void sample(int sx, int sy) {
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) return;
    final p = work.getPixel(sx, sy);
    rs.add(p.r.toInt());
    gs.add(p.g.toInt());
    bs.add(p.b.toInt());
  }

  for (var sx = x; sx < x2; sx += 2) {
    for (var d = 1; d <= ring; d++) {
      sample(sx, y - d);
      sample(sx, y2 + d - 1);
    }
  }
  for (var sy = y; sy < y2; sy += 2) {
    for (var d = 1; d <= ring; d++) {
      sample(x - d, sy);
      sample(x2 + d - 1, sy);
    }
  }

  if (rs.isEmpty) {
    return img.ColorRgb8(252, 252, 250);
  }
  rs.sort();
  gs.sort();
  bs.sort();
  final m = rs.length ~/ 2;
  return img.ColorRgb8(rs[m], gs[m], bs[m]);
}

({int textArgb, bool fontBold}) _sampleFieldTextStyle(
  img.Image work,
  double nx,
  double ny,
  double nw,
  double nh, {
  bool fontBoldHint = false,
}) {
  final w = work.width;
  final h = work.height;
  final x = (nx * w).round().clamp(0, w - 1);
  final y = (ny * h).round().clamp(0, h - 1);
  final rw = (nw * w).round().clamp(4, w - x);
  final rh = (nh * h).round().clamp(4, h - y);
  final paper = _medianPaperColorAround(work, x, y, rw, rh);

  final buckets = <int, int>{};
  var inkCount = 0;
  var strokeWidths = <int>[];

  final innerX = x + (rw * 0.12).round();
  final innerY = y + (rh * 0.18).round();
  final innerX2 = x + rw - (rw * 0.12).round();
  final innerY2 = y + rh - (rh * 0.18).round();

  for (var sy = innerY; sy < innerY2; sy += 2) {
    var run = 0;
    for (var sx = innerX; sx < innerX2; sx++) {
      final p = work.getPixel(sx, sy);
      final dr = (p.r - paper.r).abs();
      final dg = (p.g - paper.g).abs();
      final db = (p.b - paper.b).abs();
      final dist = dr + dg + db;
      final isInk = dist >= 55 && (p.r + p.g + p.b) < 720;
      if (isInk) {
        run++;
        inkCount++;
        final key = (((p.r ~/ 24) << 16) | ((p.g ~/ 24) << 8) | (p.b ~/ 24));
        buckets[key] = (buckets[key] ?? 0) + 1;
      } else if (run > 0) {
        if (run >= 2) strokeWidths.add(run);
        run = 0;
      }
    }
    if (run >= 2) strokeWidths.add(run);
  }

  var textArgb = 0xFF1E293B;
  if (buckets.isNotEmpty) {
    final best = buckets.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final r = ((best.key >> 16) & 0xFF) * 24 + 12;
    final g = ((best.key >> 8) & 0xFF) * 24 + 12;
    final b = (best.key & 0xFF) * 24 + 12;
    textArgb = 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  var fontBold = fontBoldHint;
  if (strokeWidths.isNotEmpty) {
    strokeWidths.sort();
    final medianStroke = strokeWidths[strokeWidths.length ~/ 2];
    if (medianStroke >= 3 || inkCount / math.max(1, rw * rh) > 0.11) {
      fontBold = true;
    }
  }

  return (textArgb: textArgb, fontBold: fontBold);
}

void _drawAnnotationText(
  img.Image work,
  String text,
  img.BitmapFont font,
  int x,
  int y,
  img.ColorRgb8 color, {
  bool bold = false,
}) {
  img.drawString(work, text, font: font, x: x, y: y, color: color);
  if (bold) {
    img.drawString(work, text, font: font, x: x + 1, y: y, color: color);
    img.drawString(work, text, font: font, x: x, y: y + 1, color: color);
  }
}

void _fillSeamlessRegion(
  img.Image work,
  int x,
  int y,
  int rw,
  int rh,
) {
  final paper = _medianPaperColorAround(work, x, y, rw, rh);
  img.fillRect(
    work,
    x1: x,
    y1: y,
    x2: (x + rw).clamp(0, work.width),
    y2: (y + rh).clamp(0, work.height),
    color: paper,
  );
}

Uint8List _flattenPdfAnnotationsIsolate(_FlattenAnnotationsArgs a) {
  final decoded = img.decodeImage(a.page);
  if (decoded == null) return a.page;
  var work = img.Image.from(decoded);
  final w = work.width;
  final h = work.height;
  final items = [...a.items]..sort((a, b) {
      if (a.type == 'whiteout' && b.type != 'whiteout') return -1;
      if (a.type != 'whiteout' && b.type == 'whiteout') return 1;
      return 0;
    });
  for (final ann in items) {
    final x = (ann.nx * w).round().clamp(0, w - 1);
    final y = (ann.ny * h).round().clamp(0, h - 1);
    final rw = (ann.nw * w).round().clamp(4, w);
    final rh = (ann.nh * h).round().clamp(4, h);
    if (ann.type == 'highlight') {
      img.fillRect(
        work,
        x1: x,
        y1: y,
        x2: (x + rw).clamp(0, w),
        y2: (y + rh).clamp(0, h),
        color: img.ColorRgba8(
          (ann.argb >> 16) & 0xFF,
          (ann.argb >> 8) & 0xFF,
          ann.argb & 0xFF,
          90,
        ),
      );
    } else if (ann.type == 'whiteout') {
      _fillSeamlessRegion(work, x, y, rw, rh);
    } else if (ann.type == 'check') {
      img.drawRect(
        work,
        x1: x,
        y1: y,
        x2: x + rw,
        y2: y + rh,
        color: img.ColorRgb8(34, 197, 94),
        thickness: 3,
      );
      img.drawString(
        work,
        'X',
        font: ann.fontScale >= 1.2 ? img.arial24 : img.arial14,
        x: x + 2,
        y: y + 1,
        color: img.ColorRgb8(22, 163, 74),
      );
    } else {
      if (ann.seamless) {
        _fillSeamlessRegion(work, x, y, rw, rh);
      }
      final font = ann.fontScale >= 1.35
          ? img.arial48
          : (ann.fontScale >= 1.05 ? img.arial24 : img.arial14);
      final lineH = ann.fontScale >= 1.35
          ? 52
          : (ann.fontScale >= 1.05 ? 28 : 16);
      final tc = ann.textArgb;
      final textColor = img.ColorRgb8(
        (tc >> 16) & 0xFF,
        (tc >> 8) & 0xFF,
        tc & 0xFF,
      );
      final lines = (ann.text.isEmpty ? 'Texto' : ann.text).split('\n');
      var dy = y;
      for (final line in lines) {
        if (dy > h) break;
        _drawAnnotationText(
          work,
          line,
          font,
          x,
          dy,
          textColor,
          bold: ann.fontBold,
        );
        dy += lineH;
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(work, quality: 90));
}

class _EncodePageArgs {
  const _EncodePageArgs({
    required this.width,
    required this.height,
    required this.pixels,
    required this.asPng,
    required this.jpegQuality,
  });
  final int width;
  final int height;
  final Uint8List pixels;
  final bool asPng;
  final int jpegQuality;
}

Uint8List _encodePageIsolate(_EncodePageArgs a) {
  final im = img.Image.fromBytes(
    width: a.width,
    height: a.height,
    bytes: a.pixels.buffer,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(
    a.asPng ? img.encodePng(im) : img.encodeJpg(im, quality: a.jpegQuality),
  );
}

class _ImagesToPdfArgs {
  const _ImagesToPdfArgs({
    required this.images,
    required this.level,
  });
  final List<Uint8List> images;
  final UtilitariosCompressLevel level;
}

Future<Uint8List> _imagesToPdfIsolate(_ImagesToPdfArgs args) async {
  final level = args.level;
  final quality = level.pdfPageJpegQuality;
  final maxSide = level.maxSide;

  final doc = pw.Document();
  var pages = 0;
  for (final raw in args.images) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) continue;
    // EXIF (câmera) sem canvas A4 pesado — página A4 + contain = margens brancas grátis.
    var work = img.bakeOrientation(decoded);
    final maxDim = work.width > work.height ? work.width : work.height;
    final needsResize = maxDim > maxSide;
    final canReuseJpeg = !needsResize &&
        _looksLikeJpeg(raw) &&
        work.width == decoded.width &&
        work.height == decoded.height;

    late final Uint8List jpg;
    if (canReuseJpeg) {
      jpg = raw;
    } else {
      if (needsResize) {
        work = img.copyResize(
          work,
          width: work.width >= work.height ? maxSide : null,
          height: work.height > work.width ? maxSide : null,
          interpolation: img.Interpolation.linear,
        );
      }
      jpg = Uint8List.fromList(img.encodeJpg(work, quality: quality));
    }

    final pageFormat = UtilitariosExportPageFormat.pdfForAspect(
      width: work.width.toDouble(),
      height: work.height.toDouble(),
    );
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(jpg),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
    pages++;
  }
  if (pages == 0) {
    throw StateError('Nenhuma imagem válida para gerar o PDF.');
  }
  return doc.save();
}

bool _looksLikeJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

class _DocumentTextArgs {
  const _DocumentTextArgs({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
}

String _documentTextIsolate(_DocumentTextArgs a) {
  final lower = a.fileName;
  String text;
  if (lower.endsWith('.txt') || lower.endsWith('.rtf')) {
    text = utf8.decode(a.bytes, allowMalformed: true);
    if (lower.endsWith('.rtf')) {
      text = text
          .replaceAll(RegExp(r'\\[a-z]+\d* ?'), ' ')
          .replaceAll(RegExp(r'[{}]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
  } else if (lower.endsWith('.docx')) {
    text = _extractTextFromDocxSync(a.bytes);
  } else if (lower.endsWith('.doc')) {
    throw StateError(
      'Arquivo .doc antigo não é suportado. Salve como .docx ou .txt e tente de novo.',
    );
  } else {
    text = utf8.decode(a.bytes, allowMalformed: true);
  }
  if (text.trim().isEmpty) {
    return 'Documento sem texto extraível.';
  }
  // Evita PDF gigante / MultiPage lento.
  if (text.length > 120000) {
    text = '${text.substring(0, 120000)}\n\n[… texto truncado para manter o app rápido …]';
  }
  return text;
}

Future<Uint8List> _textToPdfWithTheme(String text, pw.ThemeData theme) async {
  final doc = pw.Document(theme: theme);
  final chunks = text.split('\n');
  doc.addPage(
    pw.MultiPage(
      pageFormat: UtilitariosExportPageFormat.a4Portrait,
      margin: const pw.EdgeInsets.all(UtilitariosExportPageFormat.pdfTextMarginPt),
      build: (_) => [
        for (final line in chunks)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              line.isEmpty ? ' ' : line,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.35),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}

Future<Uint8List> _formattedParagraphsToPdf(
  List<({String text, bool isHeading, bool isBold})> paragraphs,
  pw.ThemeData theme,
) async {
  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: UtilitariosExportPageFormat.a4Portrait,
      margin: const pw.EdgeInsets.all(UtilitariosExportPageFormat.pdfTextMarginPt),
      build: (_) => [
        for (final p in paragraphs)
          if (p.text.trim().isNotEmpty)
            pw.Padding(
              padding: pw.EdgeInsets.only(
                bottom: p.isHeading ? 10 : 6,
                top: p.isHeading ? 8 : 0,
              ),
              child: pw.Text(
                p.text.trim(),
                style: pw.TextStyle(
                  fontSize: p.isHeading ? 15 : 11,
                  fontWeight: (p.isHeading || p.isBold)
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  lineSpacing: 1.35,
                ),
              ),
            ),
      ],
    ),
  );
  return doc.save();
}

String _extractTextFromDocxSync(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('word/document.xml');
  if (file == null) {
    throw StateError(
      'DOCX inválido (sem word/document.xml). Abra no Word e salve de novo como .docx.',
    );
  }
  final xml = utf8.decode(file.content as List<int>, allowMalformed: true);
  final buf = StringBuffer();
  // Quebra de parágrafo / linha do Word.
  final parts = xml.split(RegExp(r'</w:p>|</w:tr>|<w:br\s*/>|<w:cr\s*/>'));
  for (final part in parts) {
    final texts = RegExp(r'<w:t(?:\s[^>]*)?>([^<]*)</w:t>')
        .allMatches(part)
        .map((m) => _decodeXmlEntities(m.group(1) ?? ''))
        .where((s) => s.isNotEmpty)
        .join();
    if (texts.trim().isEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      continue;
    }
    if (buf.isNotEmpty) buf.writeln();
    buf.write(texts);
  }
  final out = buf.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return out;
}

String _decodeXmlEntities(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) {
          final code = int.tryParse(m.group(1) ?? '');
          if (code == null) return m.group(0)!;
          return String.fromCharCode(code);
        },
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) {
          final code = int.tryParse(m.group(1) ?? '', radix: 16);
          if (code == null) return m.group(0)!;
          return String.fromCharCode(code);
        },
      );
}

Uint8List _buildMinimalDocxIsolate(String plainText) {
  return _buildFormattedDocxIsolate(
    _PdfExportDocument(
      blocks: plainText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((t) => _PdfExportBlock(kind: 'paragraph', text: t))
          .toList(),
      plainFallback: plainText,
    ),
  );
}

/// Bloco estruturado para export Word/Excel (serializável no isolate).
class _PdfExportBlock {
  const _PdfExportBlock({
    required this.kind,
    this.text,
    this.rows,
    this.bold = false,
  });
  final String kind;
  final String? text;
  final List<List<String>>? rows;
  final bool bold;
}

class _PdfExportDocument {
  const _PdfExportDocument({required this.blocks, required this.plainFallback});
  final List<_PdfExportBlock> blocks;
  final String plainFallback;
}

String _docxEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

String _docxRun(
  String text, {
  bool bold = false,
  int halfPts = 22,
  String color = '334155',
}) {
  final t = _docxEscape(text);
  final body = t.isEmpty ? ' ' : t;
  final rPr = bold
      ? '<w:rPr><w:b/><w:sz w:val="$halfPts"/><w:color w:val="$color"/></w:rPr>'
      : '<w:rPr><w:sz w:val="$halfPts"/><w:color w:val="$color"/></w:rPr>';
  return '<w:r>$rPr<w:t xml:space="preserve">$body</w:t></w:r>';
}

String _docxParagraphBlock(
  String text, {
  bool heading = false,
  bool bold = false,
}) {
  final pPr = heading
      ? '<w:pPr><w:spacing w:before="160" w:after="120"/></w:pPr>'
      : '<w:pPr><w:spacing w:after="100" w:line="276" w:lineRule="auto"/></w:pPr>';
  return '<w:p>$pPr${_docxRun(text, bold: heading || bold, halfPts: heading ? 28 : 22, color: heading ? '1E293B' : '334155')}</w:p>';
}

String _docxTableBlock(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final normalized = rows;
  final tblRows = StringBuffer();
  for (var ri = 0; ri < normalized.length; ri++) {
    final isHeader = ri == 0;
    tblRows.write('<w:tr>');
    if (isHeader) tblRows.write('<w:trPr><w:tblHeader/></w:trPr>');
    for (final cell in normalized[ri]) {
      final tcPr = isHeader
          ? '<w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="EEF2FF"/></w:tcPr>'
          : '<w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>';
      tblRows.write('<w:tc>$tcPr<w:p>${_docxRun(cell, bold: isHeader)}</w:p></w:tc>');
    }
    tblRows.write('</w:tr>');
  }

  return '''<w:tbl>
  <w:tblPr>
    <w:tblW w:w="5000" w:type="pct"/>
    <w:tblBorders>
      <w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
      <w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
      <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
      <w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>
      <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
      <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E2E8F0"/>
    </w:tblBorders>
  </w:tblPr>
  $tblRows
</w:tbl>
<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>''';
}

Uint8List _buildFormattedDocxIsolate(_PdfExportDocument doc) {
  final body = StringBuffer();
  if (doc.blocks.isEmpty) {
    for (final line in doc.plainFallback.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      body.write(_docxParagraphBlock(t, heading: _pdfLooksLikeHeading(t)));
    }
    if (body.isEmpty) {
      body.write(_docxParagraphBlock(doc.plainFallback));
    }
  } else {
    for (final b in doc.blocks) {
      switch (b.kind) {
        case 'pageBreak':
          body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
        case 'heading':
          body.write(_docxParagraphBlock(b.text ?? '', heading: true));
        case 'paragraph':
          body.write(
            _docxParagraphBlock(
              b.text ?? '',
              bold: b.bold,
            ),
          );
        case 'table':
          body.write(_docxTableBlock(b.rows ?? const []));
      }
    }
  }

  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault>
  </w:docDefaults>
</w:styles>''';

  final document = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $body
    <w:sectPr>
      ${UtilitariosExportPageFormat.docxSectionProperties}
    </w:sectPr>
  </w:body>
</w:document>''';

  final archive = Archive();
  void add(String name, String data) {
    final b = utf8.encode(data);
    archive.addFile(ArchiveFile(name, b.length, b));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('word/_rels/document.xml.rels', docRels);
  add('word/styles.xml', styles);
  add('word/document.xml', document);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _colIndexToLetters(int index) {
  var n = index;
  final chars = <int>[];
  while (n > 0) {
    n--;
    chars.add(65 + (n % 26));
    n ~/= 26;
  }
  return String.fromCharCodes(chars.reversed);
}

Uint8List _buildFormattedXlsxIsolate(_PdfExportDocument doc) {
  final sheetSpecs = <({List<String> cells, int style})>[];
  var maxCols = 1;

  void addRow(List<String> cells, {int style = 0}) {
    if (cells.isEmpty) {
      sheetSpecs.add((cells: const [''], style: 0));
      return;
    }
    maxCols = math.max(maxCols, cells.length);
    sheetSpecs.add((cells: cells, style: style));
  }

  if (doc.blocks.isEmpty) {
    for (final line in doc.plainFallback.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) addRow([t]);
    }
  } else {
    for (final b in doc.blocks) {
      switch (b.kind) {
        case 'pageBreak':
          addRow(['— Página —'], style: 3);
          addRow(const []);
        case 'heading':
          addRow([b.text ?? ''], style: 3);
          addRow(const []);
        case 'paragraph':
          addRow([b.text ?? '']);
        case 'table':
          final rows = b.rows ?? const <List<String>>[];
          for (var ri = 0; ri < rows.length; ri++) {
            addRow(rows[ri], style: ri == 0 ? 1 : 2);
          }
          addRow(const []);
      }
    }
  }

  if (sheetSpecs.isEmpty) {
    addRow(['Conteúdo convertido no GestÃ£o Yahweh']);
  }

  final sst = <String>[];
  final sstIndex = <String, int>{};
  int sstId(String value) {
    final v = value.length > 32000 ? value.substring(0, 32000) : value;
    final hit = sstIndex[v];
    if (hit != null) return hit;
    final id = sst.length;
    sst.add(v);
    sstIndex[v] = id;
    return id;
  }

  final sheetRows = StringBuffer();
  for (var r = 0; r < sheetSpecs.length; r++) {
    final spec = sheetSpecs[r];
    final rowNum = r + 1;
    sheetRows.write('<row r="$rowNum">');
    for (var c = 0; c < spec.cells.length; c++) {
      final col = _colIndexToLetters(c + 1);
      final addr = '$col$rowNum';
      final val = spec.cells[c];
      if (val.trim().isEmpty) {
        sheetRows.write('<c r="$addr" s="${spec.style}"/>');
        continue;
      }
      final numVal = double.tryParse(val.replaceAll(',', '.'));
      if (numVal != null && RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(val.trim())) {
        sheetRows.write('<c r="$addr" s="${spec.style}"><v>$numVal</v></c>');
      } else {
        final idx = sstId(val);
        sheetRows.write('<c r="$addr" s="${spec.style}" t="s"><v>$idx</v></c>');
      }
    }
    sheetRows.write('</row>');
  }

  final sstXml = StringBuffer();
  for (final s in sst) {
    sstXml.write('<si><t xml:space="preserve">${_xmlEscape(s)}</t></si>');
  }

  final lastRow = sheetSpecs.length;
  final lastCol = _colIndexToLetters(maxCols);
  final now = DateTime.now().toUtc().toIso8601String();

  final cols = StringBuffer();
  for (var c = 1; c <= maxCols; c++) {
    final w = (c == 1 ? 14.0 : 22.0).clamp(10.0, 48.0);
    cols.write('<col min="$c" max="$c" width="$w" customWidth="1"/>');
  }

  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

  const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  final core = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>PDF → Excel</dc:title>
  <dc:creator>GestÃ£o Yahweh</dc:creator>
  <cp:lastModifiedBy>GestÃ£o Yahweh</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';

  const app = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>GestÃ£o Yahweh</Application>
  <Company>GestÃ£o Yahweh</Company>
</Properties>''';

  const workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Documento" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';

  const workbookRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>''';

  const styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>
    <font><b/><sz val="11"/><color rgb="FF1E293B"/><name val="Calibri"/><family val="2"/></font>
  </fonts>
  <fills count="3">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFEEF2FF"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color auto="1"/></left>
      <right style="thin"><color auto="1"/></right>
      <top style="thin"><color auto="1"/></top>
      <bottom style="thin"><color auto="1"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="4">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

  final sharedStrings = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${sst.length}" uniqueCount="${sst.length}">
$sstXml
</sst>''';

  final sheet = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <dimension ref="A1:$lastCol$lastRow"/>
  <sheetViews><sheetView workbookViewId="0"/></sheetViews>
  <sheetFormatPr defaultRowHeight="16"/>
  <cols>$cols</cols>
  <sheetData>
    $sheetRows
  </sheetData>
  ${UtilitariosExportPageFormat.xlsxPageSetupBlock}
</worksheet>''';

  final archive = Archive();
  void add(String name, String data) {
    final b = utf8.encode(data);
    archive.addFile(ArchiveFile(name, b.length, b));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('docProps/core.xml', core);
  add('docProps/app.xml', app);
  add('xl/workbook.xml', workbook);
  add('xl/_rels/workbook.xml.rels', workbookRels);
  add('xl/styles.xml', styles);
  add('xl/sharedStrings.xml', sharedStrings);
  add('xl/worksheets/sheet1.xml', sheet);

  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) {
    throw StateError('Falha ao gerar o arquivo Excel.');
  }
  return Uint8List.fromList(encoded);
}

class _ZipImagesArgs {
  const _ZipImagesArgs({
    required this.pages,
    required this.stem,
    required this.extension,
  });
  final List<Uint8List> pages;
  final String stem;
  final String extension;
}

Uint8List _zipImagesIsolate(_ZipImagesArgs a) {
  final ext = a.extension.replaceAll('.', '').toLowerCase();
  final archive = Archive();
  for (var i = 0; i < a.pages.length; i++) {
    final name = '${a.stem}_${i + 1}.$ext';
    archive.addFile(ArchiveFile(name, a.pages[i].length, a.pages[i]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _ArchiveFilesArgs {
  const _ArchiveFilesArgs({required this.files, required this.format});
  final List<({String name, Uint8List bytes})> files;
  final UtilitariosArchiveFormat format;
}

Uint8List _archiveFilesIsolate(_ArchiveFilesArgs a) {
  final archive = Archive();
  final used = <String, int>{};
  for (final f in a.files) {
    var safe = f.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (safe.isEmpty) safe = 'arquivo';
    final count = used.update(safe, (v) => v + 1, ifAbsent: () => 0);
    if (count > 0) {
      final dot = safe.lastIndexOf('.');
      if (dot > 0) {
        safe = '${safe.substring(0, dot)}_$count${safe.substring(dot)}';
      } else {
        safe = '${safe}_$count';
      }
    }
    archive.addFile(ArchiveFile(safe, f.bytes.length, f.bytes));
  }
  final level = switch (a.format) {
    UtilitariosArchiveFormat.zip => DeflateLevel.defaultCompression,
    UtilitariosArchiveFormat.zipMax ||
    UtilitariosArchiveFormat.rar =>
      DeflateLevel.bestCompression,
  };
  final encoded = ZipEncoder().encode(archive, level: level);
  if (encoded.isEmpty) {
    throw StateError('Falha ao gerar o arquivo compactado.');
  }
  return Uint8List.fromList(encoded);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Páginas JPEG → PPTX válido (1 slide por página) — abre no PowerPoint sem reparo.
Uint8List _buildMinimalPptxFromImagesIsolate(List<Uint8List> pages) {
  if (pages.isEmpty) {
    throw StateError('Nenhuma página para o PowerPoint.');
  }
  final n = pages.length > 15 ? 15 : pages.length;
  final archive = Archive();

  void addXml(String name, String data) {
    final b = utf8.encode(data);
    archive.addFile(ArchiveFile(name, b.length, b));
  }

  void addBin(String name, Uint8List data) {
    // Mídia sem compressão — PowerPoint abre sem pedir reparo.
    final f = ArchiveFile(name, data.length, data)
      ..compression = CompressionType.none;
    archive.addFile(f);
  }

  final overrideSlides = StringBuffer();
  for (var i = 1; i <= n; i++) {
    overrideSlides.writeln(
      '  <Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
    );
  }

  // Content Types completos (PowerPoint exige slideLayout + theme + master).
  final contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
$overrideSlides</Types>''';

  const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  final now = DateTime.now().toUtc().toIso8601String();
  final core = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>GestÃ£o Yahweh</dc:title>
  <dc:creator>GestÃ£o Yahweh</dc:creator>
  <cp:lastModifiedBy>GestÃ£o Yahweh</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';

  final app = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>GestÃ£o Yahweh</Application>
  <PresentationFormat>Widescreen</PresentationFormat>
  <Slides>$n</Slides>
  <ScaleCrop>false</ScaleCrop>
  <Company>GestÃ£o Yahweh</Company>
</Properties>''';

  // rId1 = slideMaster; rId2.. = slides; último = theme
  final masterRid = 1;
  final themeRid = n + 2;
  final sldIdLst = StringBuffer();
  final presRels = StringBuffer()
    ..writeln(
      '  <Relationship Id="rId$masterRid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>',
    );
  for (var i = 1; i <= n; i++) {
    final rid = i + 1;
    sldIdLst.writeln('    <p:sldId id="${255 + i}" r:id="rId$rid"/>');
    presRels.writeln(
      '  <Relationship Id="rId$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>',
    );
  }
  presRels.writeln(
    '  <Relationship Id="rId$themeRid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>',
  );

  final presentation = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 saveSubsetFonts="1">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId$masterRid"/>
  </p:sldMasterIdLst>
  <p:sldIdLst>
$sldIdLst  </p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>''';

  final presentationRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$presRels</Relationships>''';

  const theme = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="GestaoYahweh">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
      <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
      <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
      <a:accent2><a:srgbClr val="C0504D"/></a:accent2>
      <a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
      <a:accent4><a:srgbClr val="8064A2"/></a:accent4>
      <a:accent5><a:srgbClr val="4BACC6"/></a:accent5>
      <a:accent6><a:srgbClr val="F79646"/></a:accent6>
      <a:hlink><a:srgbClr val="0000FF"/></a:hlink>
      <a:folHlink><a:srgbClr val="800080"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office">
      <a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
      <a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Office">
      <a:fillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1"><a:gsLst>
          <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="50000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
          <a:gs pos="35000"><a:schemeClr val="phClr"><a:tint val="37000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
          <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="15000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
        </a:gsLst><a:lin ang="16200000" scaled="1"/></a:gradFill>
        <a:gradFill rotWithShape="1"><a:gsLst>
          <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="100000"/><a:shade val="100000"/><a:satMod val="130000"/></a:schemeClr></a:gs>
          <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="50000"/><a:shade val="100000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
        </a:gsLst><a:lin ang="16200000" scaled="0"/></a:gradFill>
      </a:fillStyleLst>
      <a:lnStyleLst>
        <a:ln w="9525" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"><a:shade val="95000"/><a:satMod val="105000"/></a:schemeClr></a:solidFill><a:prstDash val="solid"/></a:ln>
        <a:ln w="25400" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
        <a:ln w="38100" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>
      </a:lnStyleLst>
      <a:effectStyleLst>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle><a:effectLst/></a:effectStyle>
        <a:effectStyle><a:effectLst/></a:effectStyle>
      </a:effectStyleLst>
      <a:bgFillStyleLst>
        <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
        <a:gradFill rotWithShape="1"><a:gsLst>
          <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="40000"/><a:satMod val="350000"/></a:schemeClr></a:gs>
          <a:gs pos="100000"><a:schemeClr val="phClr"><a:tint val="20000"/><a:satMod val="255000"/></a:schemeClr></a:gs>
        </a:gsLst><a:path path="circle"><a:fillToRect l="50000" t="-80000" r="50000" b="180000"/></a:path></a:gradFill>
        <a:gradFill rotWithShape="1"><a:gsLst>
          <a:gs pos="0"><a:schemeClr val="phClr"><a:tint val="80000"/><a:satMod val="300000"/></a:schemeClr></a:gs>
          <a:gs pos="100000"><a:schemeClr val="phClr"><a:shade val="30000"/><a:satMod val="200000"/></a:schemeClr></a:gs>
        </a:gsLst><a:path path="circle"><a:fillToRect l="50000" t="50000" r="50000" b="50000"/></a:path></a:gradFill>
      </a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
</a:theme>''';

  // Master com referência obrigatória ao slideLayout.
  const slideMaster = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>''';

  const slideMasterRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''';

  const slideLayout = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 type="blank" preserve="1">
  <p:cSld name="Em branco">
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>''';

  const slideLayoutRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';

  addXml('[Content_Types].xml', contentTypes);
  addXml('_rels/.rels', rootRels);
  addXml('docProps/core.xml', core);
  addXml('docProps/app.xml', app);
  addXml('ppt/presentation.xml', presentation);
  addXml('ppt/_rels/presentation.xml.rels', presentationRels);
  addXml('ppt/theme/theme1.xml', theme);
  addXml('ppt/slideMasters/slideMaster1.xml', slideMaster);
  addXml('ppt/slideMasters/_rels/slideMaster1.xml.rels', slideMasterRels);
  addXml('ppt/slideLayouts/slideLayout1.xml', slideLayout);
  addXml('ppt/slideLayouts/_rels/slideLayout1.xml.rels', slideLayoutRels);

  for (var i = 1; i <= n; i++) {
    final imgName = 'image$i.jpeg';
    addBin('ppt/media/$imgName', pages[i - 1]);

    // Cada slide DEVE referenciar o slideLayout (senão o PowerPoint pede reparo).
    final slideRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$imgName"/>
</Relationships>''';

    final slide = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="2" name="Página $i"/>
          <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr>
          <p:nvPr/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rId2"/>
          <a:stretch><a:fillRect/></a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm>
            <a:off x="0" y="0"/>
            <a:ext cx="12192000" cy="6858000"/>
          </a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
        </p:spPr>
      </p:pic>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';

    addXml('ppt/slides/slide$i.xml', slide);
    addXml('ppt/slides/_rels/slide$i.xml.rels', slideRels);
  }

  final encoded = ZipEncoder().encode(archive);
  if (encoded.isEmpty) {
    throw StateError('Falha ao gerar o arquivo PowerPoint.');
  }
  return Uint8List.fromList(encoded);
}

/// Lê XLSX/CSV → lista de linhas (máx. 80 linhas × 12 colunas).
List<List<String>> _excelRowsIsolate(_DocumentTextArgs a) {
  final lower = a.fileName;
  if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
    final text = utf8.decode(a.bytes, allowMalformed: true);
    final sep = text.contains(';') && !text.contains(',') ? ';' : ',';
    final rows = <List<String>>[];
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      if (line.trim().isEmpty) continue;
      rows.add(line.split(sep).map((c) => c.trim()).toList());
      if (rows.length >= 80) break;
    }
    if (rows.isEmpty) {
      throw StateError('Planilha vazia.');
    }
    return rows;
  }
  if (!lower.endsWith('.xlsx')) {
    throw StateError(
      'Use .xlsx ou .csv. Arquivo .xls antigo não é suportado.',
    );
  }
  return _parseXlsxRows(a.bytes);
}

List<List<String>> _parseXlsxRows(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final shared = <String>[];
  final sst = archive.findFile('xl/sharedStrings.xml');
  if (sst != null) {
    final xml = utf8.decode(sst.content as List<int>, allowMalformed: true);
    // <si>…<t>…</t>…</si> (pode ter rich text com vários <t>)
    for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(xml)) {
      final chunk = si.group(1) ?? '';
      final parts = RegExp(r'<t[^>]*>([^<]*)</t>')
          .allMatches(chunk)
          .map((m) => m.group(1) ?? '')
          .join();
      shared.add(parts);
    }
  }

  ArchiveFile? sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
  sheetFile ??= archive.files.cast<ArchiveFile?>().firstWhere(
        (f) => f != null && f.name.contains('worksheets/sheet'),
        orElse: () => null,
      );
  if (sheetFile == null) {
    throw StateError('Planilha Excel sem abas legíveis.');
  }
  final sheetXml =
      utf8.decode(sheetFile.content as List<int>, allowMalformed: true);

  final rows = <List<String>>[];
  for (final rowMatch
      in RegExp(r'<row[^>]*>([\s\S]*?)</row>').allMatches(sheetXml)) {
    final rowXml = rowMatch.group(1) ?? '';
    final cells = <int, String>{};
    var maxCol = -1;
    for (final cMatch
        in RegExp(r'<c([^>]*)>([\s\S]*?)</c>').allMatches(rowXml)) {
      final attrs = cMatch.group(1) ?? '';
      final body = cMatch.group(2) ?? '';
      final ref = RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs);
      final colLetters = ref?.group(1) ?? 'A';
      final col = _colLettersToIndex(colLetters);
      if (col > maxCol) maxCol = col;
      final t = RegExp(r't="([^"]+)"').firstMatch(attrs)?.group(1);
      String value = '';
      if (t == 's') {
        final v = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1);
        final idx = int.tryParse(v ?? '') ?? -1;
        if (idx >= 0 && idx < shared.length) value = shared[idx];
      } else if (t == 'inlineStr') {
        value = RegExp(r'<t[^>]*>([^<]*)</t>').firstMatch(body)?.group(1) ?? '';
      } else {
        value = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1) ?? '';
      }
      cells[col] = value;
    }
    if (maxCol < 0) continue;
    final capped = maxCol > 11 ? 11 : maxCol;
    final row = List<String>.generate(capped + 1, (i) => cells[i] ?? '');
    rows.add(row);
    if (rows.length >= 80) break;
  }
  if (rows.isEmpty) {
    throw StateError('Planilha Excel vazia ou sem células legíveis.');
  }
  return rows;
}

int _colLettersToIndex(String letters) {
  var n = 0;
  for (final code in letters.codeUnits) {
    n = n * 26 + (code - 64);
  }
  return n - 1;
}

Future<Uint8List> _rowsToPdfWithTheme(
  List<List<String>> rows,
  pw.ThemeData theme,
) async {
  if (rows.isEmpty) {
    throw StateError('Nenhuma linha para gerar o PDF.');
  }
  final colCount = rows
      .map((r) => r.length)
      .fold<int>(0, (a, b) => a > b ? a : b)
      .clamp(1, 12);
  final headers = List<String>.generate(
    colCount,
    (i) => i < rows.first.length && rows.first[i].trim().isNotEmpty
        ? rows.first[i]
        : 'Col ${i + 1}',
  );
  final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];

  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: UtilitariosExportPageFormat.pdfForTableColumns(colCount),
      margin: const pw.EdgeInsets.all(UtilitariosExportPageFormat.pdfTableMarginPt),
      build: (_) => [
        pw.Text(
          'Planilha — GestÃ£o Yahweh',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [
            for (final r in dataRows.take(60))
              List<String>.generate(
                colCount,
                (i) => i < r.length ? r[i] : '',
              ),
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        ),
        if (dataRows.length > 60)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '… linhas extras omitidas para manter o PDF leve.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}

