import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';

/// Gravação patrimônio — Storage (5 fotos) → `foto01`…`foto05` → Firestore.
abstract final class PatrimonioSaveService {
  PatrimonioSaveService._();

  static const Duration kSaveTimeout = Duration(seconds: 60);

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
    if (hasSlotUploads) {
      await DirectStorageUrlPublish.ensureReady(requireAuth: true);
    }

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
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await runPublish().timeout(
          kSaveTimeout,
          onTimeout: () => throw TimeoutException(
            'Salvar patrimônio demorou demais. Verifique a rede e tente de novo.',
            kSaveTimeout,
          ),
        );
        return;
      } catch (e, st) {
        last = e;
        if (attempt < 2 && isFirebaseNoAppError(e)) {
          await EcoFireDirectFirebase.ensureDefaultApp();
          await DirectStorageUrlPublish.ensureReady(requireAuth: true);
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (attempt + 1)),
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

  /// Write-first: grava metadados e devolve — fotos ficam para [uploadPhotosInBackground].
  static Future<void> saveMetadataFirst({
    required String churchIdHint,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
  }) async {
    await PatrimonioPublishService.publishMetadataWithPendingUploads(
      seedTenantId: resolveChurchId(churchIdHint),
      itemId: itemId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      indexedSlotUrls: indexedSlotUrls,
      indexedSlotPaths: indexedSlotPaths,
    );
  }

  /// Upload de fotos pendentes — compressão em isolate + patch Firestore silencioso.
  static Future<void> uploadPhotosInBackground({
    required String churchIdHint,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    Map<int, Uint8List> uploadsBySlot = const {},
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
  }) async {
    if (uploadsBySlot.isEmpty) return;
    try {
      await save(
        churchIdHint: churchIdHint,
        itemId: itemId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        uploadsBySlot: uploadsBySlot,
        indexedSlotUrls: indexedSlotUrls,
        indexedSlotPaths: indexedSlotPaths,
      );
    } catch (e, st) {
      if (CrashlyticsService.shouldReport(e)) {
        unawaited(
          CrashlyticsService.record(e, st, reason: 'patrimonio_photos_bg'),
        );
      }
    }
  }
}
