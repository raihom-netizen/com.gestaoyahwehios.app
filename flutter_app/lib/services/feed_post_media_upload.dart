import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;

/// Uploads rápidos de fotos em avisos/eventos (paralelo limitado + token único).
abstract final class FeedPostMediaUpload {
  FeedPostMediaUpload._();

  /// Um refresh de token antes do lote — evita N× `getIdToken(true)` por foto.
  static Future<void> warmAuthToken() async {
    await FirebaseBootstrap.ensureInitialized();
    FirebaseBootstrapService.refreshCachedApp();
    try {
      await firebaseDefaultAuth.currentUser
          ?.getIdToken(false)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Sem getIdToken(true) — quota Identity Toolkit.
    }
  }

  /// Limita WebP do feed (~900KB) sem reconverter para JPEG.
  static Future<Uint8List> prepareFeedWebpBytes(Uint8List bytes) async {
    if (!bytesLookLikeWebp(bytes)) return bytes;
    if (bytes.length <= 900000) return bytes;
    return ImageHelper.compressWebpUnderMaxBytes(bytes);
  }

  /// Várias fotos com paralelismo limitado (evita saturar rede móvel).
  static Future<List<T>> uploadParallel<T>({
    required int count,
    required Future<T> Function(
      int index,
      void Function(double slotProgress) reportSlot,
    )
        uploadOne,
    String? progressLabel,
    void Function(double progress)? onBatchProgress,
    int? maxConcurrent,
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
      GlobalUploadProgress.instance.startBatch(
        itemLabel: progressLabel!,
        totalItems: count,
      );
    }
    try {
      final workers =
          (maxConcurrent ?? mediaFeedUploadMaxConcurrent).clamp(1, count);
      final results = List<T?>.filled(count, null);
      var nextIndex = 0;

      Future<void> runWorker() async {
        while (true) {
          final i = nextIndex++;
          if (i >= count) return;
          results[i] = await uploadOne(i, (p) {
            slotProgress[i] = p.clamp(0.0, 1.0);
            if (startedProgress) {
              GlobalUploadProgress.instance.updateBatch(
                currentItem: i + 1,
                totalItems: count,
                slotProgress01: p,
              );
            }
            report();
          });
        }
      }

      await Future.wait(List.generate(workers, (_) => runWorker()));
      return results.cast<T>();
    } finally {
      if (startedProgress) {
        GlobalUploadProgress.instance.end();
      }
    }
  }

  /// WebP/JPEG preparado → `putData` directo (sem fila offline nem segunda compressão).
  static Future<String> uploadFeedPhotoBytes({
    required String storagePath,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final webp = bytesLookLikeWebp(bytes);
    final prepared = webp ? await prepareFeedWebpBytes(bytes) : bytes;
    if (prepared.isEmpty) {
      throw StateError('Falha ao preparar imagem para envio.');
    }
    if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await ensureUploadBootstrapForStoragePath(storagePath);
    }
    final url = await YahwehMediaUploadPipeline.uploadPreparedBytes(
      storagePath: storagePath,
      bytes: prepared,
      contentType: webp ? 'image/webp' : 'image/jpeg',
      maxAttempts: 3,
      onProgress: onProgress,
    );
    return url;
  }

  static Future<MediaUploadResult> uploadFeedPhotoDetailed({
    required String storagePath,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    final url = await uploadFeedPhotoBytes(
      storagePath: storagePath,
      bytes: bytes,
      onProgress: onProgress,
    );
    final webp = bytesLookLikeWebp(bytes);
    return MediaUploadResult(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: webp ? 'image/webp' : 'image/jpeg',
    );
  }
}
