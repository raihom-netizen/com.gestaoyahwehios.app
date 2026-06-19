import 'package:gestao_yahweh/core/carteirinha_visual_tokens.dart';
import 'package:gestao_yahweh/ui/pdf/verso_carteirinha_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Frente da carteirinha CR80 — alinhada ao cartão digital (gradiente, foto, QR, validade).
class FrenteCarteirinhaPdfWidget extends pw.StatelessWidget {
  FrenteCarteirinhaPdfWidget({
    required this.nome,
    required this.categoria,
    required this.validade,
    required this.churchTitle,
    required this.churchSubtitle,
    required this.qrPayload,
    this.photoImage,
    this.logoImage,
    PdfColor? gradientStart,
    PdfColor? gradientEnd,
    PdfColor? accentGold,
  })  : accentGold = accentGold ?? PdfColor.fromHex('#E8C478'),
        gradientStart = gradientStart ?? PdfColor.fromHex('#0F766E'),
        gradientEnd = gradientEnd ?? PdfColor.fromHex('#0284C7'),
        super();

  final String nome;
  final String categoria;
  final String validade;
  final String churchTitle;
  final String churchSubtitle;
  final String qrPayload;
  final pw.ImageProvider? photoImage;
  final pw.ImageProvider? logoImage;
  final PdfColor gradientStart;
  final PdfColor gradientEnd;
  final PdfColor accentGold;

  static double get cardWidthPt => VersoCarteirinhaPdfWidget.cardWidthPt;
  static double get cardHeightPt => VersoCarteirinhaPdfWidget.cardHeightPt;

  @override
  pw.Widget build(pw.Context context) {
    final fg = PdfColors.white;
    final nomeTxt = nome.trim().isEmpty ? '—' : nome.trim();
    final catTxt = categoria.trim().isEmpty ? 'Membro' : categoria.trim();
    final valTxt = validade.trim().isEmpty ? '—' : validade.trim();

    return pw.Container(
      width: cardWidthPt,
      height: cardHeightPt,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(12),
        gradient: pw.LinearGradient(
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.8),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 11,
        verticalRadius: 11,
        child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 26,
                      height: 26,
                      margin: const pw.EdgeInsets.only(right: 6),
                      child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          churchTitle.trim().isEmpty
                              ? 'Gestão YAHWEH'
                              : churchTitle.trim(),
                          maxLines: 1,
                          style: pw.TextStyle(
                            color: fg,
                            fontSize: 7.2,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (churchSubtitle.trim().isNotEmpty)
                          pw.Text(
                            churchSubtitle.trim(),
                            maxLines: 1,
                            style: pw.TextStyle(
                              color: PdfColor(fg.red, fg.green, fg.blue, 0.88),
                              fontSize: 5.6,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 58,
                      height: 72,
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F1F5F9'),
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(
                          color: PdfColor(fg.red, fg.green, fg.blue, 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: photoImage != null
                          ? pw.ClipRRect(
                              horizontalRadius: 7,
                              verticalRadius: 7,
                              child: pw.Image(
                                photoImage!,
                                fit: pw.BoxFit.cover,
                              ),
                            )
                          : pw.Center(
                              child: pw.Text(
                                'Sem foto',
                                style: pw.TextStyle(
                                  color: PdfColors.grey600,
                                  fontSize: 5.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                    pw.SizedBox(width: 7),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1.2,
                            ),
                            decoration: pw.BoxDecoration(
                              color: PdfColor(
                                accentGold.red,
                                accentGold.green,
                                accentGold.blue,
                                0.22,
                              ),
                              borderRadius: pw.BorderRadius.circular(99),
                            ),
                            child: pw.Text(
                              'CREDENCIAL DE MEMBRO',
                              style: pw.TextStyle(
                                color: accentGold,
                                fontSize: 4.4,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            nomeTxt,
                            maxLines: 3,
                            style: pw.TextStyle(
                              color: fg,
                              fontSize: 9.2,
                              fontWeight: pw.FontWeight.bold,
                              lineSpacing: 1.05,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            catTxt,
                            maxLines: 2,
                            style: pw.TextStyle(
                              color: PdfColor(fg.red, fg.green, fg.blue, 0.92),
                              fontSize: 6.4,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Spacer(),
                          pw.Text(
                            'Validade: $valTxt',
                            style: pw.TextStyle(
                              color: PdfColor(fg.red, fg.green, fg.blue, 0.9),
                              fontSize: 5.8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (qrPayload.trim().isNotEmpty) ...[
                      pw.SizedBox(width: 4),
                      pw.SizedBox(
                        width: 44,
                        height: 44,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qrPayload.trim(),
                          drawText: false,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Carteirinha digital — valide pelo QR',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColor(fg.red, fg.green, fg.blue, 0.72),
                  fontSize: 4.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
