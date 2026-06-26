import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/video_handler_service.dart';

/// Publicação de evento — pipeline **linear**: bootstrap → fotos/vídeo → Storage → Firestore → agenda → feed/site.
///
/// Proibido: `publishState`, stub Firestore antes do Storage, write-first.
abstract final class EventoPublishService {
  EventoPublishService._();

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static DocumentReference<Map<String, dynamic>> docRef({
    required String churchId,
    required String docId,
  }) =>
      EventosPublishVerificationService.eventoDocRef(
        igrejaId: churchId,
        docId: docId,
      );

  static Future<void> ensureReady({String logLabel = 'evento_prepare'}) async {
    await EcoFirePublishBootstrap.ensureHard(
      logLabel: logLabel,
      strict: true,
    );
  }

  /// Bootstrap EcoFire — Firebase + Storage + Auth (sem warm duplicado).
  static Future<void> prepareFullPipeline({
    String logLabel = 'evento_prepare',
    bool withMedia = true,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.06);
    Object? last;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (attempt > 0) {
          FirebaseBootstrapService.resetPublishWarmState();
        }
        await FirebaseBootstrapService.ensureStorageAlwaysLinked(
          refreshAuthToken: true,
          maxAttempts: 5,
        );
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: withMedia ? '${logLabel}_media' : logLabel,
        );
        if (withMedia) {
          await ensureFirebaseReadyForMediaUpload();
        }
        await EcoFirePublishBootstrap.ensureHard(
          logLabel: withMedia ? '${logLabel}_media' : logLabel,
          strict: true,
        );
        onProgress?.call(0.12);
        return;
      } catch (e, st) {
        last = e;
        ChurchPublishFlowLog.logCatch(e, st, label: 'evento_bootstrap_$attempt');
        if (attempt < 4 && isFirebaseNoAppError(e)) {
          await Future<void>.delayed(
            Duration(milliseconds: 320 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }
    throw StateError('Firebase indisponível ($logLabel).');
  }

  static Future<String> publish({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    String? videoStoragePath,
    String? localVideoPath,
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
    void Function(double progress)? onUploadProgress,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);
    final localVideo = (localVideoPath ?? '').trim();

    if (isNewDoc && !hasNewPhotos && existingUrls.isEmpty && !hasVideo) {
      throw StateError('Adicione pelo menos uma foto ou um vídeo ao evento.');
    }

    await prepareFullPipeline(
      logLabel: hasNewPhotos || localVideo.isNotEmpty || hasVideo
          ? 'evento_publish_media'
          : 'evento_publish',
      withMedia: hasNewPhotos || localVideo.isNotEmpty || hasVideo,
      onProgress: onUploadProgress == null
          ? null
          : (p) => onUploadProgress!(p.clamp(0.06, 0.14)),
    );

    var resolvedVideoPath = (videoStoragePath ?? '').trim();
    final payload = Map<String, dynamic>.from(corePayload);

    if (hasVideo && localVideo.isNotEmpty) {
      ChurchPublishFlowLog.uploadStart('evento video ${docRef.id}');
      final uploaded = await VideoHandlerService.instance.compressAndUploadFromPath(
        localPath: localVideo,
        tenantId: churchId,
        eventPostDocId: docRef.id,
        videoSlotIndex: 0,
        onUploadProgress: onUploadProgress == null
            ? null
            : (p) => onUploadProgress!(0.14 + p.clamp(0.0, 1.0) * 0.24),
      );
      if (uploaded == null) {
        throw StateError('Não foi possível enviar o vídeo do evento.');
      }
      resolvedVideoPath = uploaded.videoStoragePath;
      payload['videoUrl'] = uploaded.videoUrl;
      if (uploaded.thumbUrl.isNotEmpty) {
        payload['thumbUrl'] = uploaded.thumbUrl;
      }
      payload['videoPath'] = resolvedVideoPath;
      payload['videos'] = [
        {
          'videoUrl': uploaded.videoUrl,
          'thumbUrl': uploaded.thumbUrl,
        },
      ];
      ChurchPublishFlowLog.uploadOk('evento video ${docRef.id}');
    }

    try {
      return await ChurchFeedLinearPublishService.publishEvento(
        docRef: docRef,
        tenantId: churchId,
        corePayload: payload,
        isNewDoc: isNewDoc,
        existingPhotoRefs: existingUrls,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        publicSite: publicSite,
        hasVideo: hasVideo && resolvedVideoPath.isNotEmpty,
        videoStoragePath:
            resolvedVideoPath.isNotEmpty ? resolvedVideoPath : null,
        eventStartAt: eventStartAt,
        location: location,
        syncAgenda: syncAgenda,
        agendaCategory: agendaCategory,
        agendaColorHex: agendaColorHex,
        onUploadProgress: onUploadProgress,
      );
    } catch (e) {
      if (EcoFireResilientPublish.shouldQueueSilently(e)) {
        ChurchPublishFlowLog.logCatch(e, StackTrace.current, label: 'evento_offline');
        rethrow;
      }
      rethrow;
    }
  }
}
