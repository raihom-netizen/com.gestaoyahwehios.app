import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:image/image.dart' as img;

/// Perfis de compressão — alvo de tamanho e qualidade por módulo.
enum YahwehCompressProfile {
  chat,
  feed,
  patrimonio,
  member,
  logo,
  thumb,
  generic,
}

class _ProfileConfig {
  const _ProfileConfig({
    required this.maxEdge,
    required this.targetBytes,
    required this.qualities,
  });
  final int maxEdge;
  final int targetBytes;
  final List<int> qualities;
}

const Map<YahwehCompressProfile, _ProfileConfig> _kProfiles = {
  YahwehCompressProfile.chat: _ProfileConfig(
    maxEdge: 800,
    targetBytes: 200 * 1024,
    qualities: [70, 62, 55, 48],
  ),
  YahwehCompressProfile.feed: _ProfileConfig(
    maxEdge: 1440,
    targetBytes: 500 * 1024,
    qualities: [75, 68, 60, 52],
  ),
  YahwehCompressProfile.patrimonio: _ProfileConfig(
    maxEdge: 1200,
    targetBytes: 500 * 1024,
    qualities: [70, 62, 55, 48],
  ),
  YahwehCompressProfile.member: _ProfileConfig(
    maxEdge: 768,
    targetBytes: 300 * 1024,
    qualities: [82, 74, 66, 58],
  ),
  YahwehCompressProfile.logo: _ProfileConfig(
    maxEdge: 800,
    targetBytes: 200 * 1024,
    qualities: [70, 62, 55, 48],
  ),
  YahwehCompressProfile.thumb: _ProfileConfig(
    maxEdge: 480,
    targetBytes: 80 * 1024,
    qualities: [72, 64, 56, 48],
  ),
  YahwehCompressProfile.generic: _ProfileConfig(
    maxEdge: 1600,
    targetBytes: 700 * 1024,
    qualities: [78, 70, 62, 55, 48],
  ),
};

class _CompressArgs {
  const _CompressArgs({
    required this.raw,
    required this.maxEdge,
    required this.targetBytes,
    required this.qualities,
  });
  final Uint8List raw;
  final int maxEdge;
  final int targetBytes;
  final List<int> qualities;
}

abstract final class YahwehIsolateCompress {
  YahwehIsolateCompress._();

  static Future<Uint8List> compress(
    Uint8List raw, {
    YahwehCompressProfile profile = YahwehCompressProfile.generic,
  }) async {
    if (raw.isEmpty) return raw;
    if (_isWebp(raw)) return raw;
    final config =
        _kProfiles[profile] ?? _kProfiles[YahwehCompressProfile.generic]!;
    final args = _CompressArgs(
      raw: raw,
      maxEdge: config.maxEdge,
      targetBytes: config.targetBytes,
      qualities: config.qualities,
    );
    if (kIsWeb) return _compressInIsolate(args);
    try {
      return await compute(_compressInIsolate, args);
    } catch (_) {
      return raw;
    }
  }

  static Future<Uint8List> compressWithTarget(
    Uint8List raw, {
    required int maxEdge,
    required int targetBytes,
    List<int>? qualities,
  }) async {
    if (raw.isEmpty) return raw;
    if (_isWebp(raw)) return raw;
    final args = _CompressArgs(
      raw: raw,
      maxEdge: maxEdge,
      targetBytes: targetBytes,
      qualities: qualities ?? const [78, 70, 62, 55, 48],
    );
    if (kIsWeb) return _compressInIsolate(args);
    try {
      return await compute(_compressInIsolate, args);
    } catch (_) {
      return raw;
    }
  }

  static Future<Uint8List> compressForChat(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.chat);
  static Future<Uint8List> compressForFeed(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.feed);
  static Future<Uint8List> compressForPatrimonio(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.patrimonio);
  static Future<Uint8List> compressForMember(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.member);
  static Future<Uint8List> compressForLogo(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.logo);
  static Future<Uint8List> compressForThumb(Uint8List raw) =>
      compress(raw, profile: YahwehCompressProfile.thumb);

  static bool _isWebp(Uint8List bytes) {
    return bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }
}

Uint8List _compressInIsolate(_CompressArgs args) {
  if (args.raw.isEmpty) return args.raw;
  try {
    final decoded = img.decodeImage(args.raw);
    if (decoded == null) return args.raw;
    var w = decoded.width;
    var h = decoded.height;
    if (w <= 0 || h <= 0) return args.raw;
    img.Image work = decoded;
    if (work.numChannels == 4) {
      final flat = img.Image(width: w, height: h);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, work);
      work = flat;
    }
    final maxEdge = args.maxEdge;
    if (w > maxEdge || h > maxEdge) {
      if (w >= h) {
        h = (h * maxEdge / w).round().clamp(1, 1 << 20);
        w = maxEdge;
      } else {
        w = (w * maxEdge / h).round().clamp(1, 1 << 20);
        h = maxEdge;
      }
      work = img.copyResize(
        work,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    }
    Uint8List best = Uint8List.fromList(
      img.encodeJpg(work, quality: args.qualities.first),
    );
    for (final q in args.qualities) {
      final encoded = Uint8List.fromList(img.encodeJpg(work, quality: q));
      if (encoded.isEmpty) continue;
      best = encoded;
      if (encoded.length <= args.targetBytes) break;
    }
    if (best.length > args.targetBytes * 2) {
      var shrunk = work;
      for (var i = 0; i < 4; i++) {
        final nw = (shrunk.width * 9 ~/ 10).clamp(200, 4000);
        final nh = (shrunk.height * 9 ~/ 10).clamp(200, 4000);
        shrunk = img.copyResize(
          shrunk,
          width: nw,
          height: nh,
          interpolation: img.Interpolation.linear,
        );
        final encoded = Uint8List.fromList(
          img.encodeJpg(shrunk, quality: args.qualities.last),
        );
        if (encoded.isEmpty) break;
        best = encoded;
        if (encoded.length <= args.targetBytes) break;
      }
    }
    return best;
  } catch (_) {
    return args.raw;
  }
}
