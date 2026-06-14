import 'dart:typed_data';

import 'package:gestao_yahweh/services/prayer_pedidos_filter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Gera PDF do painel analítico de Pedidos de Oração.
abstract final class PrayerPedidosReportPdf {
  PrayerPedidosReportPdf._();

  static Future<Uint8List> build({
    required String churchName,
    required PrayerPedidosAnalyticsSnapshot stats,
    required PrayerPedidosFilter filter,
    required DateTime generatedAt,
  }) async {
    final doc = pw.Document();
    final (start, end) = filter.resolveRange(now: generatedAt);
    final periodLabel = _periodLabel(filter, start, end);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text(
            'Relatório — Pedidos de Oração',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Igreja: $churchName'),
          pw.Text('Gerado em: ${_fmtDateTime(generatedAt)}'),
          pw.Text('Período: $periodLabel'),
          if (filter.categoria != null)
            pw.Text('Categoria: ${filter.categoria}'),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _kpiBox('Total', '${stats.total}'),
              _kpiBox('Abertos', '${stats.abertos}'),
              _kpiBox('Respondidos', '${stats.respondidos}'),
              _kpiBox('Intercessões', '${stats.totalIntercessoes}'),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Por categoria',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          ...stats.porCategoria.entries.map(
            (e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(e.key)),
                  pw.Text('${e.value}'),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Top intercessores',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          if (stats.topIntercessores.isEmpty)
            pw.Text('Nenhum registro no período.')
          else
            ...stats.topIntercessores.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  children: [
                    pw.Expanded(child: pw.Text(e.key)),
                    pw.Text('${e.value}'),
                  ],
                ),
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Por mês',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          ...stats.porMes.entries.map(
            (e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(e.key)),
                  pw.Text('${e.value}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _kpiBox(String label, String value) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDateTime(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _periodLabel(
    PrayerPedidosFilter filter,
    DateTime? start,
    DateTime? end,
  ) {
    switch (filter.period) {
      case PrayerPeriodPreset.all:
        return 'Todos';
      case PrayerPeriodPreset.week:
        return 'Esta semana';
      case PrayerPeriodPreset.month:
        return 'Este mês';
      case PrayerPeriodPreset.year:
        return 'Este ano';
      case PrayerPeriodPreset.custom:
        if (start == null && end == null) return 'Personalizado';
        final s = start != null ? _fmtDate(start) : '…';
        final e = end != null ? _fmtDate(end) : '…';
        return '$s — $e';
    }
  }

  static String _fmtDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
