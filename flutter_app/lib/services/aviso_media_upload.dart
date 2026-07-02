import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/services/ecofire_feed_photo_slot.dart';

/// Upload de fotos de aviso — `igrejas/{churchId}/avisos/{postId}/…`.
///
/// Pipeline único: [ChurchCentralStorageUpload] → URL https → Firestore.
abstract final class AvisoMediaUpload {
  AvisoMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 45);
  static const int maxParallelSlots = 5;

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

    EcoFireFlow.log('AVISO_PHOTO slot $pid#$slotIndex');

    final uploaded = await ChurchCentralStorageUpload.uploadAvisoPhoto(
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

    EcoFireFlow.log('AVISO_PHOTO OK ${uploaded.storagePath}');
    return EcoFireFeedPhotoSlot(
      fullUrl: uploaded.downloadUrl,
      thumbUrl: uploaded.downloadUrl,
      fullPath: uploaded.storagePath,
      thumbPath: uploaded.storagePath,
    );
  }

  /// Lote de até 5 fotos — paralelo seguro com [Future.wait].
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
