import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Extrato financeiro de **uma pessoa** — membro ou fornecedor.
///
/// É o mesmo documento para os dois porque a pergunta é a mesma: quanto entrou
/// e quanto saiu por causa desta pessoa, no período escolhido. Só mudam as
/// palavras do cabeçalho («contribuiu» faz sentido para membro, não para
/// fornecedor).
///
/// **Não leva saldo de bancos.** O saldo da igreja não diz nada sobre um
/// fornecedor em particular, e pô-lo aqui já fez o utilizador ler o saldo
/// negativo da igreja como dívida àquele fornecedor.
Future<Uint8List> buildFinanceVinculoExtratoPdf({
  required ReportPdfBranding branding,
  required String tipo,
  required String nome,
  required List<Map<String, dynamic>> lancamentos,
  required String periodoLabel,
  DateTime? generatedAt,
}) async {
  final ehMembro = tipo == 'membro';
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final dayFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  final when = generatedAt ?? DateTime.now();

  var despesas = 0.0;
  var receitas = 0.0;
  var pendentes = 0.0;
  final linhas = <List<String>>[];
  // Totais por categoria: é o que responde «em que é que este dinheiro foi
  // parar» sem obrigar a somar a tabela à mão.
  final porCategoria = <String, double>{};

  final ordenados = [...lancamentos]..sort((a, b) {
    final da = financeLancamentoDate(a);
    final db = financeLancamentoDate(b);
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });

  for (final m in ordenados) {
    final t = financeInferTipo(m);
    if (t == 'transferencia') continue;
    final v = financeParseValorBr(m['amount'] ?? m['valor']);
    final isSaida = t.contains('saida') || t.contains('despesa');
    final isEntrada = t.contains('entrada') || t.contains('receita');
    if (isSaida) {
      despesas += v;
    } else if (isEntrada) {
      receitas += v;
    }
    final pendente = (m['status'] ?? '').toString().trim() == 'pending';
    if (pendente) pendentes += v;

    final categoria = (m['categoria'] ?? m['category'] ?? 'Sem categoria')
        .toString()
        .trim();
    final catKey = categoria.isEmpty ? 'Sem categoria' : categoria;
    porCategoria[catKey] = (porCategoria[catKey] ?? 0) + (isSaida ? v : -v);

    final dt = financeLancamentoDate(m);
    linhas.add([
      dt != null ? dayFmt.format(dt) : '—',
      isSaida ? 'Despesa' : 'Receita',
      pdfSafeText(catKey),
      pdfSafeText(
        (m['descricao'] ?? m['description'] ?? '').toString(),
      ),
      pendente ? 'Pendente' : 'Pago',
      money.format(v),
    ]);
  }

  final catOrdenadas = porCategoria.entries.toList()
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          'Extrato financeiro — $nome',
          branding: branding,
          extraLines: [
            ehMembro ? 'Membro' : 'Fornecedor',
            'Período: $periodoLabel',
            '---',
            ehMembro
                ? 'Contribuições: ${money.format(receitas)} · Despesas: ${money.format(despesas)} · Saldo: ${money.format(receitas - despesas)}'
                : 'Despesas: ${money.format(despesas)} · Receitas: ${money.format(receitas)} · Saldo: ${money.format(receitas - despesas)}',
            'Lançamentos: ${linhas.length}'
                '${pendentes > 0 ? ' · Pendentes: ${money.format(pendentes)}' : ''}',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        if (catOrdenadas.isNotEmpty) ...[
          pw.Text(
            'Resumo por categoria',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const ['Categoria', 'Total no período'],
            data: [
              for (final e in catOrdenadas.take(12))
                [
                  pdfSafeText(e.key),
                  money.format(e.value.abs()),
                ],
            ],
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
              1: const pw.FixedColumnWidth(86),
            },
          ),
          pw.SizedBox(height: 18),
        ],
        pw.Text(
          'Lançamentos',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        if (linhas.isEmpty)
          pw.Text(
            'Nenhum lançamento no período escolhido.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          pw.Table.fromTextArray(
            headers: const [
              'Data',
              'Tipo',
              'Categoria',
              'Descrição',
              'Status',
              'Valor',
            ],
            data: linhas,
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
              0: const pw.FixedColumnWidth(56),
              1: const pw.FixedColumnWidth(48),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(3),
              4: const pw.FixedColumnWidth(46),
              5: const pw.FixedColumnWidth(62),
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
