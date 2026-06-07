import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/immediate_storage_upload_guard.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';

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
  }) async {
    try {
      await ImmediateStorageUploadGuard.ensureReady(debugLabel: 'patrimonio_photo');
      await ImmediateMediaWarm.warmPatrimonio();
      final path =
          ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemDocId, slotIndex);
      final result = await PatrimonioMediaUpload.uploadGalleryPhoto(
        storagePath: path,
        rawBytes: rawBytes,
        thumbStoragePath: PatrimonioMediaUpload.thumbPathForSlot(
          tenantId: tenantId,
          itemDocId: itemDocId,
          slotIndex: slotIndex,
        ),
      );
      final url = result.downloadUrl.trim();
      if (url.isEmpty) {
        throw StateError('Upload do património não devolveu URL.');
      }
      return url;
    } catch (e, st) {
      ImmediateStorageUploadGuard.rethrowAsUserError(e, st);
    }
  }
}
