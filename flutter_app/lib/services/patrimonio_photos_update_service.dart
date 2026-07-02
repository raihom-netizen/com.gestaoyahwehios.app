import 'dart:typed_data';

import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/patrimonio_save_service.dart';

/// Fotos do património — upload strict Storage → Firestore (`foto01`…`foto05`).
abstract final class PatrimonioPhotosUpdateService {
  PatrimonioPhotosUpdateService._();

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  /// Publica fotos em fluxo linear (sem fila «uploading» eterno).
  static Future<void> publishPhotosStrict({
    required String churchIdHint,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> indexedSlotUrls,
    required List<String> indexedSlotPaths,
    Map<int, Uint8List> uploadsBySlot = const {},
    void Function(double progress, String label)? onProgress,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    await PatrimonioSaveService.save(
      churchIdHint: churchId,
      itemId: itemId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      uploadsBySlot: uploadsBySlot,
      indexedSlotUrls: indexedSlotUrls,
      indexedSlotPaths: indexedSlotPaths,
      onProgress: onProgress,
    );
    await ChurchPatrimonioLoadService.invalidate(churchId);
  }
}
