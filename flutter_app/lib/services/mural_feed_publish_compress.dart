import 'dart:typed_data';

import 'package:gestao_yahweh/services/church_instant_upload_pipeline.dart';

/// Legado — **não usar em código novo**. Delega a [ChurchInstantUploadPipeline]
/// (1 JPEG/WebP por foto; sem 3 tiers thumb/medium/full).
@Deprecated(
  'Use ChurchInstantUploadPipeline.prepareImageBytes ou EcoFireFeedPublishService.uploadPhotoSlot.',
)
abstract final class MuralFeedPublishCompress {
  MuralFeedPublishCompress._();

  static Future<Uint8List> compressBytes(Uint8List raw) =>
      ChurchInstantUploadPipeline.prepareImageBytes(raw);

  static Future<Uint8List> compressPath(String path) =>
      ChurchInstantUploadPipeline.prepareImageBytes(Uint8List(0), localPath: path);
}
