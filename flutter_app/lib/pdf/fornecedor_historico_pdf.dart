import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Histórico financeiro + compromissos de um fornecedor (PDF A4 retrato, rápido).
Future<Uint8List> buildFornecedorHistoricoPdf({
  required ReportPdfBranding branding,
  required String fornecedorNome,
  required List<Map<String, dynamic>> lancamentos,
  required List<Map<String, dynamic>> compromissos,
  List<String> filterSummaryLines = const [],
  DateTime? generatedAt,
}) async {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final dayFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  final when = generatedAt ?? DateTime.now();

  var despesas = 0.0;
  var receitas = 0.0;
  final finRows = <List<String>>[];

  for (final m in lancamentos) {
    final t = financeInferTipo(m);
    if (t == 'transferencia') continue;
    final v = financeParseValorBr(m['amount'] ?? m['valor']);
    final isSaida = t.contains('saida') || t.contains('despesa');
    if (isSaida) {
      despesas += v;
    } else if (t.contains('entrada') || t.contains('receita')) {
      receitas += v;
    }
    final ts = m['createdAt'] ?? m['date'];
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    finRows.add([
      dt != null ? dayFmt.format(dt) : '—',
      isSaida ? 'Despesa' : 'Receita',
      pdfSafeText((m['descricao'] ?? m['categoria'] ?? '').toString()),
      money.format(v),
    ]);
  }

  final compRows = <List<String>>[];
  for (final m in compromissos) {
    final ts = m['dataVencimento'];
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    final val = m['valorEstimado'];
    final vStr = val is num && val.toDouble() > 0
        ? money.format(val.toDouble())
        : '—';
    compRows.add([
      dt != null ? dtFmt.format(dt) : '—',
      pdfSafeText((m['titulo'] ?? '').toString()),
      (m['status'] ?? 'pendente').toString(),
      vStr,
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
          'Histórico — $fornecedorNome',
          branding: branding,
          extraLines: [
            ...filterSummaryLines,
            if (filterSummaryLines.isNotEmpty) '---',
            'Despesas: ${money.format(despesas)} · Receitas: ${money.format(receitas)} · Saldo: ${money.format(receitas - despesas)}',
            'Lançamentos: ${finRows.length} · Compromissos: ${compRows.length}',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        pw.Text(
          'Lançamentos financeiros',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        if (finRows.isEmpty)
          pw.Text('Nenhum lançamento vinculado.', style: const pw.TextStyle(fontSize: 10))
        else
          pw.Table.fromTextArray(
            headers: const ['Data', 'Tipo', 'Descrição', 'Valor'],
            data: finRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(58),
              1: const pw.FixedColumnWidth(52),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FixedColumnWidth(62),
            },
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Compromissos / visitas / manutenção',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        if (compRows.isEmpty)
          pw.Text('Nenhum compromisso registado.', style: const pw.TextStyle(fontSize: 10))
        else
          pw.Table.fromTextArray(
            headers: const ['Data/hora', 'Descrição', 'Status', 'Valor prev.'],
            data: compRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FixedColumnWidth(78),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(52),
              3: const pw.FixedColumnWidth(58),
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
