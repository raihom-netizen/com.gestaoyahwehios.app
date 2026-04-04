import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as im;

/// Mensagem enviável para [compute] / isolate.
class CertPdfImageOptimizeMessage {
  final Uint8List bytes;
  final int maxW;
  final int maxH;
  final int jpegQuality;

  CertPdfImageOptimizeMessage({
    required this.bytes,
    required this.maxW,
    required this.maxH,
    this.jpegQuality = 86,
  });
}

/// Redimensiona imagens antes de [pw.MemoryImage]: evita decodificar fotos de vários MB no motor PDF.
///
/// Deve ser **top-level** para uso com `compute()`.
Uint8List optimizeCertPdfImageBytes(CertPdfImageOptimizeMessage args) {
  try {
    if (args.bytes.length < 64) return args.bytes;
    final src = im.decodeImage(args.bytes);
    if (src == null) return args.bytes;
    final w = src.width;
    final h = src.height;
    if (w <= 0 || h <= 0) return args.bytes;
    if (w <= args.maxW && h <= args.maxH) return args.bytes;

    final scale = math.min(args.maxW / w, args.maxH / h);
    final nw = math.max(1, (w * scale).round());
    final nh = math.max(1, (h * scale).round());

    final out = im.copyResize(
      src,
      width: nw,
      height: nh,
      interpolation: im.Interpolation.linear,
    );

    if (out.hasAlpha) {
      return Uint8List.fromList(im.encodePng(out, level: 6));
    }
    final q = args.jpegQuality.clamp(50, 95).toInt();
    return Uint8List.fromList(im.encodeJpg(out, quality: q));
  } catch (_) {
    return args.bytes;
  }
}

/// Limite de ~500 KB em memória após [im.decodeImage] + [im.copyResize] + JPEG.
class CertPdfImageMaxMemoryMessage {
  final Uint8List bytes;
  final int maxW;
  final int maxH;
  final int maxOutputBytes;

  CertPdfImageMaxMemoryMessage({
    required this.bytes,
    required this.maxW,
    required this.maxH,
    this.maxOutputBytes = 512000,
  });
}

/// Redimensiona e recompressa até ficar abaixo de [maxOutputBytes] (padrão 500 KB).
Uint8List optimizeCertPdfImageBytesMaxMemory(CertPdfImageMaxMemoryMessage args) {
  try {
    if (args.bytes.length < 64) return args.bytes;
    final src = im.decodeImage(args.bytes);
    if (src == null) return args.bytes;
    var w = src.width;
    var h = src.height;
    if (w <= 0 || h <= 0) return args.bytes;

    var scale = math.min(args.maxW / w, args.maxH / h);
    if (scale > 1) scale = 1;
    var nw = math.max(1, (w * scale).round());
    var nh = math.max(1, (h * scale).round());

    im.Image out = im.copyResize(
      src,
      width: nw,
      height: nh,
      interpolation: im.Interpolation.linear,
    );

    if (out.hasAlpha) {
      return Uint8List.fromList(im.encodePng(out, level: 6));
    }

    var q = 88;
    Uint8List encoded = Uint8List.fromList(im.encodeJpg(out, quality: q));
    while (encoded.length > args.maxOutputBytes && q > 42) {
      q -= 10;
      encoded = Uint8List.fromList(im.encodeJpg(out, quality: q));
    }

    if (encoded.length > args.maxOutputBytes && nw > 64 && nh > 64) {
      nw = math.max(64, (nw * 0.85).round());
      nh = math.max(64, (nh * 0.85).round());
      out = im.copyResize(
        src,
        width: nw,
        height: nh,
        interpolation: im.Interpolation.linear,
      );
      if (out.hasAlpha) {
        return Uint8List.fromList(im.encodePng(out, level: 6));
      }
      q = 82;
      encoded = Uint8List.fromList(im.encodeJpg(out, quality: q));
      while (encoded.length > args.maxOutputBytes && q > 42) {
        q -= 10;
        encoded = Uint8List.fromList(im.encodeJpg(out, quality: q));
      }
    }

    return encoded;
  } catch (_) {
    return args.bytes;
  }
}
