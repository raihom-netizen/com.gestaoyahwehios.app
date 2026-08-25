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
///
/// O **nome do membro** é a coluna que manda: é por ele que o tesoureiro
/// procura na folha impressa. Por isso vai em primeiro lugar depois da posição,
/// com largura suficiente para o nome completo não se partir.
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
  final accent = branding.accent;

  const corEntrada = PdfColor.fromInt(0xFF15803D);
  const corSaida = PdfColor.fromInt(0xFFB91C1C);
  const corSaldo = PdfColor.fromInt(0xFF1D4ED8);
  const ink = PdfColor.fromInt(0xFF0F172A);
  const muted = PdfColor.fromInt(0xFF64748B);
  const borda = PdfColor.fromInt(0xFFE2E8F0);

  var totalRec = 0.0;
  var totalDes = 0.0;
  var totalLanc = 0;
  final rows = <List<String>>[];
  for (var i = 0; i < linhas.length; i++) {
    final l = linhas[i];
    totalRec += l.receitas;
    totalDes += l.despesas;
    totalLanc += l.lancamentos;
    final nome = pdfSafeText(l.nome).trim();
    rows.add([
      '${i + 1}',
      nome.isEmpty ? 'Membro sem nome' : nome,
      pdfSafeText(l.departamentos.isEmpty ? '—' : l.departamentos.join(', ')),
      '${l.lancamentos}',
      money.format(l.receitas),
      money.format(l.despesas),
      money.format(l.saldo),
    ]);
  }
  final totalSaldo = totalRec - totalDes;

  // Pódio: quem mais contribuiu no período, independentemente da ordenação
  // escolhida na tela. É a primeira coisa que perguntam ao ver o relatório.
  final topContribuintes = [...linhas.where((l) => l.receitas > 0)]
    ..sort((a, b) => b.receitas.compareTo(a.receitas));

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

  /// Linha do pódio: posição + nome do membro + barra de proporção + valor.
  pw.Widget linhaPodio(int pos, MembroFinanceiroLinha l, double maximo) {
    final frac = maximo <= 0 ? 0.0 : (l.receitas / maximo).clamp(0.0, 1.0);
    final cheio = (frac * 1000).round().clamp(8, 1000);
    final nome = pdfSafeText(l.nome).trim();
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 15,
                height: 15,
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(right: 7),
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  '$pos',
                  style: pw.TextStyle(
                    fontSize: 7.6,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  nome.isEmpty ? 'Membro sem nome' : nome,
                  maxLines: 1,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
              ),
              pw.Text(
                money.format(l.receitas),
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: corEntrada,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          // Barra de proporção por `flex` — o `package:pdf` não tem
          // FractionallySizedBox, e dois Expanded dão a mesma leitura.
          pw.Container(
            height: 5,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF1F5F9),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: cheio,
                  child: pw.Container(
                    height: 5,
                    decoration: pw.BoxDecoration(
                      color: corEntrada,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                  ),
                ),
                if (cheio < 1000)
                  pw.Expanded(flex: 1000 - cheio, child: pw.SizedBox(height: 5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Faixa de fecho: os totais que têm de bater com a tela.
  pw.Widget faixaTotais() => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF8FAFC),
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: borda, width: 1),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'TOTAL DE ${rows.length} MEMBRO(S) - $totalLanc LANÇAMENTO(S)',
                style: pw.TextStyle(
                  fontSize: 8.4,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.6,
                  color: muted,
                ),
              ),
            ),
            pw.Text(
              'Contribuições ${money.format(totalRec)}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: corEntrada,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Despesas ${money.format(totalDes)}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: corSaida,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Saldo ${money.format(totalSaldo)}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: corSaldo,
              ),
            ),
          ],
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
          'Financeiro por membro',
          branding: branding,
          extraLines: [
            'Período: $periodoLabel  ·  Filtro: $filtroLabel',
            'Contribuições: ${money.format(totalRec)} · '
                'Despesas: ${money.format(totalDes)} · '
                'Saldo: ${money.format(totalSaldo)}',
            'Membros com movimento: ${rows.length}',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            statCard('Contribuições', money.format(totalRec), corEntrada),
            statCard('Despesas', money.format(totalDes), corSaida),
            statCard('Saldo', money.format(totalSaldo), corSaldo),
            statCard('Membros', '${rows.length}', accent),
            statCard('Lançamentos', '$totalLanc', accent),
          ],
        ),
        pw.SizedBox(height: 18),
        if (topContribuintes.length >= 2) ...[
          tituloSecao('Quem mais contribuiu'),
          pw.SizedBox(height: 9),
          for (var i = 0; i < topContribuintes.length && i < 5; i++)
            linhaPodio(i + 1, topContribuintes[i], topContribuintes.first.receitas),
          pw.SizedBox(height: 12),
        ],
        tituloSecao('Membros no período'),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF8FAFC),
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: borda, width: 1),
            ),
            child: pw.Text(
              'Nenhum membro com movimento no período escolhido.',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
          )
        else ...[
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              '#',
              'Membro',
              'Departamento',
              'Lanç.',
              'Contribuiu',
              'Despesas',
              'Saldo',
            ],
            data: rows,
            accent: accent,
            // O nome do membro leva a maior fatia; o dinheiro fica fixo com
            // folga para não partir no meio («R$ 1.234, 56»).
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(2.7),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FixedColumnWidth(36),
              4: const pw.FixedColumnWidth(72),
              5: const pw.FixedColumnWidth(68),
              6: const pw.FixedColumnWidth(68),
            },
            cellAlignmentsExtra: {
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
            },
          ),
          faixaTotais(),
        ],
      ],
    ),
  );
  return pdf.save();
}
