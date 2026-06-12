import 'dart:typed_data';

import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/patrimonio_strict_publish_service.dart';

/// Gravação patrimônio — um caminho: Firebase OK → upload → Storage → Firestore.
///
/// Storage: `igrejas/{churchId}/patrimonio/{itemId}/galeria_01.webp` … `_05.webp`
/// Firestore: `fotoStoragePaths`, `fotos`, `fotoUrls`
abstract final class PatrimonioSaveService {
  PatrimonioSaveService._();

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  /// Upload (se houver fotos novas) + metadados + verificação Storage/Firestore.
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
    await FirebaseBootstrapService.runGuarded(
      () async {
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'patrimonio_save',
        );
        onProgress?.call(0.02, 'A preparar gravação…');

        if (newImages.isNotEmpty) {
          var slotDone = 0;
          await PatrimonioStrictPublishService.publish(
            seedTenantId: churchId,
            itemId: itemId,
            corePayload: corePayload,
            isNewDoc: isNewDoc,
            newImages: newImages,
            startSlot: startSlot,
            existingPaths: existingPaths,
            existingUrls: existingUrls,
            onUploadProgress: (p) {
              slotDone = (p * newImages.length).floor().clamp(0, newImages.length);
              final label = slotDone < newImages.length
                  ? 'A enviar foto ${slotDone + 1} de ${newImages.length}…'
                  : 'A confirmar fotos no Storage…';
              onProgress?.call(0.05 + p * 0.82, label);
            },
          );
          onProgress?.call(0.95, 'Patrimônio gravado.');
          return;
        }

        onProgress?.call(0.4, 'A gravar dados…');
        await PatrimonioStrictPublishService.publishMetadataOnly(
          seedTenantId: churchId,
          itemId: itemId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingPaths: existingPaths,
          existingUrls: existingUrls,
        );
        onProgress?.call(1.0, 'Concluído.');
      },
      debugLabel: 'patrimonio_save',
      requireAuth: true,
    );
  }
}
