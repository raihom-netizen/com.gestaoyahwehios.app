import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/upload_bytes_core.dart';

/// Upload patrimônio — `igrejas/{churchId}/patrimonio/{itemId}/foto_1.jpg` … `foto_4.jpg`.
/// Retry directo (sem fila bloqueante) — evita travar em ~28% na 2.ª foto.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<PatrimonioGalleryUploadResult> uploadGalleryPhoto({
    required String churchId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
    bool skipPrepare = true,
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

    await FirebaseBootstrapService.ensureStorageAlwaysLinked(refreshAuthToken: true);

    final path = ChurchStorageLayout.patrimonioPhotoPath(cid, iid, slotIndex);

    final url = await uploadStoragePutDataWithRetry(
      storagePath: path,
      bytes: rawBytes,
      contentType: 'image/jpeg',
      maxAttempts: 4,
      useOfflineQueue: false,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto ${slotIndex + 1} demorou demais. Verifique a rede.',
      ),
    );

    return PatrimonioGalleryUploadResult(
      downloadUrl: url,
      storagePath: path,
      slotIndex: slotIndex,
    );
  }

  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosSequential({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    void Function(double batchProgress)? onBatchProgress,
    bool skipPrepare = true,
  }) async =>
      uploadGalleryPhotosParallel(
        churchId: churchId,
        itemDocId: itemDocId,
        images: images,
        startSlot: startSlot,
        onBatchProgress: onBatchProgress,
        skipPrepare: skipPrepare,
        maxParallel: 1,
      );

  /// Até [maxParallel] fotos em paralelo — mais rápido na Web e Android.
  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosParallel({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    void Function(double batchProgress)? onBatchProgress,
    bool skipPrepare = true,
    int maxParallel = 2,
  }) async {
    if (images.isEmpty) return const [];
    final count = images.length.clamp(0, kMaxPatrimonioPhotosPerItem - startSlot);
    if (count <= 0) return const [];

    final parallel = maxParallel.clamp(1, 3);
    final results = List<PatrimonioGalleryUploadResult?>.filled(count, null);
    var completed = 0;

    Future<void> uploadOne(int i) async {
      final slot = startSlot + i;
      results[i] = await uploadGalleryPhoto(
        churchId: churchId,
        itemDocId: itemDocId,
        slotIndex: slot,
        rawBytes: images[i],
        skipPrepare: skipPrepare,
      );
      completed++;
      onBatchProgress?.call(completed / count);
    }

    for (var start = 0; start < count; start += parallel) {
      final end = (start + parallel).clamp(0, count);
      await Future.wait([
        for (var i = start; i < end; i++) uploadOne(i),
      ]);
    }

    onBatchProgress?.call(1.0);
    return results.whereType<PatrimonioGalleryUploadResult>().toList();
  }
}

/// Resultado de upload de galeria — um ficheiro por slot na pasta do bem.
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
