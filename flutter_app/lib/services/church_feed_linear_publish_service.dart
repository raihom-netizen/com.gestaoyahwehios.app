import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity, isValidImageUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

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
    void Function(double progress)? onUploadProgress,
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
        onUploadProgress: onUploadProgress,
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
    void Function(double progress)? onUploadProgress,
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
        onUploadProgress: onUploadProgress,
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
    void Function(double progress)? onUploadProgress,
  }) async {
    final isEvento = kind == PublicationKind.evento;
    final postType = isEvento ? 'evento' : 'aviso';
    final docId = docRef.id;
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);

    await ensureFirebaseReadyForPublishUpload();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
    await FastMediaPublishBootstrap.warmForFeedPublish()
        .timeout(const Duration(seconds: 28));

    if (isEvento) {
      ChurchPublishFlowLog.eventoStart();
    } else {
      ChurchPublishFlowLog.avisoStart();
    }

    final existingPaths = _pathsFromRefs(existingPhotoRefs);
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    var existingUrls =
        await EcoFireFeedPublishService.refsToPlayableUrls(existingPhotoRefs);
    final uploadedPaths = <String>[];
    final alignedThumbPaths = <String>[];
    final alignedThumbUrls = <String>[];

    if (hasNewPhotos) {
      ChurchPublishFlowLog.uploadStart('$postType $docId');
      final slots = await ChurchFeedMediaStorageFields.uploadPhotoSlots(
        tenantId: churchId,
        postType: postType,
        postId: docId,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
      );
      for (final slot in slots) {
        uploadedPaths.add(slot.fullPath);
        alignedThumbPaths.add(slot.thumbPath);
        final direct = sanitizeImageUrl(slot.downloadUrl ?? '');
        if (isValidImageUrl(direct)) {
          existingUrls = dedupeImageRefsByStorageIdentity([
            ...existingUrls,
            direct,
          ]);
        } else {
          final url = await EcoFireFeedPublishService.refsToPlayableUrls(
            [slot.fullPath],
          );
          if (url.isNotEmpty) {
            existingUrls = dedupeImageRefsByStorageIdentity([
              ...existingUrls,
              ...url,
            ]);
          }
        }
        final thumbDirect = sanitizeImageUrl(slot.thumbDownloadUrl ?? '');
        if (isValidImageUrl(thumbDirect)) {
          alignedThumbUrls.add(thumbDirect);
        }
      }
      ChurchPublishFlowLog.uploadOk('$postType $docId (${slots.length} fotos)');
      if (alignedThumbUrls.isEmpty) {
        for (final tp in alignedThumbPaths) {
          final tu = await EcoFireFeedPublishService.refsToPlayableUrls([tp]);
          if (tu.isNotEmpty) alignedThumbUrls.add(tu.first);
        }
      }
    }

    final allPaths = <String>[
      ...existingPaths,
      ...uploadedPaths,
    ];

    if (hasNewPhotos && uploadedPaths.isNotEmpty) {
      await ChurchStorageMetadataVerify.assertAllExist(
        uploadedPaths,
        timeout: ChurchStorageMetadataVerify.kDefaultTimeout,
        maxAttempts: ChurchStorageMetadataVerify.kMaxAttempts,
      );
    }

    final aspectRatio = _aspectRatioFromPayload(corePayload);
    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      ChurchFeedMediaStorageFields.buildStoragePathOnlyFields(
        photoPaths: allPaths,
        thumbPaths: alignedThumbPaths,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        videoPath: videoStoragePath,
        allowDeleteSentinels: !isNewDoc,
        isEvento: isEvento,
      ),
    );
    payload.addAll(
      MuralPostMediaPayload.buildMediaFields(
        allUrls: existingUrls,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        allowDeleteSentinels: !isNewDoc,
        imageVariants: null,
      ),
    );
    if (alignedThumbUrls.isNotEmpty) {
      payload['thumbUrl'] = alignedThumbUrls.first;
      payload['thumbUrls'] = alignedThumbUrls;
    }
    if (existingUrls.isNotEmpty) {
      final first = existingUrls.first;
      payload['fotos'] = existingUrls;
      payload['imageUrl'] = first;
      payload['imageUrls'] = existingUrls;
      payload['defaultImageUrl'] = first;
      payload['imagemUrl'] = first;
      payload['imagem_url'] = first;
      if (alignedThumbUrls.isEmpty) {
        payload['thumbUrl'] = first;
        payload['thumbUrls'] = existingUrls;
      }
    }
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
