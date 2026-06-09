import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Patrimônio — upload validado → Firestore → confirmação (sem falso sucesso).
abstract final class PatrimonioStrictPublishService {
  PatrimonioStrictPublishService._();

  static const String photoUploadStateField =
      EntityPublishStatus.photoUploadStateField;
  static const String statePublished = EntityPublishStatus.published;

  /// Upload fotos → validar Storage → gravar Firestore → confirmar doc.
  static Future<void> publish({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<Uint8List> newImages,
    required int startSlot,
    List<String> existingPaths = const [],
    String? userUid,
  }) async {
    final igrejaId = await PatrimonioPublishVerificationService
        .resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );

    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: igrejaId,
      itemId: itemId,
    );

    await PatrimonioPublishVerificationService.logPublishPhase(
      phase: 'before',
      igrejaId: igrejaId,
      itemId: itemId,
      nome: (corePayload['nome'] ?? '').toString(),
    );

    final allPaths = List<String>.from(existingPaths);
    final thumbPaths = <String>[];

    if (newImages.isNotEmpty) {
      await Future.wait(
        List.generate(
          newImages.length,
          (j) => FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
            tenantId: igrejaId,
            itemDocId: itemId,
            slot: startSlot + j,
          ),
        ),
      );

      const uploadConcurrency = 3;
      for (var batchStart = 0;
          batchStart < newImages.length;
          batchStart += uploadConcurrency) {
        final batchEnd =
            math.min(batchStart + uploadConcurrency, newImages.length);
        final chunk = await Future.wait(
          List.generate(batchEnd - batchStart, (k) {
            final j = batchStart + k;
            final slot = startSlot + j;
            final path = PatrimonioPublishVerificationService.photoStoragePath(
              igrejaId: igrejaId,
              itemId: itemId,
              slot: slot,
            );
            return PatrimonioMediaUpload.uploadGalleryPhoto(
              storagePath: path,
              rawBytes: newImages[j],
              thumbStoragePath: PatrimonioMediaUpload.thumbPathForSlot(
                tenantId: igrejaId,
                itemDocId: itemId,
                slotIndex: slot,
              ),
            );
          }),
        );
        for (final r in chunk) {
          allPaths.add(r.storagePath);
          final tp = r.thumbStoragePath?.trim() ?? '';
          if (tp.isNotEmpty) thumbPaths.add(tp);
        }
      }

      await PatrimonioPublishVerificationService.verifyStorageMetadata(
        photoPaths: allPaths.skip(existingPaths.length),
        thumbPaths: thumbPaths,
      );
    }

    final payload = Map<String, dynamic>.from(corePayload);
    payload['fotos'] = allPaths;
    payload['fotoStoragePaths'] = allPaths;
    if (allPaths.isNotEmpty) {
      payload['imageStoragePath'] = allPaths.first;
      payload['fotoPath'] = allPaths.first;
      payload['fotoPrincipalPath'] = allPaths.first;
      if (thumbPaths.isNotEmpty) {
        payload['fotoPrincipalThumbPath'] = thumbPaths.first;
        payload['thumbStoragePath'] = thumbPaths.first;
      }
      if (allPaths.length > 1) {
        payload['gallery'] = allPaths.sublist(1);
      } else {
        payload['gallery'] = FieldValue.delete();
      }
    }
    payload['ativo'] = true;
    payload[photoUploadStateField] = statePublished;
    payload['photoUploadError'] = FieldValue.delete();
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) {
      payload['criadoEm'] = FieldValue.serverTimestamp();
    }

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
    );

    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);

    await PatrimonioPublishVerificationService.logPublishPhase(
      phase: 'after',
      igrejaId: igrejaId,
      itemId: itemId,
      nome: (corePayload['nome'] ?? '').toString(),
      storagePaths: allPaths,
    );

    YahwehFlowLog.patrimonioSuccess();
    FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
      tenantId: igrejaId,
      itemDocId: itemId,
    );
  }

  /// Metadados sem fotos novas — só Firestore + confirmação.
  static Future<void> publishMetadataOnly({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    List<String> existingPaths = const [],
    String? userUid,
  }) async {
    final igrejaId = await PatrimonioPublishVerificationService
        .resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
      igrejaId: igrejaId,
      itemId: itemId,
    );
    final payload = Map<String, dynamic>.from(corePayload);
    if (existingPaths.isNotEmpty) {
      payload['fotos'] = existingPaths;
      payload['fotoStoragePaths'] = existingPaths;
      payload['imageStoragePath'] = existingPaths.first;
      payload['fotoPath'] = existingPaths.first;
      payload['fotoPrincipalPath'] = existingPaths.first;
      payload['fotoPrincipalThumbPath'] =
          PatrimonioMediaUpload.thumbPathForSlot(
        tenantId: igrejaId,
        itemDocId: itemId,
        slotIndex: 0,
      );
      if (existingPaths.length > 1) {
        payload['gallery'] = existingPaths.sublist(1);
      }
    }
    payload['ativo'] = true;
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
    );
    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
  }
}
