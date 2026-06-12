import 'dart:typed_data';

import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/patrimonio_strict_publish_service.dart';

/// Gravação patrimônio — Storage paralelo → Firestore → confirmação.
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
        onProgress?.call(0.02, 'A preparar gravação…');
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'patrimonio_save',
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () {},
        );

        if (newImages.isNotEmpty) {
          onProgress?.call(0.04, 'A ligar Storage…');
          await FastMediaPublishBootstrap.warmForPatrimonioSave().timeout(
            const Duration(seconds: 25),
            onTimeout: () {},
          );
          onProgress?.call(0.06, 'A enviar ${newImages.length} foto(s)…');

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
              final label = p < 0.15
                  ? 'A preparar fotos…'
                  : p < 0.88
                      ? 'A enviar fotos ($pct%)…'
                      : 'A gravar no Firestore…';
              onProgress?.call(0.06 + p * 0.9, label);
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
