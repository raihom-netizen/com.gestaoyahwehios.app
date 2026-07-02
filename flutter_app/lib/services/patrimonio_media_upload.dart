import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// Upload patrimônio — `igrejas/{churchId}/patrimonio/{itemId}/foto_N.jpg`.
///
/// Pipeline único: [ChurchCentralStorageUpload] → URL https → Firestore.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<PatrimonioGalleryUploadResult> uploadGalleryPhoto({
    required String churchId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
    bool skipPrepare = false,
    bool ensureReady = true,
  }) async {
    final cid = churchId.trim();
    final iid = itemDocId.trim();
    if (cid.isEmpty || iid.isEmpty) {
      throw ArgumentError('churchId e itemDocId são obrigatórios.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    if (slotIndex < 0 || slotIndex >= kMaxPatrimonioPhotosPerItem) {
      throw StateError(
        'Slot de foto inválido ($slotIndex). Máximo: $kMaxPatrimonioPhotosPerItem fotos.',
      );
    }

    final path =
        ChurchStorageLayout.patrimonioPhotoPath(cid, iid, slotIndex);
    LegacyPathGuard.assertCanonicalStoragePath(
      path,
      context: 'patrimonio_photo',
    );

    try {
      final uploaded = await ChurchCentralStorageUpload.uploadPatrimonioPhoto(
        churchId: cid,
        itemDocId: iid,
        slotIndex: slotIndex,
        rawBytes: rawBytes,
        onProgress: onProgress,
      ).timeout(
        uploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload da foto ${slotIndex + 1} demorou demais. Verifique a rede.',
        ),
      );

      return PatrimonioGalleryUploadResult(
        downloadUrl: uploaded.downloadUrl,
        storagePath: uploaded.storagePath,
        slotIndex: slotIndex,
      );
    } catch (e, st) {
      unawaited(
        CrashlyticsService.record(e, st, reason: 'patrimonio_upload_$slotIndex'),
      );
      rethrow;
    }
  }

  /// Várias fotos em paralelo (máx. [maxParallel] simultâneas).
  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosParallel({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    int maxParallel = 4,
    void Function(double progress)? onBatchProgress,
  }) async {
    if (images.isEmpty) return const [];
    final cid = churchId.trim();
    final iid = itemDocId.trim();
    if (cid.isEmpty || iid.isEmpty) {
      throw ArgumentError('churchId e itemDocId são obrigatórios.');
    }

    final results = <PatrimonioGalleryUploadResult>[];
    var completed = 0;
    final total = images.length;
    final parallel = maxParallel.clamp(1, kMaxPatrimonioPhotosPerItem);

    for (var batchStart = 0; batchStart < images.length; batchStart += parallel) {
      final batchEnd = (batchStart + parallel).clamp(0, images.length);
      final batch = images.sublist(batchStart, batchEnd);
      final batchResults = await Future.wait(
        List.generate(batch.length, (i) {
          final slot = startSlot + batchStart + i;
          return uploadGalleryPhoto(
            churchId: cid,
            itemDocId: iid,
            slotIndex: slot,
            rawBytes: batch[i],
          );
        }),
      );
      for (final r in batchResults) {
        results.add(r);
        completed++;
        onBatchProgress?.call(completed / total);
      }
    }
    return results;
  }
}

class PatrimonioGalleryUploadResult {
  const PatrimonioGalleryUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.slotIndex,
  });

  final String downloadUrl;
  final String storagePath;
  final int slotIndex;
}
