import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/transactional_media_publish_pipeline.dart';

/// Resultado de upload de galeria — um ficheiro por slot na pasta do bem.
class PatrimonioGalleryUploadResult {
  const PatrimonioGalleryUploadResult({
    required this.full,
  });

  final MediaUploadResult full;

  String get downloadUrl => full.downloadUrl;
  String get storagePath => full.storagePath;
}

/// Upload de fotos do patrimônio — compactação 1024/80 % → Storage → URL.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static Future<PatrimonioGalleryUploadResult> uploadGalleryPhoto({
    required String storagePath,
    required Uint8List rawBytes,
    String? thumbStoragePath,
    void Function(double progress)? onProgress,
  }) async {
    final contentType = kIsWeb ? 'image/jpeg' : 'image/webp';
    final upload = await TransactionalMediaPublishPipeline.compressAndUpload(
      rawBytes: rawBytes,
      storagePath: storagePath,
      contentType: contentType,
      module: TransactionalMediaModule.strict,
      onProgress: (phase, p) {
        if (onProgress == null) return;
        onProgress(TransactionalMediaPublishPipeline.combinedProgress(phase, p));
      },
      useOfflineQueue: false,
    );

    return PatrimonioGalleryUploadResult(
      full: MediaUploadResult(
        downloadUrl: upload.downloadUrl,
        storagePath: upload.storagePath,
        contentType: upload.contentType,
      ),
    );
  }

  /// Sem thumb separada — um ficheiro por slot.
  static String thumbPathForSlot({
    required String tenantId,
    required String itemDocId,
    required int slotIndex,
  }) =>
      '';
}
