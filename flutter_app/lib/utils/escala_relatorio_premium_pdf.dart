import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Relatórios resumo premium (presenças, faltas, indisponível, listagens).
Future<Uint8List> buildEscalaPremiumTablePdf({
  required ReportPdfBranding branding,
  required String reportTitle,
  String churchAddress = '',
  String churchPhone = '',
  String periodLabel = '',
  required List<String> columnHeaders,
  required List<List<String>> rows,
}) async {
  final doc = await PdfSuperPremiumTheme.newPdfDocument();
  final accent = branding.accent;
  final ink = PdfColor.fromInt(0xFF0F172A);
  final muted = PdfColor.fromInt(0xFF64748B);

  pw.Widget logoBlock() {
    final b = branding.logoBytes;
    if (b == null || b.isEmpty) return pw.SizedBox();
    return pw.Image(pw.MemoryImage(b), width: 68, height: 68, fit: pw.BoxFit.contain);
  }

  pw.Widget cell(String text, {bool bold = false, double size = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        pdfSafeText(text),
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: ink,
        ),
      ),
    );
  }

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
      children: columnHeaders.map((h) => cell(h, bold: true, size: 9.2)).toList(),
    ),
    for (final r in rows)
      pw.TableRow(
        children: r.map((c) => cell(c, size: 8.6)).toList(),
      ),
  ];

  final colCount = columnHeaders.length;
  final flex = List<double>.filled(colCount, 1.0);
  if (colCount >= 3) flex[0] = 1.35;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            logoBlock(),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafeText(branding.churchName.isEmpty ? 'Igreja' : branding.churchName),
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: ink),
                  ),
                  if (churchAddress.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(pdfSafeText(churchAddress), style: pw.TextStyle(fontSize: 9.5, color: muted)),
                    ),
                  if (churchPhone.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text('Tel.: $churchPhone', style: pw.TextStyle(fontSize: 9.5, color: muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 3, color: accent),
        pw.SizedBox(height: 12),
        pw.Text(
          pdfSafeText(reportTitle.toUpperCase()),
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: accent,
            letterSpacing: 0.85,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Relatório de escala — dados do período filtrado',
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: ink),
        ),
        if (periodLabel.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            pdfSafeText(periodLabel),
            style: pw.TextStyle(fontSize: 10.5, color: muted, fontWeight: pw.FontWeight.bold),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.7),
          columnWidths: {
            for (var i = 0; i < colCount; i++) i: pw.FlexColumnWidth(flex[i]),
          },
          children: tableRows,
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Emitido em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 8.2, color: muted),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          pdfSafeText('Gestão YAHWEH — uso interno / gestão ministerial.'),
          style: pw.TextStyle(fontSize: 8.2, color: muted, fontStyle: pw.FontStyle.italic),
        ),
      ],
    ),
  );

  return doc.save();
}

/// Map nome → quantidade → linhas de tabela.
List<List<String>> rowsFromNameCounts(Map<String, int> map) {
  final entries = map.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return entries.map((e) => [e.key, '${e.value}']).toList();
}
