import 'dart:typed_data';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload de fotos do patrimônio — WebP 80% + `putData` directo (padrão Controle Total).
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static Future<MediaUploadResult> uploadGalleryPhoto({
    required String storagePath,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
  }) async {
    await ensureUploadBootstrapForStoragePath(storagePath);
    final bytes = await ImageHelper.compressPatrimonioPhotoForUpload(rawBytes);
    if (bytes.isEmpty) {
      throw StateError(
        'Não foi possível processar a imagem. Tente outra foto ou formato.',
      );
    }
    final url = await YahwehMediaUploadPipeline.uploadPreparedBytes(
      storagePath: storagePath,
      bytes: bytes,
      contentType: 'image/webp',
      maxAttempts: 4,
      onProgress: onProgress,
    );
    return MediaUploadResult(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: 'image/webp',
    );
  }
}
