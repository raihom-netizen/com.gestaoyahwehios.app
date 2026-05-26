import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/image_aspect_ratio_util.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação estilo WhatsApp no mural (avisos/eventos): documento primeiro, fotos depois.
abstract final class MuralFastPublishService {
  MuralFastPublishService._();

  static const String stateUploading = 'uploading';
  static const String statePublished = 'published';
  static const String stateFailed = 'failed';

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
  }) async {
    try {
      await FeedPostMediaUpload.warmAuthToken().timeout(const Duration(seconds: 25));
      final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
        count: newImages.length,
        progressLabel: 'A enviar imagens…',
        uploadOne: (i, report) => uploadSlot(newImages[i], startSlotIndex + i, report)
            .timeout(const Duration(minutes: 4)),
      ).timeout(_batchTimeout);
      final allUrls = dedupeImageRefsByStorageIdentity([
        ...existingUrls,
        ...uploaded,
      ]);
      var aspectRatio = 1.0;
      if (newImages.isNotEmpty) {
        final ar = await imageAspectRatioFromBytes(newImages.first);
        if (ar != null) aspectRatio = ar.clamp(0.4, 2.3);
      }
      final patch = buildMediaFields(
        allUrls: allUrls,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
      );
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
    } on TimeoutException {
      await _markFailed(
        docRef: docRef,
        message: 'Tempo esgotado ao enviar fotos. Toque em «Tentar de novo».',
      );
    } catch (e) {
      await _markFailed(
        docRef: docRef,
        message: formatUploadErrorForUser(e),
      );
    }
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
