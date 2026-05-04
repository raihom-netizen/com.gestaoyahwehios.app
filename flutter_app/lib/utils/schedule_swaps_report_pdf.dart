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
  final accent = branding.accent;
  final ink = PdfColor.fromInt(0xFF0F172A);
  final muted = PdfColor.fromInt(0xFF64748B);

  pw.Widget logoBlock() {
    final b = branding.logoBytes;
    if (b == null || b.isEmpty) return pw.SizedBox();
    return pw.Image(pw.MemoryImage(b), width: 72, height: 72, fit: pw.BoxFit.contain);
  }

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

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            logoBlock(),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafeText(branding.churchName.isEmpty ? 'Igreja' : branding.churchName),
                    style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: ink),
                  ),
                  if (churchAddress.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text(pdfSafeText(churchAddress),
                          style: pw.TextStyle(fontSize: 10, color: muted)),
                    ),
                  if (churchPhone.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text('Tel.: $churchPhone',
                          style: pw.TextStyle(fontSize: 10, color: muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 3, color: accent),
        pw.SizedBox(height: 14),
        pw.Text(
          'RELATÓRIO DE TROCAS DE ESCALA',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: accent,
            letterSpacing: 0.9,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Trocas efetuadas (substituição confirmada)',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: ink),
        ),
        if (periodLabel.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            pdfSafeText(periodLabel),
            style: pw.TextStyle(fontSize: 11.5, color: muted, fontWeight: pw.FontWeight.bold),
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.75),
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
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
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
        pw.SizedBox(height: 20),
        pw.Text(
          'Emitido em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 8.5, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          pdfSafeText('Gestão YAHWEH — relatório interno da igreja.'),
          style: pw.TextStyle(fontSize: 8.5, color: muted, fontStyle: pw.FontStyle.italic),
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
