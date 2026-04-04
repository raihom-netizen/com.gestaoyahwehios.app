import 'package:barcode/barcode.dart' show BarcodeQRCorrectionLevel;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Verso da carteirinha para PDF (CR80 horizontal): QR + regras, degradê alinhado à frente.
class VersoCarteirinhaPdfWidget extends pw.StatelessWidget {
  VersoCarteirinhaPdfWidget({
    required this.validationUrl,
    required this.nomeIgreja,
    List<String>? regrasUso,
    /// Nome completo do membro logo abaixo do QR (fiscal identifica antes de escanear).
    this.titularNomeQr,
    this.validadeDestaque,
    this.barcodeData,
    PdfColor? gradientStart,
    PdfColor? gradientEnd,
    this.foregroundColor = PdfColors.white,
    this.rodapeColor = PdfColors.grey300,
    this.congregacao,
    this.fraseInstitucional,
    this.pdfInkEconomy = false,
  })  : regrasUso = (regrasUso == null || regrasUso.isEmpty) ? kRegrasPadrao : List<String>.from(regrasUso),
        gradientStart = gradientStart ?? PdfColor.fromHex('#004D40'),
        gradientEnd = gradientEnd ?? PdfColor.fromHex('#00BFA5'),
        super();

  /// Regras exibidas quando a igreja não define lista em `config/carteira`.
  static const List<String> kRegrasPadrao = [
    'Este documento é pessoal e intransferível.',
    'Válido apenas se acompanhado de documento oficial com foto.',
    'Em caso de perda, comunique imediatamente à secretaria da igreja.',
    'O uso indevido poderá acarretar na suspensão dos direitos de membro.',
    'Esta credencial é de propriedade da instituição emissora.',
  ];

  final String validationUrl;
  final String nomeIgreja;
  final List<String> regrasUso;
  final String? titularNomeQr;
  /// Exibido em destaque no painel do QR (validade da credencial).
  final String? validadeDestaque;
  /// Opcional: payload Code128 (ex.: `tenantId|memberId`).
  final String? barcodeData;
  final PdfColor gradientStart;
  final PdfColor gradientEnd;
  final PdfColor foregroundColor;
  final PdfColor rodapeColor;
  /// Congregação / sede (opcional).
  final String? congregacao;
  /// Frase oficial da igreja no rodapé (opcional).
  final String? fraseInstitucional;

  /// Fundo branco e borda fina (economia de tinta em jato de tinta).
  final bool pdfInkEconomy;

  /// Largura/altura em pontos PDF (~CR80 horizontal ISO/IEC 7810).
  static const double cardWidthPt = 242.64;
  static const double cardHeightPt = 153.07;

  @override
  pw.Widget build(pw.Context context) {
    final ink = pdfInkEconomy;
    final fg = ink ? PdfColors.grey900 : foregroundColor;
    final rod = ink ? PdfColors.grey700 : rodapeColor;
    final tituloStyle = pw.TextStyle(
      color: fg,
      fontSize: 10,
      fontWeight: pw.FontWeight.bold,
    );
    final regraStyle = pw.TextStyle(
      color: fg,
      fontSize: 7,
      lineSpacing: 2,
    );
    final titularQrStyle = pw.TextStyle(
      color: fg,
      fontSize: 5.5,
      fontWeight: pw.FontWeight.bold,
      lineSpacing: 1.2,
    );
    final rodapeStyle = pw.TextStyle(
      color: rod,
      fontSize: 6,
      fontStyle: pw.FontStyle.italic,
    );

    final divCor = ink ? PdfColors.grey400 : PdfColor(1, 1, 1, 0.35);

    final decoration = ink
        ? pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(16),
            border: pw.Border.all(color: gradientStart, width: 1.35),
          )
        : pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(16),
            gradient: pw.LinearGradient(
              colors: [gradientStart, gradientEnd],
              begin: pw.Alignment.topLeft,
              end: pw.Alignment.bottomRight,
            ),
          );

    return pw.Container(
      width: cardWidthPt,
      height: cardHeightPt,
      decoration: decoration,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(5),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.BarcodeWidget(
                      data: validationUrl,
                      barcode: pw.Barcode.qrCode(
                        errorCorrectLevel: BarcodeQRCorrectionLevel.high,
                      ),
                      width: 60,
                      height: 60,
                      color: PdfColors.black,
                    ),
                  ),
                  if ((titularNomeQr ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Titular: ${titularNomeQr!.trim()}',
                      style: titularQrStyle,
                      textAlign: pw.TextAlign.center,
                      maxLines: 3,
                    ),
                  ],
                  if ((validadeDestaque ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'VALIDADE: ${validadeDestaque!.trim()}',
                        style: tituloStyle.copyWith(
                          color: PdfColors.black,
                          fontSize: 8,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Escaneie o QR Code para conferir se a credencial está ativa.',
                    style: regraStyle.copyWith(fontSize: 6),
                    textAlign: pw.TextAlign.center,
                  ),
                  if ((congregacao ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Congregação: ${congregacao!.trim()}',
                      style: titularQrStyle.copyWith(fontSize: 6),
                      textAlign: pw.TextAlign.center,
                      maxLines: 2,
                    ),
                  ],
                  if ((barcodeData ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: barcodeData!.trim(),
                        width: 92,
                        height: 20,
                        color: PdfColors.black,
                        drawText: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          pw.Center(
            child: pw.Container(
              width: 1,
              height: cardHeightPt * 0.82,
              color: divCor,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(15, 15, 15, 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('REGRAS E OBSERVAÇÕES', style: tituloStyle),
                  pw.Divider(color: fg, thickness: 0.5, height: 8),
                  pw.SizedBox(height: 2),
                  ...regrasUso.map(
                    (regra) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: regraStyle),
                          pw.Expanded(
                            child: pw.Text(
                              regra,
                              style: regraStyle,
                              textAlign: pw.TextAlign.justify,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Divider(color: divCor, thickness: 0.5, height: 8),
                  pw.Text(nomeIgreja, style: rodapeStyle),
                  if ((fraseInstitucional ?? '').trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(
                        fraseInstitucional!.trim(),
                        style: rodapeStyle.copyWith(fontSize: 5.2),
                        maxLines: 3,
                      ),
                    ),
                  pw.Text('Sistema de Gestão YAHWEH', style: rodapeStyle.copyWith(fontSize: 5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
