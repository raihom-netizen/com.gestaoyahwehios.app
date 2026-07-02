import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/services/ecofire_feed_photo_slot.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;

/// Upload de fotos de evento — `igrejas/{churchId}/eventos/{postId}/…`.
///
/// Pipeline único: [ChurchCentralStorageUpload] → URL https → Firestore.
abstract final class EventoMediaUpload {
  EventoMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);
  static const int maxParallelSlots = kMaxEventFeedPhotosPerPost;

  static Future<void> ensureUploadReady({bool requireAuth = true}) async {
    await DirectStorageUrlPublish.ensureReady(requireAuth: requireAuth);
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
    final uploaded = await ChurchCentralStorageUpload.uploadImageAtPath(
      storagePath: path,
      rawBytes: compressedBytes,
      logLabel: 'evento_template_cover',
      alreadyCompressed: true,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da capa do template demorou demais. Verifique a rede.',
      ),
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
    final cid = churchId.trim();
    final pid = postId.trim();
    if (cid.isEmpty || pid.isEmpty) {
      throw ArgumentError('churchId e postId são obrigatórios.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }

    EcoFireFlow.log('EVENTO_PHOTO slot $pid#$slotIndex');

    final uploaded = await ChurchCentralStorageUpload.uploadEventoPhoto(
      churchId: cid,
      postId: pid,
      slotIndex: slotIndex,
      rawBytes: rawBytes,
      alreadyCompressed: alreadyCompressed,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto ${slotIndex + 1} demorou demais. Verifique a rede.',
      ),
    );

    EcoFireFlow.log('EVENTO_PHOTO OK ${uploaded.storagePath}');
    return EcoFireFeedPhotoSlot(
      fullUrl: uploaded.downloadUrl,
      thumbUrl: uploaded.downloadUrl,
      fullPath: uploaded.storagePath,
      thumbPath: uploaded.storagePath,
    );
  }

  static Future<List<EcoFireFeedPhotoSlot>> uploadPhotoBatch({
    required String churchId,
    required String postId,
    required int startSlotIndex,
    required List<Uint8List> bytesList,
    bool alreadyCompressed = true,
    void Function(double progress)? onProgress,
  }) async {
    if (bytesList.isEmpty) return const [];

    final slots = List<EcoFireFeedPhotoSlot?>.filled(bytesList.length, null);
    var completed = 0;

    Future<void> uploadOne(int i) async {
      slots[i] = await uploadPhotoSlot(
        churchId: churchId,
        postId: postId,
        slotIndex: startSlotIndex + i,
        rawBytes: bytesList[i],
        alreadyCompressed: alreadyCompressed,
      );
      completed++;
      onProgress?.call(completed / bytesList.length);
    }

    for (var start = 0; start < bytesList.length; start += maxParallelSlots) {
      final end = (start + maxParallelSlots).clamp(0, bytesList.length);
      await Future.wait([
        for (var i = start; i < end; i++) uploadOne(i),
      ]);
    }

    return slots.whereType<EcoFireFeedPhotoSlot>().toList();
  }
}
