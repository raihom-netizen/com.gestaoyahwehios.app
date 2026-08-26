import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// PDF único de uma escala gerada — logo e dados da igreja, tabela de membros (CPF mascarado), assinatura única ao estilo ofício.
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

  final ink = PdfColor.fromInt(0xFF0F172A);
  final muted = PdfColor.fromInt(0xFF64748B);

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

  /// Uma linha de assinatura centralizada (padrão ofício).
  pw.Widget officialSingleSignatureBlock({
    required String captionBelow,
    required String signerName,
    Uint8List? signatureBytes,
  }) {
    final hasSig = showDigitalSignatures &&
        signatureBytes != null &&
        signatureBytes.length > 24;
    final lineW = 268.0;
    return pw.Center(
      child: pw.SizedBox(
        width: lineW,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (hasSig)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.SizedBox(
                  width: 160,
                  height: 38,
                  child: pw.Image(
                    pw.MemoryImage(signatureBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: ink, width: 0.9)),
              ),
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.SizedBox(height: hasSig ? 6 : 28),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              pdfSafeText(
                signerName.trim().isNotEmpty ? signerName.trim() : captionBelow,
              ),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 10,
                color: ink,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  final sigBytes = (preparedBySignatureBytes != null &&
          preparedBySignatureBytes.length > 24)
      ? preparedBySignatureBytes
      : ((approverSignatureBytes != null && approverSignatureBytes.length > 24)
          ? approverSignatureBytes
          : null);
  // UMA assinatura só (padrão certificados): o signatário responsável — líder do
  // departamento / pastor / secretário. Prefere o aprovador; senão, quem preparou.
  // Não combina os dois nomes (o usuário não quer duas assinaturas em escalas).
  final combinedSignerLabel = () {
    final b = approverName.trim();
    if (b.isNotEmpty) return b;
    return preparedByName.trim();
  }();

  final headerExtras = <String>[
    if (dept.isNotEmpty) 'Departamento: $dept',
    'Data: $dateStr${time.isNotEmpty ? ' · Horário: $time' : ''}',
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
          'Escala de serviço',
          branding: branding,
          extraLines: headerExtras,
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(ctx),
      build: (context) => [
        pw.Text(
          pdfSafeText(title),
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 12),
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
        pw.SizedBox(height: 36),
        pw.Text(
          'Assinatura',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: ink,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 10),
        officialSingleSignatureBlock(
          captionBelow: 'Nome completo, função e data',
          signerName: combinedSignerLabel,
          signatureBytes: sigBytes,
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Data de impressão: ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
          style: pw.TextStyle(fontSize: 9, color: muted),
        ),
      ],
    ),
  );

  return doc.save();
}

/// Igual à lista ao abrir a escala no app: só os 3 dígitos centrais (`***.XXX-**`).
String _formatCpfDisplay(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) return '***.${d.substring(6, 9)}-**';
  return d.isEmpty ? '—' : '***.---**';
}
