import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

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
    await runFirestorePublishWithRecovery<void>(() async {
      await itemRef.set(
        {
          'nome': n.isEmpty ? 'Rascunho' : n,
          'categoria': categoria,
          'status': status,
          'criadoEm': FieldValue.serverTimestamp(),
          'atualizadoEm': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<String?> uploadSingleSlot({
    required String tenantId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
  }) async {
    try {
      await ImmediateMediaWarm.warmPatrimonio();
      final path =
          ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemDocId, slotIndex);
      final result = await PatrimonioMediaUpload.uploadGalleryPhoto(
        storagePath: path,
        rawBytes: rawBytes,
      );
      return result.downloadUrl;
    } catch (_) {
      return null;
    }
  }
}
