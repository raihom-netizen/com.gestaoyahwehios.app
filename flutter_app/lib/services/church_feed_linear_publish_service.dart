import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/church_instant_upload_pipeline.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Pipeline único e síncrono: upload → Storage OK → Firestore → agenda → distribuição.
abstract final class ChurchFeedLinearPublishService {
  ChurchFeedLinearPublishService._();

  static Future<String> publishAviso({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingPhotoRefs,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
  }) =>
      _publish(
        kind: PublicationKind.aviso,
        docRef: docRef,
        tenantId: tenantId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingPhotoRefs: existingPhotoRefs,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        publicSite: publicSite,
        calendarDate: calendarDate,
        syncCalendar: syncCalendar,
        hasVideo: false,
      );

  static Future<String> publishEvento({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingPhotoRefs,
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
  }) =>
      _publish(
        kind: PublicationKind.evento,
        docRef: docRef,
        tenantId: tenantId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingPhotoRefs: existingPhotoRefs,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        publicSite: publicSite,
        hasVideo: hasVideo,
        videoStoragePath: videoStoragePath,
        eventStartAt: eventStartAt,
        location: location,
        syncAgenda: syncAgenda,
        agendaCategory: agendaCategory,
        agendaColorHex: agendaColorHex,
      );

  static Future<String> _publish({
    required PublicationKind kind,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingPhotoRefs,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    String? videoStoragePath,
    bool publicSite = true,
    DateTime? calendarDate,
    DateTime? eventStartAt,
    String? location,
    bool syncCalendar = false,
    bool syncAgenda = false,
    String? agendaCategory,
    String? agendaColorHex,
  }) async {
    final isEvento = kind == PublicationKind.evento;
    final postType = isEvento ? 'evento' : 'aviso';
    final docId = docRef.id;
    final churchId = tenantId.trim();

    await ensureFirebaseReadyForPublishUpload();
    await FeedPublishPreflight.prepareForFirestoreSave();

    if (isEvento) {
      ChurchPublishFlowLog.eventoStart();
    } else {
      ChurchPublishFlowLog.avisoStart();
    }

    var existingPaths = _pathsFromRefs(existingPhotoRefs);
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    var uploadedSlots = const <FeedPhotoSlotResult>[];
    if (hasNewPhotos) {
      ChurchPublishFlowLog.uploadStart('$postType $docId');
      uploadedSlots = await ChurchFeedMediaStorageFields.uploadPhotoSlots(
        tenantId: churchId,
        postType: postType,
        postId: docId,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
      );
      ChurchPublishFlowLog.uploadOk('$postType $docId');
    }

    final uploadedPaths = uploadedSlots.map((s) => s.fullPath).toList();

    final allPaths = <String>[
      ...existingPaths,
      ...uploadedPaths,
    ];

    final alignedThumbs = <String>[];
    Map<String, dynamic>? capaVariants;
    for (var i = 0; i < uploadedSlots.length; i++) {
      final slot = uploadedSlots[i];
      alignedThumbs.add(slot.thumbPath);
      if (existingPaths.isEmpty && i == 0) {
        capaVariants = slot.imageVariants;
      } else if (startSlotIndex == 0 && i == 0) {
        capaVariants = slot.imageVariants;
      }
    }

    if (isEvento) {
      await EventosPublishVerificationService.verifyStorageMetadata(
        photoPaths: allPaths,
        videoPath: videoStoragePath,
      );
    } else {
      await AvisosPublishVerificationService.verifyStorageMetadata(
        photoPaths: allPaths,
      );
    }

    final aspectRatio = _aspectRatioFromPayload(corePayload);
    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      ChurchFeedMediaStorageFields.buildStoragePathOnlyFields(
        photoPaths: allPaths,
        thumbPaths: alignedThumbs,
        capaImageVariants: capaVariants,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        videoPath: videoStoragePath,
        allowDeleteSentinels: !isNewDoc,
        isEvento: isEvento,
      ),
    );
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';
    payload['publicSite'] = publicSite;

    await PublicationEngine.saveStrictPublished(
      docRef: docRef,
      tenantId: churchId,
      kind: kind,
      payload: payload,
      isNewDoc: isNewDoc,
    );

    if (isEvento) {
      await EventosPublishVerificationService.verifyDocumentExists(docRef);
    } else {
      await AvisosPublishVerificationService.verifyDocumentExists(docRef);
    }

    if (isEvento && syncAgenda) {
      final start = eventStartAt ?? _startAtFromPayload(payload);
      if (start != null) {
        await ChurchFeedAgendaSyncService.upsertForEvento(
          tenantId: churchId,
          eventoId: docId,
          title: (payload['title'] ?? '').toString(),
          description: (payload['text'] ?? '').toString(),
          startAt: start,
          location: location,
          category: agendaCategory ?? 'evento_social',
          colorHex: agendaColorHex ?? '#E11D48',
        );
      }
    } else if (!isEvento && syncCalendar) {
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
      kind: kind,
      postId: docId,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      phase: PublicationDistributionPhase.afterMediaFinalized,
    );

    await _logDiagnostic(
      churchId: churchId,
      docId: docId,
      tipo: postType,
      storagePaths: allPaths,
      videoPath: videoStoragePath,
      uploadStatus: hasNewPhotos ? 'ok' : 'skipped',
      firestoreStatus: 'ok',
      siteStatus: publicSite ? 'scheduled' : 'skipped',
      calendarStatus: (isEvento && syncAgenda) || syncCalendar ? 'ok' : 'skipped',
      notificationStatus: 'cf_on_create',
    );

    if (isEvento) {
      ChurchPublishFlowLog.eventoFirestoreOk();
      ChurchPublishFlowLog.moduleFinalOk(isEvento: true);
    } else {
      ChurchPublishFlowLog.avisoFirestoreOk();
      ChurchPublishFlowLog.moduleFinalOk(isEvento: false);
    }

    return docId;
  }

  static List<String> _pathsFromRefs(List<String> refs) {
    final deduped = dedupeImageRefsByStorageIdentity(refs);
    return [
      ...AvisosPublishVerificationService.storagePathsFromUrls(deduped),
    ];
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

  static DateTime? _validUntilFromPayload(Map<String, dynamic> payload) {
    final v = payload['validUntil'] ?? payload['avisoExpiresAt'];
    if (v is Timestamp) return v.toDate();
    return null;
  }

  static Future<void> _logDiagnostic({
    required String churchId,
    required String docId,
    required String tipo,
    required List<String> storagePaths,
    String? videoPath,
    required String uploadStatus,
    required String firestoreStatus,
    required String siteStatus,
    required String calendarStatus,
    required String notificationStatus,
    Object? erro,
  }) async {
    await SystemLogService.record(
      module: tipo == 'evento' ? 'eventos' : 'avisos',
      message: erro != null ? 'linear_publish_error' : 'linear_publish_ok',
      tenantId: churchId,
      canonicalId: churchId,
      severity: erro != null ? 'error' : 'info',
      error: erro,
      extra: <String, dynamic>{
        'churchId': churchId,
        'docId': docId,
        'tipo': tipo,
        'storagePaths': storagePaths,
        if (videoPath != null && videoPath.isNotEmpty) 'videoPath': videoPath,
        'uploadStatus': uploadStatus,
        'firestoreStatus': firestoreStatus,
        'siteStatus': siteStatus,
        'calendarStatus': calendarStatus,
        'notificationStatus': notificationStatus,
      },
    );
  }
}
