import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Uma linha do relatório — já achatada para não depender do widget da tela.
class VisitantesRelatorioRow {
  const VisitantesRelatorioRow({
    required this.nome,
    required this.telefone,
    required this.email,
    required this.status,
    required this.comoConheceu,
    required this.createdAt,
  });

  final String nome;
  final String telefone;
  final String email;
  final String status;
  final String comoConheceu;
  final DateTime? createdAt;
}

/// Relatório de visitantes (acompanhamento) — dia/mês/ano, cabeçalho e
/// rodapé padrão do sistema (mesmo `PdfSuperPremiumTheme` dos outros PDFs).
Future<Uint8List> buildVisitantesRelatorioPdf({
  required ReportPdfBranding branding,
  required List<VisitantesRelatorioRow> visitantes,
  required String periodoLabel,
  DateTime? generatedAt,
}) async {
  final dayFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  final when = generatedAt ?? DateTime.now();

  final accent = branding.accent;

  final rows = <List<String>>[];
  for (var i = 0; i < visitantes.length; i++) {
    final v = visitantes[i];
    rows.add([
      '${i + 1}',
      v.createdAt != null ? dayFmt.format(v.createdAt!) : '—',
      pdfSafeText(v.nome.isEmpty ? '—' : v.nome),
      pdfSafeText(v.telefone.isEmpty ? '—' : v.telefone),
      pdfSafeText(v.email.isEmpty ? '—' : v.email),
      pdfSafeText(v.status.isEmpty ? 'Novo' : v.status),
      pdfSafeText(v.comoConheceu.isEmpty ? '—' : v.comoConheceu),
    ]);
  }

  // KPIs por status — grid de cards no topo (Total / Novos / Acompanhamento / Convertidos).
  var novos = 0, acompanhamento = 0, convertidos = 0;
  for (final v in visitantes) {
    final s = (v.status.isEmpty ? 'novo' : v.status).toLowerCase();
    if (s.contains('convert')) {
      convertidos++;
    } else if (s.contains('acompanh') || s.contains('follow')) {
      acompanhamento++;
    } else {
      novos++;
    }
  }

  // Card de KPI (grid moderno) — barra de acento + número grande + rótulo.
  pw.Widget statCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(
            color: const PdfColor.fromInt(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Container(
              width: 26,
              height: 3.4,
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF0F172A),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              pdfSafeText(label),
              style: pw.TextStyle(
                fontSize: 8.4,
                color: const PdfColor.fromInt(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          'Relatório de Visitantes',
          branding: branding,
          extraLines: [
            'Período: $periodoLabel',
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        // Grid de indicadores (cards) — visão rápida do período.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            statCard('Total de visitantes', '${visitantes.length}', accent),
            statCard('Novos', '$novos', const PdfColor.fromInt(0xFF2563EB)),
            statCard('Em acompanhamento', '$acompanhamento',
                const PdfColor.fromInt(0xFFF59E0B)),
            statCard('Convertidos', '$convertidos',
                const PdfColor.fromInt(0xFF16A34A)),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Visitantes no período',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF8FAFC),
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFE2E8F0), width: 1),
            ),
            child: pw.Text(
              'Nenhum visitante cadastrado neste período.',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColor.fromInt(0xFF64748B)),
            ),
          )
        else
          ...PdfSuperPremiumTheme.fromTextArrayChunks(
            headers: const [
              '#',
              'Data',
              'Nome',
              'Telefone',
              'E-mail',
              'Status',
              'Como conheceu',
            ],
            data: rows,
            accent: accent,
            columnWidths: {
              0: const pw.FixedColumnWidth(26),
              1: const pw.FixedColumnWidth(52),
              2: const pw.FlexColumnWidth(2.4),
              3: const pw.FixedColumnWidth(64),
              4: const pw.FlexColumnWidth(2.2),
              5: const pw.FixedColumnWidth(58),
              6: const pw.FixedColumnWidth(66),
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
