import 'dart:async' show TimeoutException, unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/image_aspect_ratio_util.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/core/network_media_quality_policy.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação instantânea: Firestore com `publishState: uploading`, fotos em background.
abstract final class MuralFastPublishService {
  MuralFastPublishService._();

  static const String stateUploading = 'uploading';
  static const String statePublished = 'published';
  static const String stateFailed = 'failed';
  static const String stateDraft = 'draft';

  static const Duration _batchTimeout = Duration(minutes: 12);

  /// Após stub no Firestore: cache local + outbox + upload (não bloquear fecho do editor).
  static void scheduleBackgroundImageFinalize({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<Uint8List> newImages,
    required List<String> existingUrls,
    required int startSlotIndex,
    required Future<String> Function(
      Uint8List bytes,
      int slotIndex,
      void Function(double progress) report,
    )
        uploadSlot,
    required Map<String, dynamic> Function({
      required List<String> allUrls,
      required double aspectRatio,
      required bool hasVideo,
    })
        buildMediaFields,
    bool hasVideo = false,
    Future<void> Function()? onPublished,
  }) {
    unawaited(Future<void>(() async {
      try {
        await MuralPostPendingMediaCache.put(
          tenantId: tenantId,
          postId: postId,
          images: newImages,
        );
        await MuralPublishOutboxService.registerJob(
          tenantId: tenantId,
          postId: postId,
          postType: postType,
          existingUrls: existingUrls,
          startSlotIndex: startSlotIndex,
          hasVideo: hasVideo,
        );
      } catch (_) {}
      await uploadImagesAndFinalizePost(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        newImages: newImages,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: uploadSlot,
        buildMediaFields: buildMediaFields,
        onPublished: onPublished,
      );
    }));
  }

  /// Mobile: comprime JPEG a partir do disco e envia em background (sem bloquear o editor).
  static void scheduleBackgroundImageFinalizeFromPaths({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> localPaths,
    required List<String> existingUrls,
    required int startSlotIndex,
    required Future<String> Function(
      Uint8List bytes,
      int slotIndex,
      void Function(double progress) report,
    )
        uploadSlot,
    required Map<String, dynamic> Function({
      required List<String> allUrls,
      required double aspectRatio,
      required bool hasVideo,
    })
        buildMediaFields,
    bool hasVideo = false,
    Future<void> Function()? onPublished,
  }) {
    unawaited(Future<void>(() async {
      try {
        final preview = <Uint8List>[];
        for (final p in localPaths) {
          final f = File(p);
          if (!await f.exists()) continue;
          if (IosPublishImagePipeline.useIosLightweightPublish) {
            preview.add(
              await IosPublishImagePipeline.compressForPublishFromPath(p),
            );
          } else {
            preview.add(await f.readAsBytes());
          }
        }
        if (preview.isNotEmpty) {
          await MuralPostPendingMediaCache.put(
            tenantId: tenantId,
            postId: postId,
            images: preview,
          );
        }
        await MuralPublishOutboxService.registerJob(
          tenantId: tenantId,
          postId: postId,
          postType: postType,
          existingUrls: existingUrls,
          startSlotIndex: startSlotIndex,
          hasVideo: hasVideo,
        );
      } catch (_) {}
      await uploadImagesAndFinalizePostFromPaths(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        localPaths: localPaths,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: uploadSlot,
        buildMediaFields: buildMediaFields,
        onPublished: onPublished,
      );
    }));
  }

  /// Sobe fotos em paralelo e faz merge no post; push FCM só após `published` (Function).
  static Future<void> uploadImagesAndFinalizePost({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<Uint8List> newImages,
    required List<String> existingUrls,
    required int startSlotIndex,
    required Future<String> Function(
      Uint8List bytes,
      int slotIndex,
      void Function(double progress) report,
    )
        uploadSlot,
    required Map<String, dynamic> Function({
      required List<String> allUrls,
      required double aspectRatio,
      required bool hasVideo,
    })
        buildMediaFields,
    bool hasVideo = false,
    Future<void> Function()? onPublished,
  }) async {
    await ensureFirebaseInitialized();
    try {
      await FeedPostMediaUpload.warmAuthToken().timeout(const Duration(seconds: 25));
      Map<String, dynamic>? firstVariants;
      final maxConc = IosPublishImagePipeline.useIosLightweightPublish
          ? 1
          : await NetworkMediaQualityPolicy.maxConcurrentUploads();
      final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
        count: newImages.length,
        maxConcurrent: maxConc,
        progressLabel: 'A enviar imagens…',
        uploadOne: (i, report) async {
          final r = await MuralPostMediaPayload.uploadPhotoSlotWithVariants(
            tenantId: tenantId,
            postType: postType,
            postId: postId,
            bytes: newImages[i],
            slotIndex: startSlotIndex + i,
            onProgress: report,
          ).timeout(const Duration(minutes: 4));
          if (i == 0) firstVariants = r.imageVariants;
          await _appendImageUrl(docRef, r.primaryUrl);
          return r.primaryUrl;
        },
      ).timeout(_batchTimeout);
      await _finalizeUploaded(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        existingUrls: existingUrls,
        uploaded: uploaded,
        aspectRatioFromBytes: newImages.isNotEmpty ? newImages.first : null,
        buildMediaFields: buildMediaFields,
        hasVideo: hasVideo,
        imageVariants: firstVariants,
        onPublished: onPublished,
      );
      await IosPublishMemory.releaseAfterHeavyWork();
    } on TimeoutException {
      await _markFailed(
        docRef: docRef,
        message: 'Tempo esgotado ao enviar fotos. Toque em «Tentar de novo».',
      );
    } catch (e, st) {
      await CrashlyticsService.record(
        e,
        st,
        reason: 'mural_upload_finalize_bytes',
      );
      await _markFailed(
        docRef: docRef,
        message: formatUploadErrorForUser(e),
      );
    }
  }

  /// Mobile: lê e comprime uma foto de cada vez (evita OOM).
  static Future<void> uploadImagesAndFinalizePostFromPaths({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> localPaths,
    required List<String> existingUrls,
    required int startSlotIndex,
    required Future<String> Function(
      Uint8List bytes,
      int slotIndex,
      void Function(double progress) report,
    )
        uploadSlot,
    required Map<String, dynamic> Function({
      required List<String> allUrls,
      required double aspectRatio,
      required bool hasVideo,
    })
        buildMediaFields,
    bool hasVideo = false,
    Future<void> Function()? onPublished,
  }) async {
    await ensureFirebaseInitialized();
    if (kIsWeb) {
      throw StateError('uploadImagesAndFinalizePostFromPaths só no mobile.');
    }
    final paths = localPaths
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) {
      await _markFailed(
        docRef: docRef,
        message: 'Nenhuma foto encontrada no aparelho.',
      );
      return;
    }
    try {
      await FeedPostMediaUpload.warmAuthToken()
          .timeout(const Duration(seconds: 25));
      Map<String, dynamic>? firstVariants;
      final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
        count: paths.length,
        maxConcurrent: IosPublishImagePipeline.useIosLightweightPublish ? 1 : null,
        progressLabel: 'A enviar imagens…',
        uploadOne: (i, report) async {
          final r = await MuralPostMediaPayload.uploadPhotoSlotWithVariants(
            tenantId: tenantId,
            postType: postType,
            postId: postId,
            bytes: Uint8List(0),
            localPath: paths[i],
            slotIndex: startSlotIndex + i,
            onProgress: report,
          ).timeout(const Duration(minutes: 4));
          if (i == 0) firstVariants = r.imageVariants;
          await _appendImageUrl(docRef, r.primaryUrl);
          return r.primaryUrl;
        },
      ).timeout(_batchTimeout);
      await _finalizeUploaded(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        existingUrls: existingUrls,
        uploaded: uploaded,
        aspectRatioFromBytes: null,
        buildMediaFields: buildMediaFields,
        hasVideo: hasVideo,
        imageVariants: firstVariants,
        onPublished: onPublished,
      );
      await IosPublishMemory.releaseAfterHeavyWork();
    } on TimeoutException {
      await _markFailed(
        docRef: docRef,
        message: 'Tempo esgotado ao enviar fotos. Toque em «Tentar de novo».',
      );
    } catch (e, st) {
      await CrashlyticsService.record(
        e,
        st,
        reason: 'mural_upload_finalize_paths',
      );
      await _markFailed(
        docRef: docRef,
        message: formatUploadErrorForUser(e),
      );
    }
  }

  static Future<void> _finalizeUploaded({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> existingUrls,
    required List<String> uploaded,
    required Uint8List? aspectRatioFromBytes,
    required Map<String, dynamic> Function({
      required List<String> allUrls,
      required double aspectRatio,
      required bool hasVideo,
    })
        buildMediaFields,
    required bool hasVideo,
    Map<String, dynamic>? imageVariants,
    Future<void> Function()? onPublished,
  }) async {
    final allUrls = dedupeImageRefsByStorageIdentity([
      ...existingUrls,
      ...uploaded,
    ]);
    var aspectRatio = 1.0;
    if (aspectRatioFromBytes != null && aspectRatioFromBytes.isNotEmpty) {
      final ar = await imageAspectRatioFromBytes(aspectRatioFromBytes);
      if (ar != null) aspectRatio = ar.clamp(0.4, 2.3);
    }
    final patch = buildMediaFields(
      allUrls: allUrls,
      aspectRatio: aspectRatio,
      hasVideo: hasVideo,
    );
    if (imageVariants != null && imageVariants.isNotEmpty) {
      patch['imageVariants'] = imageVariants;
    }
    patch['publishState'] = statePublished;
    patch['pendingImageCount'] = FieldValue.delete();
    patch['publishError'] = FieldValue.delete();
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await docRef.set(patch, SetOptions(merge: true));
    await MuralPostPendingMediaCache.remove(
      tenantId: tenantId,
      postId: postId,
    );
    await MuralPublishOutboxService.clearJob(
      tenantId: tenantId,
      postId: postId,
    );
    if (postType == 'aviso') {
      FirebaseStorageCleanupService.scheduleCleanupAfterAvisoPostImageUpload(
        tenantId: tenantId,
        postDocId: postId,
      );
    } else if (postType == 'evento') {
      FirebaseStorageCleanupService.scheduleCleanupAfterEventPostImageUpload(
        tenantId: tenantId,
        postDocId: postId,
      );
    }
    if (onPublished != null) {
      try {
        await onPublished();
      } catch (_) {}
    }
  }

  static Future<void> _appendImageUrl(
    DocumentReference<Map<String, dynamic>> docRef,
    String url,
  ) async {
    if (url.trim().isEmpty) return;
    try {
      await docRef.update({
        'imageUrls': FieldValue.arrayUnion([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<void> _markFailed({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String message,
  }) async {
    final userMsg = message.trim().isEmpty
        ? 'Não foi possível enviar as fotos. Toque em «Tentar de novo».'
        : message;
    try {
      await docRef.set(
        {
          'publishState': stateFailed,
          'publishError':
              userMsg.length > 400 ? userMsg.substring(0, 400) : userMsg,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
