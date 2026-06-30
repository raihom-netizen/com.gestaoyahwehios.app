import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:gestao_yahweh/core/media/media_optimization_profile.dart';

/// Mensagem serializável para [compute] — compressão JPEG/WebP pura Dart.
class MediaOptimizeIsolateMessage {
  const MediaOptimizeIsolateMessage({
    required this.raw,
    required this.maxEdge,
    required this.quality,
    this.maxBytes = 0,
    this.preferWebp = true,
  });

  final Uint8List raw;
  final int maxEdge;
  final int quality;
  final int maxBytes;
  final bool preferWebp;
}

/// Top-level — roda em isolate (mobile/desktop).
Uint8List mediaOptimizeImageIsolate(MediaOptimizeIsolateMessage msg) {
  if (msg.raw.isEmpty) return msg.raw;
  try {
    final decoded = img.decodeImage(msg.raw);
    if (decoded == null) return msg.raw;

    var w = decoded.width;
    var h = decoded.height;
    if (w <= 0 || h <= 0) return msg.raw;

    img.Image work = decoded;
    final maxEdge = msg.maxEdge.clamp(64, 4096);
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

    var quality = msg.quality.clamp(40, 95);
    var edge = maxEdge;
    Uint8List out = _encode(work, quality, msg.preferWebp);
    final cap = msg.maxBytes;
    if (cap <= 0 || out.length <= cap) return out;

    for (var i = 0; i < 6 && out.length > cap; i++) {
      edge = (edge * 0.85).round().clamp(256, maxEdge);
      quality = (quality - 6).clamp(42, msg.quality);
      if (work.width > edge || work.height > edge) {
        if (work.width >= work.height) {
          final nh = (work.height * edge / work.width).round().clamp(1, 1 << 20);
          work = img.copyResize(work, width: edge, height: nh);
        } else {
          final nw = (work.width * edge / work.height).round().clamp(1, 1 << 20);
          work = img.copyResize(work, width: nw, height: edge);
        }
      }
      out = _encode(work, quality, msg.preferWebp);
    }
    return out;
  } catch (_) {
    return msg.raw;
  }
}

Uint8List _encode(img.Image work, int quality, bool preferWebp) {
  final jpg = img.encodeJpg(work, quality: quality);
  return jpg.isEmpty ? Uint8List(0) : Uint8List.fromList(jpg);
}

MediaOptimizeIsolateMessage profileToMessage(
  Uint8List raw,
  MediaOptimizationProfile profile,
) {
  switch (profile) {
    case MediaOptimizationProfile.chat:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.chatMaxEdge,
        quality: MediaOptimizationLimits.chatQuality,
        maxBytes: MediaOptimizationLimits.chatFullMaxBytes,
      );
    case MediaOptimizationProfile.profile:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.profileMaxEdge,
        quality: MediaOptimizationLimits.profileQuality,
      );
    case MediaOptimizationProfile.general:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.generalMaxEdge,
        quality: MediaOptimizationLimits.generalQuality,
      );
    case MediaOptimizationProfile.receipt:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.receiptMaxEdge,
        quality: MediaOptimizationLimits.receiptQuality,
      );
    case MediaOptimizationProfile.thumbPreview:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.thumbPreviewEdge,
        quality: MediaOptimizationLimits.thumbPreviewQuality,
        maxBytes: 48 * 1024,
      );
    case MediaOptimizationProfile.thumbUpload:
      return MediaOptimizeIsolateMessage(
        raw: raw,
        maxEdge: MediaOptimizationLimits.thumbUploadEdge,
        quality: MediaOptimizationLimits.thumbUploadQuality,
        maxBytes: MediaOptimizationLimits.chatThumbMaxBytes,
      );
  }
}
