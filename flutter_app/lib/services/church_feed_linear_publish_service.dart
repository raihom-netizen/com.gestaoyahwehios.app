import 'dart:async' show unawaited;
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_agenda_sync_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity, isValidImageUrl, sanitizeImageUrl;

/// Pipeline único e síncrono (Controle Total):
/// comprimir → Storage → URL/storagePath → Firestore → agenda → distribuição.
/// UI dos módulos só lê o link — nunca bytes no documento.
abstract final class ChurchFeedLinearPublishService {
  ChurchFeedLinearPublishService._();

  static void _report(void Function(double progress)? cb, double value) {
    cb?.call(value.clamp(0.0, 1.0));
  }

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
  }) async {
    return _publish(
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
      onUploadProgress: onUploadProgress,
      hasVideo: false,
    );
  }

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

    logFirebasePublishPhase(
      'linear_publish_start',
      '$postType path=${docRef.path} tenant=$churchId photos=${newImagesBytes?.length ?? newImagePaths?.length ?? 0}',
    );

    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    await DirectStorageUrlPublish.ensureReady(requireAuth: true);
    _report(onUploadProgress, 0.12);

    if (isEvento) {
      ChurchPublishFlowLog.eventoStart();
    } else {
      ChurchPublishFlowLog.avisoStart();
    }

    final existingPaths = _pathsFromRefs(existingPhotoRefs);

    var existingUrls =
        await EcoFireFeedPublishService.refsToPlayableUrls(existingPhotoRefs);
    final uploadedPaths = <String>[];
    final alignedThumbPaths = <String>[];
    final alignedThumbUrls = <String>[];
    var uploadedCount = 0;

    if (hasNewPhotos) {
      ChurchPublishFlowLog.uploadStart('$postType $docId');
      logFirebasePublishPhase(
        'linear_upload_start',
        '$postType path=${docRef.path} tenant=$churchId',
      );
      _report(onUploadProgress, 0.20);
      if (isEvento) {
        final images = newImagesBytes ?? const <Uint8List>[];
        final imagePaths = newImagePaths
                ?.map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList() ??
            const <String>[];
        final allBytes = <Uint8List>[...images];
        if (imagePaths.isNotEmpty) {
          if (kIsWeb) {
            throw StateError(
              'As fotos do evento na web devem ser enviadas em memória (bytes).',
            );
          }
          final files = <File>[];
          for (final localPath in imagePaths) {
            final file = File(localPath);
            if (!await file.exists()) {
              throw StateError('Foto do evento não encontrada no aparelho.');
            }
            files.add(file);
          }
          final readBytes = await Future.wait(
            files.map((f) async {
              final bytes = await f.readAsBytes();
              if (bytes.isEmpty) {
                throw StateError('Foto do evento vazia — selecione outra imagem.');
              }
              return bytes;
            }),
            eagerError: true,
          );
          allBytes.addAll(readBytes);
        }
        if (allBytes.isEmpty) {
          throw StateError('Inclua pelo menos uma foto no evento.');
        }

        var nextSlot = startSlotIndex;
        final batchItems = <ChurchMediaUploadBatchItem>[];
        for (final raw in allBytes) {
          batchItems.add(
            ChurchMediaUploadBatchItem(
              bytes: raw,
              storagePath: ChurchStorageLayout.eventPostPhotoPath(
                churchId,
                docId,
                nextSlot,
              ),
              logLabel: 'evento_photo',
              alreadyCompressed: false,
            ),
          );
          nextSlot++;
        }

        final batch = await ChurchMediaUploadFacade.uploadBatchParallel(
          items: batchItems,
          timeoutPerItem: const Duration(seconds: 55),
          onItemProgress: (index, p) {
            final span = 0.54 / batchItems.length;
            _report(onUploadProgress, 0.20 + span * index + p * span);
          },
          onBatchProgress: (done, total) {
            if (total <= 0) return;
            _report(onUploadProgress, 0.20 + 0.54 * (done / total));
          },
        );
        final batchErr = ChurchMediaUploadFacade.firstBatchError(batch);
        if (batchErr != null) throw batchErr;

        for (final item in batch) {
          final uploaded = item.result;
          if (uploaded == null) continue;
          uploadedPaths.add(uploaded.storagePath);
          alignedThumbPaths.add(uploaded.storagePath);
          final url = sanitizeImageUrl(uploaded.downloadUrl);
          if (isValidImageUrl(url)) {
            existingUrls = dedupeImageRefsByStorageIdentity([
              ...existingUrls,
              url,
            ]);
            alignedThumbUrls.add(url);
          }
        }
        uploadedCount = uploadedPaths.length;
      } else {
        final images = newImagesBytes ?? const <Uint8List>[];
        final imagePaths = newImagePaths
                ?.map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList() ??
            const <String>[];
        if (images.isEmpty && imagePaths.isEmpty) {
          throw StateError('Inclua pelo menos uma foto no aviso.');
        }
        final allBytes = <Uint8List>[...images];
        if (imagePaths.isNotEmpty) {
          if (kIsWeb) {
            throw StateError(
              'As fotos do aviso na web devem ser enviadas em memória (bytes).',
            );
          }
          final files = <File>[];
          for (final localPath in imagePaths) {
            final file = File(localPath);
            if (!await file.exists()) {
              throw StateError('Foto do aviso não encontrada no aparelho.');
            }
            files.add(file);
          }
          final readBytes = await Future.wait(
            files.map((f) async {
              final bytes = await f.readAsBytes();
              if (bytes.isEmpty) {
                throw StateError('Foto do aviso vazia — selecione outra imagem.');
              }
              return bytes;
            }),
            eagerError: true,
          );
          allBytes.addAll(readBytes);
        }

        var nextSlot = startSlotIndex;
        final batchItems = <ChurchMediaUploadBatchItem>[];
        for (final raw in allBytes) {
          batchItems.add(
            ChurchMediaUploadBatchItem(
              bytes: raw,
              storagePath: ChurchStorageLayout.avisoPostPhotoPath(
                churchId,
                docId,
                nextSlot,
              ),
              logLabel: 'aviso_photo',
              alreadyCompressed: false,
            ),
          );
          nextSlot++;
        }

        final batch = await ChurchMediaUploadFacade.uploadBatchParallel(
          items: batchItems,
          timeoutPerItem: const Duration(seconds: 50),
          onItemProgress: (index, p) {
            final span = 0.54 / batchItems.length;
            _report(onUploadProgress, 0.20 + span * index + p * span);
          },
          onBatchProgress: (done, total) {
            if (total <= 0) return;
            _report(onUploadProgress, 0.20 + 0.54 * (done / total));
          },
        );
        final batchErr = ChurchMediaUploadFacade.firstBatchError(batch);
        if (batchErr != null) throw batchErr;

        for (final item in batch) {
          final uploaded = item.result;
          if (uploaded == null) continue;
          uploadedPaths.add(uploaded.storagePath);
          final url = sanitizeImageUrl(uploaded.downloadUrl);
          if (isValidImageUrl(url)) {
            existingUrls = dedupeImageRefsByStorageIdentity([
              ...existingUrls,
              url,
            ]);
          }
        }
        uploadedCount = uploadedPaths.length;
      }
      ChurchPublishFlowLog.uploadOk('$postType $docId ($uploadedCount fotos)');
      logFirebasePublishPhase(
        'linear_upload_ok',
        '$postType path=${docRef.path} tenant=$churchId uploaded=$uploadedCount',
      );
      _report(onUploadProgress, 0.74);
      if (uploadedCount == 0) {
        throw StateError(
          'Não foi possível enviar as fotos para o Storage. '
          'Verifique a rede e toque em «Tentar novamente».',
        );
      }
      if (isEvento && alignedThumbUrls.isEmpty) {
        final thumbFutures = alignedThumbPaths.map(
          (tp) => EcoFireFeedPublishService.refsToPlayableUrls([tp]),
        );
        final thumbResults = await Future.wait(thumbFutures, eagerError: false);
        for (final tu in thumbResults) {
          if (tu.isNotEmpty) alignedThumbUrls.add(tu.first);
        }
      }
    }

    final allPaths = dedupeImageRefsByStorageIdentity([
      ...existingPaths,
      ...uploadedPaths,
    ]);

    if (hasNewPhotos && uploadedPaths.isNotEmpty) {
      // Happy path CT: putData já confirmou o objeto — NÃO bloquear em getMetadata
      // (era o travão ~74–88% «A gravar evento…» na Web).
      unawaited(
        ChurchStorageMetadataVerify.assertAllExist(
          uploadedPaths,
          timeout: const Duration(seconds: 8),
          maxAttempts: 2,
        ).catchError((Object e) {
          debugPrint('feed metadata verify (background): $e');
        }),
      );
    }

    final aspectRatio = _aspectRatioFromPayload(corePayload);
    final payload = Map<String, dynamic>.from(corePayload);
    final galleryUrls = dedupeImageRefsByStorageIdentity(existingUrls);
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
        allUrls: galleryUrls,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        allowDeleteSentinels: !isNewDoc,
        imageVariants: null,
      ),
    );
    if (alignedThumbUrls.isNotEmpty) {
      final thumbOnly = dedupeImageRefsByStorageIdentity(alignedThumbUrls);
      if (thumbOnly.isNotEmpty) {
        payload['thumbUrl'] = thumbOnly.first;
        payload['thumbUrls'] = thumbOnly;
      }
    }
    await _applyCanonicalVideoDisplayFields(
      payload: payload,
      videoStoragePath: videoStoragePath,
    );
    if (galleryUrls.isNotEmpty) {
      final first = galleryUrls.first;
      payload['fotos'] = galleryUrls;
      payload['imageUrl'] = first;
      payload['imageUrls'] = galleryUrls;
      payload['defaultImageUrl'] = first;
      payload['imagemUrl'] = first;
      payload['imagem_url'] = first;
    }
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';
    payload['publicSite'] = publicSite;

    _report(onUploadProgress, 0.78);
    logFirebasePublishPhase(
      'linear_firestore_before_save',
      '$postType path=${docRef.path} tenant=$churchId',
    );
    await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
    await PublicationEngine.saveStrictPublished(
      docRef: docRef,
      tenantId: churchId,
      kind: kind,
      payload: payload,
      isNewDoc: isNewDoc,
      onProgress: onUploadProgress,
    );
    if (isEvento) {
      // Mirror legado em background — não segurar o progresso em ~78–88%.
      unawaited(
        _mirrorEventoToLegacyEventsCollection(
          churchId: churchId,
          docId: docId,
          payload: payload,
        ),
      );
    }

    // Verify em background — não segurar a UI em 78–88%.
    unawaited(
      _verifyFeedDocPublished(
        docRef: docRef,
        isEvento: isEvento,
      ).catchError((Object e) {
        debugPrint('feed doc verify (background): $e');
      }),
    );
    logFirebasePublishPhase(
      'linear_firestore_saved',
      '$postType path=${docRef.path} tenant=$churchId',
    );
    _report(onUploadProgress, 0.88);

    // Agenda/calendário em background — não segurar UI em ~88% (Web).
    if (isEvento && syncAgenda) {
      final start = eventStartAt ?? _startAtFromPayload(payload);
      if (start != null) {
        unawaited(
          ChurchFeedAgendaSyncService.upsertForEvento(
            tenantId: churchId,
            eventoId: docId,
            title: (payload['title'] ?? '').toString(),
            description: (payload['text'] ?? '').toString(),
            startAt: start,
            location: location,
            category: agendaCategory ?? 'evento_social',
            colorHex: agendaColorHex ?? '#E11D48',
          )
              .timeout(
                kIsWeb
                    ? const Duration(seconds: 12)
                    : const Duration(seconds: 30),
              )
              .catchError((Object e) {
            debugPrint('EVENTOS agenda sync (background): $e');
          }),
        );
      }
    } else if (!isEvento && syncCalendar) {
      final refDate = calendarDate ?? _validUntilFromPayload(payload);
      if (refDate != null) {
        unawaited(
          ChurchFeedAgendaSyncService.upsertForAviso(
            tenantId: churchId,
            avisoId: docId,
            title: (payload['title'] ?? '').toString(),
            description: (payload['text'] ?? '').toString(),
            referenceDate: refDate,
          ).catchError((Object e) {
            debugPrint('AVISOS calendar sync (background): $e');
          }),
        );
      }
    }

    _report(onUploadProgress, 0.92);
    PublicationEngine.scheduleDistribution(
      tenantId: churchId,
      kind: kind,
      postId: docId,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      phase: PublicationDistributionPhase.afterMediaFinalized,
    );
    logFirebasePublishPhase(
      'linear_publish_ok',
      '$postType path=${docRef.path} tenant=$churchId',
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

    _report(onUploadProgress, 1.0);

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

  static Future<void> _mirrorEventoToLegacyEventsCollection({
    required String churchId,
    required String docId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await firebaseDefaultFirestore
          .collection(ChurchDataPaths.rootCollection)
          .doc(churchId)
          .collection(ChurchDataPaths.legacyEventosEn)
          .doc(docId)
          .set(Map<String, dynamic>.from(payload), SetOptions(merge: true));
    } catch (e) {
      debugPrint('EVENTOS mirror legacy events failed: $e');
    }
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

  static Future<void> _verifyFeedDocPublished({
    required DocumentReference<Map<String, dynamic>> docRef,
    required bool isEvento,
  }) async {
    Future<void> verify() async {
      if (isEvento) {
        await EventosPublishVerificationService.verifyDocumentExists(
          docRef,
          preferServer: !kIsWeb,
        );
      } else {
        await AvisosPublishVerificationService.verifyDocumentExists(
          docRef,
          preferServer: !kIsWeb,
        );
      }
    }

    if (kIsWeb) {
      try {
        await verify().timeout(const Duration(seconds: 10));
      } catch (_) {
        // CF Admin SDK já gravou — não bloquear por lag de leitura web.
      }
      return;
    }
    await verify();
  }

  static Future<void> _applyCanonicalVideoDisplayFields({
    required Map<String, dynamic> payload,
    String? videoStoragePath,
  }) async {
    final path = (videoStoragePath ?? '').trim();
    if (path.isEmpty) return;

    payload['videoPath'] = path;
    payload['videoStoragePath'] = path;

    try {
      final videoUrls = await EcoFireFeedPublishService.refsToPlayableUrls([path]);
      final videoUrl = videoUrls.isNotEmpty ? sanitizeImageUrl(videoUrls.first) : '';
      if (videoUrl.isNotEmpty) {
        payload['videoUrl'] = videoUrl;
        payload['mediaUrl'] = videoUrl;
      }

      String thumbStoragePath = '';
      final directThumbPath = (payload['thumbStoragePath'] ?? '').toString().trim();
      if (directThumbPath.isNotEmpty) {
        thumbStoragePath = directThumbPath;
      } else {
        final thumbPaths = payload['thumbStoragePaths'];
        if (thumbPaths is List && thumbPaths.isNotEmpty) {
          thumbStoragePath = (thumbPaths.first ?? '').toString().trim();
        }
      }

      String thumbUrl = '';
      if (thumbStoragePath.isNotEmpty) {
        final thumbUrls =
            await EcoFireFeedPublishService.refsToPlayableUrls([thumbStoragePath]);
        if (thumbUrls.isNotEmpty) {
          thumbUrl = sanitizeImageUrl(thumbUrls.first);
          payload['thumbUrl'] = thumbUrl;
          payload['thumbUrls'] = [thumbUrl];
          payload['thumbStoragePath'] = thumbStoragePath;
        }
      }

      payload['videos'] = [
        {
          if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
          'videoStoragePath': path,
          'storagePath': path,
          if (thumbStoragePath.isNotEmpty) 'thumbStoragePath': thumbStoragePath,
          if (thumbUrl.isNotEmpty) 'thumbUrl': thumbUrl,
        }
      ];
    } catch (_) {
      payload['videos'] = [
        {
          'videoStoragePath': path,
          'storagePath': path,
        }
      ];
    }
  }
}
