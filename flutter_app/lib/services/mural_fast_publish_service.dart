import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/image_aspect_ratio_util.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação estilo WhatsApp no mural (avisos/eventos): documento primeiro, fotos depois.
abstract final class MuralFastPublishService {
  MuralFastPublishService._();

  static const String stateUploading = 'uploading';
  static const String statePublished = 'published';
  static const String stateFailed = 'failed';

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
  }) async {
    try {
      await FeedPostMediaUpload.warmAuthToken();
      final uploaded = await FeedPostMediaUpload.uploadParallel<String>(
        count: newImages.length,
        progressLabel: 'A enviar imagens…',
        uploadOne: (i, report) =>
            uploadSlot(newImages[i], startSlotIndex + i, report),
      );
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
        hasVideo: false,
      );
      patch['publishState'] = statePublished;
      patch['pendingImageCount'] = FieldValue.delete();
      patch['publishError'] = FieldValue.delete();
      patch['updatedAt'] = FieldValue.serverTimestamp();
      await docRef.set(patch, SetOptions(merge: true));
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
    } catch (e) {
      try {
        await docRef.set(
          {
            'publishState': stateFailed,
            'publishError': e.toString(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }
}
