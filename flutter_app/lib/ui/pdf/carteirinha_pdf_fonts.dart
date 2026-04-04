import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Fontes TTF com suporte a acentos (pt-BR) para PDF da carteirinha — evita Helvetica limitada do pacote `pdf`.
class CarteirinhaPdfFonts {
  CarteirinhaPdfFonts._();

  static pw.ThemeData? _theme;
  static bool _loaded = false;

  /// Carrega Roboto dos assets (uma vez). Em falha retorna `null` (PDF usa fonte padrão).
  static Future<pw.ThemeData?> loadThemeData() async {
    if (_loaded) return _theme;
    _loaded = true;
    try {
      final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      final italicData = await rootBundle.load('assets/fonts/Roboto-Italic.ttf');
      final base = pw.Font.ttf(regular);
      final boldFont = pw.Font.ttf(bold);
      final italicFont = pw.Font.ttf(italicData);
      _theme = pw.ThemeData.withFont(
        base: base,
        bold: boldFont,
        italic: italicFont,
        boldItalic: boldFont,
      );
    } catch (e, st) {
      debugPrint('CarteirinhaPdfFonts: falha ao carregar TTF — $e\n$st');
      _theme = null;
    }
    return _theme;
  }

  @visibleForTesting
  static void resetForTest() {
    _theme = null;
    _loaded = false;
  }
}
