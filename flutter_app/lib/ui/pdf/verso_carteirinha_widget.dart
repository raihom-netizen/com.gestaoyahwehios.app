import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Verso da carteirinha (PDF CR80): alinhado à carteira digital — dados, validade, QR e regras compactas.
class VersoCarteirinhaPdfWidget extends pw.StatelessWidget {
  VersoCarteirinhaPdfWidget({
    required this.validationUrl,
    required this.nomeIgreja,
    List<String>? regrasUso,
    this.validadeDestaque,
    this.barcodeData,
    PdfColor? gradientStart,
    PdfColor? gradientEnd,
    this.foregroundColor = PdfColors.white,
    this.rodapeColor = PdfColors.grey300,
    this.congregacao,
    this.fraseInstitucional,
    this.pdfInkEconomy = false,
    this.cpfDoc = '',
    this.nascimentoDoc = '',
    this.filiacaoPaiMaeDoc = '',
    this.assinaturaImage,
    this.signatoryNome = '',
    this.signatoryCargo = '',
  })  : regrasUso = (regrasUso == null || regrasUso.isEmpty)
            ? kRegrasPadrao
            : List<String>.from(regrasUso),
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
  final String? validadeDestaque;
  final String? barcodeData;
  final PdfColor gradientStart;
  final PdfColor gradientEnd;
  final PdfColor foregroundColor;
  final PdfColor rodapeColor;
  final String? congregacao;
  final String? fraseInstitucional;
  final bool pdfInkEconomy;

  final String cpfDoc;
  final String nascimentoDoc;
  final String filiacaoPaiMaeDoc;
  final pw.ImageProvider? assinaturaImage;
  final String signatoryNome;
  final String signatoryCargo;

  static const double cardWidthPt = 242.64;
  static const double cardHeightPt = 153.07;

  static pw.Widget _miniField(String label, String value, PdfColor fg, bool ink) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    final dim = ink ? PdfColors.grey700 : PdfColor(fg.red, fg.green, fg.blue, 0.82);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.Text(
        '$label: $v',
        maxLines: 2,
        style: pw.TextStyle(
          fontSize: 5.2,
          lineSpacing: 1.05,
          color: dim,
        ),
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  @override
  pw.Widget build(pw.Context context) {
    final ink = pdfInkEconomy;
    final fg = ink ? PdfColors.grey900 : foregroundColor;
    final rod = ink ? PdfColors.grey700 : rodapeColor;
    final glassFill = ink
        ? PdfColors.grey200
        : PdfColor(1, 1, 1, 0.16);
    final glassBorder =
        ink ? PdfColors.grey400 : PdfColor(1, 1, 1, 0.28);

    final tituloStyle = pw.TextStyle(
      color: fg,
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
    );
    final rodapeStyle = pw.TextStyle(
      color: rod,
      fontSize: 4.8,
      fontStyle: pw.FontStyle.italic,
    );
    final regraMicro = pw.TextStyle(
      color: fg,
      fontSize: 4.4,
      lineSpacing: 1.05,
    );

    final decoration = ink
        ? pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(16),
            border: pw.Border.all(color: gradientStart, width: 1.2),
          )
        : pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(16),
            gradient: pw.LinearGradient(
              colors: [gradientStart, gradientEnd],
              begin: pw.Alignment.bottomLeft,
              end: pw.Alignment.topRight,
            ),
          );

    final validadeTxt = (validadeDestaque ?? '').trim();
    final regrasCurta = regrasUso.length > 2 ? regrasUso.sublist(0, 2) : regrasUso;

    return pw.Container(
      width: cardWidthPt,
      height: cardHeightPt,
      decoration: decoration,
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              nomeIgreja,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: tituloStyle,
            ),
            pw.SizedBox(height: 4),
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 14,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: glassFill,
                            borderRadius: pw.BorderRadius.circular(6),
                            border: pw.Border.all(color: glassBorder, width: 0.6),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'VALIDADE',
                                style: pw.TextStyle(
                                  color: ink
                                      ? PdfColors.grey700
                                      : PdfColor(fg.red, fg.green, fg.blue, 0.75),
                                  fontSize: 4.8,
                                  fontWeight: pw.FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              pw.Text(
                                validadeTxt.isEmpty ? '—' : validadeTxt,
                                style: pw.TextStyle(
                                  color: fg,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        _miniField('CPF', cpfDoc, fg, ink),
                        _miniField('Nascimento', nascimentoDoc, fg, ink),
                        _miniField('Filiação (Pai e Mãe)', filiacaoPaiMaeDoc, fg, ink),
                        if ((congregacao ?? '').trim().isNotEmpty)
                          _miniField('Congregação', congregacao!.trim(), fg, ink),
                        pw.Spacer(),
                        if ((signatoryNome).trim().isNotEmpty) ...[
                          pw.Container(
                              width: 72,
                              height: 0.6,
                              color: PdfColor(fg.red, fg.green, fg.blue, 0.45)),
                          if (assinaturaImage != null)
                            pw.Container(
                              width: 64,
                              height: 18,
                              margin: const pw.EdgeInsets.only(top: 2),
                              child: pw.Image(assinaturaImage!,
                                  fit: pw.BoxFit.contain),
                            ),
                          pw.Text(
                            signatoryNome.trim(),
                            style: pw.TextStyle(
                              color: fg,
                              fontSize: 6,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (signatoryCargo.trim().isNotEmpty)
                            pw.Text(
                              signatoryCargo.trim(),
                              style: pw.TextStyle(
                                color: ink ? PdfColors.grey700 : PdfColor(fg.red, fg.green, fg.blue, 0.8),
                                fontSize: 5,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    flex: 11,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(4),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.white,
                            borderRadius: pw.BorderRadius.circular(6),
                          ),
                          child: pw.BarcodeWidget(
                            data: validationUrl,
                            barcode: pw.Barcode.qrCode(),
                            width: 48,
                            height: 48,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Validar credencial',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            color: ink ? PdfColors.grey800 : PdfColor(fg.red, fg.green, fg.blue, 0.88),
                            fontSize: 4.8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Spacer(),
                        ...regrasCurta.map(
                          (regra) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text(
                              '• $regra',
                              style: regraMicro,
                              maxLines: 3,
                              textAlign: pw.TextAlign.left,
                            ),
                          ),
                        ),
                        if ((barcodeData ?? '').trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 2, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(2),
                            ),
                            child: pw.BarcodeWidget(
                              barcode: pw.Barcode.code128(),
                              data: barcodeData!.trim(),
                              width: 68,
                              height: 14,
                              color: PdfColors.black,
                              drawText: false,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Divider(color: ink ? PdfColors.grey300 : PdfColor(1, 1, 1, 0.25), height: 1),
            pw.SizedBox(height: 2),
            pw.Text(nomeIgreja, style: rodapeStyle.copyWith(fontSize: 4.6)),
            if ((fraseInstitucional ?? '').trim().isNotEmpty)
              pw.Text(
                fraseInstitucional!.trim(),
                maxLines: 2,
                style: rodapeStyle.copyWith(fontSize: 4.2),
              ),
            pw.Text(
              'Sistema de Gestão YAHWEH',
              style: rodapeStyle.copyWith(fontSize: 3.8),
            ),
          ],
        ),
      ),
    );
  }
}
