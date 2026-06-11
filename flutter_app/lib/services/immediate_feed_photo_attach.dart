import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/immediate_storage_upload_guard.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Anexa fotos de aviso/evento ao Storage **antes** de «Publicar» (padrão Controle Total).
abstract final class ImmediateFeedPhotoAttach {
  ImmediateFeedPhotoAttach._();

  /// Rascunho mínimo para o `postId` existir no Storage/Firestore.
  static Future<void> ensureDraftPost({
    required DocumentReference<Map<String, dynamic>> docRef,
    required bool isNewDoc,
    required String tenantId,
    required String postType,
    String title = '',
  }) async {
    if (!isNewDoc) return;
    final t = title.trim();
    await runFirestorePublishWithRecovery<void>(() async {
      await docRef.set(
        {
          'publishState': MuralFastPublishService.stateDraft,
          'type': postType,
          'tenantId': tenantId,
          if (t.isNotEmpty) 'title': t,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Envia uma foto para o slot; devolve URL pública (erro visível se Firebase/Storage falhar).
  static Future<String?> uploadSingleSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
  }) async {
    try {
      await ImmediateStorageUploadGuard.ensureReady(debugLabel: 'feed_photo_slot');
      await ImmediateMediaWarm.warmFeed();
      final slot = await EcoFireFeedPublishService.uploadPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        slotIndex: slotIndex,
        bytes: bytes,
        localPath: localPath,
      );
      if (slot.fullUrl.isEmpty) {
        throw StateError('Upload da foto não devolveu URL.');
      }
      return slot.fullUrl;
    } catch (e, st) {
      debugPrint('ImmediateFeedPhotoAttach.uploadSingleSlot: $e\n$st');
      ImmediateStorageUploadGuard.rethrowAsUserError(e, st);
    }
  }
}
