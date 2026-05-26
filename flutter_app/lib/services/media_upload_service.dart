import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/analytics_service.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/performance_service.dart';

import 'firebase_storage_cleanup_service.dart';
import 'image_helper.dart';
import 'media_service.dart';
import 'storage_upload_queue_service.dart';
import 'upload_bytes_core.dart';

/// Uploads com [getDownloadURL] no fim do fluxo — URLs prontas para Firestore (https).
/// Política global: [church_media_publish_policy.dart] + [StorageMediaService.publishableHttpsUrlForFirestore].
class MediaUploadService {
  MediaUploadService._();

  static bool _shouldCompressJpeg(String contentType) {
    final ct = contentType.toLowerCase().trim();
    if (ct == 'image/webp') return false;
    return ct == 'image/jpeg' || ct == 'image/jpg';
  }

  static Future<Uint8List> _prepareBytesForUpload({
    required Uint8List bytes,
    required String contentType,
    bool chatJpegFast = false,
  }) async {
    // JPEGs pequenos (thumbs / ícones): evita compressão dupla — upload mais rápido.
    if (_shouldCompressJpeg(contentType)) {
      if (chatJpegFast && bytes.length < 900 * 1024) {
        return bytes;
      }
      if (!chatJpegFast && bytes.length < 520 * 1024) {
        return bytes;
      }
    }
    if (!_shouldCompressJpeg(contentType)) return bytes;
    var prepared = await MediaService.compressImageBytes(
      bytes,
      profile: chatJpegFast
          ? MediaImageProfile.chat
          : MediaImageProfile.feed,
    );
    if (prepared.length > mediaImagePreferredMaxBytesEffective) {
      prepared = await ImageHelper.compressImageUnderMaxBytes(
        prepared,
        maxBytes: mediaImagePreferredMaxBytesEffective,
      );
    }
    return prepared;
  }

  /// Resultado padrão de upload para persistir no Firestore:
  /// - [downloadUrl] URL completa `getDownloadURL()` (com token) — gravar em `foto_url` / `FOTO_URL_OU_ID` / `fotoUrl`
  /// - [storagePath] para fallback/refresh de token
  /// - [contentType] para diagnóstico e processamento
  static String _uploadTraceName({
    required String contentType,
    bool chatJpegFast = false,
    String? storagePath,
  }) {
    final ct = contentType.toLowerCase();
    if (ct.contains('video')) return 'upload_video';
    if (chatJpegFast) return 'upload_image_chat';
    final path = (storagePath ?? '').toLowerCase();
    if (path.contains('/chat/') || path.contains('chat_media')) {
      return 'upload_image_chat';
    }
    if (path.contains('event') || path.contains('noticia')) {
      return 'upload_image_evento';
    }
    if (path.contains('aviso')) return 'upload_image_aviso';
    return 'upload_image';
  }

  static MediaUploadResult _result({
    required String downloadUrl,
    required String storagePath,
    required String contentType,
  }) =>
      MediaUploadResult(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        contentType: contentType,
      );

  /// [useOfflineQueue]: se false, só tentativas imediatas (usado internamente pela fila).
  static Future<String> uploadBytesWithRetry({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,

    /// Remove estes ficheiros no Storage antes do novo upload (substituição).
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,

    /// Quando true, envia [bytes] sem segunda compressão JPEG em [_prepareBytesForUpload]
    /// (ex.: já passaram por [ImageHelper.compressMemberProfileForUpload]).
    bool skipClientPrepare = false,
    bool useOfflineQueue = true,

    /// JPEG do chat: preset mais leve (menos CPU + menos bytes → upload mais rápido).
    bool chatJpegFast = false,
  }) async {
    final trace = _uploadTraceName(
      contentType: contentType,
      chatJpegFast: chatJpegFast,
      storagePath: storagePath,
    );
    return PerformanceService.track(trace, () async {
      unawaited(AnalyticsService.logUpload(trace));
      try {
        final preparedBytes = skipClientPrepare
            ? bytes
            : await _prepareBytesForUpload(
                bytes: bytes,
                contentType: contentType,
                chatJpegFast: chatJpegFast,
              );
        if (deleteFirebaseDownloadUrlsBefore != null) {
          for (final u in deleteFirebaseDownloadUrlsBefore) {
            await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
          }
        }
        if (!useOfflineQueue) {
          return uploadStoragePutDataWithRetry(
            storagePath: storagePath,
            bytes: preparedBytes,
            contentType: contentType,
            cacheControl: cacheControl,
            maxAttempts: maxAttempts,
            onProgress: onProgress,
            onTaskStarted: onUploadTaskCreated,
          );
        }
        try {
          return await uploadStoragePutDataWithRetry(
            storagePath: storagePath,
            bytes: preparedBytes,
            contentType: contentType,
            cacheControl: cacheControl,
            maxAttempts: maxAttempts,
            onProgress: onProgress,
            onTaskStarted: onUploadTaskCreated,
          );
        } catch (e, st) {
          if (isLikelyNetworkUploadError(e)) {
            return StorageUploadQueueService.instance.enqueuePutData(
              storagePath: storagePath,
              bytes: preparedBytes,
              contentType: contentType,
              cacheControl: cacheControl,
              onProgress: onProgress,
            );
          }
          await CrashlyticsService.record(e, st, reason: trace);
          rethrow;
        }
      } catch (e, st) {
        await CrashlyticsService.record(e, st, reason: trace);
        rethrow;
      }
    });
  }

  static Future<MediaUploadResult> uploadBytesDetailed({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    bool skipClientPrepare = false,
    bool useOfflineQueue = true,
    bool chatJpegFast = false,
  }) async {
    final url = await uploadBytesWithRetry(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      cacheControl: cacheControl,
      maxAttempts: maxAttempts,
      deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
      onProgress: onProgress,
      onUploadTaskCreated: onUploadTaskCreated,
      skipClientPrepare: skipClientPrepare,
      useOfflineQueue: useOfflineQueue,
      chatJpegFast: chatJpegFast,
    );
    return _result(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: contentType,
    );
  }

  static Future<String> uploadFileWithRetry({
    required String storagePath,
    required File file,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    bool useOfflineQueue = true,
    bool skipRecompress = false,
    bool chatJpegFast = false,
  }) async {
    if (_shouldCompressJpeg(contentType) && !skipRecompress) {
      final fileBytes = await file.readAsBytes();
      final preparedBytes = await _prepareBytesForUpload(
        bytes: fileBytes,
        contentType: contentType,
        chatJpegFast: chatJpegFast,
      );
      return uploadBytesWithRetry(
        storagePath: storagePath,
        bytes: preparedBytes,
        contentType: contentType,
        cacheControl: cacheControl,
        maxAttempts: maxAttempts,
        deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
        onProgress: onProgress,
        onUploadTaskCreated: onUploadTaskCreated,
        useOfflineQueue: useOfflineQueue,
        skipClientPrepare: true,
        chatJpegFast: chatJpegFast,
      );
    }
    if (deleteFirebaseDownloadUrlsBefore != null) {
      for (final u in deleteFirebaseDownloadUrlsBefore) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
      }
    }
    if (!useOfflineQueue) {
      return uploadStoragePutFileWithRetry(
        storagePath: storagePath,
        file: file,
        contentType: contentType,
        cacheControl: cacheControl,
        maxAttempts: maxAttempts,
        onProgress: onProgress,
        onTaskStarted: onUploadTaskCreated,
      );
    }
    try {
      return await uploadStoragePutFileWithRetry(
        storagePath: storagePath,
        file: file,
        contentType: contentType,
        cacheControl: cacheControl,
        maxAttempts: maxAttempts,
        onProgress: onProgress,
        onTaskStarted: onUploadTaskCreated,
      );
    } catch (e) {
      if (isLikelyNetworkUploadError(e)) {
        final b = await file.readAsBytes();
        return StorageUploadQueueService.instance.enqueuePutData(
          storagePath: storagePath,
          bytes: b,
          contentType: contentType,
          cacheControl: cacheControl,
          onProgress: onProgress,
        );
      }
      rethrow;
    }
  }

  static Future<MediaUploadResult> uploadFileDetailed({
    required String storagePath,
    required File file,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,
    bool useOfflineQueue = true,
  }) async {
    final url = await uploadFileWithRetry(
      storagePath: storagePath,
      file: file,
      contentType: contentType,
      cacheControl: cacheControl,
      maxAttempts: maxAttempts,
      deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
      onProgress: onProgress,
      useOfflineQueue: useOfflineQueue,
    );
    return _result(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: contentType,
    );
  }

  /// Legado: gravava `_thumb` / `_card` / `_full` no mesmo bucket (três ficheiros).
  /// Política atual: **um** ficheiro canónico por recurso (como buckets só com o original).
  @Deprecated('Usar um único uploadBytesDetailed/uploadFileDetailed; não criar variantes no Storage.')
  static Future<Map<String, MediaUploadResult>> uploadImageVariants({
    required String basePathWithoutExt,
    required Uint8List imageBytes,
    String ext = 'jpg',
    String contentType = 'image/jpeg',
    String cacheControl = 'public, max-age=31536000',
  }) async {
    final cleanExt = ext.replaceAll('.', '').toLowerCase();
    final variants = <String, String>{
      'thumb': '${basePathWithoutExt}_thumb.$cleanExt',
      'card': '${basePathWithoutExt}_card.$cleanExt',
      'full': '${basePathWithoutExt}_full.$cleanExt',
    };
    final entries = variants.entries.toList();
    final results = await Future.wait(
      entries.map(
        (entry) => uploadBytesDetailed(
          storagePath: entry.value,
          bytes: imageBytes,
          contentType: contentType,
          cacheControl: cacheControl,
        ),
      ),
    );
    return Map<String, MediaUploadResult>.fromIterables(
      entries.map((e) => e.key),
      results,
    );
  }
}

class MediaUploadResult {
  final String downloadUrl;
  final String storagePath;
  final String contentType;

  const MediaUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
  });

  Map<String, dynamic> toJson() => {
        'url': downloadUrl,
        'storagePath': storagePath,
        'contentType': contentType,
      };
}
