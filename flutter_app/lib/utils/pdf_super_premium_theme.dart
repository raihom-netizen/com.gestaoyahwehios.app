import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Tema Super Premium para relatórios PDF: cartão claro, borda suave, logo da igreja, tipografia sóbria.
class PdfSuperPremiumTheme {
  PdfSuperPremiumTheme._();

  static PdfColor get _border => PdfColor.fromInt(0xFFE2E8F0);
  static PdfColor get _cardBg => PdfColors.white;
  static PdfColor get _muted => PdfColor.fromInt(0xFF64748B);
  static PdfColor get _ink => PdfColor.fromInt(0xFF0F172A);
  static PdfColor get _tableHeaderBg => PdfColor.fromInt(0xFFF1F5F9);

  static const double _margin = 24;

  static pw.EdgeInsets get pageMargin => const pw.EdgeInsets.all(_margin);

  static pw.TextStyle get reportTitleStyle => pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      );

  static pw.TextStyle get dateStyle =>
      pw.TextStyle(fontSize: 9, color: _muted);

  static pw.TextStyle tableHeaderStyleFor(PdfColor accent) => pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
        color: accent,
      );

  static pw.BoxDecoration tableHeaderDecorationFor(PdfColor accent) =>
      pw.BoxDecoration(
        color: _tableHeaderBg,
        border: pw.Border(
          bottom: pw.BorderSide(color: accent, width: 2),
        ),
      );

  static pw.TextStyle get tableCellStyle =>
      const pw.TextStyle(fontSize: 9, color: PdfColors.grey800);

  static pw.EdgeInsets get tableCellPadding =>
      const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  /// Cabeçalho: cartão branco, borda arredondada, logo da igreja (se houver), título e data.
  static pw.Widget header(
    String reportTitle, {
    DateTime? date,
    ReportPdfBranding? branding,
    List<String> extraLines = const [],
  }) {
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm').format(date ?? DateTime.now());
    final accent = branding?.accent ?? ReportPdfBranding.defaultAccent;
    final church = (branding?.churchName ?? '').trim();

    pw.ImageProvider? logoProv;
    final lb = branding?.logoBytes;
    if (lb != null && lb.length > 32) {
      logoProv = pw.MemoryImage(lb);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoProv != null)
            pw.Container(
              width: 48,
              height: 48,
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(logoProv, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (church.isNotEmpty)
                  pw.Text(
                    church,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: _muted,
                      letterSpacing: 0.15,
                    ),
                  ),
                if (church.isNotEmpty) pw.SizedBox(height: 3),
                pw.Text(
                  reportTitle,
                  style: pw.TextStyle(
                    fontSize: 13,
                    color: accent,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (extraLines.isNotEmpty) pw.SizedBox(height: 4),
                ...extraLines.expand(
                  (line) => [
                    pw.Text(
                      line,
                      style: pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                    pw.SizedBox(height: 2),
                  ],
                ),
              ],
            ),
          ),
          pw.Text(
            dateStr,
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        ],
      ),
    );
  }

  /// Rodapé: nome da igreja + página (sem marca da plataforma).
  static pw.Widget footer(pw.Context context, {String? churchName}) {
    final left = (churchName ?? '').trim().isNotEmpty
        ? '${churchName!.trim()} · Relatório'
        : 'Relatório';
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              left,
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  /// Tabela estilo premium: cabeçalho cinza-claro, traço inferior na cor da igreja, linhas zebradas.
  static pw.Widget fromTextArray({
    required List<String> headers,
    required List<List<String>> data,
    pw.TextStyle? headerStyle,
    pw.TextStyle? cellStyle,
    pw.BoxDecoration? headerDecoration,
    pw.EdgeInsets? cellPadding,
    PdfColor? accent,
  }) {
    final ac = accent ?? ReportPdfBranding.defaultAccent;
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: headerStyle ?? tableHeaderStyleFor(ac),
      cellStyle: cellStyle ?? tableCellStyle,
      headerDecoration: headerDecoration ?? tableHeaderDecorationFor(ac),
      cellPadding: cellPadding ?? tableCellPadding,
    );
  }
}
