import 'package:pdf/pdf.dart';

/// Folha **A4** padrão em Utilitários: conversores, PDF Pro, extrator de texto, Word e Excel.
abstract final class UtilitariosExportPageFormat {
  UtilitariosExportPageFormat._();

  static const PdfPageFormat a4Portrait = PdfPageFormat.a4;
  static final PdfPageFormat a4Landscape = PdfPageFormat.a4.landscape;

  /// Retrato A4; paisagem A4 só quando o conteúdo é claramente horizontal.
  static PdfPageFormat pdfForAspect({
    required double width,
    required double height,
  }) {
    if (width > height * 1.08) return a4Landscape;
    return a4Portrait;
  }

  /// Planilhas largas → A4 paisagem; demais casos → A4 retrato.
  static PdfPageFormat pdfForTableColumns(int columnCount) =>
      columnCount > 5 ? a4Landscape : a4Portrait;

  static const double pdfTextMarginPt = 40;
  static const double pdfTableMarginPt = 24;

  /// DOCX OOXML — 210 × 297 mm em twips (1/20 pt).
  static const int docxPageWidthTwips = 11906;
  static const int docxPageHeightTwips = 16838;
  static const int docxPageMarginTwips = 1134;

  static String get docxSectionProperties => '''
      <w:pgSz w:w="$docxPageWidthTwips" w:h="$docxPageHeightTwips"/>
      <w:pgMar w:top="$docxPageMarginTwips" w:right="$docxPageMarginTwips" w:bottom="$docxPageMarginTwips" w:left="$docxPageMarginTwips"/>''';

  /// Excel OOXML — paperSize 9 = A4.
  static const String xlsxPageSetupBlock = '''
  <pageSetup paperSize="9" orientation="portrait" horizontalDpi="300" verticalDpi="300" fitToWidth="1" fitToHeight="0"/>
  <printOptions horizontalCentered="1"/>''';

  /// Resolução do canvas A4 ao embutir imagens (JPEG→PDF, juntar, dividir, editor).
  static const int a4ImageLongEdgePx = 2480;
}
