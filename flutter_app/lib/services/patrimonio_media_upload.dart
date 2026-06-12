import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_media_upload.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';

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

/// Upload patrimônio — `igrejas/{churchId}/patrimonio/{itemId}/galeria_XX.webp`.
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 45);
  static const Duration batchTimeout = Duration(minutes: 3);

  /// Fotos já comprimidas no picker (WebP ~1024px) — evita reprocessar no save.
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

    final path = ChurchStorageLayout.patrimonioPhotoPath(cid, iid, slotIndex);

    final Future<String> uploadFuture;
    if (skipPrepare) {
      uploadFuture = EcoFireMediaUpload.uploadPreparedWebp(
        storagePath: path,
        bytes: rawBytes,
        onProgress: onProgress,
      );
    } else {
      uploadFuture = EcoFireMediaUpload.uploadBytes(
        storagePath: path,
        bytes: rawBytes,
        contentType: 'image/webp',
        profile: EcoFireMediaProfile.patrimonio,
        onProgress: onProgress,
      );
    }

    final url = await uploadFuture.timeout(
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

  /// Até 4 fotos em sequência — evita deadlock do 5.º slot e garante conclusão.
  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosSequential({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    void Function(double batchProgress)? onBatchProgress,
    bool skipPrepare = true,
  }) async {
    if (images.isEmpty) return const [];
    final count = images.length.clamp(0, kMaxPatrimonioPhotosPerItem - startSlot);
    if (count <= 0) return const [];

    final results = <PatrimonioGalleryUploadResult>[];
    for (var i = 0; i < count; i++) {
      final slot = startSlot + i;
      onBatchProgress?.call(i / count);
      final r = await uploadGalleryPhoto(
        churchId: churchId,
        itemDocId: itemDocId,
        slotIndex: slot,
        rawBytes: images[i],
        skipPrepare: skipPrepare,
        onProgress: (slotP) {
          onBatchProgress?.call((i + slotP) / count);
        },
      );
      results.add(r);
    }
    onBatchProgress?.call(1.0);
    return results;
  }
}
