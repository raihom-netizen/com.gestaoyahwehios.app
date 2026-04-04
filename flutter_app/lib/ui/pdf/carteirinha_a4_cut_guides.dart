import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Linhas de corte pontilhadas entre cartões numa folha A4 (impressora jato de tinta + tesoura).
class CarteirinhaA4CutGuides {
  CarteirinhaA4CutGuides._();

  /// Desenha guias por cima da grelha [child] (mesmo tamanho que o filho após layout).
  static pw.Widget overlayOnGrid({
    required int cols,
    required int rows,
    required pw.Widget child,
  }) {
    if (cols < 2 && rows < 2) return child;
    return pw.CustomPaint(
      foregroundPainter: (PdfGraphics canvas, PdfPoint size) {
        if (cols < 2 && rows < 2) return;
        canvas
          ..setStrokeColor(PdfColors.grey500)
          ..setLineWidth(0.45)
          ..setLineDashPattern([2.2, 3.8], 0);
        final cw = size.x / cols;
        final ch = size.y / rows;
        for (var c = 1; c < cols; c++) {
          final x = c * cw;
          canvas.drawLine(x, 0, x, size.y);
          canvas.strokePath();
        }
        for (var r = 1; r < rows; r++) {
          final y = r * ch;
          canvas.drawLine(0, y, size.x, y);
          canvas.strokePath();
        }
      },
      child: child,
    );
  }
}
