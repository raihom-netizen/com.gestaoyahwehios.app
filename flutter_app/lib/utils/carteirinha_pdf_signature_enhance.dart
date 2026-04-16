import 'dart:typed_data';

import 'package:image/image.dart' as img;

int _clamp255(num v) => v.round().clamp(0, 255);

/// Escurece traços claros da assinatura (equivalente ao contraste da app) e preserva
/// “papel” muito claro. Destinado a bytes já redimensionados para o PDF.
///
/// Top-level para uso com [compute] fora da UI.
Uint8List? carteirinhaPdfEnhanceSignatureBytesSync(Uint8List bytes) {
  if (bytes.length < 33) return null;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final work = decoded.convert(numChannels: 4);
    const mult = 1.62;
    const bias = -66.0;
    for (var y = 0; y < work.height; y++) {
      for (var x = 0; x < work.width; x++) {
        final p = work.getPixel(x, y);
        final a = p.a.toInt();
        if (a < 10) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lum > 246 && a > 225) {
          p.set(img.ColorUint8.rgba(255, 255, 255, a));
          continue;
        }
        p.set(
          img.ColorUint8.rgba(
            _clamp255(r * mult + bias),
            _clamp255(g * mult + bias),
            _clamp255(b * mult + bias),
            a,
          ),
        );
      }
    }

    if (work.hasAlpha) {
      return Uint8List.fromList(img.encodePng(work, level: 6));
    }
    return Uint8List.fromList(img.encodeJpg(work, quality: 82));
  } catch (_) {
    return null;
  }
}

/// Entrada/saída não-nula para [compute] (o pacote exige tipo concreto).
Uint8List carteirinhaPdfEnhanceSignatureForCompute(Uint8List bytes) {
  return carteirinhaPdfEnhanceSignatureBytesSync(bytes) ?? bytes;
}
