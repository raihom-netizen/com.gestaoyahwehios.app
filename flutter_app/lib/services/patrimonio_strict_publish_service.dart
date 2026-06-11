import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
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
    List<String> existingUrls = const [],
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
    final allUrls = existingUrls
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .toList();

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
            );
          }),
        );
        for (final r in chunk) {
          allPaths.add(r.storagePath);
          allUrls.add(sanitizeImageUrl(r.downloadUrl));
        }
      }

      await PatrimonioPublishVerificationService.verifyStorageMetadata(
        photoPaths: allPaths.skip(existingPaths.length),
      );
    }

    final payload = Map<String, dynamic>.from(corePayload);
    _applyPhotoFields(payload, allPaths, allUrls);
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
    List<String> existingUrls = const [],
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
    final urls = existingUrls
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .toList();
    if (existingPaths.isNotEmpty || urls.isNotEmpty) {
      _applyPhotoFields(payload, existingPaths, urls);
    }
    payload['ativo'] = true;
    payload[photoUploadStateField] = statePublished;
    payload['photoUploadError'] = FieldValue.delete();
    payload['atualizadoEm'] = FieldValue.serverTimestamp();
    if (isNewDoc) payload['criadoEm'] = FieldValue.serverTimestamp();

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload, SetOptions(merge: !isNewDoc)),
    );
    await PatrimonioPublishVerificationService.verifyDocumentExists(docRef);
  }

  static void _applyPhotoFields(
    Map<String, dynamic> payload,
    List<String> paths,
    List<String> urls,
  ) {
    if (paths.isNotEmpty) {
      payload['fotos'] = paths;
      payload['fotoStoragePaths'] = paths;
      payload['imageStoragePath'] = paths.first;
      payload['fotoPath'] = paths.first;
      payload['fotoPrincipalPath'] = paths.first;
      if (paths.length > 1) {
        payload['gallery'] = paths.sublist(1);
      } else {
        payload['gallery'] = FieldValue.delete();
      }
    }
    if (urls.isNotEmpty) {
      payload['fotoUrls'] = urls;
      payload['imageUrl'] = urls.first;
      payload['fotoUrl'] = urls.first;
      payload['thumbnail'] = urls.first;
      payload['fotoPrincipalThumbPath'] = FieldValue.delete();
      payload['thumbStoragePath'] = FieldValue.delete();
    }
  }
}
