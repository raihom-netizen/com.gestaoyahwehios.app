import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';
import 'package:gestao_yahweh/services/patrimonio_save_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Fotos do património — upload strict Storage → Firestore (`foto01`…`foto05`).
abstract final class PatrimonioPhotosUpdateService {
  PatrimonioPhotosUpdateService._();

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static List<String> _normalizeSlotUrls(List<String> raw) {
    final out = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
    for (var i = 0; i < PatrimonioPhotoFields.maxPhotos; i++) {
      out[i] = i < raw.length ? sanitizeImageUrl(raw[i]) : '';
    }
    return out;
  }

  static List<String> _normalizeSlotPaths(List<String> raw) {
    final out = List<String>.filled(PatrimonioPhotoFields.maxPhotos, '');
    for (var i = 0; i < PatrimonioPhotoFields.maxPhotos; i++) {
      out[i] = i < raw.length ? raw[i].trim() : '';
    }
    return out;
  }

  /// Remove slot — apaga Storage + limpa `foto0N` no Firestore de imediato.
  static Future<void> clearSlotNow({
    required String churchIdHint,
    required String itemId,
    required int slot,
    required List<String> indexedSlotUrls,
    required List<String> indexedSlotPaths,
    required Map<String, dynamic> corePayload,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    final iid = itemId.trim();
    if (churchId.isEmpty || iid.isEmpty) return;
    final idx = slot.clamp(0, PatrimonioPhotoFields.maxPhotos - 1);

    final urls = _normalizeSlotUrls(indexedSlotUrls);
    final paths = _normalizeSlotPaths(indexedSlotPaths);
    urls[idx] = '';
    paths[idx] = '';

    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: 'patrimonio_foto_clear',
    );
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    await FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
      tenantId: churchId,
      itemDocId: iid,
      slot: idx,
    );

    await runFirestorePublishWithRecovery(
      () => PatrimonioPublishService.publishMetadataOnly(
        seedTenantId: churchId,
        itemId: iid,
        corePayload: corePayload,
        isNewDoc: false,
        indexedSlotUrls: urls,
        indexedSlotPaths: paths,
      ),
    ).timeout(const Duration(seconds: 28));

    await ChurchPatrimonioLoadService.invalidate(churchId);
  }

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
      indexedSlotUrls: _normalizeSlotUrls(indexedSlotUrls),
      indexedSlotPaths: _normalizeSlotPaths(indexedSlotPaths),
      onProgress: onProgress,
    );
    await ChurchPatrimonioLoadService.invalidate(churchId);
  }
}
