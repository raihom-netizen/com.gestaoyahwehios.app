import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// PDF único de uma escala gerada — logo e dados da igreja, tabela de membros, assinaturas (celotex).
Future<Uint8List> buildScheduleEscalaPdf({
  required Map<String, dynamic> escalaData,
  required ReportPdfBranding branding,
  String churchAddress = '',
  String churchPhone = '',
  String preparedByName = '',
  String approverName = '',
  bool showDigitalSignatures = false,
  Uint8List? preparedBySignatureBytes,
  Uint8List? approverSignatureBytes,
}) async {
  final doc = await PdfSuperPremiumTheme.newPdfDocument();
  final title = (escalaData['title'] ?? 'Escala').toString().trim();
  final dept = (escalaData['departmentName'] ?? '').toString().trim();
  final time = (escalaData['time'] ?? '').toString().trim();
  final obs = (escalaData['observations'] ?? '').toString().trim();
  DateTime? dt;
  try {
    dt = (escalaData['date'] as Timestamp?)?.toDate();
  } catch (_) {}
  final dateStr =
      dt != null ? DateFormat('dd/MM/yyyy', 'pt_BR').format(dt) : '-';
  final cpfs = ((escalaData['memberCpfs'] as List?) ?? [])
      .map((e) => e.toString())
      .toList();
  final names = ((escalaData['memberNames'] as List?) ?? [])
      .map((e) => e.toString())
      .toList();
  final confirmations =
      (escalaData['confirmations'] as Map<String, dynamic>?) ?? {};

  final accent = branding.accent;
  final ink = PdfColor.fromInt(0xFF0F172A);
  final muted = PdfColor.fromInt(0xFF64748B);

  pw.Widget logoBlock() {
    final b = branding.logoBytes;
    if (b == null || b.isEmpty) return pw.SizedBox();
    return pw.Image(
      pw.MemoryImage(b),
      width: 76,
      height: 76,
      fit: pw.BoxFit.contain,
    );
  }

  String statusFor(String cpf) {
    final s = (confirmations[cpf] ?? '').toString();
    if (s == 'confirmado') return 'Confirmado';
    if (s == 'indisponivel') return 'Indisponível';
    if (s == 'falta_nao_justificada') return 'Falta injustificada';
    if (s.isNotEmpty) return s;
    return 'Pendente';
  }

  pw.Widget cell(
    String text, {
    bool bold = false,
    bool center = false,
    double size = 10,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        pdfSafeText(text),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: ink,
        ),
      ),
    );
  }

  pw.Widget signatureLine(
    String captionBelow, {
    String signerName = '',
    Uint8List? signatureBytes,
  }) {
    final hasSig = showDigitalSignatures &&
        signatureBytes != null &&
        signatureBytes.length > 24;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (hasSig)
          pw.Center(
            child: pw.SizedBox(
              width: 150,
              height: 34,
              child: pw.Image(
                pw.MemoryImage(signatureBytes),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        pw.Container(
          width: double.infinity,
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2.2)),
          ),
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.SizedBox(height: hasSig ? 8 : 26),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          pdfSafeText(
            signerName.trim().isNotEmpty ? signerName.trim() : captionBelow,
          ),
          style: pw.TextStyle(
            fontSize: 9.2,
            color: muted,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            logoBlock(),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafeText(branding.churchName.isEmpty
                        ? 'Igreja'
                        : branding.churchName),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  if (churchAddress.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 5),
                      child: pw.Text(
                        pdfSafeText(churchAddress),
                        style: pw.TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ),
                  if (churchPhone.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        'Tel.: $churchPhone',
                        style: pw.TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(height: 4, color: accent),
        pw.SizedBox(height: 18),
        pw.Text(
          'ESCALA DE SERVIÇO',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: accent,
            letterSpacing: 1.1,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          pdfSafeText(title),
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.DefaultTextStyle(
          style: pw.TextStyle(fontSize: 13, color: ink),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Data: ',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  pw.Text(pdfSafeText(dateStr),
                      style: const pw.TextStyle(fontSize: 14)),
                  pw.SizedBox(width: 32),
                  pw.Text(
                    'Horário: ',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  pw.Text(
                    pdfSafeText(time.isEmpty ? '-' : time),
                    style: const pw.TextStyle(fontSize: 14),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Departamento: ',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      pdfSafeText(dept.isEmpty ? '-' : dept),
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (obs.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Observações',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                    color: ink,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  pdfSafeText(obs),
                  style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.35),
                ),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Text(
          'Membros escalados',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(
            color: PdfColor.fromInt(0xFFCBD5E1),
            width: 0.85,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(3.2),
            2: const pw.FlexColumnWidth(1.9),
            3: const pw.FlexColumnWidth(2.1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
              children: [
                cell('Nº', bold: true, center: true, size: 11),
                cell('Nome', bold: true, size: 11),
                cell('CPF', bold: true, size: 11),
                cell('Situação', bold: true, size: 11),
              ],
            ),
            for (var i = 0; i < cpfs.length; i++)
              pw.TableRow(
                children: [
                  cell('${i + 1}', center: true),
                  cell(i < names.length ? names[i] : '-'),
                  cell(_formatCpfDisplay(cpfs[i])),
                  cell(statusFor(cpfs[i])),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 28),
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAFC),
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(
              color: PdfColor(accent.red, accent.green, accent.blue, 0.38),
              width: 1.25,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                height: 3,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Assinaturas',
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Text(
                'Responsável pela elaboração desta escala',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 10),
              signatureLine(
                'Nome completo (letra de forma legível)',
                signerName: preparedByName,
                signatureBytes: preparedBySignatureBytes,
              ),
              pw.SizedBox(height: 22),
              pw.Text(
                'Líder do ministério / Pastor responsável (conferência)',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 10),
              signatureLine(
                'Nome, função e data',
                signerName: approverName,
                signatureBytes: approverSignatureBytes,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Data de impressão: ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          pdfSafeText(
              'Gestão YAHWEH - documento para afixação em quadro de avisos ou arquivo da igreja.'),
          style: pw.TextStyle(
            fontSize: 9,
            color: muted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

String _formatCpfDisplay(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return raw;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}
