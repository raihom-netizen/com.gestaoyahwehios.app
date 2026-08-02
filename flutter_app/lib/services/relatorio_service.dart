import 'dart:typed_data' show Uint8List;
import 'dart:async';

import 'package:flutter/material.dart' show BuildContext, MediaQuery, Offset, Rect, RenderBox;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/core/gestao_yahweh_brand_asset_service.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Subconjunto do RelatorioService CT — PDF local (Utilitários) + share iOS.
/// Branding financeiro: cabeçalho igreja · rodapé Gestão YAHWEH.
abstract final class RelatorioService {
  RelatorioService._();

  /// Autoria oficial no rodapé dos PDFs financeiros.
  static const String kFinanceFooterBrand = 'Gestão YAHWEH';

  static pw.ThemeData? _latinPdfThemeReady;
  static Future<pw.ThemeData>? _latinPdfThemeInFlight;
  static Future<ReportPdfBranding>? _financeBrandingInFlight;
  static ReportPdfBranding? _financeBrandingReady;
  static String? _financeBrandingTenant;
  static Uint8List? _systemLogoReady;
  static Future<Uint8List?>? _systemLogoInFlight;

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

  /// Aquece assets PDF (fontes, logos) em background.
  static Future<void> warmUpPdfAssets() async {
    unawaited(loadFinanceReportPdfBranding());
    unawaited(loadFinanceSystemLogoBytes());
  }

  /// Garante ícone GY no rodapé antes de gerar qualquer relatório do sistema.
  static Future<void> ensureSystemReportFooterLogo() =>
      loadFinanceSystemLogoBytes();

  /// Gera nome de ficheiro para relatorio PDF a partir do periodo — CT compat.
  static String reportFilenameFromPeriod(
    String prefix,
    DateTime start,
    DateTime end,
    String? suffix,
  ) {
    final ds = '${start.year}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}';
    final de = '${end.year}${end.month.toString().padLeft(2, '0')}${end.day.toString().padLeft(2, '0')}';
    final suf = (suffix != null && suffix.isNotEmpty) ? '_$suffix' : '';
    return '${prefix}_$ds-$de$suf.pdf';
  }

  /// Sanitiza texto para uso em relatorio PDF — CT compat.
  static String sanitizeForReport(String text) => text;

  /// Branding PDF financeiro: logo igreja → Storage → fallback Gestão YAHWEH.
  static Future<ReportPdfBranding> loadFinanceReportPdfBranding({
    String? tenantId,
  }) async {
    final tid = (tenantId ?? ChurchContextService.currentChurchId ?? '').trim();
    final cached = _financeBrandingReady;
    if (cached != null && _financeBrandingTenant == tid) return cached;
    final inflight = _financeBrandingInFlight;
    if (inflight != null && _financeBrandingTenant == tid) return inflight;
    _financeBrandingTenant = tid;
    final fut = loadReportPdfBranding(tid).then((b) {
      _financeBrandingReady = b;
      return b;
    });
    _financeBrandingInFlight = fut;
    try {
      return await fut;
    } finally {
      if (identical(_financeBrandingInFlight, fut)) {
        _financeBrandingInFlight = null;
      }
    }
  }

  /// Título de marca para cabeçalho do extrato (sempre dados da igreja).
  static String financeBrandTitle(ReportPdfBranding branding) {
    final name = branding.churchName.trim();
    return name.isNotEmpty ? name : 'Igreja';
  }

  /// Logo da igreja para o cabeçalho (null se ainda não houver logo cadastrada).
  static Uint8List? financeHeaderLogoBytes(ReportPdfBranding branding) {
    if (!branding.logoIsChurch) return null;
    final b = branding.logoBytes;
    if (b == null || b.length < 32) return null;
    return b;
  }

  /// Escudo Gestão YAHWEH para o rodapé (autoria).
  static Future<Uint8List?> loadFinanceSystemLogoBytes() async {
    final hit = _systemLogoReady;
    if (hit != null && hit.length > 32) return hit;
    final inflight = _systemLogoInFlight;
    if (inflight != null) return inflight;
    final fut = () async {
      try {
        final b = await GestaoYahwehBrandAssetService.loadPngBytes();
        _systemLogoReady = b;
        PdfSuperPremiumTheme.setSystemFooterLogo(b);
        return b;
      } catch (_) {
        return null;
      }
    }();
    _systemLogoInFlight = fut;
    try {
      return await fut;
    } finally {
      if (identical(_systemLogoInFlight, fut)) {
        _systemLogoInFlight = null;
      }
    }
  }

  /// Carrega bytes do logo da igreja (cabeçalho financeiro).
  static Future<Uint8List?> loadPdfLogoBytesOnce({String? tenantId}) async {
    final b = await loadFinanceReportPdfBranding(tenantId: tenantId);
    return financeHeaderLogoBytes(b);
  }

  /// Partilha bytes PDF (printing sharePdf) — CT compat.
  static Future<void> sharePdfBytes(
    Uint8List bytes,
    String filename, {
    BuildContext? anchorContext,
    Rect? sharePositionOrigin,
    Offset? anchorPoint,
  }) async {
    await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
    );
  }

  /// Constroi badge de logo para cabecalho PDF — CT compat.
  static pw.Widget buildPdfLogoBadge(
    Uint8List? logoBytes, {
    pw.EdgeInsets margin = pw.EdgeInsets.zero,
    double size = 48,
  }) {
    if (logoBytes == null || logoBytes.isEmpty) {
      return pw.SizedBox(width: size, height: size);
    }
    return pw.Container(
      margin: margin,
      width: size,
      height: size,
      child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
    );
  }
}
