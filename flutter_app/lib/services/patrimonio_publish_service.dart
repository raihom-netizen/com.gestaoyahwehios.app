import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Patrimônio Ecofire — Storage (4 fotos) → URLs → Firestore **uma vez** (`foto01`…`foto04`).
abstract final class PatrimonioPublishService {
  PatrimonioPublishService._();

  static const String photoUploadStateField =
      EntityPublishStatus.photoUploadStateField;

  /// Entrada pública — online linear; offline/rede fraca → fila silenciosa.
  static Future<void> publish({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    Map<int, Uint8List> uploadsBySlot = const {},
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    List<Uint8List> newImages = const [],
    int startSlot = 0,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    String? userUid,
    void Function(double progress)? onUploadProgress,
  }) async {
    final igrejaId = PatrimonioPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: igrejaId,
      itemId: itemId,
    );

    try {
      await publishLinear(
        igrejaId: igrejaId,
        itemId: itemId,
        docRef: docRef,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        uploadsBySlot: uploadsBySlot,
        indexedSlotUrls: indexedSlotUrls,
        indexedSlotPaths: indexedSlotPaths,
        newImages: newImages,
        startSlot: startSlot,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
        onUploadProgress: onUploadProgress,
      );
    } catch (e) {
      if (!EcoFireResilientPublish.shouldQueueSilently(e)) rethrow;
      await EcoFireResilientPublish.queuePatrimonioPublish(
        churchId: igrejaId,
        itemId: itemId,
        docRef: docRef,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        uploadsBySlot: uploadsBySlot,
        indexedSlotUrls: indexedSlotUrls,
        indexedSlotPaths: indexedSlotPaths,
        newImages: newImages,
        startSlot: startSlot,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
      );
      EcoFireResilientPublish.scheduleSync(reason: 'patrimonio_queued');
    }
  }

  /// Fluxo síncrono — **nunca** deixa `uploading` se Storage terminou.
  static Future<void> publishLinear({
    required String igrejaId,
    required String itemId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    Map<int, Uint8List> uploadsBySlot = const {},
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    List<Uint8List> newImages = const [],
    int startSlot = 0,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    void Function(double progress)? onUploadProgress,
  }) async {
    await DirectStorageUrlPublish.ensureReady();

    unawaited(
      PatrimonioPublishVerificationService.logPublishPhase(
        phase: 'before',
        igrejaId: igrejaId,
        itemId: itemId,
        nome: (corePayload['nome'] ?? '').toString(),
      ),
    );

    onUploadProgress?.call(0.03);

    var slotUrls = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
    var slotPaths = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');

    if (indexedSlotUrls.length >= PatrimonioPhotoFields.maxPhotos) {
      for (var i = 0; i < PatrimonioPhotoFields.maxPhotos; i++) {
        slotUrls[i] = sanitizeImageUrl(indexedSlotUrls[i]);
        slotPaths[i] = i < indexedSlotPaths.length
            ? indexedSlotPaths[i].trim()
            : '';
      }
    } else {
      for (var i = 0;
          i < existingUrls.length && i < PatrimonioPhotoFields.maxPhotos;
          i++) {
        slotUrls[i] = sanitizeImageUrl(existingUrls[i]);
      }
      for (var i = 0;
          i < existingPaths.length && i < PatrimonioPhotoFields.maxPhotos;
          i++) {
        slotPaths[i] = existingPaths[i].trim();
      }
    }

    final uploadedPaths = <String>[];

    if (uploadsBySlot.isNotEmpty) {
      final slots = uploadsBySlot.keys.toList()..sort();
      final total = slots.length;

      await Future.wait(
        slots.map(
          (slot) => FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: igrejaId,
            itemDocId: itemId,
            slot: slot,
          ),
        ),
      );

      onUploadProgress?.call(0.06);

      List<PatrimonioGalleryUploadResult> uploaded;
      try {
        uploaded = await FirebaseBootstrapService.runGuarded(
          () => Future.wait(
            slots.map((slot) async {
              final bytes = uploadsBySlot[slot];
              if (bytes == null || bytes.isEmpty) {
                throw StateError('Foto do slot $slot está vazia.');
              }
              if (slot < 0 || slot >= PatrimonioPhotoFields.maxPhotos) {
                throw StateError('Slot de foto inválido ($slot).');
              }
              return PatrimonioMediaUpload.uploadGalleryPhoto(
                churchId: igrejaId,
                itemDocId: itemId,
                slotIndex: slot,
                rawBytes: bytes,
              );
            }),
          ),
          debugLabel: 'patrimonio_publish_slots',
        );
      } catch (e, st) {
        if (CrashlyticsService.shouldReport(e)) {
          unawaited(
            CrashlyticsService.record(e, st, reason: 'patrimonio_publish_slots'),
          );
        }
        rethrow;
      }

      for (var i = 0; i < uploaded.length; i++) {
        final r = uploaded[i];
        slotUrls[r.slotIndex] = sanitizeImageUrl(r.downloadUrl);
        slotPaths[r.slotIndex] = r.storagePath;
        uploadedPaths.add(r.storagePath);
        onUploadProgress?.call(0.06 + ((i + 1) / total) * 0.78);
      }

      if (uploadedPaths.isNotEmpty) {
        await PatrimonioPublishVerificationService.verifyStorageMetadata(
          photoPaths: uploadedPaths,
          timeout: const Duration(seconds: 12),
          maxAttempts: 4,
        );
      }
    } else {
      final maxNew = (kMaxPatrimonioPhotosPerItem - startSlot)
          .clamp(0, kMaxPatrimonioPhotosPerItem);
      final batch = newImages.take(maxNew).toList(growable: false);

      if (batch.isNotEmpty) {
        for (var j = 0; j < batch.length; j++) {
          await FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: igrejaId,
            itemDocId: itemId,
            slot: startSlot + j,
          );
        }
        onUploadProgress?.call(0.06);

        final uploaded = await PatrimonioMediaUpload.uploadGalleryPhotosParallel(
          churchId: igrejaId,
          itemDocId: itemId,
          images: batch,
          startSlot: startSlot,
          maxParallel: 4,
          onBatchProgress: (p) => onUploadProgress?.call(0.06 + p * 0.78),
        );

        if (uploaded.length != batch.length) {
          throw StateError(
            'Envio incompleto: ${uploaded.length}/${batch.length} fotos no Storage.',
          );
        }

        for (final r in uploaded) {
          final idx = r.slotIndex;
          if (idx >= 0 && idx < PatrimonioPhotoFields.maxPhotos) {
            slotUrls[idx] = sanitizeImageUrl(r.downloadUrl);
            slotPaths[idx] = r.storagePath;
          }
        }

        await PatrimonioPublishVerificationService.verifyStorageMetadata(
          photoPaths: uploaded.map((e) => e.storagePath),
          timeout: const Duration(seconds: 12),
          maxAttempts: 4,
        );
      }
    }

    // Remove slots vazios no Storage acima da contagem final.
    var finalCount = 0;
    for (var i = PatrimonioPhotoFields.maxPhotos - 1; i >= 0; i--) {
      if (slotUrls[i].isNotEmpty) {
        finalCount = i + 1;
        break;
      }
    }
    for (var slot = finalCount; slot < PatrimonioPhotoFields.maxPhotos; slot++) {
      await FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
        tenantId: igrejaId,
        itemDocId: itemId,
        slot: slot,
      );
    }

    await FirebaseStorageCleanupService.deleteLegacyPatrimonioGaleriaInItemFolder(
      tenantId: igrejaId,
      itemDocId: itemId,
    );

    onUploadProgress?.call(0.88);

    final payload = Map<String, dynamic>.from(corePayload);
    PatrimonioPhotoFields.applyIndexedSlots(payload, slotUrls, slotPaths);
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.published;
    payload['photoUploadError'] = FieldValue.delete();
    payload['publishState'] = FieldValue.delete();
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) {
      payload['criadoEm'] = FieldValue.serverTimestamp();
    }

    onUploadProgress?.call(0.92);

    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException(
          'Gravação no Firestore demorou demais. Verifique a rede.',
        ),
      ),
    );

    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef)
        .timeout(const Duration(seconds: 20));

    onUploadProgress?.call(1.0);

    unawaited(
      PatrimonioPublishVerificationService.logPublishPhase(
        phase: 'after',
        igrejaId: igrejaId,
        itemId: itemId,
        nome: (corePayload['nome'] ?? '').toString(),
        storagePaths: slotPaths.where((p) => p.trim().isNotEmpty).toList(),
      ),
    );

    YahwehFlowLog.patrimonioSuccess();
    FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
      tenantId: igrejaId,
      itemDocId: itemId,
    );
    unawaited(
      ModuleMediaOutboxService.clearPatrimonio(
        tenantId: igrejaId,
        itemId: itemId,
      ),
    );
  }

  /// Metadados sem fotos novas.
  static Future<void> publishMetadataOnly({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    String? userUid,
  }) async {
    final igrejaId = PatrimonioPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: igrejaId,
      itemId: itemId,
    );
    final payload = Map<String, dynamic>.from(corePayload);
    if (indexedSlotUrls.length >= PatrimonioPhotoFields.maxPhotos) {
      PatrimonioPhotoFields.applyIndexedSlots(
        payload,
        indexedSlotUrls,
        indexedSlotPaths,
      );
    } else {
      final urls = existingUrls
          .map((e) => sanitizeImageUrl(e))
          .where((e) => e.isNotEmpty)
          .toList();
      if (urls.isNotEmpty || existingPaths.isNotEmpty) {
        PatrimonioPhotoFields.applyToPayload(payload, urls, existingPaths);
      }
    }
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.published;
    payload['photoUploadError'] = FieldValue.delete();
    payload['publishState'] = FieldValue.delete();
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
      ),
    );
    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
  }

  /// Metadados imediatos com fotos pendentes — UI fecha; upload continua em background.
  static Future<void> publishMetadataWithPendingUploads({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    String? userUid,
  }) async {
    final igrejaId = PatrimonioPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: igrejaId,
      itemId: itemId,
    );
    final payload = Map<String, dynamic>.from(corePayload);
    if (indexedSlotUrls.length >= PatrimonioPhotoFields.maxPhotos) {
      PatrimonioPhotoFields.applyIndexedSlots(
        payload,
        indexedSlotUrls,
        indexedSlotPaths,
      );
    }
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.uploading;
    payload['publishState'] = EntityPublishStatus.uploading;
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
      ),
    );
    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
  }

  /// Repara doc preso em `uploading` — lê URLs do Storage e grava Firestore.
  static Future<void> repairFromStorage({
    required String churchId,
    required String itemId,
    Map<String, dynamic>? corePayload,
  }) async {
    final cid = churchId.trim();
    final iid = itemId.trim();
    if (cid.isEmpty || iid.isEmpty) return;

    await FirebaseBootstrapService.ensureStorageAlwaysLinked(refreshAuthToken: true);

    final urls = <String>[];
    final paths = <String>[];
    for (var slot = 0; slot < PatrimonioPhotoFields.maxPhotos; slot++) {
      final path = PatrimonioPublishVerificationService.photoStoragePath(
        igrejaId: cid,
        itemId: iid,
        slot: slot,
      );
      try {
        final url = await firebaseDefaultStorage.ref(path).getDownloadURL();
        if (url.trim().isNotEmpty) {
          paths.add(path);
          urls.add(sanitizeImageUrl(url));
        }
      } catch (_) {}
    }
    if (urls.isEmpty) return;

    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: cid,
      itemId: iid,
    );
    final payload = Map<String, dynamic>.from(corePayload ?? {});
    PatrimonioPhotoFields.applyToPayload(payload, urls, paths);
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.published;
    payload['photoUploadError'] = FieldValue.delete();
    payload['publishState'] = FieldValue.delete();
    payload['atualizadoEm'] = FieldValue.serverTimestamp();

    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: cid,
      collection: 'patrimonio',
      docId: iid,
      data: payload,
      isNewDoc: false,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: true)),
      ),
    );
  }
}
