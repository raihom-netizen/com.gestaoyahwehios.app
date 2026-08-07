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

  final rows = visitantes
      .map(
        (v) => [
          v.createdAt != null ? dayFmt.format(v.createdAt!) : '—',
          pdfSafeText(v.nome.isEmpty ? '—' : v.nome),
          pdfSafeText(v.telefone.isEmpty ? '—' : v.telefone),
          pdfSafeText(v.email.isEmpty ? '—' : v.email),
          pdfSafeText(v.status.isEmpty ? 'Novo' : v.status),
          pdfSafeText(v.comoConheceu.isEmpty ? '—' : v.comoConheceu),
        ],
      )
      .toList();

  final porStatus = <String, int>{};
  for (final v in visitantes) {
    final s = v.status.isEmpty ? 'Novo' : v.status;
    porStatus[s] = (porStatus[s] ?? 0) + 1;
  }
  final statusSummary = porStatus.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(' · ');

  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: PdfSuperPremiumTheme.header(
          'Relatório de Visitantes',
          branding: branding,
          extraLines: [
            'Período: $periodoLabel',
            'Total de visitantes: ${visitantes.length}',
            if (statusSummary.isNotEmpty) statusSummary,
          ],
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: 'Gerado em ${dtFmt.format(when)}',
      ),
      build: (ctx) => [
        pw.Text(
          'Visitantes no período',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        if (rows.isEmpty)
          pw.Text(
            'Nenhum visitante cadastrado neste período.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          pw.Table.fromTextArray(
            headers: const [
              'Data',
              'Nome',
              'Telefone',
              'E-mail',
              'Status',
              'Como conheceu',
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
              0: const pw.FixedColumnWidth(52),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FixedColumnWidth(64),
              5: const pw.FixedColumnWidth(70),
            },
          ),
      ],
    ),
  );
  return pdf.save();
}
