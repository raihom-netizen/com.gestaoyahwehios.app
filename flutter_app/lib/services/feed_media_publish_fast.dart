import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';

/// Publicação rápida (padrão Controle Total): grava Firestore → fecha UI → fotos em background.
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
  }) async {
    await ensureFirebaseReadyForPublishUpload();

    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(corePayload),
    );
    patch['publishState'] = FeedMediaPublishService.statusProcessing;
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: isNewDoc,
      pendingPhotoCount: pendingPhotoCount,
      clearPublishError: true,
    );
    patch['updatedAt'] = FieldValue.serverTimestamp();
    if (isNewDoc) {
      await docRef.set(patch);
    } else {
      await docRef.set(patch, SetOptions(merge: true));
    }

    final postId = docRef.id;
    if (pendingPhotoCount <= 0) {
      return postId;
    }

    Future<void> publishedHook() async {
      try {
        await onPublished?.call();
      } catch (_) {}
    }

    if (kIsWeb) {
      final images = newImagesBytes ?? const <Uint8List>[];
      if (images.isEmpty) {
        throw StateError('Não foi possível ler as fotos para enviar.');
      }
      MuralFastPublishService.scheduleBackgroundImageFinalize(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        newImages: images,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: MuralPostMediaPayload.buildMediaFields,
        onPublished: publishedHook,
      );
    } else {
      final paths = newImagePaths
              ?.map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      if (paths.isEmpty) {
        throw StateError('Não foi possível ler as fotos para enviar.');
      }
      MuralFastPublishService.scheduleBackgroundImageFinalizeFromPaths(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        localPaths: paths,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: MuralPostMediaPayload.buildMediaFields,
        onPublished: publishedHook,
      );
    }
    return postId;
  }
}
