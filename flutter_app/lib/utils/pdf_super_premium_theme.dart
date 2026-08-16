
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Tema Super Premium para relatórios PDF.
/// Cabeçalho = dados/logo da igreja ? Rodap? = autoria Gestão YAHWEH.
class PdfSuperPremiumTheme {
  PdfSuperPremiumTheme._();

  static pw.ThemeData? _robotoPdfTheme;

  /// Escudo Gestão YAHWEH cacheado para o rodapé de todos os PDFs.
  static Uint8List? _systemFooterLogoBytes;

  static const String kFooterBrand = 'Gestão YAHWEH';

  /// Define o ícone de autoria do rodapé (chamar no warm-up / branding).
  static void setSystemFooterLogo(Uint8List? bytes) {
    if (bytes != null && bytes.length > 32) {
      _systemFooterLogoBytes = bytes;
    }
  }

  static Uint8List? get systemFooterLogoBytes => _systemFooterLogoBytes;

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
      debugPrint('PdfSuperPremiumTheme: Roboto PDF ? $e\n$st');
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

  /// Largura fixa da coluna ?ndice (# / ordem). =44pt para 3 dígitos sem empilhar caracteres no `pdf`.
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

  /// Cabeçalho moderno: logo + nome + dados da igreja, título do relatório.
  static pw.Widget header(
    String reportTitle, {
    DateTime? date,
    ReportPdfBranding? branding,
    List<String> extraLines = const [],
  }) {
    final dateStr =
        DateFormat('dd/MM/yyyy HH:mm').format(date ?? DateTime.now());
    final churchRaw = (branding?.churchName ?? '').trim();
    final church =
        pdfSafeText(churchRaw.isNotEmpty ? churchRaw : 'Igreja');
    final safeTitle = pdfSafeText(reportTitle);
    final detailLines = <String>[
      ...?(branding?.churchDetailLines),
      ...extraLines,
    ]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(pdfSafeText)
        .toList();

    // Cabeçalho estilo OFÍCIO (leve p/ impressão): só logo + dados da igreja,
    // texto escuro sobre fundo branco e uma linha fina embaixo. Sem faixa verde.
    final ink = PdfColor.fromInt(0xFF1F2937);
    final muted = PdfColor.fromInt(0xFF6B7280);
    final rule = PdfColor.fromInt(0xFF9CA3AF);

    pw.Widget logoBadge() {
      final lb = branding?.logoBytes;
      if (lb == null || lb.length <= 32) {
        return pw.SizedBox(width: 0, height: 0);
      }
      return pw.Container(
        width: headerLogoSizePt,
        height: headerLogoSizePt,
        margin: const pw.EdgeInsets.only(right: 14),
        child: pw.Image(pw.MemoryImage(lb), fit: pw.BoxFit.contain),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      margin: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: rule, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          logoBadge(),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  church,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  safeTitle,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    color: muted,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (detailLines.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  ...detailLines.take(5).map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 1.5),
                          child: pw.Text(
                            line,
                            style: pw.TextStyle(fontSize: 7.8, color: muted),
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
          pw.Text(
            dateStr,
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
    );
  }

  /// Cabeçalho estilo ofício — logo à esquerda; nome completo + endereço completo à direita.
  static pw.Widget oficioLetterHeader({
    required ReportPdfBranding branding,
    required Map<String, dynamic> churchData,
    required String documentTitle,
  }) {
    final accent = branding.accent;
    // Nome: ignora string vazia (?? não basta) e cobre razaoSocial/nomeIgreja.
    var churchName = churchTaxIdChurchNameFromMap(churchData).trim();
    if (churchName.isEmpty) {
      churchName = branding.churchName.trim();
    }
    churchName = pdfSafeText(churchName);
    final safeTitle = pdfSafeText(documentTitle);

    pw.ImageProvider? logoProv;
    final lb = branding.logoBytes;
    if (lb != null && lb.length > 32) {
      logoProv = pw.MemoryImage(lb);
    }

    String s(dynamic v) => (v ?? '').toString().trim();
    final rua = s(churchData['rua'] ??
        churchData['address'] ??
        churchData['logradouro'] ??
        churchData['LOGRADOURO']);
    final qd = s(churchData['quadraLoteNumero'] ??
        churchData['quadra_lote_numero']);
    final ruaLine =
        rua.isEmpty ? qd : (qd.isEmpty ? rua : '$rua, $qd');
    final bairro = s(churchData['bairro'] ?? churchData['BAIRRO']);
    final cidade = s(churchData['cidade'] ??
        churchData['CIDADE'] ??
        churchData['localidade'] ??
        churchData['LOCALIDADE']);
    final uf = s(churchData['estado'] ??
        churchData['ESTADO'] ??
        churchData['UF'] ??
        churchData['uf']);
    final cepRaw = s(churchData['cep'] ?? churchData['CEP']);
    final cep = _formatCepPdf(cepRaw);
    final tel = s(churchData['telefoneIgreja'] ??
        churchData['telefone_igreja'] ??
        churchData['telefone'] ??
        churchData['whatsappIgreja'] ??
        churchData['whatsapp_igreja'] ??
        churchData['whatsapp'] ??
        churchData['phone'] ??
        churchData['gestorTelefone'] ??
        churchData['gestor_telefone']);
    final legacyEndereco = s(churchData['endereco'] ??
        churchData['ENDERECO'] ??
        churchData['enderecoCompleto'] ??
        churchData['endereco_completo']);

    String cityLine = '';
    if (cidade.isNotEmpty && uf.isNotEmpty) {
      cityLine = '$cidade - $uf';
    } else if (cidade.isNotEmpty) {
      cityLine = cidade;
    } else if (uf.isNotEmpty) {
      cityLine = uf;
    }
    if (cep.isNotEmpty) {
      cityLine = cityLine.isEmpty ? 'CEP $cep' : '$cityLine ? CEP $cep';
    }

    final addrParts = <String>[
      if (ruaLine.isNotEmpty) ruaLine,
      if (bairro.isNotEmpty) bairro,
    ];
    // Cadastro legado: só campo «endereco» completo.
    final useLegacyAlone =
        addrParts.isEmpty && cityLine.isEmpty && legacyEndereco.isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoProv != null)
              pw.Container(
                width: 78,
                height: 78,
                margin: const pw.EdgeInsets.only(right: 16, top: 2),
                child: pw.Image(logoProv, fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (churchName.isNotEmpty)
                    pw.Text(
                      churchName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 13.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                        letterSpacing: 0.35,
                      ),
                    ),
                  if (churchName.isNotEmpty) pw.SizedBox(height: 6),
                  if (useLegacyAlone)
                    pw.Text(
                      pdfSafeText(legacyEndereco),
                      style: pw.TextStyle(fontSize: 9.2, color: _muted),
                    )
                  else ...[
                    if (addrParts.isNotEmpty)
                      pw.Text(
                        pdfSafeText(addrParts.join(' ? ')),
                        style: pw.TextStyle(fontSize: 9.2, color: _muted),
                      ),
                    if (cityLine.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        pdfSafeText(cityLine),
                        style: pw.TextStyle(fontSize: 9.2, color: _muted),
                      ),
                    ],
                    // Se partes vazias mas há legado parcial, mostra legado.
                    if (addrParts.isEmpty &&
                        cityLine.isEmpty &&
                        legacyEndereco.isNotEmpty)
                      pw.Text(
                        pdfSafeText(legacyEndereco),
                        style: pw.TextStyle(fontSize: 9.2, color: _muted),
                      ),
                  ],
                  if (tel.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      pdfSafeText('Tel.: $tel'),
                      style: pw.TextStyle(fontSize: 9.2, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 2.2,
          decoration: pw.BoxDecoration(
            color: accent,
            borderRadius: pw.BorderRadius.circular(1),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            safeTitle,
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: accent,
              letterSpacing: 0.2,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }

  static String _formatCepPdf(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 8) return raw.trim();
    return '${d.substring(0, 5)}-${d.substring(5)}';
  }

  /// Rodapé moderno: autoria Gestão YAHWEH (+ ícone) em todos os relatórios.
  /// [churchName] mantido por compatibilidade — não é mais usado como autoria.
  static pw.Widget footer(
    pw.Context context, {
    String? churchName,
    Uint8List? systemLogoBytes,
    String footerBrand = kFooterBrand,
  }) {
    final brand =
        footerBrand.trim().isEmpty ? kFooterBrand : footerBrand.trim();
    final logo = systemLogoBytes ?? _systemFooterLogoBytes;
    final muted = _muted;
    final footerAccent = PdfColor.fromInt(0xFF0F172A);
    final now = DateTime.now();
    final emitido =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF8FAFC),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null && logo.length > 32)
            pw.Container(
              width: 20,
              height: 20,
              margin: const pw.EdgeInsets.only(right: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(5),
                border: pw.Border.all(
                    color: PdfColor.fromInt(0xFFE2E8F0), width: 0.6),
              ),
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(2),
                child:
                    pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
              ),
            )
          else
            pw.Container(
              width: 20,
              height: 20,
              margin: const pw.EdgeInsets.only(right: 8),
              decoration: pw.BoxDecoration(
                color: footerAccent,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'GY',
                style: pw.TextStyle(
                  fontSize: 6.5,
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
                  pdfSafeText('Gerado por $brand'),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: footerAccent,
                  ),
                ),
                pw.Text(
                  'Sistema de gestão ministerial ? Autoria oficial',
                  style: pw.TextStyle(fontSize: 6.8, color: muted),
                ),
              ],
            ),
          ),
          pw.Text(
            'Emitido $emitido  ?  Pag. ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.2, color: muted),
          ),
        ],
      ),
    );
  }

  static PdfColor _accentStrokeSoft(PdfColor a) => PdfColor(
        a.red,
        a.green,
        a.blue,
        (a.alpha * 0.45).clamp(0.22, 0.58),
      );

  /// Duas colunas com traço forte e rótulos — fechamentos financeiros e relatórios similares.
  static pw.Widget reportDualSignatureAttestation({
    required PdfColor accent,
    String leftTitle = 'Tesoureiro(a)',
    String rightTitle = 'Pastor Presidente',
    String subtitle = 'Assinatura e carimbo',
    double signatureSpacePt = 40,
    String leftSignerName = '',
    String rightSignerName = '',
    Uint8List? leftSignatureImageBytes,
    Uint8List? rightSignatureImageBytes,
    bool showDigitalSignatures = false,
    PdfDigitalStampInput? leftDigitalStamp,
    PdfDigitalStampInput? rightDigitalStamp,
  }) {
    final stroke = _accentStrokeSoft(accent);
    pw.Widget slot(
      String title,
      String signerName,
      Uint8List? signatureBytes,
      PdfDigitalStampInput? digitalStamp,
    ) {
      final canShowDigitalStamp =
          showDigitalSignatures && digitalStamp != null;
      final canShowSignature = !canShowDigitalStamp &&
          showDigitalSignatures &&
          signatureBytes != null &&
          signatureBytes.length > 24;
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 5),
          padding: const pw.EdgeInsets.fromLTRB(11, 10, 11, 10),
          decoration: pw.BoxDecoration(
            color: _cardBg,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: stroke, width: 1.35),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                height: 3.2,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(height: 9),
              pw.Text(
                pdfSafeText(title),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 10.8,
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                pdfSafeText(subtitle),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 7.6, color: _muted),
              ),
              if (canShowDigitalStamp) ...[
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pdfDigitalCertificateStampBlock(
                    digitalStamp,
                    maxWidth: 228,
                  ),
                ),
              ] else if (canShowSignature) ...[
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.SizedBox(
                    width: 106,
                    height: 24,
                    child: pw.Image(
                      pw.MemoryImage(signatureBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
              pw.SizedBox(height: canShowDigitalStamp ? 8 : signatureSpacePt),
              pw.Container(
                height: 2,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(0.5),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                child: pw.Text(
                  signerName.trim().isEmpty
                      ? 'Nome legível'
                      : pdfSafeText(signerName.trim()),
                  textAlign: pw.TextAlign.center,
                  maxLines: 5,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: 7.4,
                    color: _muted,
                    lineSpacing: 1.12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // A SELEÇÃO manda (padrão certificado): renderiza só os slots com signatário.
    // 1 preenchido ? 1 assinatura CENTRALIZADA; 2 ? duas colunas; 0 ? duas (linhas
    // em branco para assinar à mão, como antes).
    bool has(String name, Uint8List? sig, PdfDigitalStampInput? stamp) =>
        name.trim().isNotEmpty ||
        (showDigitalSignatures && stamp != null) ||
        (sig != null && sig.length > 24);
    final hasLeft =
        has(leftSignerName, leftSignatureImageBytes, leftDigitalStamp);
    final hasRight =
        has(rightSignerName, rightSignatureImageBytes, rightDigitalStamp);

    if (hasLeft != hasRight) {
      // Exatamente um signatário ? centralizado.
      final title = hasLeft ? leftTitle : rightTitle;
      final name = hasLeft ? leftSignerName : rightSignerName;
      final sig = hasLeft ? leftSignatureImageBytes : rightSignatureImageBytes;
      final stamp = hasLeft ? leftDigitalStamp : rightDigitalStamp;
      return pw.Center(
        child: pw.ConstrainedBox(
          constraints: const pw.BoxConstraints(maxWidth: 300),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [slot(title, name, sig, stamp)],
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        slot(leftTitle, leftSignerName, leftSignatureImageBytes, leftDigitalStamp),
        slot(rightTitle, rightSignerName, rightSignatureImageBytes, rightDigitalStamp),
      ],
    );
  }

  /// Caixa única de validação pastoral (inventário / termos no papel).
  static pw.Widget reportPastoralSignatureBox({
    required PdfColor accent,
    String sectionTitle = 'Validação pastoral',
    String label = 'Assinatura do pastor responsável',
    String hintLeft = 'Nome legível e carimbo (opcional)',
    String hintRight = 'Data: _______________',
    double lineSpaceBeforeBarPt = 22,
    String signerName = '',
    Uint8List? signatureImageBytes,
    bool showDigitalSignature = false,
    PdfDigitalStampInput? digitalStamp,
  }) {
    final stroke = _accentStrokeSoft(accent);
    final canShowDigitalStamp = showDigitalSignature && digitalStamp != null;
    final canShowSignature = !canShowDigitalStamp &&
        showDigitalSignature &&
        signatureImageBytes != null &&
        signatureImageBytes.length > 24;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 6),
        pw.Text(
          pdfSafeText(sectionTitle),
          style: pw.TextStyle(
            fontSize: 11.5,
            fontWeight: pw.FontWeight.bold,
            color: accent,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF8FAFC),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: stroke, width: 1.35),
          ),
          padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                height: 3,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                pdfSafeText(label),
                style: pw.TextStyle(
                  fontSize: 9.8,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              if (canShowDigitalStamp) ...[
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pdfDigitalCertificateStampBlock(
                    digitalStamp,
                    maxWidth: 248,
                  ),
                ),
              ] else if (canShowSignature) ...[
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.SizedBox(
                    width: 140,
                    height: 30,
                    child: pw.Image(
                      pw.MemoryImage(signatureImageBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ],
              pw.SizedBox(height: canShowDigitalStamp ? 8 : lineSpaceBeforeBarPt),
              pw.Container(
                width: double.infinity,
                height: 2,
                decoration: pw.BoxDecoration(
                  color: accent,
                  borderRadius: pw.BorderRadius.circular(0.5),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      pdfSafeText(
                        signerName.trim().isNotEmpty
                            ? signerName.trim()
                            : hintLeft,
                      ),
                      style: pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    pdfSafeText(hintRight),
                    style: pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
