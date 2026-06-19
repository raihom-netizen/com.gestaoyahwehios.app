import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';import 'package:gestao_yahweh/services/crashlytics_service.dart';
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
    Map<int, Uint8List> uploadsBySlot = const {},
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    List<Uint8List> newImages = const [],
    int startSlot = 0,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    void Function(double progress, String label)? onProgress,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    onProgress?.call(0.02, 'Salvando patrimônio e enviando fotos…');

    final hasSlotUploads = uploadsBySlot.isNotEmpty || newImages.isNotEmpty;

    Future<void> runPublish() async {
      if (hasSlotUploads) {
        final count = uploadsBySlot.isNotEmpty
            ? uploadsBySlot.length
            : newImages.length;
        onProgress?.call(
          0.05,
          'Salvando patrimônio e enviando $count foto(s)…',
        );
        await PatrimonioPublishService.publish(
          seedTenantId: churchId,
          itemId: itemId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          uploadsBySlot: uploadsBySlot,
          indexedSlotUrls: indexedSlotUrls,
          indexedSlotPaths: indexedSlotPaths,
          newImages: newImages,
          startSlot: startSlot,
          existingPaths: existingPaths,
          existingUrls: existingUrls,
          onUploadProgress: (p) {
            final pct = (p * 100).clamp(0, 100).toStringAsFixed(0);
            final label = p < 0.12
                ? 'Salvando patrimônio e enviando fotos…'
                : p < 0.88
                    ? 'Enviando fotos… $pct%'
                    : 'A gravar no Firestore… $pct%';
            onProgress?.call(0.05 + p * 0.93, label);
          },
        );
        onProgress?.call(1.0, 'Patrimônio gravado.');
        return;
      }

      onProgress?.call(0.4, 'Salvando patrimônio…');
      await PatrimonioPublishService.publishMetadataOnly(
        seedTenantId: churchId,
        itemId: itemId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        indexedSlotUrls: indexedSlotUrls,
        indexedSlotPaths: indexedSlotPaths,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
      );
      onProgress?.call(1.0, 'Patrimônio gravado.');
    }

    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await runPublish();
        return;
      } catch (e, st) {
        last = e;
        if (attempt == 0 && isFirebaseNoAppError(e)) {
          FirebaseBootstrapService.resetPublishWarmState();
          await FirebaseBootstrapService.ensureAlwaysOn(
            refreshAuthToken: true,
          );
          continue;
        }
        if (CrashlyticsService.shouldReport(e)) {
          unawaited(
            CrashlyticsService.record(e, st, reason: 'patrimonio_save'),
          );
        }
        rethrow;
      }
    }
    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }
  }
}
