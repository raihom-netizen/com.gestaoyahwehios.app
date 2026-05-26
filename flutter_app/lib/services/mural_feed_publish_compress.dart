import 'dart:typed_data';

import 'package:gestao_yahweh/services/media_image_variants_service.dart';

/// Legado — delega a [MediaImageVariantsService] (WebP q70, até 1920px).
abstract final class MuralFeedPublishCompress {
  MuralFeedPublishCompress._();

  static Future<Uint8List> compressBytes(Uint8List raw) async {
    final tiers = await MediaImageVariantsService.encodeFeedWebpTiers(bytes: raw);
    return tiers.full;
  }

  static Future<Uint8List> compressPath(String path) async {
    final tiers = await MediaImageVariantsService.encodeFeedWebpTiers(localPath: path);
    return tiers.full;
  }
}
