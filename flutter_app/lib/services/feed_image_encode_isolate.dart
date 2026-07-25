import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lado maior máximo (px) — alinhado ao teto do feed CT (1600).
const int kFeedEncodeFallbackMaxEdgePx = 1600;

const int kFeedEncodeFallbackJpegQuality = 78;

const int kFeedEncodeFallbackTargetBytes = 700 * 1024;

/// Top-level para [compute] — decode/resize/encode JPEG sem plugins nativos.
Uint8List encodeFeedImageForUploadIsolate(Uint8List raw) {
  if (raw.isEmpty) return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var w = decoded.width;
    var h = decoded.height;
    if (w <= 0 || h <= 0) return raw;

    img.Image work = decoded;
    final maxEdge = kFeedEncodeFallbackMaxEdgePx;
    if (w > maxEdge || h > maxEdge) {
      if (w >= h) {
        h = (h * maxEdge / w).round().clamp(1, 1 << 20);
        w = maxEdge;
      } else {
        w = (w * maxEdge / h).round().clamp(1, 1 << 20);
        h = maxEdge;
      }
      work = img.copyResize(
        decoded,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    }

    const qualities = <int>[78, 70, 62, 55, 48];
    Uint8List best = Uint8List.fromList(
      img.encodeJpg(work, quality: kFeedEncodeFallbackJpegQuality),
    );
    for (final q in qualities) {
      final jpg = img.encodeJpg(work, quality: q);
      if (jpg.isEmpty) continue;
      best = Uint8List.fromList(jpg);
      if (best.length <= kFeedEncodeFallbackTargetBytes) break;
    }
    if (best.isEmpty) return raw;
    return best;
  } catch (_) {
    return raw;
  }
}
