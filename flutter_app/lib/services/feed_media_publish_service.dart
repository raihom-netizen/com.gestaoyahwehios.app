import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/services/feed_media_publish_fast.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Fachada legada — **toda** publicação mural/feed delega a [PublicationEngine].
///
/// Aviso, evento, notícia, mural e feed público: um único fluxo
/// (Firestore → distribuição em background).
@Deprecated('Preferir PublicationEngine diretamente')
abstract final class FeedMediaPublishService {
  FeedMediaPublishService._();

  static const String statusProcessing = PublicationEngine.statusProcessing;
  static const String statusPublished = PublicationEngine.statusPublished;
  static const String statusFailed = PublicationEngine.statusFailed;
  static const String statusDraft = PublicationEngine.statusDraft;

  static const int kMaxPhotosPerPost = PublicationEngine.kMaxPhotosPerPost;
  static const int kMaxPhotosPerEvento = PublicationEngine.kMaxPhotosPerEvento;
  static const int kMaxVideosPerPost = PublicationEngine.kMaxVideosPerPost;

  static Future<DocumentReference<Map<String, dynamic>>> postRef({
    required String tenantId,
    required String postType,
    String? postId,
  }) async {
    final db = await FirebaseService.firestore(requireAuth: true);
    final col = postType == 'aviso'
        ? ChurchTenantPostsCollections.avisos
        : ChurchTenantPostsCollections.eventos;
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final ref =         ChurchOperationalPaths.churchDoc(op)
        .collection(col);
    return postId == null ? ref.doc() : ref.doc(postId);
  }

  @Deprecated('Use PublicationEngine.publishNow')
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

  static Future<String> publishNow({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    String postType = 'aviso',
    bool publicSite = true,
  }) async {
    if (postType == 'aviso' || postType == 'evento') {
      throw StateError(
        'publishNow legado desativado para $postType. '
        'Use pipeline linear (upload → Storage → Firestore).',
      );
    }
    await FeedPublishPreflight.prepareForFirestoreSave();
    return PublicationEngine.publishNow(
      docRef: docRef,
      tenantId: _tenantFromRef(docRef),
      kind: PublicationEngine.kindFromPostType(postType),
      payload: payload,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
    );
  }

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
    bool publicSite = true,
  }) {
    if (postType == 'aviso' || postType == 'evento') {
      throw StateError(
        'Publicação legada desativada para $postType. '
        'Use AvisoStrictPublishService ou EventoStrictPublishService.',
      );
    }
    final pending =
        (newImagesBytes?.length ?? newImagePaths?.length ?? 0).clamp(0, 99);
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
      publicSite: publicSite,
    );
  }

  static Future<void> markPublishFailed({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Object error,
  }) async {
    try {
      await FirebaseBootstrap.ensureInitialized();
    } catch (e, st) {
      ChurchPublishFlowLog.logCatch(e, st, label: 'markPublishFailed_bootstrap');
      return;
    }
    await docRef.set(
      {
        'publishState': statusFailed,
        'publicado': false,
        'status': 'erro',
        'publishError': error.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> resumePendingUploadsForTenant(String tenantId) async {
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) return;
    await PendingUploadsFirestoreService.resumeAllForTenant(tenantId);
  }

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
    bool publicSite = true,
  }) async {
    if (pendingPhotoCount <= 0) {
      return publishNow(
        docRef: docRef,
        payload: stubPayload,
        isNewDoc: isNewDoc,
        postType: postType,
        publicSite: publicSite,
      );
    }
    return FeedMediaPublishFast.publishWithPhotosInBackground(
      docRef: docRef,
      tenantId: tenantId,
      postType: postType,
      corePayload: stubPayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      pendingPhotoCount: pendingPhotoCount,
      newImagesBytes: newImagesBytes,
      newImagePaths: newImagePaths,
      onPublished: onPublished,
      publicSite: publicSite,
    );
  }

  static String _tenantFromRef(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length >= 2 && parts[0] == 'igrejas') return parts[1];
    return '';
  }
}
