import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Histórico financeiro + compromissos de um fornecedor.
///
/// Mesmo desenho do extrato de membro/fornecedor: cartão de identidade com o
/// **nome** em destaque, indicadores no topo e tabelas no padrão premium. Antes
/// era o único relatório do módulo ainda com a tabela cinzenta antiga, colunas
/// estreitas demais (a data partia-se ao meio) e a data lida só de `Timestamp`
/// — lançamentos gravados com data em texto saíam todos com «—».
Future<Uint8List> buildFornecedorHistoricoPdf({
  required ReportPdfBranding branding,
  required String fornecedorNome,
  required List<Map<String, dynamic>> lancamentos,
  required List<Map<String, dynamic>> compromissos,
  List<String> filterSummaryLines = const [],
  String periodoLabel = '',
  DateTime? generatedAt,
}) async {
  final money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final dayFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  final when = generatedAt ?? DateTime.now();
  final accent = branding.accent;

  const corEntrada = PdfColor.fromInt(0xFF15803D);
  const corSaida = PdfColor.fromInt(0xFFB91C1C);
  const corSaldo = PdfColor.fromInt(0xFF1D4ED8);
  const corAviso = PdfColor.fromInt(0xFFB45309);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const muted = PdfColor.fromInt(0xFF64748B);
  const borda = PdfColor.fromInt(0xFFE2E8F0);

  final nomeLimpo = pdfSafeText(fornecedorNome).trim();
  final nome = nomeLimpo.isEmpty ? 'Fornecedor sem nome' : nomeLimpo;

  var despesas = 0.0;
  var receitas = 0.0;
  var pendentes = 0.0;
  final finRows = <List<String>>[];
  final porCategoria = <String, double>{};
  final contagemCategoria = <String, int>{};

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
    if (isSaida) {
      despesas += v;
    } else if (t.contains('entrada') || t.contains('receita')) {
      receitas += v;
    }
    final pendente = (m['status'] ?? '').toString().trim() == 'pending';
    if (pendente) pendentes += v;

    final cat = (m['categoria'] ?? m['category'] ?? '').toString().trim();
    final catKey = cat.isEmpty ? 'Sem categoria' : cat;
    porCategoria[catKey] = (porCategoria[catKey] ?? 0) + v;
    contagemCategoria[catKey] = (contagemCategoria[catKey] ?? 0) + 1;

    // `financeLancamentoDate` entende Timestamp, DateTime, mapa e texto — a
    // versão anterior só lia Timestamp e perdia a data de tudo o resto.
    final dt = financeLancamentoDate(m);
    finRows.add([
      dt != null ? dayFmt.format(dt) : '—',
      isSaida ? 'Despesa' : 'Receita',
      pdfSafeText(catKey),
      pdfSafeText((m['descricao'] ?? m['description'] ?? '').toString()),
      pendente ? 'Pendente' : 'Pago',
      money.format(v),
    ]);
  }

  final compRows = <List<String>>[];
  var compAbertos = 0;
  final compOrdenados = [...compromissos]..sort((a, b) {
    final da = financeLancamentoDate(a) ?? _dataCompromisso(a);
    final db = financeLancamentoDate(b) ?? _dataCompromisso(b);
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  for (final m in compOrdenados) {
    final dt = _dataCompromisso(m);
    final val = m['valorEstimado'] ?? m['valor'];
    final v = financeParseValorBr(val);
    final status = (m['status'] ?? 'pendente').toString().trim();
    if (status.toLowerCase().startsWith('pend')) compAbertos++;
    compRows.add([
      dt != null ? dtFmt.format(dt) : '—',
      pdfSafeText((m['titulo'] ?? m['descricao'] ?? '').toString()),
      pdfSafeText(status.isEmpty ? 'pendente' : status),
      v > 0 ? money.format(v) : '—',
    ]);
  }

  final saldo = receitas - despesas;
  final movimento = receitas + despesas;
  final categorias = porCategoria.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // ─────────────────────────────── peças visuais

  pw.Widget statCard(String label, String value, PdfColor cor) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 3.5),
        padding: const pw.EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: borda, width: 1),
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

  pw.Widget cartaoIdentidade() {
    final inicial = nome.substring(0, 1).toUpperCase();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: borda, width: 1),
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
                  'FORNECEDOR',
                  style: pw.TextStyle(
                    fontSize: 7.6,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.1,
                    color: muted,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  nome,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          if (periodoLabel.trim().isNotEmpty)
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
          border: pw.Border.all(color: borda, width: 1),
        ),
        child: pw.Text(
          pdfSafeText(texto),
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
      );

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          'Histórico do fornecedor - $nome',
          branding: branding,
          extraLines: [
            'Fornecedor: $nome',
            ...filterSummaryLines,
            'Despesas: ${money.format(despesas)} · Receitas: ${money.format(receitas)} · Saldo: ${money.format(saldo)}',
            'Lançamentos: ${finRows.length} · Compromissos: ${compRows.length}',
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
            statCard('Despesas', money.format(despesas), corSaida),
            statCard('Receitas', money.format(receitas), corEntrada),
            statCard('Saldo', money.format(saldo), corSaldo),
            statCard(
              'Pendentes',
              pendentes > 0 ? money.format(pendentes) : '—',
              pendentes > 0 ? corAviso : muted,
            ),
            statCard(
              'Compromissos',
              compAbertos > 0
                  ? '${compRows.length} ($compAbertos aberto/s)'
                  : '${compRows.length}',
              accent,
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        if (categorias.isNotEmpty) ...[
          tituloSecao('Resumo por categoria'),
          pw.SizedBox(height: 8),
          PdfSuperPremiumTheme.fromTextArray(
            headers: const ['Categoria', 'Lanç.', 'Total', '% do total'],
            data: [
              for (final e in categorias.take(14))
                [
                  pdfSafeText(e.key),
                  '${contagemCategoria[e.key] ?? 0}',
                  money.format(e.value),
                  movimento <= 0
                      ? '—'
                      : '${((e.value / movimento) * 100).toStringAsFixed(1)}%',
                ],
            ],
            accent: accent,
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FixedColumnWidth(42),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(78),
            },
            cellAlignmentsExtra: {
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 18),
        ],
        tituloSecao('Lançamentos de $nome'),
        pw.SizedBox(height: 8),
        if (finRows.isEmpty)
          vazio('Nenhum lançamento vinculado a este fornecedor.')
        else
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              'Data',
              'Tipo',
              'Categoria',
              'Descrição',
              'Status',
              'Valor',
            ],
            data: finRows,
            accent: accent,
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
        pw.SizedBox(height: 18),
        tituloSecao('Compromissos, visitas e manutenção'),
        pw.SizedBox(height: 8),
        if (compRows.isEmpty)
          vazio('Nenhum compromisso registado para este fornecedor.')
        else
          PdfSuperPremiumTheme.fromTextArray(
            headers: const ['Data e hora', 'Descrição', 'Status', 'Valor prev.'],
            data: compRows,
            accent: accent,
            // «22/07/2026 15:54» precisa de ~92pt com o recuo da célula; com os
            // 78pt antigos a hora caía para a linha de baixo.
            columnWidths: {
              0: const pw.FixedColumnWidth(96),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(66),
              3: const pw.FixedColumnWidth(70),
            },
            cellAlignmentsExtra: {
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
            },
          ),
      ],
    ),
  );
  return pdf.save();
}

/// Data do compromisso — aceita os vários formatos já gravados no Firestore.
DateTime? _dataCompromisso(Map<String, dynamic> m) => financeLancamentoDate({
      'date': m['dataVencimento'] ?? m['data'] ?? m['date'] ?? m['createdAt'],
    });
