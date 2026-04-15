import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Entrada serializável para [compute] — redimensiona foto/logo para PDF (CR80).
/// Top-level obrigatório para isolate.
///
/// Sempre devolve **JPEG** quando [decodeImage] tem sucesso. Antes, imagens já
/// pequenas (ex. logo WebP) voltavam nos bytes originais — o `pdf`/`MemoryImage`
/// não embute WebP de forma confiável na web (área branca).
Uint8List? carteirinhaPdfResizeBytesForEmbed(Map<String, dynamic> arg) {
  final bytes = arg['b'];
  if (bytes is! Uint8List || bytes.length < 33) {
    return null;
  }
  final maxSide = (arg['m'] as int?) ?? 200;
  final quality = (arg['q'] as int?) ?? 68;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final w = decoded.width;
    final h = decoded.height;
    img.Image toEncode = decoded;
    if (w > maxSide || h > maxSide) {
      final scale = w >= h ? (maxSide / w) : (maxSide / h);
      final rw = (w * scale).round().clamp(1, maxSide);
      final rh = (h * scale).round().clamp(1, maxSide);
      toEncode = img.copyResize(
        decoded,
        width: rw,
        height: rh,
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
  } catch (_) {
    return null;
  }
}
