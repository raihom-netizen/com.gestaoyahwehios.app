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
  final ink = PdfColor.fromInt(0xFF0F172A);

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

  final extras = <String>[
    if (periodLabel.isNotEmpty) periodLabel,
    if (churchAddress.isNotEmpty) churchAddress,
    if (churchPhone.isNotEmpty) 'Tel.: $churchPhone',
  ];

  doc.addPage(
    pw.MultiPage(
      // Uma tabela longa é UM widget que ocupa muitas páginas: o limite padrão
      // de 20 do pacote abortava o relatório grande com TooManyPagesException.
      maxPages: 2000,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          reportTitle,
          branding: branding,
          extraLines: extras,
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(ctx),
      build: (context) => [
        pw.Text(
          'Relatório de escala — dados do período filtrado',
          style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold, color: ink),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromInt(0xFFCBD5E1), width: 0.7),
          columnWidths: {
            for (var i = 0; i < colCount; i++) i: pw.FlexColumnWidth(flex[i]),
          },
          children: tableRows,
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Emitido em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 8.2, color: PdfColor.fromInt(0xFF64748B)),
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
