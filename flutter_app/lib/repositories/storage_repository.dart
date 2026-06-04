import 'dart:typed_data';

import 'package:gestao_yahweh/services/storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Fachada UI → [StorageService] (Clean Architecture).
abstract final class StorageRepository {
  StorageRepository._();

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
      StorageService.uploadPhotosParallel<T>(
        count: count,
        uploadOne: uploadOne,
        progressLabel: progressLabel,
        onBatchProgress: onBatchProgress,
        maxConcurrent: maxConcurrent,
      );

  static Future<Uint8List> compressImageBytes(Uint8List input) =>
      StorageService.compressImageBytes(input);

  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    YahwehUploadModule? module,
    String? tenantId,
    void Function(double progress)? onProgress,
  }) =>
      StorageService.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        module: module,
        tenantId: tenantId,
        onProgress: onProgress,
      );

  static Future<void> warmAuthToken() => StorageService.warmAuthToken();
}
