import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/immediate_storage_upload_guard.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Fotos do património — Storage slot fixo → `foto01`…`foto04` (sem chaves legadas).
abstract final class ImmediatePatrimonioPhotoAttach {
  ImmediatePatrimonioPhotoAttach._();

  static Future<void> ensureItemStub({
    required DocumentReference<Map<String, dynamic>> itemRef,
    required bool isNewItem,
    required String nome,
    required String categoria,
    required String status,
  }) async {
    if (!isNewItem) return;
    final n = nome.trim();
    final tid = itemRef.parent.parent?.id ?? '';
    await PatrimonioOfflineSync.set(
      ref: itemRef,
      tenantId: tid,
      merge: true,
      data: {
        'nome': n.isEmpty ? 'Rascunho' : n,
        'categoria': categoria,
        'status': status,
        EntityPublishStatus.photoUploadStateField:
            EntityPublishStatus.uploading,
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<String?> uploadSingleSlot({
    required String tenantId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
    required DocumentReference<Map<String, dynamic>> itemRef,
    List<String> existingUrls = const [],
    List<String> existingPaths = const [],
  }) async {
    try {
      await ImmediateStorageUploadGuard.ensureReady(debugLabel: 'patrimonio_photo');
      await ImmediateMediaWarm.warmPatrimonio();

      await FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
        tenantId: tenantId,
        itemDocId: itemDocId,
        slot: slotIndex,
      );

      final result = await PatrimonioMediaUpload.uploadGalleryPhoto(
        churchId: tenantId,
        itemDocId: itemDocId,
        slotIndex: slotIndex,
        rawBytes: rawBytes,
        skipPrepare: true,
      );
      final path = result.storagePath;
      final url = sanitizeImageUrl(result.downloadUrl);
      if (url.isEmpty) {
        throw StateError('Upload do património não devolveu URL.');
      }

      final slotUrls = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
      final slotPaths = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
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
      if (slotIndex >= 0 && slotIndex < PatrimonioPhotoFields.maxPhotos) {
        slotUrls[slotIndex] = url;
        slotPaths[slotIndex] = path;
      }

      final patch = <String, dynamic>{
        EntityPublishStatus.photoUploadStateField:
            EntityPublishStatus.published,
        'photoUploadError': FieldValue.delete(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      };
      PatrimonioPhotoFields.applyIndexedSlots(patch, slotUrls, slotPaths);

      await FirestoreWebGuard.runWithWebRecovery(
        () => itemRef.set(patch, SetOptions(merge: true)),
      );

      FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
        tenantId: tenantId,
        itemDocId: itemDocId,
      );

      return url;
    } catch (e, st) {
      ImmediateStorageUploadGuard.rethrowAsUserError(e, st);
    }
  }
}
