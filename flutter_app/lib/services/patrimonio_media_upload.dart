import 'dart:typed_data';

import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload de fotos do patrimônio — WebP 80% + `putData` directo (padrão Controle Total).
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static Future<MediaUploadResult> uploadGalleryPhoto({
    required String storagePath,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await StorageService.compressImageBytes(
      rawBytes,
      profile: MediaImageProfile.feed,
    );
    if (bytes.isEmpty) {
      throw StateError(
        'Não foi possível processar a imagem. Tente outra foto ou formato.',
      );
    }
    final url = await StorageService.uploadBytes(
      storagePath: storagePath,
      bytes: bytes,
      contentType: 'image/webp',
      module: YahwehUploadModule.generic,
      onProgress: onProgress,
    );
    return MediaUploadResult(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: 'image/webp',
    );
  }
}
