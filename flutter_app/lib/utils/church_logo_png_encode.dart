import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Codifica a logo da igreja como PNG (transparência preservada quando o decode suportar).
/// Limita o maior lado a [maxSide] px para o Storage não crescer sem controlo.
Future<Uint8List> encodeChurchLogoAsPng(
  Uint8List raw, {
  int maxSide = 1600,
}) async {
  if (raw.isEmpty) return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final w = decoded.width;
    final h = decoded.height;
    if (w <= 0 || h <= 0) return raw;
    img.Image out = decoded;
    if (w > maxSide || h > maxSide) {
      final scale = maxSide / (w > h ? w : h);
      final nw = (w * scale).round().clamp(1, maxSide);
      final nh = (h * scale).round().clamp(1, maxSide);
      out = img.copyResize(decoded, width: nw, height: nh);
    }
    return Uint8List.fromList(img.encodePng(out));
  } catch (e) {
    debugPrint('encodeChurchLogoAsPng: $e');
    return raw;
  }
}
