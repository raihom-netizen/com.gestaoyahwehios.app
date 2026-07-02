import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/member_card_pdf_builder.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_pdf_capture_leaf.dart';
import 'package:screenshot/screenshot.dart';

/// Rasteriza [MemberCardCnhDigital] para PNG — PDF fica idêntico ao cartão na tela.
abstract final class MemberCardPdfRasterService {
  MemberCardPdfRasterService._();

  static final ScreenshotController _controller = ScreenshotController();

  /// Equilíbrio nitidez × velocidade (impressão jato/laser).
  static const double capturePixelRatio = 1.75;
  static Duration get captureDelay =>
      Duration(milliseconds: YahwehPerformanceV4.memberCardPdfCaptureDelayMs);

  static Future<Uint8List?> captureSlice({
    required MemberCardPdfSlice slice,
    Uint8List? logoBytes,
  }) async {
    try {
      final bytes = await _controller
          .captureFromWidget(
            MemberCardPdfCaptureLeaf(
              data: slice.view,
              logoBytes: logoBytes,
              photoBytes: slice.photoBytes,
            ),
            pixelRatio: capturePixelRatio,
            delay: captureDelay,
          )
          .timeout(const Duration(seconds: 12));
      return bytes;
    } on TimeoutException {
      return null;
    } catch (e, st) {
      debugPrint('MemberCardPdfRasterService.captureSlice: $e\n$st');
      return null;
    }
  }

  /// Capturas em paralelo limitado (UI thread — não exagerar).
  static Future<List<Uint8List?>> captureBatch({
    required List<MemberCardPdfSlice> slices,
    Uint8List? logoBytes,
    int parallel = 3,
    void Function(int done, int total)? onProgress,
  }) async {
    if (slices.isEmpty) return const [];
    final out = List<Uint8List?>.filled(slices.length, null);
    final total = slices.length;
    var done = 0;
    final p = math.max(
      1,
      parallel.clamp(1, YahwehPerformanceV4.memberCardPdfRasterParallel),
    );

    for (var i = 0; i < slices.length; i += p) {
      final end = math.min(i + p, slices.length);
      final chunk = List.generate(end - i, (j) => i + j);
      await Future.wait(
        chunk.map((idx) async {
          out[idx] = await captureSlice(
            slice: slices[idx],
            logoBytes: logoBytes,
          );
        }),
      );
      done = end;
      onProgress?.call(done, total);
    }
    return out;
  }
}
