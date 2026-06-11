import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/immediate_storage_upload_guard.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Fotos do património no Storage antes de «Salvar» (padrão Controle Total).
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

      final path =
          ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemDocId, slotIndex);
      final result = await PatrimonioMediaUpload.uploadGalleryPhoto(
        storagePath: path,
        rawBytes: rawBytes,
      );
      final url = sanitizeImageUrl(result.downloadUrl);
      if (url.isEmpty) {
        throw StateError('Upload do património não devolveu URL.');
      }

      final paths = List<String>.from(existingPaths);
      final urls = existingUrls
          .map((e) => sanitizeImageUrl(e))
          .where((e) => e.isNotEmpty)
          .toList();
      while (paths.length < slotIndex) {
        paths.add('');
      }
      while (urls.length < slotIndex) {
        urls.add('');
      }
      if (paths.length == slotIndex) {
        paths.add(path);
        urls.add(url);
      } else if (slotIndex < paths.length) {
        paths[slotIndex] = path;
        urls[slotIndex] = url;
      } else {
        paths.add(path);
        urls.add(url);
      }
      final cleanPaths = paths.where((p) => p.trim().isNotEmpty).toList();
      final cleanUrls = urls.where((u) => u.trim().isNotEmpty).toList();

      await FirestoreWebGuard.runWithWebRecovery(
        () => itemRef.set(
          {
            'fotoStoragePaths': cleanPaths,
            'fotoUrls': cleanUrls,
            'fotos': cleanPaths,
            if (cleanPaths.isNotEmpty) ...{
              'imageStoragePath': cleanPaths.first,
              'fotoPath': cleanPaths.first,
              'fotoPrincipalPath': cleanPaths.first,
              'imageUrl': cleanUrls.first,
              'fotoUrl': cleanUrls.first,
            },
            EntityPublishStatus.photoUploadStateField:
                EntityPublishStatus.published,
            'photoUploadError': FieldValue.delete(),
            'atualizadoEm': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
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
