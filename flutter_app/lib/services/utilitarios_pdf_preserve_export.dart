import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'package:gestao_yahweh/services/utilitarios_local_service.dart';

/// Edição nativa no **PDF original** (não rasteriza páginas).
///
/// Fluxo tipo Word: localiza o trecho antigo ? cobre só ele ? redesenha o
/// texto novo na mesma linha/baseline, expandindo para a direita se precisar.
/// O restante do documento (fontes, QR, vetores, layout) permanece intacto.
class UtilitariosPdfPreserveExport {
  UtilitariosPdfPreserveExport._();

  static Future<Uint8List> export({
    required Uint8List originalPdf,
    required List<List<UtilPdfPageAnnotation>> annotationsByPage,
  }) async {
    final hasAny = annotationsByPage.any((p) => p.isNotEmpty);
    if (!hasAny) return originalPdf;

    final payload = <Map<String, dynamic>>[];
    for (final page in annotationsByPage) {
      payload.add({
        'items': page
            .map(
              (a) => <String, dynamic>{
                'type': a.type,
                'nx': a.nx,
                'ny': a.ny,
                'nw': a.nw,
                'nh': a.nh,
                'text': a.text,
                'argb': a.argb,
                'textArgb': a.textArgb,
                'backgroundArgb': a.backgroundArgb,
                'fontScale': a.fontScale,
                'fontBold': a.fontBold,
                'fontItalic': a.fontItalic,
                'fontFamily': a.fontFamily,
                'seamless': a.seamless,
                'replaceSourceText': a.replaceSourceText,
              },
            )
            .toList(),
      });
    }

    try {
      return await compute(
        _exportNativeEditIsolate,
        _PreserveExportArgs(pdf: originalPdf, pages: payload),
      );
    } catch (e, st) {
      debugPrint('UtilitariosPdfPreserveExport isolate: $e\n$st');
      return _exportNativeEditIsolate(
        _PreserveExportArgs(pdf: originalPdf, pages: payload),
      );
    }
  }
}

class _PreserveExportArgs {
  const _PreserveExportArgs({required this.pdf, required this.pages});
  final Uint8List pdf;
  final List<Map<String, dynamic>> pages;
}

Future<Uint8List> _exportNativeEditIsolate(_PreserveExportArgs args) async {
  final document = sf.PdfDocument(inputBytes: args.pdf);
  try {
    final extractor = sf.PdfTextExtractor(document);
    final count = document.pages.count;

    for (var i = 0; i < count; i++) {
      if (i >= args.pages.length) break;
      final rawItems = args.pages[i]['items'];
      if (rawItems is! List || rawItems.isEmpty) continue;

      final page = document.pages[i];
      final size = page.getClientSize();
      final pageW = size.width;
      final pageH = size.height;
      if (pageW < 1 || pageH < 1) continue;

      List<sf.TextLine> lines = const [];
      try {
        lines = extractor.extractTextLines(
          startPageIndex: i,
          endPageIndex: i,
        );
      } catch (_) {}

      final items = rawItems
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      items.sort((a, b) {
        int rank(String t) => switch (t) {
              'whiteout' => 0,
              'highlight' => 1,
              'text' => 2,
              'check' => 3,
              _ => 4,
            };
        return rank('${a['type']}').compareTo(rank('${b['type']}'));
      });

      for (final map in items) {
        _applyNativeEdit(
          page: page,
          pageIndex: i,
          pageW: pageW,
          pageH: pageH,
          extractor: extractor,
          lines: lines,
          a: map,
        );
      }
    }

    final saved = await document.save();
    return Uint8List.fromList(saved);
  } finally {
    document.dispose();
  }
}

void _applyNativeEdit({
  required sf.PdfPage page,
  required int pageIndex,
  required double pageW,
  required double pageH,
  required sf.PdfTextExtractor extractor,
  required List<sf.TextLine> lines,
  required Map<String, dynamic> a,
}) {
  final type = (a['type'] ?? '').toString();
  final region = _normRectTopLeft(a, pageW, pageH);
  if (region == null) return;

  switch (type) {
    case 'whiteout':
      final cover = _resolveSourceBounds(
            extractor: extractor,
            pageIndex: pageIndex,
            lines: lines,
            region: region,
            pageH: pageH,
            source: (a['replaceSourceText'] ?? '').toString().trim(),
          ) ??
          region;
      _coverRegion(page, cover, a['backgroundArgb'] ?? 0xFFFFFFFF, pad: 0.6);
      break;
    case 'highlight':
      _applyHighlight(page, region, a);
      break;
    case 'check':
      _drawCheck(page, region, a);
      break;
    case 'text':
      _replaceTextLikeWord(
        page: page,
        pageIndex: pageIndex,
        pageW: pageW,
        pageH: pageH,
        region: region,
        a: a,
        extractor: extractor,
        lines: lines,
      );
      break;
  }
}

/// Substituição estilo Word: mesma linha, tipografia do trecho, sem comprimir
/// o texto no centro da caixa.
void _replaceTextLikeWord({
  required sf.PdfPage page,
  required int pageIndex,
  required double pageW,
  required double pageH,
  required Rect region,
  required Map<String, dynamic> a,
  required sf.PdfTextExtractor extractor,
  required List<sf.TextLine> lines,
}) {
  final newText = (a['text'] ?? '').toString();
  final source = (a['replaceSourceText'] ?? '').toString().trim();
  final bg = a['backgroundArgb'] ?? 0xFFFFFFFF;

  var cover = region;
  double? detectedFontSize;
  String? detectedFontName;
  var baselineTop = region.top;

  final found = _resolveSourceBounds(
    extractor: extractor,
    pageIndex: pageIndex,
    lines: lines,
    region: region,
    pageH: pageH,
    source: source,
  );
  if (found != null) {
    cover = found;
    baselineTop = found.top;
  }

  final line = _lineOverlapping(lines, cover, pageH) ??
      _lineOverlapping(lines, region, pageH);
  if (line != null) {
    if (line.fontSize > 0) detectedFontSize = line.fontSize;
    if (line.fontName.isNotEmpty) detectedFontName = line.fontName;
    final d = _asTopLeft(line.bounds, pageH);
    final f = _flipY(line.bounds, pageH);
    final lb = _iou(d, cover) >= _iou(f, cover) ? d : f;
    if (_iou(lb, cover) > 0.05 || _iou(lb, region) > 0.05) {
      baselineTop = lb.top;
      cover = Rect.fromLTRB(
        math.min(cover.left, lb.left),
        lb.top - 0.35,
        math.max(cover.right, lb.right),
        lb.bottom + 0.35,
      );
    }
  }

  // Cobre só o trecho antigo (papel / célula).
  _coverRegion(page, cover, bg, pad: 0.45);

  if (newText.trim().isEmpty) return;

  final scale = (a['fontScale'] as num?)?.toDouble() ?? 1.0;
  // Fonte pela tipografia detectada ? nunca pela altura ?gigante? da caixa OCR.
  final natural = detectedFontSize ?? (cover.height * 0.72);
  final fontSize = (natural * scale).clamp(7.0, 36.0);
  final family = _familyFromName(
    detectedFontName ?? a['fontFamily']?.toString(),
  );
  final bold = a['fontBold'] == true;
  final italic = a['fontItalic'] == true;
  final style = bold
      ? sf.PdfFontStyle.bold
      : (italic ? sf.PdfFontStyle.italic : sf.PdfFontStyle.regular);
  final font = sf.PdfStandardFont(family, fontSize, style: style);

  // Mede o texto novo e expande para a direita (Word), sem encolher no meio.
  final measured = font.measureString(newText);
  final neededW = measured.width + 1.2;
  final left = cover.left + 0.25;
  final maxW = math.max(4.0, pageW - left - 1.0);
  final drawW = math.min(maxW, math.max(cover.width, neededW));

  // Se couber em uma linha, desenha sem wrap (evita ?bloco comprimido?).
  final singleLine = !newText.contains('\n') && measured.width <= maxW + 0.5;
  final drawH = singleLine
      ? math.max(fontSize * 1.15, cover.height)
      : math.max(cover.height, measured.height + 2);

  // Limpa um pouco mais à direita se o texto novo for maior.
  if (drawW > cover.width + 1) {
    _coverRegion(
      page,
      Rect.fromLTWH(cover.right, cover.top, drawW - cover.width + 1, cover.height),
      bg,
      pad: 0.2,
    );
  }

  page.graphics.drawString(
    newText,
    font,
    brush: sf.PdfSolidBrush(_pdfColor(a['textArgb'] ?? 0xFF1E293B)),
    bounds: Rect.fromLTWH(
      left,
      baselineTop,
      drawW,
      drawH,
    ),
    format: sf.PdfStringFormat(
      alignment: sf.PdfTextAlignment.left,
      lineAlignment: sf.PdfVerticalAlignment.top,
      wordWrap:
          singleLine ? sf.PdfWordWrapType.none : sf.PdfWordWrapType.word,
    ),
  );
}

void _applyHighlight(sf.PdfPage page, Rect region, Map<String, dynamic> a) {
  try {
    final color = _pdfColor(a['argb'] ?? 0xFFFFF59D);
    final annot = sf.PdfTextMarkupAnnotation(region, 'Destaque', color);
    annot.textMarkupAnnotationType = sf.PdfTextMarkupAnnotationType.highlight;
    page.annotations.add(annot);
    annot.flatten();
    return;
  } catch (_) {
    final g = page.graphics;
    g.save();
    g.setTransparency(0.32);
    g.drawRectangle(
      bounds: region,
      brush: sf.PdfSolidBrush(_pdfColor(a['argb'] ?? 0xFFFFF59D)),
    );
    g.restore();
  }
}

void _drawCheck(sf.PdfPage page, Rect region, Map<String, dynamic> a) {
  final color = _pdfColor(a['argb'] ?? 0xFF16A34A);
  final font = sf.PdfStandardFont(
    sf.PdfFontFamily.helvetica,
    (region.height * 0.85).clamp(8.0, 28.0),
    style: sf.PdfFontStyle.bold,
  );
  page.graphics.drawString(
    '?',
    font,
    brush: sf.PdfSolidBrush(color),
    bounds: region,
    format: sf.PdfStringFormat(
      alignment: sf.PdfTextAlignment.center,
      lineAlignment: sf.PdfVerticalAlignment.middle,
    ),
  );
}

void _coverRegion(sf.PdfPage page, Rect region, Object? argb, {double pad = 0.5}) {
  final r = Rect.fromLTRB(
    region.left - pad,
    region.top - pad,
    region.right + pad,
    region.bottom + pad,
  );
  page.graphics.drawRectangle(
    bounds: r,
    brush: sf.PdfSolidBrush(_pdfColor(argb ?? 0xFFFFFFFF)),
  );
}

/// UI usa Y a partir do topo (Flutter). Syncfusion graphics = topo.
Rect? _normRectTopLeft(Map<String, dynamic> a, double pageW, double pageH) {
  final nx = (a['nx'] as num?)?.toDouble() ?? 0;
  final ny = (a['ny'] as num?)?.toDouble() ?? 0;
  final nw = (a['nw'] as num?)?.toDouble() ?? 0;
  final nh = (a['nh'] as num?)?.toDouble() ?? 0;
  if (nw <= 0 || nh <= 0) return null;
  final x = (nx * pageW).clamp(0.0, pageW);
  final y = (ny * pageH).clamp(0.0, pageH);
  final w = (nw * pageW).clamp(1.0, pageW - x);
  final h = (nh * pageH).clamp(1.0, pageH - y);
  return Rect.fromLTWH(x, y, w, h);
}

/// Alguns extratores devolvem Y com origem no fundo ? tenta os dois.
Rect _asTopLeft(Rect bounds, double pageH) {
  // Se o retângulo parece já top-left (top < bottom e top pequeno relativo),
  // mantém. Se bottom < top (raro em Dart Rect), normaliza.
  if (bounds.bottom >= bounds.top) return bounds;
  return Rect.fromLTRB(bounds.left, bounds.bottom, bounds.right, bounds.top);
}

Rect _flipY(Rect r, double pageH) {
  final top = pageH - r.bottom;
  final bottom = pageH - r.top;
  return Rect.fromLTRB(r.left, top, r.right, bottom);
}

Rect? _resolveSourceBounds({
  required sf.PdfTextExtractor extractor,
  required int pageIndex,
  required List<sf.TextLine> lines,
  required Rect region,
  required double pageH,
  required String source,
}) {
  if (source.isNotEmpty) {
    try {
      final matches = extractor.findText(
        [source],
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      final best = _bestOverlapFlexible(matches, region, pageH);
      if (best != null) return best;
    } catch (_) {}
  }

  final line = _lineOverlapping(lines, region, pageH);
  if (line != null) {
    final lb = _asTopLeft(line.bounds, pageH);
    if (_iou(lb, region) > 0.12) {
      return Rect.fromLTRB(
        math.max(region.left, lb.left - 0.4),
        math.max(region.top, lb.top - 0.3),
        math.min(region.right, lb.right + 0.4),
        math.min(region.bottom, lb.bottom + 0.3),
      );
    }
  }
  return null;
}

Rect? _bestOverlapFlexible(
  List<sf.MatchedItem> matches,
  Rect region,
  double pageH,
) {
  sf.MatchedItem? best;
  var bestScore = 0.0;
  var bestFlipped = false;
  for (final m in matches) {
    final direct = _asTopLeft(m.bounds, pageH);
    final s1 = _iou(direct, region);
    final flipped = _flipY(m.bounds, pageH);
    final s2 = _iou(flipped, region);
    if (s1 >= s2 && s1 > bestScore) {
      bestScore = s1;
      best = m;
      bestFlipped = false;
    } else if (s2 > bestScore) {
      bestScore = s2;
      best = m;
      bestFlipped = true;
    }
  }
  if (best == null) return null;
  if (bestScore < 0.06) {
    for (final m in matches) {
      final d = _asTopLeft(m.bounds, pageH);
      final f = _flipY(m.bounds, pageH);
      if (region.overlaps(d.inflate(4)) || region.overlaps(f.inflate(4))) {
        final preferFlip = _iou(f, region) > _iou(d, region);
        return preferFlip ? f : d;
      }
    }
  }
  if (bestScore <= 0) return null;
  return bestFlipped
      ? _flipY(best.bounds, pageH)
      : _asTopLeft(best.bounds, pageH);
}

sf.TextLine? _lineOverlapping(
  List<sf.TextLine> lines,
  Rect region,
  double pageH,
) {
  sf.TextLine? best;
  var bestScore = 0.0;
  for (final line in lines) {
    final d = _asTopLeft(line.bounds, pageH);
    final f = _flipY(line.bounds, pageH);
    final score = math.max(_iou(d, region), _iou(f, region));
    if (score > bestScore) {
      bestScore = score;
      best = line;
    }
  }
  return bestScore >= 0.05 ? best : null;
}

double _iou(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width <= 0 || inter.height <= 0) return 0;
  final interArea = inter.width * inter.height;
  final union = a.width * a.height + b.width * b.height - interArea;
  if (union <= 0) return 0;
  return interArea / union;
}

sf.PdfFontFamily _familyFromName(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('times') ||
      n.contains('roman') ||
      n.contains('georgia') ||
      n.contains('serif')) {
    return sf.PdfFontFamily.timesRoman;
  }
  if (n.contains('courier') || n.contains('mono') || n.contains('consolas')) {
    return sf.PdfFontFamily.courier;
  }
  return sf.PdfFontFamily.helvetica;
}

sf.PdfColor _pdfColor(Object? argb) {
  final v = argb is int ? argb : int.tryParse('$argb') ?? 0xFF000000;
  return sf.PdfColor(
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  );
}
