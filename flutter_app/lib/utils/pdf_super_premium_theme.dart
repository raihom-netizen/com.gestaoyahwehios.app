import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Tema Super Premium para relatórios PDF: cartão claro, borda suave, logo da igreja, tipografia sóbria.
class PdfSuperPremiumTheme {
  PdfSuperPremiumTheme._();

  static pw.ThemeData? _robotoPdfTheme;

  /// Roboto dos assets — acentos, `@`, cifrão e símbolos comuns (evita “tofu” da Helvetica padrão).
  static Future<pw.ThemeData?> loadRobotoPdfTheme() async {
    if (_robotoPdfTheme != null) return _robotoPdfTheme;
    try {
      final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      final italic = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
      _robotoPdfTheme = pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        italic: pw.Font.ttf(italic),
        boldItalic: pw.Font.ttf(bold),
      );
    } catch (e, st) {
      debugPrint('PdfSuperPremiumTheme: Roboto PDF — $e\n$st');
      _robotoPdfTheme = null;
    }
    return _robotoPdfTheme;
  }

  static Future<pw.Document> newPdfDocument() async {
    final t = await loadRobotoPdfTheme();
    return t != null ? pw.Document(theme: t) : pw.Document();
  }

  /// Cabeçalhos mais curtos só no PDF — evita partir palavras em colunas estreitas.
  static String _compactTableHeader(String raw) {
    final h = raw.trim();
    const map = <String, String>{
      'Data de nascimento': 'Nascimento',
      'Faixa etária': 'Faixa',
      'Departamento': 'Depto.',
      'Gênero': 'Sexo',
    };
    return map[h] ?? h;
  }

  static PdfColor get _border => PdfColor.fromInt(0xFFE2E8F0);
  static PdfColor get _cardBg => PdfColors.white;
  static PdfColor get _muted => PdfColor.fromInt(0xFF64748B);
  static PdfColor get _ink => PdfColor.fromInt(0xFF0F172A);
  static PdfColor get _tableHeaderBg => PdfColor.fromInt(0xFFF1F5F9);

  /// Largura fixa da coluna índice (# / ordem). ≥44pt para 3 dígitos sem empilhar caracteres no `pdf`.
  static const double indexColumnPt = 44;

  /// Margem uniforme A4 nos PDFs do painel (relatórios, recibos).
  static const double _margin = 44;

  /// Margem A4 cartas ministeriais (~3 cm) — normas cultas / ofício.
  static const double churchLetterMarginPt = 85;

  static pw.EdgeInsets get churchLetterPageMargin =>
      const pw.EdgeInsets.all(churchLetterMarginPt);

  /// Logo do cabeçalho (pt): destaque forte nos relatórios (Financeiro, Patrimônio, etc.).
  static const double headerLogoSizePt = 136;

  static pw.EdgeInsets get pageMargin => const pw.EdgeInsets.all(_margin);

  static pw.TextStyle get reportTitleStyle => pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      );

  static pw.TextStyle get dateStyle =>
      pw.TextStyle(fontSize: 9, color: _muted);

  static pw.TextStyle tableHeaderStyleFor(PdfColor accent) => pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 8.65,
        color: accent,
        letterSpacing: 0,
      );

  static pw.BoxDecoration tableHeaderDecorationFor(PdfColor accent) =>
      pw.BoxDecoration(
        color: _tableHeaderBg,
        border: pw.Border(
          bottom: pw.BorderSide(color: accent, width: 2),
        ),
      );

  static pw.TextStyle get tableCellStyle => const pw.TextStyle(
        fontSize: 8.65,
        color: PdfColors.grey800,
        lineSpacing: 1.18,
      );

  static pw.EdgeInsets get tableCellPadding =>
      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6);

  /// Borda suave: contorno + linhas internas leves (menos peso que grade completa espessa).
  static pw.TableBorder get _tableBorderSoft => pw.TableBorder(
        top: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 1.05),
        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 1.05),
        left: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 1.05),
        right: pw.BorderSide(color: PdfColor.fromInt(0xFFCBD5E1), width: 1.05),
        horizontalInside: pw.BorderSide(color: _border, width: 0.55),
        verticalInside: pw.BorderSide(color: _border, width: 0.45),
      );

  /// Larguras: coluna 0 = índice fixo (não espreme com e-mail); demais por tipo de campo.
  static Map<int, pw.TableColumnWidth> columnWidthsMemberReport(
      List<String> fieldKeys) {
    final m = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(indexColumnPt),
    };
    for (var i = 0; i < fieldKeys.length; i++) {
      final c = i + 1;
      switch (fieldKeys[i]) {
        case 'email':
          m[c] = const pw.FlexColumnWidth(2.65);
          break;
        case 'nome':
          m[c] = const pw.FlexColumnWidth(3.35);
          break;
        case 'telefone':
          m[c] = const pw.FlexColumnWidth(2.0);
          break;
        case 'departamento':
          m[c] = const pw.FlexColumnWidth(2.55);
          break;
        case 'cpf':
          m[c] = const pw.FlexColumnWidth(1.55);
          break;
        case 'dataNascimento':
          m[c] = const pw.FlexColumnWidth(1.65);
          break;
        case 'sexo':
          m[c] = const pw.FlexColumnWidth(1.35);
          break;
        case 'faixaEtaria':
          m[c] = const pw.FlexColumnWidth(1.35);
          break;
        case 'status':
          m[c] = const pw.FlexColumnWidth(1.25);
          break;
        default:
          m[c] = const pw.FlexColumnWidth(1.2);
      }
    }
    return m;
  }

  static Map<int, pw.TableColumnWidth> columnWidthsPatrimonioReport(
      List<String> fieldKeys) {
    final m = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(indexColumnPt),
    };
    for (var i = 0; i < fieldKeys.length; i++) {
      final c = i + 1;
      switch (fieldKeys[i]) {
        case 'descricao':
          m[c] = const pw.FlexColumnWidth(2.65);
          break;
        case 'nome':
          m[c] = const pw.FlexColumnWidth(2.35);
          break;
        case 'categoria':
          m[c] = const pw.FlexColumnWidth(1.25);
          break;
        case 'status':
          m[c] = const pw.FlexColumnWidth(1.05);
          break;
        case 'valor':
          m[c] = const pw.FlexColumnWidth(1.65);
          break;
        case 'localizacao':
          m[c] = const pw.FlexColumnWidth(1.85);
          break;
        case 'responsavel':
          m[c] = const pw.FlexColumnWidth(1.75);
          break;
        case 'numeroSerie':
          m[c] = const pw.FlexColumnWidth(1.35);
          break;
        case 'dataAquisicao':
        case 'proximaManutencao':
          m[c] = const pw.FlexColumnWidth(1.4);
          break;
        default:
          m[c] = const pw.FlexColumnWidth(1.15);
      }
    }
    return m;
  }

  /// Relatório de eventos (títulos longos + local).
  static Map<int, pw.TableColumnWidth> get columnWidthsEventosReport => {
        0: const pw.FixedColumnWidth(indexColumnPt),
        1: const pw.FlexColumnWidth(3.1),
        2: const pw.FlexColumnWidth(1.45),
        3: const pw.FlexColumnWidth(1.25),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.55),
      };

  static Map<int, pw.TableColumnWidth> get columnWidthsAniversariantesSimples =>
      {
        0: const pw.FixedColumnWidth(indexColumnPt),
        1: const pw.FlexColumnWidth(3.45),
        2: const pw.FlexColumnWidth(1.35),
        3: const pw.FlexColumnWidth(1.2),
      };

  /// Relatório financeiro (sem coluna #): data, tipo, categoria, descrição, valor.
  static Map<int, pw.TableColumnWidth> get columnWidthsFinanceiroReport => {
        0: const pw.FlexColumnWidth(1.05),
        1: const pw.FlexColumnWidth(0.95),
        2: const pw.FlexColumnWidth(1.15),
        3: const pw.FlexColumnWidth(3.35),
        4: const pw.FlexColumnWidth(1.05),
      };

  /// Lista patrimônio PDF rápido (6 colunas, sem #).
  static Map<int, pw.TableColumnWidth> get columnWidthsPatrimonioListaSimples =>
      {
        0: const pw.FlexColumnWidth(2.2),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.05),
        3: const pw.FlexColumnWidth(1.55),
        4: const pw.FlexColumnWidth(1.65),
        5: const pw.FlexColumnWidth(1.55),
      };

  /// Frotas — abastecimentos: data, placa, motorista, combustível, valor.
  static Map<int, pw.TableColumnWidth> get columnWidthsFrotasAbastecimentos =>
      {
        0: const pw.FlexColumnWidth(1.15),
        1: const pw.FlexColumnWidth(0.85),
        2: const pw.FlexColumnWidth(1.45),
        3: const pw.FlexColumnWidth(1.05),
        4: const pw.FlexColumnWidth(1.0),
      };

  /// Cabeçalho: cartão branco, borda arredondada, logo da igreja (se houver), título e data.
  static pw.Widget header(
    String reportTitle, {
    DateTime? date,
    ReportPdfBranding? branding,
    List<String> extraLines = const [],
  }) {
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm').format(date ?? DateTime.now());
    final accent = branding?.accent ?? ReportPdfBranding.defaultAccent;
    final church = pdfSafeText((branding?.churchName ?? '').trim());
    final safeTitle = pdfSafeText(reportTitle);

    pw.ImageProvider? logoProv;
    final lb = branding?.logoBytes;
    if (lb != null && lb.length > 32) {
      logoProv = pw.MemoryImage(lb);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoProv != null)
            pw.Container(
              width: headerLogoSizePt,
              height: headerLogoSizePt,
              margin: const pw.EdgeInsets.only(right: 14),
              child: pw.Image(logoProv, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                if (church.isNotEmpty)
                  pw.Text(
                    church,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: _muted,
                      letterSpacing: 0.15,
                    ),
                  ),
                if (church.isNotEmpty) pw.SizedBox(height: 3),
                pw.Text(
                  safeTitle,
                  style: pw.TextStyle(
                    fontSize: 13,
                    color: accent,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (extraLines.isNotEmpty) pw.SizedBox(height: 4),
                ...extraLines.expand(
                  (line) => [
                    pw.Text(
                      pdfSafeText(line),
                      style: pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                    pw.SizedBox(height: 2),
                  ],
                ),
              ],
            ),
          ),
          pw.Text(
            dateStr,
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        ],
      ),
    );
  }

  /// Rodapé: nome da igreja + página (sem marca da plataforma).
  static pw.Widget footer(pw.Context context, {String? churchName}) {
    final left = pdfSafeText(
      (churchName ?? '').trim().isNotEmpty
          ? '${churchName!.trim()} · Relatório'
          : 'Relatório',
    );
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              left,
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  /// Tabela estilo premium: bordas suaves, cabeçalho com traço na cor da igreja.
  ///
  /// Coluna `0` com [pw.FixedColumnWidth] (ex.: índice #) fica centralizada; [zebraStripes] alterna o fundo.
  static pw.Widget fromTextArray({
    required List<String> headers,
    required List<List<String>> data,
    pw.TextStyle? headerStyle,
    pw.TextStyle? cellStyle,
    pw.BoxDecoration? headerDecoration,
    pw.EdgeInsets? cellPadding,
    PdfColor? accent,
    Map<int, pw.TableColumnWidth>? columnWidths,
    Map<int, pw.Alignment>? cellAlignmentsExtra,
    bool zebraStripes = true,
  }) {
    final ac = accent ?? ReportPdfBranding.defaultAccent;
    final safeHeaders =
        headers.map((h) => pdfSafeText(_compactTableHeader(h))).toList();
    final safeData =
        data.map((row) => row.map(pdfSafeText).toList()).toList();
    final cw = columnWidths;
    final hasIndexFixed = cw != null && cw[0] is pw.FixedColumnWidth;
    final alignMerged = <int, pw.Alignment>{
      if (hasIndexFixed) 0: pw.Alignment.center,
      ...?cellAlignmentsExtra,
    };
    return pw.TableHelper.fromTextArray(
      headers: safeHeaders,
      data: safeData,
      headerStyle: headerStyle ?? tableHeaderStyleFor(ac),
      cellStyle: cellStyle ?? tableCellStyle,
      headerDecoration: headerDecoration ?? tableHeaderDecorationFor(ac),
      cellPadding: cellPadding ?? tableCellPadding,
      border: _tableBorderSoft,
      columnWidths: columnWidths,
      defaultColumnWidth: const pw.FlexColumnWidth(1),
      tableWidth: pw.TableWidth.max,
      cellAlignments: alignMerged.isEmpty ? null : alignMerged,
      headerAlignments: alignMerged.isEmpty ? null : alignMerged,
      rowDecoration: zebraStripes
          ? const pw.BoxDecoration(color: PdfColors.white)
          : null,
      oddRowDecoration: zebraStripes
          ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8FAFC))
          : null,
    );
  }
}
