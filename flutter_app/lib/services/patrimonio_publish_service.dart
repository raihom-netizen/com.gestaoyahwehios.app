import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart'
    show storageDownloadUrlOrNull;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Patrimônio Ecofire — Storage (5 fotos) → URLs → Firestore **uma vez** (`foto01`…`foto05`).
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
    await ChurchMediaUploadFacade.ensureReady();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

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

      // Controle Total: NÃO apagar slot antes do putData — overwrite no path
      // canónico; limpeza de legado só após Upload OK.
      onUploadProgress?.call(0.06);

      List<PatrimonioGalleryUploadResult> uploaded;
      try {
        Future<PatrimonioGalleryUploadResult> uploadSlot(int slot) async {
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
            alreadyCompressed: true,
          );
        }

        if (kIsWeb) {
          // Web: uploads com concorrência limitada (3 em paralelo).
          uploaded = <PatrimonioGalleryUploadResult>[];
          const maxConcurrent = 3;
          for (var i = 0; i < slots.length; i += maxConcurrent) {
            final batch = slots.sublist(
              i,
              [i + maxConcurrent, slots.length].reduce((a, b) => a < b ? a : b),
            );
            final results = await Future.wait(batch.map(uploadSlot));
            uploaded.addAll(results);
            onUploadProgress?.call(
              0.06 + (uploaded.length / total) * 0.78,
            );
          }
        } else {
          uploaded = await FirebaseBootstrapService.runGuarded(
            () => Future.wait(slots.map(uploadSlot)),
            debugLabel: 'patrimonio_publish_slots',
          );
        }
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
        unawaited(
          PatrimonioPublishVerificationService.verifyStorageMetadata(
            photoPaths: uploadedPaths,
            timeout: const Duration(seconds: 12),
            maxAttempts: 2,
          ).catchError((_) {}),
        );
      }

      // Após Storage OK: limpar só artefactos legado (webp/png/galeria_*) do slot.
      // O path canónico foto_N.jpg acaba de ser sobrescrito — não apagar de novo.
      FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
        tenantId: igrejaId,
        itemDocId: itemId,
      );
    } else {
      final maxNew = (kMaxPatrimonioPhotosPerItem - startSlot)
          .clamp(0, kMaxPatrimonioPhotosPerItem);
      final batch = newImages.take(maxNew).toList(growable: false);

      if (batch.isNotEmpty) {
        // CT: sem delete-before-upload; overwrite no path canónico.
        onUploadProgress?.call(0.06);

        final uploaded = await PatrimonioMediaUpload.uploadGalleryPhotosParallel(
          churchId: igrejaId,
          itemDocId: itemId,
          images: batch,
          startSlot: startSlot,
          maxParallel: 4,
          alreadyCompressed: true,
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

        unawaited(
          PatrimonioPublishVerificationService.verifyStorageMetadata(
            photoPaths: uploaded.map((e) => e.storagePath),
            timeout: const Duration(seconds: 12),
            maxAttempts: 2,
          ).catchError((_) {}),
        );

        FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
          tenantId: igrejaId,
          itemDocId: itemId,
        );
      }
    }

    // Remove Storage de qualquer slot vazio — paralelo.
    final emptySlotFutures = <Future<void>>[];
    for (var slot = 0; slot < PatrimonioPhotoFields.maxPhotos; slot++) {
      if (slotUrls[slot].trim().isEmpty) {
        slotPaths[slot] = '';
        emptySlotFutures.add(
          FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: igrejaId,
            itemDocId: itemId,
            slot: slot,
          ),
        );
      }
    }
    if (emptySlotFutures.isNotEmpty) {
      await Future.wait(emptySlotFutures, eagerError: false);
    }

    unawaited(
      FirebaseStorageCleanupService.deleteLegacyPatrimonioGaleriaInItemFolder(
        tenantId: igrejaId,
        itemDocId: itemId,
      ),
    );

    onUploadProgress?.call(0.88);

    final payload = Map<String, dynamic>.from(corePayload);
    PatrimonioPhotoFields.applyIndexedSlots(
      payload,
      slotUrls,
      slotPaths,
      allowDeleteSentinels: !isNewDoc,
    );
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.published;
    if (!isNewDoc) {
      payload['photoUploadError'] = FieldValue.delete();
      payload['publishState'] = FieldValue.delete();
    }
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) {
      payload['criadoEm'] = FieldValue.serverTimestamp();
    }

    onUploadProgress?.call(0.92);

    await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);

    final mergeWrite = FirestoreWriteGuard.effectiveSetMerge(
      merge: !isNewDoc,
      data: payload,
    );
    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: mergeWrite)),
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Gravação no Firestore demorou demais. Verifique a rede.',
        ),
      ),
    );

    unawaited(() async {
      try {
        await PatrimonioPublishVerificationService.verifyDocumentExists(docRef)
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
    }());

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
        allowDeleteSentinels: !isNewDoc,
      );
    } else {
      final urls = existingUrls
          .map((e) => sanitizeImageUrl(e))
          .where((e) => e.isNotEmpty)
          .toList();
      if (urls.isNotEmpty || existingPaths.isNotEmpty) {
        PatrimonioPhotoFields.applyToPayload(
          payload,
          urls,
          existingPaths,
          allowDeleteSentinels: !isNewDoc,
        );
      }
    }
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.published;
    if (!isNewDoc) {
      payload['photoUploadError'] = FieldValue.delete();
      payload['publishState'] = FieldValue.delete();
    }
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    final mergeMeta = FirestoreWriteGuard.effectiveSetMerge(
      merge: !isNewDoc,
      data: payload,
    );
    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: mergeMeta)),
      ),
    );
    unawaited(() async {
      try {
        await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
      } catch (_) {}
    }());
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
        allowDeleteSentinels: !isNewDoc,
      );
    }
    payload['churchId'] = igrejaId;
    payload['tenantId'] = igrejaId;
    payload['ativo'] = true;
    payload[photoUploadStateField] = EntityPublishStatus.uploading;
    payload['publishState'] = EntityPublishStatus.uploading;
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    final mergePending = FirestoreWriteGuard.effectiveSetMerge(
      merge: !isNewDoc,
      data: payload,
    );
    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: igrejaId,
      collection: 'patrimonio',
      docId: itemId,
      data: payload,
      isNewDoc: isNewDoc,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: mergePending)),
      ),
    );
    unawaited(() async {
      try {
        await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
      } catch (_) {}
    }());
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
    final futures = <Future<void>>[];
    final results = List<bool>.filled(PatrimonioPhotoFields.maxPhotos, false);
    final urlResults = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
    final pathResults = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
    for (var slot = 0; slot < PatrimonioPhotoFields.maxPhotos; slot++) {
      final path = PatrimonioPublishVerificationService.photoStoragePath(
        igrejaId: cid,
        itemId: iid,
        slot: slot,
      );
      futures.add(() async {
        try {
          final url = await storageDownloadUrlOrNull(
            firebaseDefaultStorage.ref(path),
          );
          if (url != null && url.trim().isNotEmpty) {
            results[slot] = true;
            pathResults[slot] = path;
            urlResults[slot] = sanitizeImageUrl(url);
          }
        } catch (_) {}
      }());
    }
    await Future.wait(futures, eagerError: false);
    for (var slot = 0; slot < PatrimonioPhotoFields.maxPhotos; slot++) {
      if (results[slot]) {
        paths.add(pathResults[slot]);
        urls.add(urlResults[slot]);
      }
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
