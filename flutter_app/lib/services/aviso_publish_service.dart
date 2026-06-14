import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação de aviso — fluxo Ecofire: Firebase → Storage → Firestore → site/notificar.
abstract final class AvisoPublishService {
  AvisoPublishService._();

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static DocumentReference<Map<String, dynamic>> docRef({
    required String churchId,
    required String docId,
  }) =>
      AvisosPublishVerificationService.avisoDocRef(
        igrejaId: churchId,
        docId: docId,
      );

  static Future<void> ensureReady({String logLabel = 'aviso_prepare'}) async {
    await EcoFireResilientPublish.prepareForPublish(logLabel: logLabel);
  }

  static Future<String> publish({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = docRef.id;
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    return EcoFireResilientPublish.runOrQueue(
      logLabel: hasNewPhotos ? 'aviso_publish_photos' : 'aviso_publish',
      optimisticResult: docId,
      onQueue: () => EcoFireResilientPublish.queueFeedPublish(
        churchId: churchId,
        docId: docId,
        postType: 'aviso',
        docRef: docRef,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: false,
        bytesList: newImagesBytes,
        localPaths: newImagePaths,
      ),
      action: () async {
        if (hasNewPhotos) {
          await EcoFirePublishBootstrap.ensureHard(
            logLabel: 'aviso_publish_strict',
            strict: true,
          );
        }
        final id = await _publishOnline(
          docRef: docRef,
          tenantId: tenantId,
          churchId: churchId,
          docId: docId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingUrls: existingUrls,
          startSlotIndex: startSlotIndex,
          newImagesBytes: newImagesBytes,
          newImagePaths: newImagePaths,
          publicSite: publicSite,
          calendarDate: calendarDate,
          syncCalendar: syncCalendar,
          onUploadProgress: onUploadProgress,
        );
        if (hasNewPhotos) {
          await AvisosPublishVerificationService.verifyPublishedMedia(
            docRef,
            minPhotos: 1,
          );
        }
        return id;
      },
    );
  }

  static Future<String> _publishOnline({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required String churchId,
    required String docId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    if (hasNewPhotos) {
      return GestaoYahwehWriteFirstPublishService.publishFeedWithPendingMedia(
        docRef: docRef,
        churchId: churchId,
        docId: docId,
        postType: 'aviso',
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: false,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        onUploadProgress: onUploadProgress,
      );
    }

    await EcoFirePublishBootstrap.ensureHard(
      logLabel: 'aviso_publish',
      strict: false,
    );
    ChurchPublishFlowLog.avisoStart();

    final existingPaths = _pathsFromRefs(existingUrls);

    var photoUrls =
        await EcoFireFeedPublishService.refsToPlayableUrls(existingUrls);
    final alignedThumbPaths = <String>[];
    final alignedThumbUrls = <String>[];

    final allPaths = <String>[...existingPaths];
    final aspectRatio = _aspectRatioFromPayload(corePayload);

    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      ChurchFeedMediaStorageFields.buildStoragePathOnlyFields(
        photoPaths: allPaths,
        thumbPaths: alignedThumbPaths,
        aspectRatio: aspectRatio,
        hasVideo: false,
        allowDeleteSentinels: !isNewDoc,
        isEvento: false,
      ),
    );
    payload.addAll(
      MuralPostMediaPayload.buildMediaFields(
        allUrls: photoUrls,
        aspectRatio: aspectRatio,
        hasVideo: false,
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
    payload['imageVariants'] = FieldValue.delete();
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';
    payload['publicSite'] = publicSite;

    onUploadProgress?.call(0.88);
    await PublicationEngine.saveStrictPublished(
      docRef: docRef,
      tenantId: churchId,
      kind: PublicationKind.aviso,
      payload: payload,
      isNewDoc: isNewDoc,
    );
    await AvisosPublishVerificationService.verifyDocumentExists(docRef);

    onUploadProgress?.call(0.94);
    if (syncCalendar) {
      final refDate = calendarDate ?? _validUntilFromPayload(payload);
      if (refDate != null) {
        await ChurchFeedAgendaSyncService.upsertForAviso(
          tenantId: churchId,
          avisoId: docId,
          title: (payload['title'] ?? '').toString(),
          description: (payload['text'] ?? '').toString(),
          referenceDate: refDate,
        );
      }
    }

    await PublicationEngine.runDistributionAwait(
      tenantId: churchId,
      kind: PublicationKind.aviso,
      postId: docId,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      phase: PublicationDistributionPhase.afterMediaFinalized,
    );

    onUploadProgress?.call(1.0);
    ChurchPublishFlowLog.avisoFirestoreOk();
    ChurchPublishFlowLog.moduleFinalOk(isEvento: false);
    return docId;
  }

  static List<String> _pathsFromRefs(List<String> refs) {
    final deduped = dedupeImageRefsByStorageIdentity(refs);
    return [...AvisosPublishVerificationService.storagePathsFromUrls(deduped)];
  }

  static double _aspectRatioFromPayload(Map<String, dynamic> payload) {
    final prev = payload['media_info'];
    if (prev is Map) {
      final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
      if (oar is num) return oar.toDouble().clamp(0.45, 1.9);
    }
    return 1.0;
  }

  static DateTime? _validUntilFromPayload(Map<String, dynamic> payload) {
    final v = payload['validUntil'] ?? payload['avisoExpiresAt'];
    if (v is Timestamp) return v.toDate();
    return null;
  }
}
