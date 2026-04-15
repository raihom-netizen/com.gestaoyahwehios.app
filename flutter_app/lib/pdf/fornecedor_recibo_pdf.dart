import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/valor_real_extenso.dart';

/// Recibo de pagamento a fornecedor/prestador (PDF A4 retrato).
Future<Uint8List> buildFornecedorReciboPdf({
  required ReportPdfBranding branding,
  required String fornecedorNome,
  String? fornecedorCpfCnpj,
  String? fornecedorEndereco,
  required double valor,
  required String referente,
  DateTime? dataPagamento,
  String textoLegalExtra = '',
}) async {
  final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dataStr = dataPagamento != null
      ? DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR').format(dataPagamento)
      : DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR').format(DateTime.now());
  final extenso = valorRealPorExtenso(valor);

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
          pw.SizedBox(height: 18),
          pw.Text(
            pdfSafeText(
              'Recebemos de ${branding.churchName}, inscrita neste ato, a importância de '
              '${nf.format(valor)} ($extenso), referente a:'),
            style: pw.TextStyle(fontSize: 11, lineSpacing: 1.35),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              pdfSafeText(referente.isEmpty ? '-' : referente),
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Dados do beneficiário (fornecedor/prestador):',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            pdfSafeText(fornecedorNome),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (fornecedorCpfCnpj != null && fornecedorCpfCnpj.trim().isNotEmpty)
            pw.Text(pdfSafeText('CPF/CNPJ: $fornecedorCpfCnpj'),
                style: const pw.TextStyle(fontSize: 10)),
          if (fornecedorEndereco != null && fornecedorEndereco.trim().isNotEmpty)
            pw.Text(pdfSafeText(fornecedorEndereco),
                style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 24),
          if (textoLegalExtra.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                pdfSafeText(textoLegalExtra),
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Data: $dataStr', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 28),
                  pw.Container(
                    width: 220,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    pdfSafeText(
                        'Assinatura / carimbo - ${branding.churchName}'),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
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
