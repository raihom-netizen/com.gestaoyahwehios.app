import 'package:gestao_yahweh/ui/widgets/member_card_cnh_data.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Carteira membro digital — padrão CNH (PDF), alinhada a [MemberCardCnhDigital].
class MemberCardCnhPdfWidget extends pw.StatelessWidget {
  MemberCardCnhPdfWidget({
    required this.data,
    this.photoImage,
    this.logoImage,
    this.signatureImage,
  }) : super();

  final MemberCardCnhViewData data;
  final pw.ImageProvider? photoImage;
  final pw.ImageProvider? logoImage;
  final pw.ImageProvider? signatureImage;

  /// Portrait CNH (~54 × 86 mm).
  static const double cardWidthPt = 153;
  static const double cardHeightPt = 244;

  static final PdfColor _headerNavy = PdfColor.fromHex('#0D2C54');
  static final PdfColor _borderGreen = PdfColor.fromHex('#2E7D32');
  static final PdfColor _labelColor = PdfColor.fromHex('#4A5D48');
  static final PdfColor _valueColor = PdfColor.fromHex('#142414');
  static final PdfColor _bgGreen = PdfColor.fromHex('#E8F5E9');

  @override
  pw.Widget build(pw.Context context) {
    return pw.Container(
      width: cardWidthPt,
      height: cardHeightPt,
      decoration: pw.BoxDecoration(
        color: _bgGreen,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _borderGreen, width: 1.6),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 9,
        verticalRadius: 9,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              color: _headerNavy,
              child: pw.Text(
                'MEMBRO PADRÃO — GESTÃO YAHWEH',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 6.2,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(7, 6, 7, 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (photoImage != null)
                    pw.Container(
                      width: 38,
                      height: 48,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Image(photoImage!, fit: pw.BoxFit.cover),
                    )
                  else
                    pw.Container(
                      width: 38,
                      height: 48,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey300,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                    ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Container(
                          width: 44,
                          height: 44,
                          decoration: pw.BoxDecoration(
                            shape: pw.BoxShape.circle,
                            border: pw.Border.all(color: _borderGreen, width: 1.2),
                            color: PdfColors.white,
                          ),
                          padding: const pw.EdgeInsets.all(2),
                          child: logoImage != null
                              ? pw.Image(logoImage!, fit: pw.BoxFit.contain)
                              : pw.SizedBox(width: 44, height: 44),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          data.churchTitle.toUpperCase(),
                          maxLines: 2,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 5.8,
                            fontWeight: pw.FontWeight.bold,
                            color: _headerNavy,
                          ),
                        ),
                        if (data.churchSubtitle.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            data.churchSubtitle,
                            maxLines: 1,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 5,
                              color: _labelColor,
                            ),
                          ),
                        ],
                        pw.SizedBox(height: 4),
                        _field('CÓD. MEMBRO', data.codigoMembro, size: 5.5),
                        pw.SizedBox(height: 2),
                        _field('IGREJA SEDE', data.igrejaSede, size: 5.5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.Container(height: 0.6, color: PdfColors.grey400),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(7, 4, 7, 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _field('NOME', data.nome, size: 7.5, bold: true),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(child: _field('CPF', data.cpf, size: 6)),
                      pw.SizedBox(width: 4),
                      pw.Expanded(
                        child: _field('DATA NASC.', data.dataNascimento, size: 6),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  _field('FILIAÇÃO', data.filiacao, size: 6, maxLines: 2),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _field('DATA ADMISSÃO', data.dataAdmissao, size: 6),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Expanded(
                        child: _field(
                          'VÁLIDO ATÉ',
                          data.validade,
                          size: 6,
                          valueColor: data.validade == 'Permanente'
                              ? PdfColor.fromHex('#0F5132')
                              : PdfColor.fromHex('#B91C1C'),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  _field('CATEGORIA', data.categoria, size: 6),
                ],
              ),
            ),
            if (data.assinada)
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(7, 0, 7, 3),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#E8F5EC'),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(
                      color: PdfColor.fromHex('#A7D7B5'),
                    ),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (signatureImage != null)
                        pw.Container(
                          width: 28,
                          height: 14,
                          margin: const pw.EdgeInsets.only(right: 4),
                          child: pw.Image(signatureImage!, fit: pw.BoxFit.contain),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'ASSINATURA DIGITAL',
                              style: pw.TextStyle(
                                fontSize: 4.8,
                                fontWeight: pw.FontWeight.bold,
                                color: _labelColor,
                              ),
                            ),
                            pw.Text(
                              data.assinanteNomeCargo.isNotEmpty
                                  ? data.assinanteNomeCargo
                                  : 'Credencial assinada',
                              maxLines: 2,
                              style: pw.TextStyle(
                                fontSize: 5.8,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex('#0F5132'),
                              ),
                            ),
                            if (data.assinadaEmTexto.isNotEmpty)
                              pw.Text(
                                data.assinadaEmTexto,
                                style: pw.TextStyle(fontSize: 5, color: _labelColor),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(7, 0, 7, 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (logoImage != null)
                    pw.SizedBox(
                      width: 14,
                      height: 14,
                      child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
                    ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'YHAWEH',
                          style: pw.TextStyle(
                            fontSize: 5.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _headerNavy,
                          ),
                        ),
                        pw.Text(
                          'GESTÃO',
                          style: pw.TextStyle(fontSize: 5, color: _labelColor),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(2),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(3),
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: data.qrPayload,
                      width: 38,
                      height: 38,
                      drawText: false,
                    ),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              color: PdfColor.fromHex('#EEF2F7'),
              child: pw.Text(
                'VALIDAÇÃO VIA GESTÃO YAHWEH',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 4.8,
                  fontWeight: pw.FontWeight.bold,
                  color: _labelColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _field(
    String label,
    String value, {
    double size = 6,
    bool bold = false,
    PdfColor? valueColor,
    int maxLines = 1,
  }) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 4.8,
            fontWeight: pw.FontWeight.bold,
            color: _labelColor,
          ),
        ),
        pw.Text(
          v,
          maxLines: maxLines,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: valueColor ?? _valueColor,
          ),
        ),
      ],
    );
  }
}
