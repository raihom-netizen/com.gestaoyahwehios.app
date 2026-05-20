import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:image/image.dart' as img;

double? _decodeAspectRatioIsolate(Uint8List bytes) {
  try {
    final im = img.decodeImage(bytes);
    if (im == null || im.height <= 0) return null;
    return im.width / im.height;
  } catch (_) {
    return null;
  }
}

/// Lê proporção da imagem fora da thread UI (nativo).
Future<double?> imageAspectRatioFromBytes(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  if (kIsWeb) return _decodeAspectRatioIsolate(bytes);
  return compute(_decodeAspectRatioIsolate, bytes);
}
