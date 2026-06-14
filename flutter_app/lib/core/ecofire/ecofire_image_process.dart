import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart'
    show kEventoAvisoFeedEncodeMaxEdgePx;
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/media_service.dart';

/// Compressão/crop **antes** do upload — padrão EcoFire (`ImageProcessService`).
///
/// Gestão YAHWEH usa WebP/JPEG via [MediaService] (nunca Base64 no Firestore).
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
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem (logo).');
    }
    final resized = _resizeKeepAspect(decoded, logoMaxSide);
    return (
      bytes: Uint8List.fromList(img.encodePng(resized)),
      mime: 'image/png',
    );
  }

  static Future<({Uint8List bytes, String mime})> processForMemberProfile(
    Uint8List inputBytes,
  ) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem (membro).');
    }
    final cropped = _cropCenterAspect(decoded, 1.0);
    final resized = img.copyResize(
      cropped,
      width: memberSize,
      height: memberSize,
      interpolation: img.Interpolation.linear,
    );
    return _encodeProfile(resized, MediaImageProfile.feed, preferWebp: true);
  }

  static Future<({Uint8List bytes, String mime})> processForMemberThumb(
    Uint8List inputBytes,
  ) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem (thumb).');
    }
    final cropped = _cropCenterAspect(decoded, 1.0);
    final resized = img.copyResize(
      cropped,
      width: thumbSize,
      height: thumbSize,
      interpolation: img.Interpolation.linear,
    );
    return _encodeProfile(resized, MediaImageProfile.thumb, preferWebp: true);
  }

  static Future<({Uint8List bytes, String mime})> processForFeedPhoto(
    Uint8List inputBytes,
  ) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem (feed).');
    }
    final resized = _resizeKeepAspect(decoded, feedMaxEdge);
    final encoded = await _encodeProfile(
      resized,
      MediaImageProfile.feed,
      preferWebp: false,
    );
    return (bytes: encoded.bytes, mime: 'image/jpeg');
  }

  static Future<({Uint8List bytes, String mime})> processForPatrimonio(
    Uint8List inputBytes,
  ) async {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw StateError('Não foi possível decodificar a imagem (patrimônio).');
    }
    final cropped = _cropCenterAspect(decoded, 1.0);
    final resized = img.copyResize(
      cropped,
      width: patrimonioSize,
      height: patrimonioSize,
      interpolation: img.Interpolation.linear,
    );
    return _encodeProfile(resized, MediaImageProfile.patrimonio, preferWebp: true);
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

  static Future<({Uint8List bytes, String mime})> _encodeProfile(
    img.Image image,
    MediaImageProfile profile, {
    required bool preferWebp,
  }) async {
    final bridge = Uint8List.fromList(img.encodeJpg(image, quality: 92));
    final out = await MediaService.compressImageBytes(bridge, profile: profile);
    final mime = preferWebp &&
            (profile == MediaImageProfile.feed ||
                profile == MediaImageProfile.patrimonio ||
                profile == MediaImageProfile.thumb)
        ? 'image/webp'
        : 'image/jpeg';
    return (bytes: out, mime: mime);
  }

  static img.Image _resizeKeepAspect(img.Image source, int maxSide) {
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

  static img.Image _cropCenterAspect(img.Image source, double aspect) {
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
}
