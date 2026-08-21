import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/ui/pages/membros_financeiro_geral_page.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Relatório geral: quanto cada membro contribuiu e gastou no período.
///
/// Sai na ordem em que está na tela — se o utilizador ordenou por «mais
/// contribuiu», o PDF sai assim. O papel tem de conferir com o que ele viu.
Future<Uint8List> buildMembrosFinanceiroGeralPdf({
  required ReportPdfBranding branding,
  required List<MembroFinanceiroLinha> linhas,
  required String periodoLabel,
  required String filtroLabel,
  DateTime? generatedAt,
}) async {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final when = generatedAt ?? DateTime.now();

  var totalRec = 0.0;
  var totalDes = 0.0;
  final rows = <List<String>>[];
  for (final l in linhas) {
    totalRec += l.receitas;
    totalDes += l.despesas;
    rows.add([
      pdfSafeText(l.nome),
      pdfSafeText(
        l.departamentos.isEmpty ? '—' : l.departamentos.join(', '),
      ),
      money.format(l.receitas),
      money.format(l.despesas),
      money.format(l.saldo),
    ]);
  }

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          'Financeiro por membro',
          branding: branding,
          extraLines: [
            'Período: $periodoLabel',
            'Filtro: $filtroLabel',
            '---',
            'Contribuições: ${money.format(totalRec)} · '
                'Despesas: ${money.format(totalDes)} · '
                'Saldo: ${money.format(totalRec - totalDes)}',
            'Membros com movimento: ${rows.length}',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        if (rows.isEmpty)
          pw.Text(
            'Nenhum membro com movimento no período escolhido.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          pw.Table.fromTextArray(
            headers: const [
              'Membro',
              'Departamento',
              'Contribuições',
              'Despesas',
              'Saldo',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE2E8F0),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FixedColumnWidth(72),
              3: const pw.FixedColumnWidth(66),
              4: const pw.FixedColumnWidth(66),
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
