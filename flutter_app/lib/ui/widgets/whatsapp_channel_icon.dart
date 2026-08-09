import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Verde oficial da marca WhatsApp.
const Color kWhatsAppBrandGreen = Color(0xFF25D366);

/// Marca WhatsApp em **branco** para uso sobre fundo verde/gradiente
/// (Canais oficiais, site público). Mantido por compatibilidade.
class WhatsappChannelIcon extends StatelessWidget {
  final double size;

  const WhatsappChannelIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return WhatsappBrandIcon(size: size, color: Colors.white);
  }
}

/// **Logo oficial** do WhatsApp — balão verde arredondado com o telefone branco.
/// Autocontido (duas cores): usar em botões só-ícone sobre fundo neutro/claro.
class WhatsAppOfficialLogo extends StatelessWidget {
  final double size;

  /// Cor do balão (fundo). Padrão: verde oficial.
  final Color background;

  /// Cor do telefone/glifo. Padrão: branco.
  final Color glyph;

  const WhatsAppOfficialLogo({
    super.key,
    required this.size,
    this.background = kWhatsAppBrandGreen,
    this.glyph = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final s = size.clamp(14.0, 96.0);
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        size: Size(s, s),
        painter: _WhatsAppLogoPainter(background: background, glyph: glyph),
      ),
    );
  }
}

/// Glifo WhatsApp monocromático (balão + telefone) na cor [color].
/// Sobre fundo verde (usa branco), o telefone fica vazado revelando o fundo —
/// vetorial e estável na web/PWA.
class WhatsappBrandIcon extends StatelessWidget {
  final double size;
  final Color color;

  const WhatsappBrandIcon({
    super.key,
    required this.size,
    this.color = kWhatsAppBrandGreen,
  });

  @override
  Widget build(BuildContext context) {
    final s = size.clamp(12.0, 40.0);
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        size: Size(s, s),
        painter: _WhatsAppLogoPainter(background: null, glyph: color),
      ),
    );
  }
}

/// Desenha o balão do WhatsApp + o telefone fiel à marca.
/// - [background] != null → logo oficial: balão [background] + telefone [glyph].
/// - [background] == null → monocromático: balão [glyph] com o telefone vazado.
class _WhatsAppLogoPainter extends CustomPainter {
  final Color? background;
  final Color glyph;

  const _WhatsAppLogoPainter({required this.background, required this.glyph});

  Path _bubblePath(double w, double h) {
    final r = w * 0.30;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.05, h * 0.05, w * 0.90, h * 0.90),
          Radius.circular(r),
        ),
      );
    // Cauda no canto inferior esquerdo (marca WhatsApp).
    final tail = Path()
      ..moveTo(w * 0.12, h * 0.86)
      ..lineTo(w * 0.02, h * 0.98)
      ..lineTo(w * 0.26, h * 0.90)
      ..close();
    path.addPath(tail, Offset.zero);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bg = background;
    final u = math.min(w, h);

    // Handset: arco espesso com pontas arredondadas, levemente inclinado.
    final rr = u * 0.22;
    final t = u * 0.135;
    final rect = Rect.fromCircle(center: Offset(w * 0.5, h * 0.5), radius: rr);
    final handset = Path()..addArc(rect, math.pi * 0.60, math.pi * 1.05);

    if (bg != null) {
      // ---- Logo oficial (duas cores) ----
      canvas.drawPath(
        _bubblePath(w, h),
        Paint()
          ..color = bg
          ..isAntiAlias = true,
      );
      canvas.save();
      canvas.translate(w * 0.5, h * 0.5);
      canvas.rotate(0.32);
      canvas.translate(-w * 0.5, -h * 0.5);
      canvas.drawPath(
        handset,
        Paint()
          ..color = glyph
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = t
          ..isAntiAlias = true,
      );
      canvas.restore();
      return;
    }

    // ---- Monocromático: balão preenchido + telefone vazado ----
    canvas.saveLayer(Rect.fromLTWH(0, 0, w, h), Paint());
    canvas.drawPath(
      _bubblePath(w, h),
      Paint()
        ..color = glyph
        ..isAntiAlias = true,
    );
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(0.32);
    canvas.translate(-w * 0.5, -h * 0.5);
    canvas.drawPath(
      handset,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = t
        ..isAntiAlias = true,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WhatsAppLogoPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.glyph != glyph;
}
