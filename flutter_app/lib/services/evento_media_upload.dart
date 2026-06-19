import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/ecofire_feed_photo_slot.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload de fotos de evento — `igrejas/{churchId}/eventos/{postId}/…`.
///
/// Compressão obrigatória + [UnifiedUploadService] (anti `firebase_core/no-app`).
abstract final class EventoMediaUpload {
  EventoMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);
  static const int maxParallelSlots = kMaxEventFeedPhotosPerPost;

  static Future<void> ensureUploadReady() async {
    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: 'evento_media',
    );
    await ensureFirebaseReadyForMediaUpload();
    await EcoFirePublishBootstrap.ensureHard(
      logLabel: 'evento_media',
      strict: true,
    );
    if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: true,
      );
    }
  }

  static Future<EcoFireFeedPhotoSlot> uploadPhotoSlot({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List rawBytes,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) async {
    final cid = churchId.trim();
    final pid = postId.trim();
    if (cid.isEmpty || pid.isEmpty) {
      throw ArgumentError('churchId e postId são obrigatórios.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }

    return FirebaseBootstrapService.runGuarded(
      () async {
        await ensureUploadReady();
        EcoFireFlow.log('EVENTO_PHOTO slot $pid#$slotIndex');

        final processed = alreadyCompressed
            ? (bytes: rawBytes, mime: 'image/jpeg')
            : await EcoFireImageProcess.processForFeedPhoto(rawBytes);

        final storagePath =
            ChurchStorageLayout.eventPostPhotoPath(cid, pid, slotIndex);
        LegacyPathGuard.assertCanonicalStoragePath(
          storagePath,
          context: 'evento_photo',
        );

        final url = await UnifiedUploadService.uploadImage(
          storagePath: storagePath,
          bytes: processed.bytes,
          contentType: processed.mime,
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

        EcoFireFlow.log('EVENTO_PHOTO OK $storagePath');
        return EcoFireFeedPhotoSlot(
          fullUrl: url,
          thumbUrl: url,
          fullPath: storagePath,
          thumbPath: storagePath,
        );
      },
      debugLabel: 'evento_photo_slot',
    );
  }

  /// Capa de template fixo — `igrejas/{churchId}/eventos/templates/…`.
  static Future<String> uploadTemplateCover({
    required String churchId,
    required String templateId,
    required Uint8List compressedBytes,
    void Function(double progress)? onProgress,
  }) async {
    if (compressedBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    return FirebaseBootstrapService.runGuarded(
      () async {
        await ensureUploadReady();
        final path = ChurchStorageLayout.eventTemplateCoverPath(
          churchId.trim(),
          templateId.trim(),
        );
        LegacyPathGuard.assertCanonicalStoragePath(
          path,
          context: 'event_template_cover',
        );
        return UnifiedUploadService.uploadJpegBytes(
          storagePath: path,
          bytes: compressedBytes,
        ).timeout(
          uploadTimeout,
          onTimeout: () => throw TimeoutException(
            'Upload da capa demorou demais. Verifique a rede.',
          ),
        );
      },
      debugLabel: 'event_template_cover',
    );
  }

  /// Lote de fotos — paralelo seguro com [Future.wait].
  static Future<List<EcoFireFeedPhotoSlot>> uploadPhotoBatch({
    required String churchId,
    required String postId,
    required int startSlotIndex,
    required List<Uint8List> bytesList,
    bool alreadyCompressed = true,
    void Function(double progress)? onProgress,
  }) async {
    if (bytesList.isEmpty) return const [];

    await ensureUploadReady();

    final slots = List<EcoFireFeedPhotoSlot?>.filled(bytesList.length, null);
    var completed = 0;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> uploadOne(int i) async {
      try {
        slots[i] = await uploadPhotoSlot(
          churchId: churchId,
          postId: postId,
          slotIndex: startSlotIndex + i,
          rawBytes: bytesList[i],
          alreadyCompressed: alreadyCompressed,
        );
      } catch (e, st) {
        firstError ??= e;
        firstStack ??= st;
        unawaited(
          CrashlyticsService.record(
            e,
            st,
            reason: 'evento_photo_batch_slot_$i',
          ),
        );
        rethrow;
      } finally {
        completed++;
        onProgress?.call(completed / bytesList.length);
      }
    }

    for (var start = 0; start < bytesList.length; start += maxParallelSlots) {
      final end = (start + maxParallelSlots).clamp(0, bytesList.length);
      try {
        await Future.wait([
          for (var i = start; i < end; i++) uploadOne(i),
        ]);
      } catch (_) {
        if (firstError != null) {
          if (firstError is Exception) throw firstError!;
          throw StateError(firstError.toString());
        }
        rethrow;
      }
    }

    final out = slots.whereType<EcoFireFeedPhotoSlot>().toList();
    if (out.length != bytesList.length && firstError != null) {
      unawaited(
        CrashlyticsService.record(
          firstError!,
          firstStack ?? StackTrace.current,
          reason: 'evento_photo_batch_incomplete',
        ),
      );
      if (firstError is Exception) throw firstError!;
      throw StateError(firstError.toString());
    }
    return out;
  }
}
