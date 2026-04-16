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
                        width: 72,
                        height: 0.6,
                        color: PdfColor(fg.red, fg.green, fg.blue, 0.45)),
                    if (assinaturaImage != null)
                      pw.Container(
                        width: 80,
                        height: 30,
                        margin: const pw.EdgeInsets.only(top: 2),
                        child: pw.Image(assinaturaImage!, fit: pw.BoxFit.contain),
                      ),
                    if (signatoryNome.trim().isNotEmpty)
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
                          color: ink
                              ? PdfColors.grey700
                              : PdfColor(fg.red, fg.green, fg.blue, 0.8),
                          fontSize: 5,
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
