import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Extrai texto de PDF (extrato com texto embutido) para importação de lançamentos.
abstract final class FinancePdfTextService {
  FinancePdfTextService._();

  static bool _init = false;

  static Future<void> _ensure() async {
    if (_init) return;
    await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
    _init = true;
  }

  /// Heurística: ficheiro parece bytes brutos de PDF, não UTF-8.
  static bool textLooksLikePdfBinary(String s) {
    final t = s.trim();
    if (t.length < 32) return false;
    if (t.startsWith('%PDF')) return true;
    if (t.contains('endstream') && t.contains('FlateDecode')) return true;
    var ctrl = 0;
    for (var i = 0; i < t.length && i < 4000; i++) {
      final c = t.codeUnitAt(i);
      if (c < 9 || (c > 13 && c < 32)) ctrl++;
    }
    return ctrl > 80;
  }

  static Future<String> extractPlainText(Uint8List bytes,
      {String sourceName = 'documento.pdf'}) async {
    await _ensure();
    final doc = await PdfDocument.openData(bytes, sourceName: sourceName);
    try {
      await doc.loadPagesProgressively();
      final sb = StringBuffer();
      for (final page in doc.pages) {
        final loaded =
            await page.waitForLoaded(timeout: const Duration(seconds: 12));
        final p = loaded ?? page;
        final raw = await p.loadText();
        if (raw != null && raw.fullText.trim().isNotEmpty) {
          sb.writeln(raw.fullText);
        }
      }
      return sb.toString();
    } finally {
      await doc.dispose();
    }
  }
}
