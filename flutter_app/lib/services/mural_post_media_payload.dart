import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        firebaseStorageObjectPathFromHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;

/// Campos de mídia partilhados entre editor do mural e reenvio em background.
abstract final class MuralPostMediaPayload {
  MuralPostMediaPayload._();

  static const Duration _photoSlotTimeout = Duration(minutes: 4);
  static const Duration _batchTimeout = Duration(minutes: 12);

  /// Upload de um slot (usado em background após stub no Firestore).
  static Future<List<String>> uploadNewPhotosBeforePublish({
    required String tenantId,
    required String postType,
    required String postId,
    required List<Uint8List> newImages,
    required int startSlotIndex,
  }) async {
    if (newImages.isEmpty) return const [];
    if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await FastMediaPublishBootstrap.warmForFeedPublish()
          .timeout(const Duration(seconds: 20));
    }
    final maxConc = mediaFeedUploadMaxConcurrent.clamp(1, newImages.length);
    final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
      count: newImages.length,
      maxConcurrent: maxConc,
      progressLabel: 'A enviar imagens…',
      uploadOne: (i, report) => uploadPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        bytes: newImages[i],
        slotIndex: startSlotIndex + i,
        onProgress: report,
      ).timeout(_photoSlotTimeout),
    ).timeout(_batchTimeout);
    return dedupeImageRefsByStorageIdentity(uploaded);
  }

  /// Mobile: lê **uma** foto de cada vez do disco (evita OOM com 15+ fotos no iOS).
  static Future<List<String>> uploadNewPhotosBeforePublishFromPaths({
    required String tenantId,
    required String postType,
    required String postId,
    required List<String> localPaths,
    required int startSlotIndex,
  }) async {
    if (kIsWeb) {
      throw StateError('uploadNewPhotosBeforePublishFromPaths só no mobile.');
    }
    final paths = localPaths
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return const [];
    await FastMediaPublishBootstrap.warmForFeedPublish()
        .timeout(const Duration(seconds: 28));
    final maxConc = mediaFeedUploadMaxConcurrent.clamp(1, paths.length);
    final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
      count: paths.length,
      maxConcurrent: maxConc,
      progressLabel: 'A enviar imagens…',
      uploadOne: (i, report) async {
        final path = paths[i];
        final f = File(path);
        if (!await f.exists()) {
          throw StateError('Foto ${i + 1} não encontrada no aparelho.');
        }
        if (IosPublishImagePipeline.useIosLightweightPublish) {
          final r = await IosPublishImagePipeline.uploadFeedPhotoSlot(
            tenantId: tenantId,
            postType: postType,
            postId: postId,
            slotIndex: startSlotIndex + i,
            localPath: path,
            onProgress: report,
          );
          return r.primaryUrl;
        }
        final bytes =
            await IosPublishImagePipeline.compressForPublishFromPath(path);
        return uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          localPath: path,
          slotIndex: startSlotIndex + i,
          onProgress: report,
        ).timeout(_photoSlotTimeout);
      },
    ).timeout(_batchTimeout);
    return dedupeImageRefsByStorageIdentity(uploaded);
  }

  static Future<String> uploadPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required Uint8List bytes,
    required int slotIndex,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    final r = await uploadPhotoSlotWithVariants(
      tenantId: tenantId,
      postType: postType,
      postId: postId,
      bytes: bytes,
      slotIndex: slotIndex,
      localPath: localPath,
      onProgress: onProgress,
    );
    return r.primaryUrl;
  }

  /// WebP thumb/medium/full — feed e site público carregam [medium_800] primeiro.
  static Future<
      ({
        String primaryUrl,
        Map<String, dynamic> imageVariants,
      })> uploadPhotoSlotWithVariants({
    required String tenantId,
    required String postType,
    required String postId,
    required Uint8List bytes,
    required int slotIndex,
    void Function(double progress)? onProgress,
    String? localPath,
  }) async {
    // v1555: 1 WebP por foto (web + mobile) — CF `optimizeImage` gera variantes.
    try {
      return await IosPublishImagePipeline.uploadFeedPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        slotIndex: slotIndex,
        bytes: bytes,
        localPath: localPath,
        onProgress: onProgress,
      );
    } catch (e, st) {
      await YahwehTelemetry.recordUploadFailure(
        e,
        st,
        context: 'uploadPhotoSlotWithVariants_fast',
      );
      rethrow;
    }
  }

  static Map<String, dynamic> buildMediaFields({
    required List<String> allUrls,
    required double aspectRatio,
    required bool hasVideo,
    bool allowDeleteSentinels = true,
    Map<String, dynamic>? imageVariants,
  }) {
    final firstUrl = allUrls.isNotEmpty ? allUrls[0] : '';
    final patch = <String, dynamic>{};
    patch['imageUrl'] = firstUrl;
    patch['imageUrls'] = allUrls;
    patch['defaultImageUrl'] = firstUrl;
    if (firstUrl.isNotEmpty) {
      patch['imagemUrl'] = firstUrl;
      patch['imagem_url'] = firstUrl;
    } else if (allowDeleteSentinels) {
      patch['imagemUrl'] = FieldValue.delete();
      patch['imagem_url'] = FieldValue.delete();
    }
    if (imageVariants != null && imageVariants.isNotEmpty) {
      patch['imageVariants'] = imageVariants;
    }
    if (allUrls.isNotEmpty) {
      patch['media_info'] = <String, dynamic>{
        'url_original': firstUrl,
        'aspect_ratio': aspectRatio,
        'tipo': hasVideo ? 'video' : 'image',
      };
    } else if (allowDeleteSentinels) {
      patch['media_info'] = FieldValue.delete();
    }
    if (allUrls.isEmpty) {
      if (allowDeleteSentinels) {
        patch['imageStoragePath'] = FieldValue.delete();
        patch['imageStoragePaths'] = FieldValue.delete();
      }
    } else {
      final paths = _pathsFromImageUrls(allUrls);
      if (paths != null && paths.isNotEmpty) {
        patch['imageStoragePath'] = paths.first;
        patch['imageStoragePaths'] = paths;
      }
    }
    return patch;
  }

  static List<String>? _pathsFromImageUrls(List<String> urls) {
    final paths = <String>[];
    for (final u in urls) {
      final s = sanitizeImageUrl(u.trim());
      if (!isValidImageUrl(s)) return null;
      final p = firebaseStorageObjectPathFromHttpUrl(s);
      if (p == null || p.isEmpty) return null;
      paths.add(normalizeFirebaseStorageObjectPath(p));
    }
    return paths;
  }
}
