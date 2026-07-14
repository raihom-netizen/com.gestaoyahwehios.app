import 'dart:async';

import 'package:flutter/material.dart' show BuildContext, MediaQuery, Offset, Rect, RenderBox;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Subconjunto do RelatorioService CT — PDF local (Utilitários) + share iOS.
abstract final class RelatorioService {
  RelatorioService._();

  static pw.ThemeData? _latinPdfThemeReady;
  static Future<pw.ThemeData>? _latinPdfThemeInFlight;

  static Future<pw.ThemeData> latinPdfThemeForExport() async {
    final ok = _latinPdfThemeReady;
    if (ok != null) return ok;
    final inflight = _latinPdfThemeInFlight;
    if (inflight != null) return inflight;
    final fut = _latinPdfThemeLoadOnce();
    _latinPdfThemeInFlight = fut;
    return fut;
  }

  static Future<pw.ThemeData> _latinPdfThemeLoadOnce() async {
    try {
      final t = await _downloadNotoLatinPdfTheme().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('noto_sans'),
      );
      _latinPdfThemeReady = t;
      return t;
    } catch (_) {
      return pw.ThemeData();
    } finally {
      _latinPdfThemeInFlight = null;
    }
  }

  static Future<pw.ThemeData> _downloadNotoLatinPdfTheme() async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final italic = await PdfGoogleFonts.notoSansItalic();
    final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
      fontFallback: [base],
    );
  }

  static Rect shareOriginFromContext(BuildContext? context) {
    if (context == null) {
      return const Rect.fromLTWH(0, 0, 2, 2);
    }
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && ro.size.width > 0 && ro.size.height > 0) {
      final origin = ro.localToGlobal(Offset.zero) & ro.size;
      if (origin.width > 0 && origin.height > 0) return origin;
    }
    final sz = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Rect.fromCenter(
      center: Offset(sz.width / 2, pad.top + sz.height / 3),
      width: 2,
      height: 2,
    );
  }
}
