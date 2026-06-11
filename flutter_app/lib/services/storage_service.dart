import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/web_safe_media.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/church_storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:video_compress/video_compress.dart';

/// Serviço central de upload e compressão (Clean Architecture).
///
/// Telas de Avisos, Eventos, Chat, Património, Financeiro e Membros
/// devem usar esta classe — **não** `FirebaseStorage` directamente.
abstract final class StorageService {
  StorageService._();

  static const int kMaxImageEdge = kStandardUploadImageMaxEdge;
  static const int kImageQuality = kStandardUploadImageQuality;

  /// Comprime imagem agressivamente: 1024×1024 @ 80 %.
  static Future<Uint8List> compressImageBytes(
    Uint8List input, {
    MediaImageProfile profile = MediaImageProfile.feed,
  }) =>
      MediaService.compressImageBytes(input, profile: profile);

  static Future<File?> compressImageFile(
    File file, {
    MediaImageProfile profile = MediaImageProfile.feed,
  }) {
    if (kIsWeb) {
      throw UnsupportedError(
        'compressImageFile(File) não suportado na Web — use compressImageBytes + XFile.',
      );
    }
    return MediaService.compressImage(file, profile: profile);
  }

  /// Picker multi-plataforma → bytes → compressão → upload (`putData` na Web).
  static Future<String> uploadFromXFile({
    required XFile file,
    required String storagePath,
    YahwehUploadModule module = YahwehUploadModule.generic,
    MediaImageProfile profile = MediaImageProfile.feed,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    final raw = await WebSafeMedia.readBytes(file);
    final compressed = await compressImageBytes(raw, profile: profile);
    return uploadBytes(
      storagePath: storagePath,
      bytes: compressed,
      contentType: contentType,
      module: module,
      onProgress: onProgress,
    );
  }

  /// Vídeo eventos/chat — transcode nativo ~720p antes do upload.
  static Future<MediaInfo?> compressVideo(File file) =>
      MediaService.compressVideo(file);

  static Future<MediaVideoPrepareResult?> prepareVideoForUpload(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
    bool generateThumbnail = true,
  }) =>
      MediaService.prepareVideoForUpload(
        inputPath,
        onCompressProgress: onCompressProgress,
        generateThumbnail: generateThumbnail,
      );

  /// Upload paralelo em lote ([Future.wait] com concorrência limitada).
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

  /// Upload único com compressão, progresso e timeout.
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

  /// JPEG/WebP comprimido → Storage (financeiro, comprovantes, perfil).
  static Future<String> uploadCompressedImage({
    required String storagePath,
    required Uint8List rawBytes,
    YahwehUploadModule module = YahwehUploadModule.generic,
    MediaImageProfile profile = MediaImageProfile.feed,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    final compressed = await compressImageBytes(rawBytes, profile: profile);
    return uploadBytes(
      storagePath: storagePath,
      bytes: compressed,
      contentType: contentType,
      module: module,
      onProgress: onProgress,
    );
  }

  static Future<void> warmAuthToken() => FeedPostMediaUpload.warmAuthToken();

  /// Upload canónico — grava só [storagePath] em `igrejas/{churchId}/…`.
  static Future<String> uploadToChurchPath({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) =>
      ChurchStorageService.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        onProgress: onProgress,
      );
}
