import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase/firebase_retry.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/core/image_aspect_ratio_util.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/firebase_apps_diagnostic.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/analytics_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação **estrita**: Storage + [getDownloadURL] **antes** de gravar Firestore publicado.
///
/// Evita documentos vazios / `publishState: uploading` no feed e no site público.
abstract final class FeedMediaPublishStrict {
  FeedMediaPublishStrict._();

  /// Fotos novas → upload paralelo → URLs → um único `set` com `published`.
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
    await Future.wait([
      FastMediaPublishBootstrap.warmForFeedPublish(),
      AppFinalizeBootstrap.ensureSessionForPublish(
        logLabel: postType == 'aviso' ? 'avisos_strict' : 'eventos_strict',
      ),
    ]);
    logFirebasePublishPhase(
      'EVENT_START',
      '${postType == 'aviso' ? 'aviso' : 'evento'}|${docRef.path}',
    );
    logFirebaseAppsBeforeOperation('feed_strict_publish', module: postType);
    final postId = docRef.id;
    var localPathsForRetry = const <String>[];
    GlobalUploadProgress.instance.startBatch(
      itemLabel: postType == 'aviso' ? 'A publicar aviso…' : 'A publicar evento…',
      totalItems: (newImagesBytes?.length ?? newImagePaths?.length ?? 0)
          .clamp(1, 99),
    );
    try {
      List<String> uploaded = const [];
      double aspectRatio = 1.0;

      if (kIsWeb) {
        final images = newImagesBytes ?? const <Uint8List>[];
        if (images.isEmpty) {
          throw StateError('Não foi possível ler as fotos para enviar.');
        }
        uploaded = await MuralPostMediaPayload.uploadNewPhotosBeforePublish(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          newImages: images,
          startSlotIndex: startSlotIndex,
        );
        final ar = await imageAspectRatioFromBytes(images.first);
        if (ar != null) aspectRatio = ar.clamp(0.4, 2.3);
      } else {
        final paths = newImagePaths
                ?.map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList() ??
            const <String>[];
        localPathsForRetry = paths;
        if (paths.isEmpty) {
          throw StateError('Não foi possível ler as fotos para enviar.');
        }
        uploaded =
            await MuralPostMediaPayload.uploadNewPhotosBeforePublishFromPaths(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          localPaths: paths,
          startSlotIndex: startSlotIndex,
        );
      }

      final allUrls = dedupeImageRefsByStorageIdentity([
        ...existingUrls,
        ...uploaded,
      ]);
      logFirebasePublishPhase('UPLOAD_OK', docRef.path);

      final patch = Map<String, dynamic>.from(corePayload);
      patch.addAll(
        MuralPostMediaPayload.buildMediaFields(
          allUrls: allUrls,
          aspectRatio: aspectRatio,
          hasVideo: hasVideo,
        ),
      );
      patch['publishState'] = MuralFastPublishService.statePublished;
      FirestoreWriteGuard.applyMuralPublishMetaPatch(
        patch,
        isNewDoc: isNewDoc,
        clearPendingImageCount: true,
        clearPublishError: true,
      );
      patch['updatedAt'] = FieldValue.serverTimestamp();

      final safe = FirestoreWriteGuard.stripHeavyFields(patch);
      logFirebasePublishPhase('INICIO_FIRESTORE', docRef.path);
      try {
        await firebaseRetry<void>(
          () async {
            if (isNewDoc) {
              await docRef
                  .set(safe)
                  .timeout(const Duration(seconds: 30));
            } else {
              await docRef
                  .set(safe, SetOptions(merge: true))
                  .timeout(const Duration(seconds: 30));
            }
          },
          reason: 'feed_strict_firestore_${postType}',
        );
        logFirebasePublishPhase('FIRESTORE_OK', docRef.path);
        logFirebasePublishPhase('FIM_FIRESTORE', docRef.path);
      } catch (e, st) {
        logFirebasePublishPhase(
          'ERRO_FIRESTORE',
          docRef.path,
          error: e,
          stack: st,
        );
        rethrow;
      }

      if (onPublished != null) {
        try {
          await onPublished();
        } catch (_) {}
      }
      unawaited(AnalyticsService.logPublish(module: postType, success: true));
      return postId;
    } catch (e, st) {
      logFirebasePublishPhase(
        'EVENT_ERROR',
        docRef.path,
        error: e,
        stack: st,
      );
      unawaited(AnalyticsService.logPublish(module: postType, success: false));
      final module = postType == 'aviso' ? 'aviso' : 'evento';
      final path = FeedTenantStorageMap.feedPhotoPath(
        postType: postType,
        tenantId: tenantId,
        postDocId: postId,
        slotIndex: startSlotIndex,
      );
      unawaited(
        PendingUploadsFirestoreService.recordFailedBytesUpload(
          tenantId: tenantId,
          module: module,
          storagePath: path,
          error: e,
          localPath: localPathsForRetry.isEmpty ? null : localPathsForRetry.first,
          meta: {
            'postId': postId,
            'postType': postType,
            'source': 'feed_media_strict',
          },
        ),
      );
      if (!kIsWeb && localPathsForRetry.isNotEmpty) {
        unawaited(
          MuralPublishOutboxService.registerJob(
            tenantId: tenantId,
            postId: postId,
            postType: postType,
            existingUrls: existingUrls,
            startSlotIndex: startSlotIndex,
            hasVideo: hasVideo,
            localPaths: localPathsForRetry,
          ),
        );
      }
      try {
        await FeedMediaPublishService.markPublishFailed(
          docRef: docRef,
          error: formatFirebaseErrorForUser(e, stackTrace: st),
        );
      } catch (_) {}
      Error.throwWithStackTrace(e, st);
    } finally {
      GlobalUploadProgress.instance.end();
    }
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
