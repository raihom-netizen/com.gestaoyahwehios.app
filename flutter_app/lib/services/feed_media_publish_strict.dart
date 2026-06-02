import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/feed_media_publish_fast.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';

/// Legado «fotos primeiro» — **não usar** em produção.
///
/// Canónico: [FeedMediaPublishFast.publishWithPhotosInBackground] (Firestore → upload).
@Deprecated('Use FeedMediaPublishFast / FeedMediaPublishService.publish')
abstract final class FeedMediaPublishStrict {
  FeedMediaPublishStrict._();

  /// Delega ao fluxo Firestore-first (compatibilidade de imports antigos).
  static Future<String> publishWithPhotosFirst({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postType,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    Future<void> Function()? onPublished,
  }) async {
    final pending =
        (newImagesBytes?.length ?? newImagePaths?.length ?? 0).clamp(0, 99);
    if (pending <= 0) {
      return publishPayloadNow(
        docRef: docRef,
        payload: corePayload,
        isNewDoc: isNewDoc,
      );
    }
    return FeedMediaPublishFast.publishWithPhotosInBackground(
      docRef: docRef,
      tenantId: tenantId,
      postType: postType,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      pendingPhotoCount: pending,
      newImagesBytes: newImagesBytes,
      newImagePaths: newImagePaths,
      onPublished: onPublished,
    );
  }

  /// Sem fotos novas — publica directamente (texto / URLs já no Storage).
  static Future<String> publishPayloadNow({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
  }) =>
      FeedMediaPublishService.publishNow(
        docRef: docRef,
        payload: payload,
        isNewDoc: isNewDoc,
      );
}
