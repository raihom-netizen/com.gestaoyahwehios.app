import 'dart:typed_data';

import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';

/// Gravação patrimônio — Storage (4 fotos) → `foto01`…`foto04` → Firestore.
abstract final class PatrimonioSaveService {
  PatrimonioSaveService._();

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static Future<void> save({
    required String churchIdHint,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<Uint8List> newImages,
    required int startSlot,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    void Function(double progress, String label)? onProgress,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    onProgress?.call(0.02, 'A preparar gravação…');

    if (newImages.isNotEmpty) {
      onProgress?.call(0.05, 'A enviar ${newImages.length} foto(s)…');
      await PatrimonioPublishService.publish(
        seedTenantId: churchId,
        itemId: itemId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        newImages: newImages,
        startSlot: startSlot,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
        onUploadProgress: (p) {
          final pct = (p * 100).clamp(0, 100).toStringAsFixed(0);
          final label = p < 0.12
              ? 'A preparar fotos…'
              : p < 0.88
                  ? 'A enviar fotos…'
                  : 'A gravar no Firestore…';
          onProgress?.call(0.05 + p * 0.93, '$label $pct%');
        },
      );
      onProgress?.call(1.0, 'Patrimônio gravado.');
      return;
    }

    onProgress?.call(0.4, 'A gravar dados…');
    await PatrimonioPublishService.publishMetadataOnly(
      seedTenantId: churchId,
      itemId: itemId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      existingPaths: existingPaths,
      existingUrls: existingUrls,
    );
    onProgress?.call(1.0, 'Concluído.');
  }
}
