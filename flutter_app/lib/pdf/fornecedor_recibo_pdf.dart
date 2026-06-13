import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/valor_real_extenso.dart';

/// Recibo de pagamento a fornecedor/prestador (PDF A4 retrato — layout compacto e rápido).
Future<Uint8List> buildFornecedorReciboPdf({
  required ReportPdfBranding branding,
  required String fornecedorNome,
  String? fornecedorCpfCnpj,
  String? fornecedorEndereco,
  required double valor,
  required String referente,
  DateTime? dataPagamento,
  String textoLegalExtra = '',
  bool showDigitalSignature = false,
  Uint8List? churchSignatureImageBytes,
  String churchSignerName = '',
  String churchSignerRole = '',
  PdfDigitalStampInput? churchDigitalStamp,
}) async {
  final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dataStr = dataPagamento != null
      ? DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR').format(dataPagamento)
      : DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR').format(DateTime.now());
  final extenso = valorRealPorExtenso(valor);
  final hasChurchStamp =
      showDigitalSignature && churchDigitalStamp != null;
  final hasChurchSig = !hasChurchStamp &&
      showDigitalSignature &&
      churchSignatureImageBytes != null &&
      churchSignatureImageBytes.length > 24;

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          PdfSuperPremiumTheme.header(
            'Recibo de pagamento',
            branding: branding,
            extraLines: const [],
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nf.format(valor),
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  pdfSafeText(extenso),
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            pdfSafeText(
              'Recebemos de ${branding.churchName}, a importância acima, referente a:',
            ),
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.3),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              pdfSafeText(referente.isEmpty ? '-' : referente),
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Beneficiário',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            pdfSafeText(fornecedorNome),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (fornecedorCpfCnpj != null && fornecedorCpfCnpj.trim().isNotEmpty)
            pw.Text(
              pdfSafeText('CPF/CNPJ: $fornecedorCpfCnpj'),
              style: const pw.TextStyle(fontSize: 9.5),
            ),
          if (fornecedorEndereco != null && fornecedorEndereco.trim().isNotEmpty)
            pw.Text(
              pdfSafeText(fornecedorEndereco),
              style: const pw.TextStyle(fontSize: 9.5),
            ),
          pw.SizedBox(height: 18),
          if (textoLegalExtra.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                pdfSafeText(textoLegalExtra),
                style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
              ),
            ),
          pw.Spacer(),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text('Data: $dataStr', style: const pw.TextStyle(fontSize: 9.5)),
                    pw.SizedBox(height: hasChurchStamp || hasChurchSig ? 6 : 24),
                    if (hasChurchStamp)
                      pdfDigitalCertificateStampBlock(
                        churchDigitalStamp,
                        maxWidth: 210,
                      )
                    else if (hasChurchSig)
                      pw.SizedBox(
                        width: 150,
                        height: 28,
                        child: pw.Image(
                          pw.MemoryImage(churchSignatureImageBytes),
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
                      ),
                      height: 1,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      pdfSafeText(
                        churchSignerName.trim().isEmpty
                            ? 'Assinatura — ${branding.churchName}'
                            : churchSignerRole.trim().isEmpty
                                ? churchSignerName.trim()
                                : '${churchSignerName.trim()} — ${churchSignerRole.trim()}',
                      ),
                      style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.1),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.SizedBox(height: hasChurchStamp || hasChurchSig ? 34 : 52),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
                      ),
                      height: 1,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      pdfSafeText('Assinatura — $fornecedorNome'),
                      style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.1),
                      textAlign: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
        ],
      ),
    ),
  );
  return Uint8List.fromList(await pdf.save());
}
