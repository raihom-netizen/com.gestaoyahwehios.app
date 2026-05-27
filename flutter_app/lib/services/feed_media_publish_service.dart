import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/feed_editor_media_service.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';

/// Publicação instantânea unificada — avisos (`avisos`) e eventos (`noticias`).
///
/// Fluxo: Firestore primeiro (`publishState: uploading`) → UI fecha → mídia em background
/// → `publishState: published`. Não usa `tenants/posts` (modelo canónico: `igrejas/{id}/…`).
abstract final class FeedMediaPublishService {
  FeedMediaPublishService._();

  /// `uploading` ≡ `status: processing` no spec.
  static const String statusProcessing = MuralFastPublishService.stateUploading;
  static const String statusPublished = MuralFastPublishService.statePublished;
  static const String statusFailed = MuralFastPublishService.stateFailed;
  static const String statusDraft = MuralFastPublishService.stateDraft;

  static const int kMaxPhotosPerPost = 5;
  static const int kMaxVideosPerPost = 1;

  static DocumentReference<Map<String, dynamic>> postRef({
    required String tenantId,
    required String postType,
    String? postId,
  }) {
    final col = postType == 'aviso'
        ? ChurchTenantPostsCollections.avisos
        : ChurchTenantPostsCollections.noticias;
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection(col);
    return postId == null ? ref.doc() : ref.doc(postId);
  }

  /// Grava documento com `publishState: uploading` (publicação instantânea).
  static Future<String> createPost({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    int pendingPhotoCount = 0,
  }) async {
    await ensureFirebaseInitialized();
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(payload),
    );
    patch['publishState'] = statusProcessing;
    if (pendingPhotoCount > 0) {
      patch['pendingImageCount'] = pendingPhotoCount;
    }
    patch['publishError'] = FieldValue.delete();
    if (isNewDoc) {
      await docRef.set(patch);
    } else {
      await docRef.set(patch, SetOptions(merge: true));
    }
    return docRef.id;
  }

  /// Publicação imediata (sem fotos novas).
  static Future<String> publishNow({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
  }) async {
    await ensureFirebaseInitialized();
    final patch = Map<String, dynamic>.from(payload);
    patch['publishState'] = statusPublished;
    patch['pendingImageCount'] = FieldValue.delete();
    patch['publishError'] = FieldValue.delete();
    if (isNewDoc) {
      await docRef.set(patch);
    } else {
      await docRef.set(patch, SetOptions(merge: true));
    }
    return docRef.id;
  }

  /// Rascunho — texto/campos guardados sem publicar no feed.
  static Future<String> saveDraft({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
  }) async {
    await ensureFirebaseInitialized();
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(payload),
    );
    patch['publishState'] = statusDraft;
    patch['pendingImageCount'] = FieldValue.delete();
    patch['publishError'] = FieldValue.delete();
    if (isNewDoc) {
      await docRef.set(patch);
    } else {
      await docRef.set(patch, SetOptions(merge: true));
    }
    return docRef.id;
  }

  static Future<String> Function(
    Uint8List bytes,
    int slotIndex,
    void Function(double progress) report,
  ) _uploadSlotBuilder({
    required String tenantId,
    required String postType,
    required String postId,
  }) =>
      (bytes, slotIndex, report) => MuralPostMediaPayload.uploadPhotoSlot(
            tenantId: tenantId,
            postType: postType,
            postId: postId,
            bytes: bytes,
            slotIndex: slotIndex,
            onProgress: report,
          );

  static Map<String, dynamic> Function({
    required List<String> allUrls,
    required double aspectRatio,
    required bool hasVideo,
  }) _buildMediaFieldsFn() =>
      ({
        required allUrls,
        required aspectRatio,
        required hasVideo,
      }) =>
          MuralPostMediaPayload.buildMediaFields(
            allUrls: allUrls,
            aspectRatio: aspectRatio,
            hasVideo: hasVideo,
          );

  /// Agenda upload de imagens em background (JPEG comprimido no [MuralFastPublishService]).
  static void publish({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    Future<void> Function()? onPublished,
  }) {
    final uploadSlot = _uploadSlotBuilder(
      tenantId: tenantId,
      postType: postType,
      postId: postId,
    );
    final buildMedia = _buildMediaFieldsFn();

    if (kIsWeb) {
      final images = newImagesBytes ?? const <Uint8List>[];
      if (images.isEmpty) return;
      MuralFastPublishService.scheduleBackgroundImageFinalize(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        newImages: images,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: uploadSlot,
        buildMediaFields: buildMedia,
        onPublished: onPublished,
      );
      return;
    }

    final paths = newImagePaths != null
        ? FeedEditorMediaService.existingValidPaths(newImagePaths)
        : <String>[];
    if (paths.isNotEmpty) {
      MuralFastPublishService.scheduleBackgroundImageFinalizeFromPaths(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        localPaths: paths,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: uploadSlot,
        buildMediaFields: buildMedia,
        onPublished: onPublished,
      );
      return;
    }

    final images = newImagesBytes ?? const <Uint8List>[];
    if (images.isEmpty) return;
    MuralFastPublishService.scheduleBackgroundImageFinalize(
      docRef: docRef,
      tenantId: tenantId,
      postId: postId,
      postType: postType,
      newImages: images,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      uploadSlot: uploadSlot,
      buildMediaFields: buildMedia,
      onPublished: onPublished,
    );
  }

  /// Stub Firestore + upload em background (editores aviso/evento).
  static Future<String> saveStubAndSchedulePhotos({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postType,
    required Map<String, dynamic> stubPayload,
    required bool isNewDoc,
    required int pendingPhotoCount,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    Future<void> Function()? onPublished,
  }) async {
    final postId = await createPost(
      docRef: docRef,
      payload: stubPayload,
      isNewDoc: isNewDoc,
      pendingPhotoCount: pendingPhotoCount,
    );
    publish(
      docRef: docRef,
      tenantId: tenantId,
      postId: postId,
      postType: postType,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      newImagesBytes: newImagesBytes,
      newImagePaths: newImagePaths,
      onPublished: onPublished,
    );
    return postId;
  }
}
