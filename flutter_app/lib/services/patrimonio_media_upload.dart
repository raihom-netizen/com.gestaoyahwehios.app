import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Resultado de upload de galeria — imagem full + miniatura opcional.
class PatrimonioGalleryUploadResult {
  const PatrimonioGalleryUploadResult({
    required this.full,
    this.thumbDownloadUrl,
    this.thumbStoragePath,
  });

  final MediaUploadResult full;
  final String? thumbDownloadUrl;
  final String? thumbStoragePath;

  String get downloadUrl => full.downloadUrl;
  String get storagePath => full.storagePath;
}

/// Upload de fotos do patrimônio — WebP 1920px + thumb em `patrimonio/thumbs/`.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static Future<PatrimonioGalleryUploadResult> uploadGalleryPhoto({
    required String storagePath,
    required Uint8List rawBytes,
    String? thumbStoragePath,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await StorageService.compressImageBytes(
      rawBytes,
      profile: MediaImageProfile.patrimonio,
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

    String? thumbUrl;
    String? thumbPathOut;
    final thumbPath = thumbStoragePath?.trim() ?? '';
    if (thumbPath.isNotEmpty) {
      try {
        final thumbBytes = await StorageService.compressImageBytes(
          bytes,
          profile: MediaImageProfile.thumb,
        );
        if (thumbBytes.isNotEmpty) {
          thumbUrl = await StorageService.uploadBytes(
            storagePath: thumbPath,
            bytes: thumbBytes,
            contentType: 'image/webp',
            module: YahwehUploadModule.generic,
          );
          thumbPathOut = thumbPath;
        }
      } catch (_) {}
    }

    return PatrimonioGalleryUploadResult(
      full: MediaUploadResult(
        downloadUrl: url,
        storagePath: storagePath,
        contentType: 'image/webp',
      ),
      thumbDownloadUrl: thumbUrl,
      thumbStoragePath: thumbPathOut,
    );
  }

  /// Deriva path de thumb a partir do path full e metadados do item.
  static String thumbPathForSlot({
    required String tenantId,
    required String itemDocId,
    required int slotIndex,
  }) =>
      ChurchStorageLayout.patrimonioThumbPath(tenantId, itemDocId, slotIndex);
}
