import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload patrimônio — `igrejas/{churchId}/patrimonio/{itemId}/foto_N.jpg`.
///
/// Compressão obrigatória + [UnifiedUploadService] (anti `firebase_core/no-app`).
abstract final class PatrimonioMediaUpload {
  PatrimonioMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<void> _ensureUploadReady() async {
    await EcoFireDirectFirebase.ensureForStoragePut();
  }

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

    if (ensureReady) {
      await _ensureUploadReady();
    }

    final path =
        ChurchStorageLayout.patrimonioPhotoPath(cid, iid, slotIndex);
    LegacyPathGuard.assertCanonicalStoragePath(
      path,
      context: 'patrimonio_photo',
    );

    final bytes = await _compressForUpload(rawBytes);

    final url = await UnifiedUploadService.uploadImage(
      storagePath: path,
      bytes: bytes,
      contentType: 'image/jpeg',
      module: YahwehUploadModule.generic,
      skipClientPrepare: true,
      onProgress: onProgress,
      maxAttempts: 4,
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

  /// Sempre comprime em isolate — nunca envia original ao Storage.
  static Future<Uint8List> _compressForUpload(Uint8List rawBytes) async {
    return MediaOptimizationService.optimizeForReceipt(rawBytes);
  }

  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosSequential({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    void Function(double batchProgress)? onBatchProgress,
    bool skipPrepare = false,
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

  /// Até [maxParallel] fotos em paralelo — [Future.wait] seguro via [runGuarded].
  static Future<List<PatrimonioGalleryUploadResult>> uploadGalleryPhotosParallel({
    required String churchId,
    required String itemDocId,
    required List<Uint8List> images,
    required int startSlot,
    void Function(double batchProgress)? onBatchProgress,
    bool skipPrepare = false,
    int maxParallel = 4,
  }) async {
    if (images.isEmpty) return const [];
    final count =
        images.length.clamp(0, kMaxPatrimonioPhotosPerItem - startSlot);
    if (count <= 0) return const [];

    await _ensureUploadReady();

    final parallel = maxParallel.clamp(1, 2);
    final results = List<PatrimonioGalleryUploadResult?>.filled(count, null);
    var completed = 0;

    Future<PatrimonioGalleryUploadResult> uploadOne(int i) async {
      final slot = startSlot + i;
      try {
        final result = await uploadGalleryPhoto(
          churchId: churchId,
          itemDocId: itemDocId,
          slotIndex: slot,
          rawBytes: images[i],
          skipPrepare: skipPrepare,
          ensureReady: false,
        );
        results[i] = result;
        completed++;
        onBatchProgress?.call(completed / count);
        return result;
      } catch (e, st) {
        if (CrashlyticsService.shouldReport(e)) {
          unawaited(
            CrashlyticsService.record(
              e,
              st,
              reason: 'patrimonio_photo_slot_$slot',
            ),
          );
        }
        rethrow;
      }
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
