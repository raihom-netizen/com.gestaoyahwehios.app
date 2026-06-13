import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity, isValidImageUrl, sanitizeImageUrl;

/// Publicação de evento — fluxo Ecofire único:
/// Firebase OK → fotos/vídeo no Storage → Firestore → agenda → notificar/site.
///
/// Path: `igrejas/{churchId}/eventos/{postId}` + fotos/vídeos canónicos.
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
    await EcoFireResilientPublish.prepareForPublish(logLabel: logLabel);
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
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
    void Function(double progress)? onUploadProgress,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = docRef.id;
    return EcoFireResilientPublish.runOrQueue(
      logLabel: 'evento_publish',
      optimisticResult: docId,
      onQueue: () => EcoFireResilientPublish.queueFeedPublish(
        churchId: churchId,
        docId: docId,
        postType: 'evento',
        docRef: docRef,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        bytesList: newImagesBytes,
        localPaths: newImagePaths,
      ),
      action: () => _publishOnline(
        docRef: docRef,
        churchId: churchId,
        docId: docId,
        tenantId: tenantId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        videoStoragePath: videoStoragePath,
        publicSite: publicSite,
        eventStartAt: eventStartAt,
        location: location,
        syncAgenda: syncAgenda,
        agendaCategory: agendaCategory,
        agendaColorHex: agendaColorHex,
        onUploadProgress: onUploadProgress,
      ),
    );
  }

  static Future<String> _publishOnline({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String docId,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    String? videoStoragePath,
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
    void Function(double progress)? onUploadProgress,
  }) async {
    await EcoFirePublishBootstrap.ensureHard(logLabel: 'evento_publish');
    ChurchPublishFlowLog.eventoStart();

    final existingPaths = _pathsFromRefs(existingUrls);
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    var photoUrls =
        await EcoFireFeedPublishService.refsToPlayableUrls(existingUrls);
    final uploadedPaths = <String>[];
    final alignedThumbPaths = <String>[];
    final alignedThumbUrls = <String>[];

    if (hasNewPhotos) {
      onUploadProgress?.call(0.05);
      ChurchPublishFlowLog.uploadStart('evento $docId');

      final newCount = kIsWeb
          ? (newImagesBytes?.length ?? 0)
          : (newImagePaths
                  ?.map((p) => p.trim())
                  .where((p) => p.isNotEmpty)
                  .length ??
              0);

      final slots = await EcoFireFeedPublishService.uploadPendingPhotoSlots(
        tenantId: churchId,
        postType: 'evento',
        postId: docId,
        startSlotIndex: startSlotIndex,
        bytesList: newImagesBytes,
        localPaths: newImagePaths,
        onProgress: newCount > 0
            ? (p) => onUploadProgress?.call(0.05 + p * 0.65)
            : null,
      );

      for (final slot in slots) {
        uploadedPaths.add(slot.fullPath);
        alignedThumbPaths.add(slot.thumbPath);
        final direct = sanitizeImageUrl(slot.fullUrl);
        if (isValidImageUrl(direct)) {
          photoUrls = dedupeImageRefsByStorageIdentity([...photoUrls, direct]);
        }
        final thumbDirect = sanitizeImageUrl(slot.thumbUrl);
        if (isValidImageUrl(thumbDirect)) {
          alignedThumbUrls.add(thumbDirect);
        }
      }

      ChurchPublishFlowLog.uploadOk('evento $docId (${slots.length} fotos)');
      onUploadProgress?.call(0.72);

      if (uploadedPaths.isEmpty) {
        throw StateError(
          'Não foi possível enviar as fotos do evento. Verifique a conexão e tente de novo.',
        );
      }

      if (uploadedPaths.isNotEmpty) {
        await ChurchStorageMetadataVerify.assertAllExist(
          uploadedPaths,
          timeout: ChurchStorageMetadataVerify.kDefaultTimeout,
          maxAttempts: ChurchStorageMetadataVerify.kMaxAttempts,
        );
      }
    }

    if (hasVideo && videoStoragePath != null && videoStoragePath.trim().isNotEmpty) {
      onUploadProgress?.call(0.78);
      await ChurchStorageMetadataVerify.assertExists(videoStoragePath.trim());
    }

    final allPaths = <String>[...existingPaths, ...uploadedPaths];
    final aspectRatio = _aspectRatioFromPayload(corePayload);
    final videoPath = (videoStoragePath ?? '').trim();

    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      ChurchFeedMediaStorageFields.buildStoragePathOnlyFields(
        photoPaths: allPaths,
        thumbPaths: alignedThumbPaths,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        videoPath: videoPath.isNotEmpty ? videoPath : null,
        allowDeleteSentinels: !isNewDoc,
        isEvento: true,
      ),
    );
    payload.addAll(
      MuralPostMediaPayload.buildMediaFields(
        allUrls: photoUrls,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        allowDeleteSentinels: !isNewDoc,
      ),
    );
    if (alignedThumbUrls.isNotEmpty) {
      payload['thumbUrl'] = alignedThumbUrls.first;
      payload['thumbUrls'] = alignedThumbUrls;
    }
    if (photoUrls.isNotEmpty) {
      final first = photoUrls.first;
      payload['fotos'] = photoUrls;
      payload['imageUrl'] = first;
      payload['imageUrls'] = photoUrls;
      payload['defaultImageUrl'] = first;
      payload['imagemUrl'] = first;
      payload['imagem_url'] = first;
      if (alignedThumbUrls.isEmpty) {
        payload['thumbUrl'] = first;
        payload['thumbUrls'] = photoUrls;
      }
    }
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';
    payload['publicSite'] = publicSite;

    onUploadProgress?.call(0.88);
    await PublicationEngine.saveStrictPublished(
      docRef: docRef,
      tenantId: churchId,
      kind: PublicationKind.evento,
      payload: payload,
      isNewDoc: isNewDoc,
    );
    await EventosPublishVerificationService.verifyDocumentExists(docRef);

    onUploadProgress?.call(0.94);
    if (syncAgenda) {
      final start = eventStartAt ?? _startAtFromPayload(payload);
      if (start != null) {
        await ChurchFeedAgendaSyncService.upsertForEvento(
          tenantId: churchId,
          eventoId: docId,
          title: (payload['title'] ?? '').toString(),
          description: (payload['text'] ?? payload['description'] ?? '').toString(),
          startAt: start,
          location: location,
          category: agendaCategory ?? 'evento_social',
          colorHex: agendaColorHex ?? '#E11D48',
        );
      }
    }

    await PublicationEngine.runDistributionAwait(
      tenantId: churchId,
      kind: PublicationKind.evento,
      postId: docId,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      phase: PublicationDistributionPhase.afterMediaFinalized,
    );

    onUploadProgress?.call(1.0);
    ChurchPublishFlowLog.eventoFirestoreOk();
    ChurchPublishFlowLog.moduleFinalOk(isEvento: true);
    return docId;
  }

  static List<String> _pathsFromRefs(List<String> refs) {
    final deduped = dedupeImageRefsByStorageIdentity(refs);
    return [...EventosPublishVerificationService.storagePathsFromRefs(deduped)];
  }

  static double _aspectRatioFromPayload(Map<String, dynamic> payload) {
    final prev = payload['media_info'];
    if (prev is Map) {
      final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
      if (oar is num) return oar.toDouble().clamp(0.45, 1.9);
    }
    return 1.0;
  }

  static DateTime? _startAtFromPayload(Map<String, dynamic> payload) {
    final v = payload['startAt'];
    if (v is Timestamp) return v.toDate();
    return null;
  }
}
