import 'dart:typed_data';



import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/services/publication_engine.dart';



/// Ponte legada → [PublicationEngine] (não duplicar lógica).

abstract final class FeedMediaPublishFast {

  FeedMediaPublishFast._();



  static Future<String> publishWithPhotosInBackground({

    required DocumentReference<Map<String, dynamic>> docRef,

    required String tenantId,

    required String postType,

    required Map<String, dynamic> corePayload,

    required bool isNewDoc,

    required List<String> existingUrls,

    required int startSlotIndex,

    required bool hasVideo,

    required int pendingPhotoCount,

    List<Uint8List>? newImagesBytes,

    List<String>? newImagePaths,

    Future<void> Function()? onPublished,

    bool publicSite = true,

  }) async {

    final postId = await PublicationEngine.publishWithPhotosInBackground(

      docRef: docRef,

      tenantId: tenantId,

      kind: PublicationEngine.kindFromPostType(postType),

      corePayload: corePayload,

      isNewDoc: isNewDoc,

      existingUrls: existingUrls,

      startSlotIndex: startSlotIndex,

      hasVideo: hasVideo,

      pendingPhotoCount: pendingPhotoCount,

      publicSite: publicSite,

      newImagesBytes: newImagesBytes,

      newImagePaths: newImagePaths,

    );

    if (onPublished != null) {

      try {

        await onPublished();

      } catch (_) {}

    }

    return postId;

  }

}

