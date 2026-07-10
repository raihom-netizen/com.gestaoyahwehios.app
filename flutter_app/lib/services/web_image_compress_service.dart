import 'dart:typed_data';

import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart'
    show kEventoAvisoFeedEncodeMaxEdgePx, kEventoAvisoFeedWebpQuality;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:image/image.dart' as img;

/// Compactação **100 % Dart** na Web — sem `flutter_image_compress` / platform channels.
///
/// Mobile continua em [MediaService.compressImageBytes] (nativo, mais rápido).
abstract final class WebImageCompressService {
  WebImageCompressService._();

  static Future<Uint8List> compressBytes({
    required Uint8List input,
    MediaImageProfile profile = MediaImageProfile.feed,
  }) async {
    if (input.isEmpty) return input;
    if (profile == MediaImageProfile.feed && bytesLookLikeWebp(input)) {
      if (input.length <= 900000) return input;
    }

    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw StateError(
        'Não foi possível ler a imagem no navegador. Tente JPG ou PNG.',
      );
    }

    final edge = _edgeFor(profile);
    final quality = _qualityFor(profile);
    final resized = _resizeMaxEdge(decoded, edge);

    // Web: JPEG via pacote `image` (WebP encode nem sempre disponível em todas as versões).
    final jpg = img.encodeJpg(resized, quality: quality);
    if (jpg.isEmpty) {
      throw StateError('Falha ao compactar imagem na Web.');
    }
    return Uint8List.fromList(jpg);
  }

  static int _edgeFor(MediaImageProfile profile) => switch (profile) {
        MediaImageProfile.chat => MediaService.chatImageMaxEdge,
        MediaImageProfile.feed => kEventoAvisoFeedEncodeMaxEdgePx,
        MediaImageProfile.thumb => MediaService.thumbMaxEdge,
        MediaImageProfile.patrimonio => kStandardUploadImageMaxEdge,
      };

  static int _qualityFor(MediaImageProfile profile) => switch (profile) {
        MediaImageProfile.chat => kStandardUploadImageQuality,
        MediaImageProfile.feed => kEventoAvisoFeedWebpQuality,
        MediaImageProfile.thumb => MediaService.thumbJpegQuality,
        MediaImageProfile.patrimonio => kStandardUploadImageQuality,
      };

  static img.Image _resizeMaxEdge(img.Image source, int maxEdge) {
    var w = source.width;
    var h = source.height;
    if (w <= 0 || h <= 0) return source;
    if (w <= maxEdge && h <= maxEdge) return source;

    if (w >= h) {
      h = (h * maxEdge / w).round().clamp(1, 1 << 20);
      w = maxEdge;
    } else {
      w = (w * maxEdge / h).round().clamp(1, 1 << 20);
      h = maxEdge;
    }
    return img.copyResize(
      source,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }
}
