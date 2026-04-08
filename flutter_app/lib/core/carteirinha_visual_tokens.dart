import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

/// Padrão oficial Gestão YAHWEH — carteirinha na tela, PNG exportado e PDF compartilham estes tokens.
/// O gestor altera só a cor principal (e opcionalmente secundária) em Configurar carteirinha.
abstract final class CarteirinhaVisualTokens {
  CarteirinhaVisualTokens._();

  static const Color accentGoldFlutter = Color(0xFFE8C478);
  static PdfColor get accentGoldPdf => PdfColor.fromHex('#E8C478');

  /// Degradê quando não há `bgColorSecondary`: mesmo cálculo na pré-visualização e no PDF.
  static Color gradientEndFromPrimary(Color primary) => Color.alphaBlend(
        Colors.black.withValues(alpha: 0.22),
        primary,
      );

  static PdfColor flutterColorToPdfColor(Color c) =>
      PdfColor(c.red / 255.0, c.green / 255.0, c.blue / 255.0);
}
