import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:gestao_yahweh/ui/pdf/verso_carteirinha_widget.dart';

/// Folha para gráfica: cartão CR80 centralizado com sangria e marcas de corte.
class CarteirinhaPvcMarks {
  CarteirinhaPvcMarks._();

  /// ~4 mm de margem para marcas (72 pt / 25,4 mm).
  static const double bleedPt = 11.34;
  static const double markLen = 9;
  static const double markThick = 0.65;

  static PdfPageFormat pageFormat() {
    final cw = VersoCarteirinhaPdfWidget.cardWidthPt;
    final ch = VersoCarteirinhaPdfWidget.cardHeightPt;
    return PdfPageFormat(cw + bleedPt * 2, ch + bleedPt * 2);
  }

  static pw.Widget wrapWithCropMarks(pw.Widget card) {
    final pf = pageFormat();
    final cw = VersoCarteirinhaPdfWidget.cardWidthPt;
    final ch = VersoCarteirinhaPdfWidget.cardHeightPt;
    final ox = bleedPt;
    final oy = bleedPt;
    final ml = markLen;
    final t = markThick;
    final ink = PdfColors.grey800;

    pw.Widget mark(double left, double top, double w, double h) =>
        pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(width: w, height: h, color: ink),
        );

    return pw.SizedBox(
      width: pf.width,
      height: pf.height,
      child: pw.Stack(
        children: [
          pw.Container(
            width: pf.width,
            height: pf.height,
            color: PdfColors.white,
          ),
          pw.Positioned(left: ox, top: oy, child: card),
          // Canto superior esquerdo
          mark(ox - ml, oy, ml, t),
          mark(ox, oy - ml, t, ml),
          // Superior direito
          mark(ox + cw, oy, ml, t),
          mark(ox + cw - t, oy - ml, t, ml),
          // Inferior esquerdo
          mark(ox - ml, oy + ch - t, ml, t),
          mark(ox, oy + ch, t, ml),
          // Inferior direito
          mark(ox + cw, oy + ch - t, ml, t),
          mark(ox + cw - t, oy + ch, t, ml),
        ],
      ),
    );
  }
}
