import 'package:flutter/material.dart';

/// Marca WhatsApp em **branco** para uso sobre fundo verde/gradiente (Canais oficiais, site público).
/// Não usa Font Awesome nem círculo branco extra — o pai já aplica o gradiente tipo “squircle”;
/// o ícone antigo (círculo branco + glifo pequeno) virava só um disco claro em cima do verde na web.
class WhatsappChannelIcon extends StatelessWidget {
  final double size;

  const WhatsappChannelIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final s = size.clamp(14.0, 30.0);
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        size: Size(s, s),
        painter: _WhatsAppMarkWhitePainter(),
      ),
    );
  }
}

/// Silhueta branca: balão + cauda + auricular (leitura clara ao lado de YouTube/Instagram).
class _WhatsAppMarkWhitePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final bubbleR = w * 0.18;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, h * 0.10, w * 0.72, h * 0.58),
        Radius.circular(bubbleR),
      ),
      fill,
    );

    final tail = Path()
      ..moveTo(w * 0.12, h * 0.62)
      ..lineTo(w * 0.02, h * 0.90)
      ..lineTo(w * 0.28, h * 0.66)
      ..close();
    canvas.drawPath(tail, fill);

    canvas.save();
    canvas.translate(w * 0.44, h * 0.38);
    canvas.rotate(-0.52);
    final hw = w * 0.13;
    final hh = h * 0.30;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: hw, height: hh),
        Radius.circular(hw * 0.42),
      ),
      fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
