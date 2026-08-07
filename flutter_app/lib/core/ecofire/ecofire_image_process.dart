import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart'
    show
        kEventoAvisoFeedEncodeMaxEdgePx,
        kEventoAvisoFeedJpegQuality,
        kEventoAvisoFeedTargetMaxBytes;
import 'package:gestao_yahweh/core/yahweh_heavy_work.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Compressão/crop **antes** do upload — padrão EcoFire + Controle Total.
///
/// Decode/resize/encode rodam em [YahwehHeavyWork] (isolate no mobile) — **uma**
/// passagem JPEG (sem ponte q=92 + 2.ª compressão que travava a UI).
abstract final class EcoFireImageProcess {
  EcoFireImageProcess._();

  static const int feedMaxEdge = kEventoAvisoFeedEncodeMaxEdgePx;
  static const int memberSize = YahwehPerformanceV4.profileFullEdge;
  static const int patrimonioSize = YahwehPerformanceV4.uploadMaxEdgePx;
  static const int logoMaxSide = YahwehPerformanceV4.uploadMaxEdgePx;
  static const int thumbSize = YahwehPerformanceV4.profileThumbEdge;

  static Future<({Uint8List bytes, String mime})> processForLogo(
    Uint8List inputBytes,
  ) async {
    final out = await YahwehHeavyWork.run(_logoIsolate, inputBytes);
    return (bytes: out, mime: 'image/png');
  }

  static Future<({Uint8List bytes, String mime})> processForMemberProfile(
    Uint8List inputBytes,
  ) async {
    final out = await YahwehHeavyWork.run(
      _memberProfileIsolate,
      _MemberEncodeArgs(
        inputBytes,
        memberSize,
        YahwehPerformanceV4.profileFullQuality,
      ),
    );
    return (bytes: out, mime: 'image/jpeg');
  }

  static Future<({Uint8List bytes, String mime})> processForMemberThumb(
    Uint8List inputBytes,
  ) async {
    final out = await YahwehHeavyWork.run(
      _memberProfileIsolate,
      _MemberEncodeArgs(
        inputBytes,
        thumbSize,
        YahwehPerformanceV4.profileThumbQuality,
      ),
    );
    return (bytes: out, mime: 'image/jpeg');
  }

  static Future<({Uint8List bytes, String mime})> processForFeedPhoto(
    Uint8List inputBytes,
  ) async {
    final out = await YahwehHeavyWork.run(
      _feedPhotoIsolate,
      _FeedEncodeArgs(
        inputBytes,
        feedMaxEdge,
        kEventoAvisoFeedJpegQuality,
        kEventoAvisoFeedTargetMaxBytes,
      ),
    );
    return (bytes: out, mime: 'image/jpeg');
  }

  static Future<({Uint8List bytes, String mime})> processForPatrimonio(
    Uint8List inputBytes,
  ) async {
    final out = await YahwehHeavyWork.run(
      _memberProfileIsolate,
      _MemberEncodeArgs(inputBytes, patrimonioSize, 80),
    );
    return (bytes: out, mime: 'image/jpeg');
  }

  static ({Uint8List bytes, String mime}) passthrough(
    Uint8List bytes,
    String mimeType,
  ) =>
      (bytes: bytes, mime: mimeType);

  static String extensionFromMime(String mimeType) {
    final m = mimeType.toLowerCase();
    if (m.contains('webp')) return 'webp';
    if (m.contains('png')) return 'png';
    if (m.contains('jpeg') || m.contains('jpg')) return 'jpg';
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('mp4')) return 'mp4';
    return 'bin';
  }
}

@immutable
class _FeedEncodeArgs {
  const _FeedEncodeArgs(this.raw, this.maxEdge, this.quality, this.targetBytes);
  final Uint8List raw;
  final int maxEdge;
  final int quality;
  final int targetBytes;
}

@immutable
class _MemberEncodeArgs {
  const _MemberEncodeArgs(this.raw, this.edge, this.quality);
  final Uint8List raw;
  final int edge;
  final int quality;
}

Uint8List _logoIsolate(Uint8List inputBytes) {
  final decoded = img.decodeImage(inputBytes);
  if (decoded == null) {
    // Fallback: retorna bytes originais (o Storage rejeita se inválido).
    return inputBytes;
  }
  final resized = _resizeKeepAspect(decoded, EcoFireImageProcess.logoMaxSide);
  return Uint8List.fromList(img.encodePng(resized));
}

Uint8List _memberProfileIsolate(_MemberEncodeArgs args) {
  final decoded = img.decodeImage(args.raw);
  if (decoded == null) {
    // Fallback: retorna bytes originais (o Storage rejeita se inválido).
    return args.raw;
  }
  final cropped = _cropCenterAspect(decoded, 1.0);
  final resized = img.copyResize(
    cropped,
    width: args.edge,
    height: args.edge,
    interpolation: img.Interpolation.linear,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
}

/// Padrão CT: resize + qualities descendentes até caber no teto.
Uint8List _feedPhotoIsolate(_FeedEncodeArgs args) {
  final raw = args.raw;
  if (raw.isEmpty) return raw;
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    // Fallback: retorna bytes originais (o Storage rejeita se inválido).
    return raw;
  }
  final resized = _resizeKeepAspect(decoded, args.maxEdge);
  const qualities = <int>[78, 70, 62, 55, 48];
  final startQ = args.quality.clamp(48, 90);
  final ladder = <int>[
    startQ,
    for (final q in qualities)
      if (q < startQ) q,
  ];
  Uint8List best = Uint8List.fromList(img.encodeJpg(resized, quality: ladder.first));
  for (final q in ladder) {
    final enc = Uint8List.fromList(img.encodeJpg(resized, quality: q));
    if (enc.isEmpty) continue;
    best = enc;
    if (best.length <= args.targetBytes) break;
  }
  return best;
}

img.Image _resizeKeepAspect(img.Image source, int maxSide) {
  final w = source.width;
  final h = source.height;
  final m = w > h ? w : h;
  if (m <= maxSide) return source;
  final scale = maxSide / m;
  return img.copyResize(
    source,
    width: (w * scale).round(),
    height: (h * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}

img.Image _cropCenterAspect(img.Image source, double aspect) {
  final srcW = source.width;
  final srcH = source.height;
  final srcAspect = srcW / srcH;

  int cropW;
  int cropH;

  if (srcAspect > aspect) {
    cropH = srcH;
    cropW = (srcH * aspect).round();
  } else {
    cropW = srcW;
    cropH = (srcW / aspect).round();
  }

  final x = ((srcW - cropW) / 2).round().clamp(0, srcW - 1);
  final y = ((srcH - cropH) / 2).round().clamp(0, srcH - 1);

  return img.copyCrop(
    source,
    x: x,
    y: y,
    width: cropW.clamp(1, srcW - x),
    height: cropH.clamp(1, srcH - y),
  );
}
