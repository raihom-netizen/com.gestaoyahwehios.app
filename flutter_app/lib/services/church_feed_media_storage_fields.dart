import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/church_instant_upload_pipeline.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Campos Firestore só com paths do Storage (sem URLs fixas).
abstract final class ChurchFeedMediaStorageFields {
  ChurchFeedMediaStorageFields._();

  static const Duration _photoSlotTimeout = Duration(minutes: 4);
  static const Duration _batchTimeout = Duration(minutes: 12);

  /// Upload paralelo — Storage primeiro; retorna paths + thumbs por slot.
  static Future<List<FeedPhotoSlotResult>> uploadPhotoSlots({
    required String tenantId,
    required String postType,
    required String postId,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    void Function(double batchProgress01)? onBatchProgress,
  }) async {
    if (kIsWeb) {
      final images = newImagesBytes ?? const <Uint8List>[];
      if (images.isEmpty) return const [];
      if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
        await FastMediaPublishBootstrap.warmForFeedPublish()
            .timeout(const Duration(seconds: 12));
      }
      final maxConc = mediaFeedUploadMaxConcurrent.clamp(1, images.length);
      return FeedPostMediaUpload.uploadParallel<FeedPhotoSlotResult>(
        count: images.length,
        maxConcurrent: maxConc,
        progressLabel: 'A enviar imagens…',
        onBatchProgress: onBatchProgress,
        uploadOne: (i, report) => ChurchInstantUploadPipeline.uploadFeedPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          slotIndex: startSlotIndex + i,
          bytes: images[i],
          onProgress: report,
        ).timeout(_photoSlotTimeout),
      ).timeout(_batchTimeout);
    }

    final paths = newImagePaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) return const [];
    if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await FastMediaPublishBootstrap.warmForFeedPublish()
          .timeout(const Duration(seconds: 18));
    }
    final maxConc = mediaFeedUploadMaxConcurrent.clamp(1, paths.length);
    return FeedPostMediaUpload.uploadParallel<FeedPhotoSlotResult>(
      count: paths.length,
      maxConcurrent: maxConc,
      progressLabel: 'A enviar imagens…',
      onBatchProgress: onBatchProgress,
      uploadOne: (i, report) async {
        final localPath = paths[i];
        final f = File(localPath);
        if (!await f.exists()) {
          throw StateError('Foto ${i + 1} não encontrada no aparelho.');
        }
        Uint8List? bytes;
        if (!IosPublishImagePipeline.useIosLightweightPublish) {
          bytes = await IosPublishImagePipeline.compressForPublishFromPath(
            localPath,
          );
        }
        return ChurchInstantUploadPipeline.uploadFeedPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          slotIndex: startSlotIndex + i,
          bytes: bytes,
          localPath: localPath,
          onProgress: report,
        ).timeout(_photoSlotTimeout);
      },
    ).timeout(_batchTimeout);
  }

  /// Patch Firestore — apenas paths; remove URLs legadas em edição.
  static Map<String, dynamic> buildStoragePathOnlyFields({
    required List<String> photoPaths,
    required double aspectRatio,
    required bool hasVideo,
    String? videoPath,
    List<String> thumbPaths = const [],
    Map<String, dynamic>? capaImageVariants,
    bool allowDeleteSentinels = true,
    bool isEvento = false,
  }) {
    final patch = <String, dynamic>{};
    final paths = photoPaths.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final thumbs =
        thumbPaths.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    if (paths.isEmpty) {
      if (allowDeleteSentinels) {
        for (final k in _urlFieldKeys) {
          patch[k] = FieldValue.delete();
        }
        patch['imageStoragePath'] = FieldValue.delete();
        patch['imageStoragePaths'] = FieldValue.delete();
        patch['fotoPath'] = FieldValue.delete();
        patch['fotoStoragePaths'] = FieldValue.delete();
        patch['fotos'] = FieldValue.delete();
        patch['thumbStoragePath'] = FieldValue.delete();
        patch['thumbStoragePaths'] = FieldValue.delete();
        patch['imageVariants'] = FieldValue.delete();
        patch['media_info'] = FieldValue.delete();
      }
    } else {
      patch['imageStoragePath'] = paths.first;
      patch['imageStoragePaths'] = paths;
      patch['fotoPath'] = paths.first;
      patch['fotoStoragePaths'] = paths;
      if (thumbs.isNotEmpty) {
        patch['thumbStoragePath'] = thumbs.first;
        patch['thumbStoragePaths'] = thumbs;
      }
      if (capaImageVariants != null && capaImageVariants.isNotEmpty) {
        patch['imageVariants'] = capaImageVariants;
      }
      patch['media_info'] = <String, dynamic>{
        'aspect_ratio': aspectRatio.clamp(0.45, 1.9),
        'tipo': hasVideo ? 'video' : 'image',
      };
      // URLs https gravadas pelo pipeline linear — não apagar campos de URL.
    }

    final vp = videoPath?.trim() ?? '';
    if (vp.isNotEmpty) {
      patch['videoPath'] = vp;
      if (allowDeleteSentinels) {
        patch['videoUrl'] = FieldValue.delete();
      }
    } else if (allowDeleteSentinels && !hasVideo) {
      patch['videoPath'] = FieldValue.delete();
      patch['videoUrl'] = FieldValue.delete();
    }
    return patch;
  }

  static const List<String> _urlFieldKeys = [
    'imageUrl',
    'imageUrls',
    'defaultImageUrl',
    'imagemUrl',
    'imagem_url',
  ];
}
