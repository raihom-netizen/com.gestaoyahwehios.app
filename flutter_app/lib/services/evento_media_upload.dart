import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/ecofire_feed_photo_slot.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;

/// Upload de fotos de evento — padrão Controle Total (upload direto Storage).
abstract final class EventoMediaUpload {
  EventoMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 55);
  static const int maxParallelSlots = kMaxEventFeedPhotosPerPost;

  static Future<void> ensureUploadReady({bool requireAuth = true}) async {
    await ChurchMediaUploadFacade.ensureReady(requireAuth: requireAuth);
  }

  /// Capa de template — `igrejas/{id}/eventos/templates/{templateId}.jpg`.
  static Future<String> uploadTemplateCover({
    required String churchId,
    required String templateId,
    required Uint8List compressedBytes,
    void Function(double progress)? onProgress,
  }) async {
    final cid = churchId.trim();
    final tid = templateId.trim();
    if (cid.isEmpty || tid.isEmpty) {
      throw ArgumentError('churchId e templateId são obrigatórios.');
    }
    if (compressedBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    final path = ChurchStorageLayout.eventTemplateCoverPath(cid, tid);
    final uploaded = await ChurchMediaUploadFacade.uploadMidia(
      bytes: compressedBytes,
      storagePath: path,
      logLabel: 'evento_template_cover',
      alreadyCompressed: true,
      onProgress: onProgress,
      timeout: uploadTimeout,
    );
    return uploaded.downloadUrl;
  }

  static Future<EcoFireFeedPhotoSlot> uploadPhotoSlot({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List rawBytes,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) async {
    final slots = await uploadPhotoBatch(
      churchId: churchId,
      postId: postId,
      startSlotIndex: slotIndex,
      bytesList: [rawBytes],
      alreadyCompressed: alreadyCompressed,
      onProgress: onProgress,
    );
    if (slots.isEmpty) {
      throw StateError('Upload da foto do evento falhou.');
    }
    return slots.first;
  }

  static Future<List<EcoFireFeedPhotoSlot>> uploadPhotoBatch({
    required String churchId,
    required String postId,
    required int startSlotIndex,
    required List<Uint8List> bytesList,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) async {
    if (bytesList.isEmpty) return const [];

    await ensureUploadReady();

    var nextSlot = startSlotIndex;
    final batchItems = <ChurchMediaUploadBatchItem>[];
    for (final raw in bytesList) {
      batchItems.add(
        ChurchMediaUploadBatchItem(
          bytes: raw,
          storagePath: ChurchStorageLayout.eventPostPhotoPath(
            churchId,
            postId,
            nextSlot,
          ),
          logLabel: 'evento_photo',
          alreadyCompressed: alreadyCompressed,
        ),
      );
      nextSlot++;
    }

    final batch = await ChurchMediaUploadFacade.uploadBatchParallel(
      items: batchItems,
      timeoutPerItem: uploadTimeout,
      onBatchProgress: (done, total) {
        if (total <= 0) return;
        onProgress?.call(done / total);
      },
    );
    final batchErr = ChurchMediaUploadFacade.firstBatchError(batch);
    if (batchErr != null) throw batchErr;

    final slots = <EcoFireFeedPhotoSlot>[];
    for (final item in batch) {
      final uploaded = item.result;
      if (uploaded == null) continue;
      EcoFireFlow.log('EVENTO_PHOTO OK ${uploaded.storagePath}');
      slots.add(
        EcoFireFeedPhotoSlot(
          fullUrl: uploaded.downloadUrl,
          thumbUrl: uploaded.downloadUrl,
          fullPath: uploaded.storagePath,
          thumbPath: uploaded.storagePath,
        ),
      );
    }
    return slots;
  }
}
