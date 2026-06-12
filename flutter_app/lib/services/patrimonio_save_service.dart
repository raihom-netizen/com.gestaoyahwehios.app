import 'dart:typed_data';

import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/patrimonio_strict_publish_service.dart';

/// Gravação patrimônio — Storage sequencial → URLs HTTPS → Firestore.
///
/// Storage: `igrejas/{churchId}/patrimonio/{itemId}/galeria_01.webp` … `_04.webp`
/// Firestore: `fotoUrls`, `fotos` (URLs), `fotoStoragePaths`
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
    await FirebaseBootstrapService.runGuarded(
      () async {
        onProgress?.call(0.02, 'A preparar gravação…');
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'patrimonio_save',
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () {},
        );

        if (newImages.isNotEmpty) {
          onProgress?.call(0.05, 'A enviar ${newImages.length} foto(s)…');

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
              final pct = (p * 100).clamp(0, 100).toStringAsFixed(0);
              final label = p < 0.12
                  ? 'A preparar fotos…'
                  : p < 0.92
                      ? 'A enviar fotos…'
                      : 'A gravar no Firestore…';
              onProgress?.call(0.05 + p * 0.93, '$label $pct%');
            },
          );
          onProgress?.call(1.0, 'Patrimônio gravado.');
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
