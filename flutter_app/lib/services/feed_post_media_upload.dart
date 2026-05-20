import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;

/// Uploads rápidos de fotos em avisos/eventos (paralelo + token único).
abstract final class FeedPostMediaUpload {
  FeedPostMediaUpload._();

  /// Um refresh de token antes do lote — evita N× `getIdToken(true)` por foto.
  static Future<void> warmAuthToken() async {
    await FirebaseAuth.instance.currentUser?.getIdToken();
  }

  /// Limita WebP do feed (~1MB) sem reconverter para JPEG.
  static Future<Uint8List> prepareFeedWebpBytes(Uint8List bytes) async {
    if (!bytesLookLikeWebp(bytes)) return bytes;
    if (bytes.length <= 1100000) return bytes;
    return ImageHelper.compressWebpUnderMaxBytes(bytes);
  }

  /// Várias fotos em paralelo; [onBatchProgress] recebe 0..1 do lote.
  static Future<List<T>> uploadParallel<T>({
    required int count,
    required Future<T> Function(
      int index,
      void Function(double slotProgress) reportSlot,
    )
        uploadOne,
    String? progressLabel,
    void Function(double progress)? onBatchProgress,
  }) async {
    if (count <= 0) return [];
    final slotProgress = List<double>.filled(count, 0);
    void report() {
      final sum = slotProgress.fold<double>(0, (a, b) => a + b);
      final p = sum / count;
      onBatchProgress?.call(p);
      if (progressLabel != null && progressLabel.isNotEmpty) {
        GlobalUploadProgress.instance.update(p);
      }
    }

    final startedProgress =
        progressLabel != null && progressLabel.isNotEmpty;
    if (startedProgress) {
      GlobalUploadProgress.instance.start(progressLabel);
    }
    try {
      return Future.wait(
        List.generate(count, (i) {
          return uploadOne(i, (p) {
            slotProgress[i] = p.clamp(0.0, 1.0);
            report();
          });
        }),
      );
    } finally {
      if (startedProgress) {
        GlobalUploadProgress.instance.end();
      }
    }
  }

  /// [MediaUploadService.uploadBytesWithRetry] com preset do feed (WebP cap + 4 tentativas).
  static Future<String> uploadFeedPhotoBytes({
    required String storagePath,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final webp = bytesLookLikeWebp(bytes);
    final prepared = webp ? await prepareFeedWebpBytes(bytes) : bytes;
    return MediaUploadService.uploadBytesWithRetry(
      storagePath: storagePath,
      bytes: prepared,
      contentType: webp ? 'image/webp' : 'image/jpeg',
      skipClientPrepare: webp,
      chatJpegFast: !webp,
      maxAttempts: 4,
      onProgress: onProgress,
    );
  }

  static Future<MediaUploadResult> uploadFeedPhotoDetailed({
    required String storagePath,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final webp = bytesLookLikeWebp(bytes);
    final prepared = webp ? await prepareFeedWebpBytes(bytes) : bytes;
    return MediaUploadService.uploadBytesDetailed(
      storagePath: storagePath,
      bytes: prepared,
      contentType: webp ? 'image/webp' : 'image/jpeg',
      skipClientPrepare: webp,
      chatJpegFast: !webp,
      maxAttempts: 4,
      onProgress: onProgress,
    );
  }
}
