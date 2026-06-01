import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/feed_media_publish_strict.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';

/// Publicação unificada — avisos (`avisos`) e eventos (`noticias`).
///
/// **Canónico:** upload Storage → `getDownloadURL` → Firestore `published`
/// ([FeedMediaPublishStrict.publishWithPhotosFirst]).
/// O caminho «stub uploading + background» só para reenvio via [MuralPublishOutboxService].
abstract final class FeedMediaPublishService {
  FeedMediaPublishService._();

  /// `uploading` ≡ `status: processing` no spec.
  static const String statusProcessing = MuralFastPublishService.stateUploading;
  static const String statusPublished = MuralFastPublishService.statePublished;
  static const String statusFailed = MuralFastPublishService.stateFailed;
  static const String statusDraft = MuralFastPublishService.stateDraft;

  static const int kMaxPhotosPerPost = 5;
  static const int kMaxVideosPerPost = 1;

  static Future<DocumentReference<Map<String, dynamic>>> postRef({
    required String tenantId,
    required String postType,
    String? postId,
  }) async {
    final db = await FirebaseService.firestore(requireAuth: true);
    final col = postType == 'aviso'
        ? ChurchTenantPostsCollections.avisos
        : ChurchTenantPostsCollections.noticias;
    final ref = db
        .collection('igrejas')
        .doc(tenantId)
        .collection(col);
    return postId == null ? ref.doc() : ref.doc(postId);
  }

  /// **Legado / rascunho** — não usar para publicar fotos novas no mural.
  /// Fotos novas: [publish] ou [saveStubAndSchedulePhotos] (delegam a [FeedMediaPublishStrict]).
  @Deprecated('Use publish() ou saveStubAndSchedulePhotos — evita uploading antes do Storage')
  static Future<String> createPost({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    int pendingPhotoCount = 0,
  }) async {
    await ensureFirebaseReadyForPublishUpload();
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(payload),
    );
    patch['publishState'] = statusProcessing;
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: isNewDoc,
      pendingPhotoCount: pendingPhotoCount > 0 ? pendingPhotoCount : null,
      clearPublishError: true,
    );
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
    await ensureFirebaseReadyForPublishUpload();
    final patch = Map<String, dynamic>.from(payload);
    patch['publishState'] = statusPublished;
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: isNewDoc,
      clearPendingImageCount: true,
      clearPublishError: true,
    );
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await runFirestorePublishWithRecovery<void>(() async {
      if (isNewDoc) {
        await docRef.set(patch);
      } else {
        await docRef.set(patch, SetOptions(merge: true));
      }
    });
    return docRef.id;
  }

  /// Rascunho — texto/campos guardados sem publicar no feed.
  static Future<String> saveDraft({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
  }) async {
    await ensureFirebaseReadyForPublishUpload();
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(payload),
    );
    patch['publishState'] = statusDraft;
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: isNewDoc,
      clearPendingImageCount: true,
      clearPublishError: true,
    );
    if (isNewDoc) {
      await docRef.set(patch);
    } else {
      await docRef.set(patch, SetOptions(merge: true));
    }
    return docRef.id;
  }

  /// Storage + URL antes de Firestore (sem stub `uploading` no feed/site).
  static Future<String> publish({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String postId,
    required String postType,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    Future<void> Function()? onPublished,
  }) =>
      FeedMediaPublishStrict.publishWithPhotosFirst(
        docRef: docRef,
        tenantId: tenantId,
        postType: postType,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        onPublished: onPublished,
      );

  /// Marca post como falhou (mural) após erro de upload.
  static Future<void> markPublishFailed({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Object error,
  }) async {
    try {
      await FirebaseBootstrap.ensureInitialized();
    } catch (_) {
      return;
    }
    await docRef.set(
      {
        'publishState': statusFailed,
        'publishError': error.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Reenvio manual — delega ao serviço de pending uploads do tenant.
  static Future<void> resumePendingUploadsForTenant(String tenantId) async {
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) return;
    await PendingUploadsFirestoreService.resumeAllForTenant(tenantId);
  }

  /// Fotos novas: upload Storage → URLs → Firestore `published` (padrão Controle Total).
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
    if (pendingPhotoCount <= 0) {
      return publishNow(
        docRef: docRef,
        payload: stubPayload,
        isNewDoc: isNewDoc,
      );
    }
    return publish(
      docRef: docRef,
      tenantId: tenantId,
      postId: docRef.id,
      postType: postType,
      corePayload: stubPayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      newImagesBytes: newImagesBytes,
      newImagePaths: newImagePaths,
      onPublished: onPublished,
    );
  }
}
