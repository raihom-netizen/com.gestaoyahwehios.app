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
/// **De quem é o extrato tem de estar na cara.** A versão anterior punha o nome
/// só numa linha cinzenta de 10pt do cabeçalho: quem imprimia a folha ficava
/// com uma tabela de lançamentos sem dono. Agora há um cartão de identidade no
/// topo (nome grande + inicial) e o nome repete-se no cabeçalho de cada página.
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
  String filtroLabel = 'Todos os lançamentos',
  List<String> departamentos = const [],
  DateTime? generatedAt,
}) async {
  final ehMembro = tipo == 'membro';
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final dayFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  final when = generatedAt ?? DateTime.now();
  final accent = branding.accent;

  const corEntrada = PdfColor.fromInt(0xFF15803D);
  const corSaida = PdfColor.fromInt(0xFFB91C1C);
  const corSaldo = PdfColor.fromInt(0xFF1D4ED8);
  const corPendente = PdfColor.fromInt(0xFFB45309);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const muted = PdfColor.fromInt(0xFF64748B);
  const linha = PdfColor.fromInt(0xFFE2E8F0);

  final nomeLimpo = pdfSafeText(nome).trim();
  final nomeExibido = nomeLimpo.isEmpty
      ? (ehMembro ? 'Membro sem nome' : 'Fornecedor sem nome')
      : nomeLimpo;

  var despesas = 0.0;
  var receitas = 0.0;
  var pendentes = 0.0;
  final linhas = <List<String>>[];

  // Totais por categoria. Entradas e saídas ficam **separadas**: somá-las no
  // mesmo número fazia uma categoria com receita e despesa aparecer quase a
  // zero, como se não tivesse movimento nenhum.
  final catEntradas = <String, double>{};
  final catSaidas = <String, double>{};
  final catContagem = <String, int>{};

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
    if (isSaida) {
      catSaidas[catKey] = (catSaidas[catKey] ?? 0) + v;
    } else {
      catEntradas[catKey] = (catEntradas[catKey] ?? 0) + v;
    }
    catContagem[catKey] = (catContagem[catKey] ?? 0) + 1;

    final dt = financeLancamentoDate(m);
    linhas.add([
      dt != null ? dayFmt.format(dt) : '—',
      isSaida ? 'Despesa' : 'Receita',
      pdfSafeText(catKey),
      pdfSafeText((m['descricao'] ?? m['description'] ?? '').toString()),
      pendente ? 'Pendente' : 'Pago',
      money.format(v),
    ]);
  }

  final saldo = receitas - despesas;
  final movimentoTotal = receitas + despesas;

  final catChaves = {...catEntradas.keys, ...catSaidas.keys}.toList()
    ..sort((a, b) {
      final ta = (catEntradas[a] ?? 0) + (catSaidas[a] ?? 0);
      final tb = (catEntradas[b] ?? 0) + (catSaidas[b] ?? 0);
      return tb.compareTo(ta);
    });

  // ─────────────────────────────── peças visuais

  /// Cartão de indicador: barra de acento + número grande + rótulo.
  pw.Widget statCard(String label, String value, PdfColor cor) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3.5),
        padding: const pw.EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: linha, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              width: 24,
              height: 3.4,
              decoration: pw.BoxDecoration(
                color: cor,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: cor,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              pdfSafeText(label),
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Cartão de identidade — de quem é este extrato, sem depender do cabeçalho.
  pw.Widget cartaoIdentidade() {
    final inicial =
        nomeExibido.isEmpty ? '?' : nomeExibido.substring(0, 1).toUpperCase();
    final deptos = departamentos
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(pdfSafeText)
        .toList();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: linha, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 40,
            height: 40,
            margin: const pw.EdgeInsets.only(right: 12),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(20),
            ),
            child: pw.Text(
              inicial,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  ehMembro ? 'MEMBRO' : 'FORNECEDOR',
                  style: pw.TextStyle(
                    fontSize: 7.6,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.1,
                    color: muted,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  nomeExibido,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
                if (deptos.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    deptos.join(' - '),
                    maxLines: 1,
                    style: const pw.TextStyle(fontSize: 8.4, color: muted),
                  ),
                ],
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'PERÍODO',
                style: pw.TextStyle(
                  fontSize: 7.6,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.1,
                  color: muted,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                pdfSafeText(periodoLabel),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                pdfSafeText(filtroLabel),
                style: const pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget tituloSecao(String texto) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 3.5,
            height: 13,
            margin: const pw.EdgeInsets.only(right: 7),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.Text(
            pdfSafeText(texto),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
        ],
      );

  pw.Widget vazio(String texto) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF8FAFC),
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: linha, width: 1),
        ),
        child: pw.Text(
          pdfSafeText(texto),
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
      );

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.MultiPage(
      // Uma tabela longa é UM widget que ocupa muitas páginas: o limite padrão
      // de 20 do pacote abortava o relatório grande com TooManyPagesException.
      maxPages: 2000,
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          'Extrato financeiro - $nomeExibido',
          branding: branding,
          extraLines: [
            '${ehMembro ? 'Membro' : 'Fornecedor'}: $nomeExibido',
            'Período: $periodoLabel  ·  Filtro: $filtroLabel',
            ehMembro
                ? 'Contribuições: ${money.format(receitas)} · Despesas: ${money.format(despesas)} · Saldo: ${money.format(saldo)}'
                : 'Despesas: ${money.format(despesas)} · Receitas: ${money.format(receitas)} · Saldo: ${money.format(saldo)}',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        cartaoIdentidade(),
        pw.SizedBox(height: 12),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            statCard(
              ehMembro ? 'Contribuições' : 'Receitas',
              money.format(receitas),
              corEntrada,
            ),
            statCard('Despesas', money.format(despesas), corSaida),
            statCard('Saldo', money.format(saldo), corSaldo),
            statCard(
              'Pendentes',
              pendentes > 0 ? money.format(pendentes) : '—',
              pendentes > 0 ? corPendente : muted,
            ),
            statCard('Lançamentos', '${linhas.length}', accent),
          ],
        ),
        pw.SizedBox(height: 18),
        if (catChaves.isNotEmpty) ...[
          tituloSecao('Resumo por categoria'),
          pw.SizedBox(height: 8),
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              'Categoria',
              'Lanç.',
              'Entradas',
              'Saídas',
              '% do total',
            ],
            data: [
              for (final k in catChaves.take(14))
                [
                  pdfSafeText(k),
                  '${catContagem[k] ?? 0}',
                  (catEntradas[k] ?? 0) > 0
                      ? money.format(catEntradas[k]!)
                      : '—',
                  (catSaidas[k] ?? 0) > 0 ? money.format(catSaidas[k]!) : '—',
                  movimentoTotal <= 0
                      ? '—'
                      : '${((((catEntradas[k] ?? 0) + (catSaidas[k] ?? 0)) / movimentoTotal) * 100).toStringAsFixed(1)}%',
                ],
            ],
            accent: accent,
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FixedColumnWidth(42),
              2: const pw.FixedColumnWidth(74),
              3: const pw.FixedColumnWidth(74),
              4: const pw.FixedColumnWidth(78),
            },
            cellAlignmentsExtra: {
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 18),
        ],
        tituloSecao('Lançamentos de $nomeExibido'),
        pw.SizedBox(height: 8),
        if (linhas.isEmpty)
          vazio('Nenhum lançamento no período escolhido.')
        else
          ...PdfSuperPremiumTheme.fromTextArrayChunks(
            headers: const [
              'Data',
              'Tipo',
              'Categoria',
              'Descrição',
              'Status',
              'Valor',
            ],
            data: linhas,
            accent: accent,
            // Larguras à prova de quebra: a data só cabe inteira com ~64pt
            // (8pt de recuo de cada lado). Com menos, «25/08/2026» partia-se
            // ao meio e o relatório saía desconfigurado.
            columnWidths: {
              0: const pw.FixedColumnWidth(64),
              1: const pw.FixedColumnWidth(54),
              2: const pw.FlexColumnWidth(1.15),
              3: const pw.FlexColumnWidth(2.0),
              4: const pw.FixedColumnWidth(58),
              5: const pw.FixedColumnWidth(70),
            },
            cellAlignmentsExtra: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              4: pw.Alignment.center,
              5: pw.Alignment.centerRight,
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
