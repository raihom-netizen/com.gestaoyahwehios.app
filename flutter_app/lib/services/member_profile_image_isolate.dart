import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lado maior máximo (px) — um único JPEG leve para `foto_perfil.jpg`.
const int kMemberProfileMaxEdgePx = 800;

const int kMemberProfileJpegQuality = 85;

/// Função top-level para [compute] — só Dart + `image` (sem plugins / MethodChannel).
Uint8List compressMemberProfileForUploadIsolate(Uint8List raw) {
  if (raw.isEmpty) return raw;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var w = decoded.width;
    var h = decoded.height;
    if (w <= 0 || h <= 0) return raw;

    final maxEdge = kMemberProfileMaxEdgePx;
    img.Image work = decoded;
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

    final jpg = img.encodeJpg(work, quality: kMemberProfileJpegQuality);
    if (jpg.isEmpty) return raw;
    return Uint8List.fromList(jpg);
  } catch (_) {
    return raw;
  }
}
