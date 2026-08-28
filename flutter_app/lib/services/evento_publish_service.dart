import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/church_video_preupload.dart';
import 'package:gestao_yahweh/services/evento_media_upload.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/video_handler_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Publicação de evento — pipeline **linear**: bootstrap → fotos/vídeo → Storage → Firestore → agenda → feed/site.
///
/// Proibido: `publishState`, stub Firestore antes do Storage, write-first.
/// Identidade do destino do vídeo de evento (igreja + post + slot).
String eventVideoPreuploadTag({
  required String churchId,
  required String postId,
  int slot = 0,
}) => 'evento|$churchId|$postId|$slot';

abstract final class EventoPublishService {
  EventoPublishService._();

  /// Motivo da última falha de upload de vídeo, ou `null` quando correu bem.
  ///
  /// O vídeo NUNCA pode vetar a publicação: um evento com vídeo e sem fotos era
  /// descartado por inteiro (título, data, local) quando o upload falhava — foi
  /// o que apagou 7 de 7 eventos com vídeo nos logs. Agora o evento é sempre
  /// gravado e a falha do vídeo fica aqui para a UI avisar o utilizador.
  static String? lastVideoFailure;

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  /// Identidade do destino do vídeo — o editor e a publicação têm de gerar
  /// exatamente a mesma, senão o envio antecipado não é aproveitado.
  static String eventVideoPreuploadTagFor({
    required String churchId,
    required String postId,
    int slot = 0,
  }) => eventVideoPreuploadTag(churchId: churchId, postId: postId, slot: slot);

  static DocumentReference<Map<String, dynamic>> docRef({
    required String churchId,
    required String docId,
  }) => EventosPublishVerificationService.eventoDocRef(
    igrejaId: churchId,
    docId: docId,
  );

  static Future<void> ensureReady({String logLabel = 'evento_prepare'}) async {
    await ChurchMediaUploadFacade.ensureReady(requireAuth: true);
  }

  /// Gate único — Storage + Auth (padrão Controle Total).
  static Future<void> prepareFullPipeline({
    String logLabel = 'evento_prepare',
    bool withMedia = true,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.06);
    await ChurchMediaUploadFacade.ensureReady(requireAuth: true);
    onProgress?.call(0.12);
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
    lastVideoFailure = null;
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final localVideo = (localVideoPath ?? '').trim();
    final wantsVideoUpload = hasVideo && localVideo.isNotEmpty;
    // Pré-upload de fotos em paralelo com o vídeo só quando já há bytes prontos
    // (caminho real do editor de evento — ver events_manager_page.dart, sempre
    // passa newImagesBytes, nunca newImagePaths). Sem isso o vídeo (que pode
    // demorar bastante) e as fotos subiam em série, dobrando o tempo de espera.
    final canPreUploadPhotos =
        wantsVideoUpload && (newImagesBytes?.isNotEmpty ?? false);

    await ChurchMediaUploadFacade.ensureReady(requireAuth: true);

    // Eventos podem ser criados só com texto (título/data/local) — mídia é opcional.
    // A validação de conteúdo mínimo (título) já é feita na UI (_save).

    var resolvedVideoPath = (videoStoragePath ?? '').trim();
    final payload = Map<String, dynamic>.from(corePayload);

    Future<void> uploadVideo() async {
      if (!wantsVideoUpload) return;
      ChurchPublishFlowLog.uploadStart('evento video ${docRef.id}');
      try {
        // O vídeo (encode + rede) é a maior fatia do tempo: dar-lhe só 24% da
        // barra fazia a percentagem parar cedo e ficar lá minutos. 14%→59%.
        void reportVideo(double p) =>
            onUploadProgress?.call(0.14 + p.clamp(0.0, 1.0) * 0.45);
        // O editor manda o vídeo assim que ele é anexado (enquanto o
        // utilizador ainda preenche título/data/local). Se já terminou, isto
        // devolve na hora e a publicação não espera pela rede.
        final uploaded =
            await ChurchVideoPreupload.claim<VideoUploadResult>(
              localPath: localVideo,
              tag: eventVideoPreuploadTag(
                churchId: churchId,
                postId: docRef.id,
                slot: 0,
              ),
              onProgress: onUploadProgress == null ? null : reportVideo,
            ) ??
            await VideoHandlerService.instance.compressAndUploadFromPath(
              localPath: localVideo,
              tenantId: churchId,
              eventPostDocId: docRef.id,
              videoSlotIndex: 0,
              onUploadProgress: onUploadProgress == null ? null : reportVideo,
            );
        if (uploaded != null) {
          resolvedVideoPath = uploaded.videoStoragePath;
          payload['videoUrl'] = uploaded.videoUrl;
          if (uploaded.thumbUrl.isNotEmpty) {
            payload['thumbUrl'] = uploaded.thumbUrl;
          }
          payload['videoPath'] = resolvedVideoPath;
          payload['videos'] = [
            {'videoUrl': uploaded.videoUrl, 'thumbUrl': uploaded.thumbUrl},
          ];
          ChurchPublishFlowLog.uploadOk('evento video ${docRef.id}');
        } else {
          // Upload devolveu vazio: publica o evento à mesma (só texto/fotos).
          lastVideoFailure =
              'O vídeo não pôde ser enviado. O evento foi publicado sem ele.';
          ChurchPublishFlowLog.logCatch(
            StateError('video_upload_empty_fallback'),
            StackTrace.current,
            label: 'evento_video_fallback_photo_only',
          );
        }
      } catch (videoErr, videoSt) {
        // Continua publicando sem o vídeo — com ou sem fotos. Perder o evento
        // inteiro por causa do anexo era pior do que publicar sem ele.
        lastVideoFailure = videoErr is StateError
            ? videoErr.message
            : 'Falha ao enviar o vídeo. O evento foi publicado sem ele.';
        ChurchPublishFlowLog.logCatch(
          videoErr,
          videoSt,
          label: 'evento_video_fallback_photo_only',
        );
        unawaited(
          EventosPublishVerificationService.logPublishPhase(
            phase: 'video_error',
            igrejaId: churchId,
            uid: '',
            titulo: (corePayload['title'] ?? corePayload['titulo'] ?? '')
                .toString(),
            eventoId: docRef.id,
            erro: videoErr,
          ),
        );
      }
    }

    var mergedExistingUrls = existingUrls;
    var remainingNewImagesBytes = newImagesBytes;
    var remainingNewImagePaths = newImagePaths;

    Future<void> preUploadPhotos() async {
      if (!canPreUploadPhotos) return;
      try {
        final slots = await EventoMediaUpload.uploadPhotoBatch(
          churchId: churchId,
          postId: docRef.id,
          startSlotIndex: startSlotIndex,
          bytesList: newImagesBytes!,
          alreadyCompressed: true,
        );
        final urls = [
          for (final s in slots)
            if (s.fullUrl.trim().isNotEmpty) s.fullUrl.trim(),
        ];
        // Só reaproveita o pré-upload se TODAS as fotos subiram — parcial cai
        // no caminho normal (fotos sobem de novo dentro do publishEvento).
        if (urls.length == newImagesBytes.length) {
          mergedExistingUrls = dedupeImageRefsByStorageIdentity([
            ...existingUrls,
            ...urls,
          ]);
          remainingNewImagesBytes = null;
          remainingNewImagePaths = null;
        }
      } catch (e, st) {
        // Falha no pré-upload paralelo: segue com o caminho normal (fotos
        // sobem dentro do publishEvento, sem perder o evento por causa disso).
        ChurchPublishFlowLog.logCatch(
          e,
          st,
          label: 'evento_photo_preupload_fallback',
        );
      }
    }

    if (wantsVideoUpload) {
      await Future.wait([uploadVideo(), preUploadPhotos()]);
    } else {
      await uploadVideo();
    }

    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await ChurchFeedLinearPublishService.publishEvento(
          docRef: docRef,
          tenantId: churchId,
          corePayload: payload,
          isNewDoc: isNewDoc,
          existingPhotoRefs: mergedExistingUrls,
          startSlotIndex: startSlotIndex,
          newImagesBytes: remainingNewImagesBytes,
          newImagePaths: remainingNewImagePaths,
          publicSite: publicSite,
          hasVideo: hasVideo && resolvedVideoPath.isNotEmpty,
          videoStoragePath: resolvedVideoPath.isNotEmpty
              ? resolvedVideoPath
              : null,
          eventStartAt: eventStartAt,
          location: location,
          syncAgenda: syncAgenda,
          agendaCategory: agendaCategory,
          agendaColorHex: agendaColorHex,
          onUploadProgress: onUploadProgress,
        );
      } catch (e) {
        last = e;
        final retryable =
            isFirebaseNoAppError(e) || FirestoreWebGuard.isClientTerminated(e);
        if (attempt == 0 && retryable) {
          await EcoFireDirectFirebase.ensureDefaultApp();
          await ChurchMediaUploadFacade.ensureReady(requireAuth: true);
          continue;
        }
        if (EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
          ChurchPublishFlowLog.logCatch(
            e,
            StackTrace.current,
            label: 'evento_offline_queue',
          );
          await EcoFireResilientPublish.queueFeedPublish(
            churchId: churchId,
            docId: docRef.id,
            postType: 'evento',
            docRef: docRef,
            corePayload: payload,
            isNewDoc: isNewDoc,
            existingUrls: mergedExistingUrls,
            startSlotIndex: startSlotIndex,
            hasVideo: hasVideo && resolvedVideoPath.isNotEmpty,
            bytesList: remainingNewImagesBytes,
            localPaths: remainingNewImagePaths,
          );
          EcoFireResilientPublish.scheduleSync(reason: 'evento_queued');
          throw ResilientPublishQueuedException('evento:${docRef.id}');
        }
        rethrow;
      }
    }

    throw StateError(last?.toString() ?? 'Falha ao publicar evento.');
  }
}
