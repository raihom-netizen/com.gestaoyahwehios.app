import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Relatório premium: trocas de escala concluídas (quem → quem, data/hora da escala e registro).
Future<Uint8List> buildScheduleSwapsReportPdf({
  required List<Map<String, dynamic>> rows,
  required ReportPdfBranding branding,
  String churchAddress = '',
  String churchPhone = '',
  String periodLabel = '',
}) async {
  final doc = await PdfSuperPremiumTheme.newPdfDocument();
  final ink = PdfColor.fromInt(0xFF0F172A);
  final muted = PdfColor.fromInt(0xFF64748B);

  pw.Widget cell(String text,
      {bool bold = false,
      double size = 9,
      pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: pw.Text(
        pdfSafeText(text),
        textAlign: align,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: ink,
        ),
      ),
    );
  }

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
          'Relatório de trocas de escala',
          branding: branding,
          extraLines: extras,
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(ctx),
      build: (context) => [
        pw.Text(
          'Trocas efetuadas (substituição confirmada)',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink),
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromInt(0xFFCBD5E1), width: 0.75),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.15),
            1: const pw.FlexColumnWidth(1.1),
            2: const pw.FlexColumnWidth(1.45),
            3: const pw.FlexColumnWidth(1.45),
            4: const pw.FlexColumnWidth(1.45),
            5: const pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              decoration:
                  pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
              children: [
                cell('Data escala', bold: true, size: 9.5),
                cell('Horário', bold: true, size: 9.5),
                cell('Departamento', bold: true, size: 9.5),
                cell('Saiu (titular)', bold: true, size: 9.5),
                cell('Entrou (substituto)', bold: true, size: 9.5),
                cell('Concluída em', bold: true, size: 9.5),
              ],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  cell((r['escalaDateLabel'] ?? '-').toString(), size: 8.8),
                  cell((r['escalaTime'] ?? '-').toString(), size: 8.8),
                  cell((r['departmentName'] ?? '-').toString(), size: 8.8),
                  cell((r['solicitanteNome'] ?? '-').toString(), size: 8.8),
                  cell((r['alvoNome'] ?? '-').toString(), size: 8.8),
                  cell((r['resolvedLabel'] ?? '-').toString(), size: 8.8),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Emitido em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 8.5, color: muted),
        ),
      ],
    ),
  );

  return doc.save();
}

/// Normaliza um documento [troca] + dados opcionais da escala para linha do PDF.
Map<String, dynamic> rowMapFromTrocaDoc(
  Map<String, dynamic> troca, {
  String departmentName = '',
}) {
  final escalaDateLabel = (troca['escalaDateLabel'] ?? '').toString();
  final escalaTime = (troca['escalaTime'] ?? '').toString();
  String resolvedLabel = '-';
  try {
    final ts = troca['resolvedAt'];
    if (ts is Timestamp) {
      resolvedLabel = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(ts.toDate());
    }
  } catch (_) {}
  return <String, dynamic>{
    'escalaDateLabel': escalaDateLabel.isNotEmpty ? escalaDateLabel : '-',
    'escalaTime': escalaTime.isNotEmpty ? escalaTime : '-',
    'departmentName': departmentName.isNotEmpty ? departmentName : (troca['departmentId'] ?? '-').toString(),
    'solicitanteNome': (troca['solicitanteNome'] ?? '').toString().trim().isNotEmpty
        ? troca['solicitanteNome']
        : _maskCpfShort((troca['solicitanteCpf'] ?? '').toString()),
    'alvoNome': (troca['alvoNome'] ?? '').toString().trim().isNotEmpty
        ? troca['alvoNome']
        : _maskCpfShort((troca['alvoCpf'] ?? '').toString()),
    'resolvedLabel': resolvedLabel,
  };
}

String _maskCpfShort(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) return '***.${d.substring(6, 9)}-**';
  return raw.isNotEmpty ? raw : '—';
}
