import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Verso da carteirinha (PDF CR80): CPF, nascimento, batismo, filiação, estado civil, telefone e assinatura.
/// Validade na frente; estado civil também no verso (entre filiação e telefone).
class VersoCarteirinhaPdfWidget extends pw.StatelessWidget {
  VersoCarteirinhaPdfWidget({
    required this.nomeIgreja,
    List<String>? regrasUso,
    PdfColor? gradientStart,
    PdfColor? gradientEnd,
    this.foregroundColor = PdfColors.white,
    this.rodapeColor = PdfColors.grey300,
    this.fraseInstitucional,
    this.pdfInkEconomy = false,
    this.cpfDoc = '',
    this.nascimentoDoc = '',
    this.batismoDoc = '',
    this.filiacaoPaiMaeDoc = '',
    this.estadoCivilDoc = '',
    this.telefoneDoc = '',
    this.assinaturaImage,
    this.signatoryNome = '',
    this.signatoryCargo = '',
    this.showRegrasUso = false,
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

  final String nomeIgreja;
  final List<String> regrasUso;
  final PdfColor gradientStart;
  final PdfColor gradientEnd;
  final PdfColor foregroundColor;
  final PdfColor rodapeColor;
  final String? fraseInstitucional;
  final bool pdfInkEconomy;

  final String cpfDoc;
  final String nascimentoDoc;
  final String batismoDoc;
  final String filiacaoPaiMaeDoc;
  final String estadoCivilDoc;
  final String telefoneDoc;
  final pw.ImageProvider? assinaturaImage;
  final String signatoryNome;
  final String signatoryCargo;

  /// `false` = igual à carteira digital na app (sem lista de regras no meio do verso).
  final bool showRegrasUso;

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

  static pw.Widget _cpfNascimentoLine(
      String cpf, String nasc, PdfColor fg, bool ink) {
    final c = cpf.trim().isEmpty ? '—' : cpf.trim();
    final n = nasc.trim().isEmpty ? '—' : nasc.trim();
    final dim = ink ? PdfColors.grey700 : PdfColor(fg.red, fg.green, fg.blue, 0.82);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1.5),
      child: pw.Text(
        'CPF: $c    Nascimento: $n',
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
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _cpfNascimentoLine(cpfDoc, nascimentoDoc, fg, ink),
                  _miniField('Batismo', batismoDoc, fg, ink),
                  _miniField('Filiação (Pai e Mãe)', filiacaoPaiMaeDoc, fg, ink),
                  _miniField('Estado civil', estadoCivilDoc, fg, ink),
                  _miniField('Telefone', telefoneDoc, fg, ink),
                  pw.Spacer(),
                  if ((signatoryNome).trim().isNotEmpty ||
                      assinaturaImage != null ||
                      (signatoryCargo).trim().isNotEmpty) ...[
                    pw.Container(
                      width: double.infinity,
                      constraints: const pw.BoxConstraints(maxHeight: 46),
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(9),
                        border: pw.Border.all(
                          color: PdfColor(
                            gradientStart.red,
                            gradientStart.green,
                            gradientStart.blue,
                            ink ? 0.42 : 0.38,
                          ),
                          width: 0.95,
                        ),
                        color: ink
                            ? PdfColor.fromInt(0xFFFDFDFE)
                            : PdfColor(1, 1, 1, 0.11),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 8,
                        verticalRadius: 8,
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            pw.Container(
                              width: 3.2,
                              color: gradientStart,
                            ),
                            pw.Expanded(
                              child: pw.Padding(
                                padding: const pw.EdgeInsets.fromLTRB(
                                    6, 4, 6, 4),
                                child: pw.Row(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.center,
                                  children: [
                                    pw.Expanded(
                                      child: pw.Column(
                                        crossAxisAlignment:
                                            pw.CrossAxisAlignment.start,
                                        mainAxisSize: pw.MainAxisSize.min,
                                        children: [
                                          pw.Container(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.7,
                                            ),
                                            decoration: pw.BoxDecoration(
                                              color: PdfColor(
                                                gradientStart.red,
                                                gradientStart.green,
                                                gradientStart.blue,
                                                ink ? 0.12 : 0.16,
                                              ),
                                              borderRadius:
                                                  pw.BorderRadius.circular(99),
                                            ),
                                            child: pw.Text(
                                              'ASSINATURA INSTITUCIONAL',
                                              style: pw.TextStyle(
                                                color: gradientStart,
                                                fontSize: 4.6,
                                                fontWeight:
                                                    pw.FontWeight.bold,
                                                letterSpacing: 0.35,
                                              ),
                                            ),
                                          ),
                                          if (signatoryNome
                                              .trim()
                                              .isNotEmpty) ...[
                                            pw.SizedBox(height: 2.3),
                                            pw.Text(
                                              signatoryNome.trim(),
                                              maxLines: 1,
                                              overflow: pw.TextOverflow.clip,
                                              style: pw.TextStyle(
                                                color: fg,
                                                fontSize: 5.7,
                                                fontWeight:
                                                    pw.FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                          if (signatoryCargo
                                              .trim()
                                              .isNotEmpty) ...[
                                            pw.SizedBox(height: 1.5),
                                            pw.Text(
                                              signatoryCargo.trim(),
                                              maxLines: 1,
                                              overflow: pw.TextOverflow.clip,
                                              style: pw.TextStyle(
                                                color: PdfColor(
                                                  fg.red,
                                                  fg.green,
                                                  fg.blue,
                                                  ink ? 0.78 : 0.82,
                                                ),
                                                fontSize: 4.8,
                                                fontWeight:
                                                    pw.FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (assinaturaImage != null) ...[
                                      pw.SizedBox(width: 4),
                                      pw.SizedBox(
                                        width: 72,
                                        height: 30,
                                        child: pw.Image(
                                          assinaturaImage!,
                                          fit: pw.BoxFit.contain,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (showRegrasUso) ...[
                    pw.SizedBox(height: 4),
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
                  ],
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
