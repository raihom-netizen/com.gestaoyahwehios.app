import 'package:flutter/material.dart';

/// Paleta premium do editor de aviso/evento (mural).
abstract final class ChurchFeedPublishEditorTheme {
  ChurchFeedPublishEditorTheme._();

  static ({Color primary, Color secondary, Color accent, List<Color> gradient})
      paletteFor(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'evento' || t == 'noticia' || t == 'noticias') {
      return (
        primary: const Color(0xFFDB2777),
        secondary: const Color(0xFFF97316),
        accent: const Color(0xFFFBBF24),
        gradient: const [
          Color(0xFFDB2777),
          Color(0xFFEA580C),
          Color(0xFFF59E0B),
        ],
      );
    }
    return (
      primary: const Color(0xFF2563EB),
      secondary: const Color(0xFF4F46E5),
      accent: const Color(0xFF38BDF8),
      gradient: const [
        Color(0xFF1D4ED8),
        Color(0xFF4F46E5),
        Color(0xFF0EA5E9),
      ],
    );
  }

  static LinearGradient headerGradient(String type) {
    final g = paletteFor(type).gradient;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: g,
    );
  }

  static BoxDecoration photoTileDecoration(Color accent) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.22),
          accent.withValues(alpha: 0.06),
        ],
      ),
      border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
