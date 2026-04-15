import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Argumento único para [compute] (encode fora da isolate principal).
class ChurchLogoPngEncodeArgs {
  final Uint8List raw;
  final int maxSide;
  const ChurchLogoPngEncodeArgs(this.raw, this.maxSide);
}

/// Codifica a logo da igreja como PNG (transparência preservada quando o decode suportar).
/// Limita o maior lado a [maxSide] px para o Storage não crescer sem controlo.
/// **Síncrono** — usar [encodeChurchLogoAsPngInIsolate] no cadastro da igreja para não bloquear a UI.
Uint8List encodeChurchLogoAsPngSync(
  Uint8List raw, {
  int maxSide = 1280,
}) {
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
    debugPrint('encodeChurchLogoAsPngSync: $e');
    return raw;
  }
}

Uint8List _encodeChurchLogoIsolate(ChurchLogoPngEncodeArgs args) {
  return encodeChurchLogoAsPngSync(args.raw, maxSide: args.maxSide);
}

/// Decode/resize/encode em **outra isolate** — evita “0%” eterno enquanto a UI está bloqueada.
Future<Uint8List> encodeChurchLogoAsPngInIsolate(
  Uint8List raw, {
  int maxSide = 1280,
}) {
  return compute(_encodeChurchLogoIsolate, ChurchLogoPngEncodeArgs(raw, maxSide));
}

/// Compatível com chamadas antigas; preferir [encodeChurchLogoAsPngInIsolate] no fluxo de upload.
Future<Uint8List> encodeChurchLogoAsPng(
  Uint8List raw, {
  int maxSide = 1280,
}) async {
  return encodeChurchLogoAsPngSync(raw, maxSide: maxSide);
}
