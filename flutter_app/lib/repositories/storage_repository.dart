import 'dart:typed_data';

import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Fachada de upload Storage (Clean Architecture).
///
/// UI não deve chamar `FirebaseStorage` directamente — use compressão,
/// progresso e paralelismo centralizados aqui.
abstract final class StorageRepository {
  StorageRepository._();

  /// Upload paralelo de várias fotos (avisos, património, eventos).
  ///
  /// Usa [FeedPostMediaUpload.uploadParallel] com limite de concorrência
  /// para não saturar rede móvel.
  static Future<List<T>> uploadPhotosParallel<T>({
    required int count,
    required Future<T> Function(
      int index,
      void Function(double slotProgress) reportSlot,
    )
        uploadOne,
    String? progressLabel,
    void Function(double progress)? onBatchProgress,
    int? maxConcurrent,
  }) =>
      FeedPostMediaUpload.uploadParallel<T>(
        count: count,
        uploadOne: uploadOne,
        progressLabel: progressLabel,
        onBatchProgress: onBatchProgress,
        maxConcurrent: maxConcurrent,
      );

  /// Comprime bytes conforme módulo antes do put no Storage.
  static Future<Uint8List> compressImageBytes({
    required YahwehUploadModule module,
    required Uint8List bytes,
    required String contentType,
    bool chatJpegFast = false,
  }) =>
      YahwehMediaUploadPipeline.compressImageBytes(
        module: module,
        bytes: bytes,
        contentType: contentType,
        chatJpegFast: chatJpegFast,
      );

  /// Upload único com compressão, retry, timeout e progresso global.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    YahwehUploadModule? module,
    String? tenantId,
    void Function(double progress)? onProgress,
  }) =>
      YahwehMediaUploadPipeline.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        module: module,
        tenantId: tenantId,
        onProgress: onProgress,
      );

  static Future<void> warmAuthToken() => FeedPostMediaUpload.warmAuthToken();
}
