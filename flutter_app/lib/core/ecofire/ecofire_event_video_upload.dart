import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/storage_upload_metadata.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Vídeo de evento — upload directo Storage (padrão EcoFire `putFile` → URL).
abstract final class EcoFireEventVideoUpload {
  EcoFireEventVideoUpload._();

  static const int _maxAttempts = 4;

  static Future<String> putVideoFile({
    required String storagePath,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    LegacyPathGuard.assertCanonicalStoragePath(
      storagePath,
      context: 'EcoFireEventVideoUpload.putVideoFile',
    );
    EcoFireFlow.log('EVENT_VIDEO putFile $storagePath');

    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          FirebaseBootstrapService.resetPublishWarmState();
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
        await EcoFirePublishBootstrap.ensureHard(
          logLabel: 'evento_video_upload',
          strict: true,
        );
        final ref = firebaseStorageRef(storagePath);
        final ct = StorageUploadMetadata.contentTypeForPut(
          contentType: 'video/mp4',
          storagePath: storagePath,
        );
        final task = ref.putFile(
          file,
          SettableMetadata(
            contentType: ct,
            cacheControl: StorageUploadMetadata.cacheControl,
          ),
        );
        final snap = await awaitStorageUploadTask(
          task,
          payloadBytes: await file.length(),
          onProgress: onProgress,
        );
        final url = await storageDownloadUrlWithRetry(snap.ref);
        EcoFireFlow.log('EVENT_VIDEO OK $storagePath');
        return url;
      } catch (e) {
        lastError = e;
        EcoFireFlow.log('EVENT_VIDEO retry $attempt: $e');
        if (attempt < _maxAttempts - 1 && isFirebaseNoAppError(e)) {
          continue;
        }
        if (attempt < _maxAttempts - 1) {
          await FirebaseBootstrapService.ensureStorageAlwaysLinked(
            refreshAuthToken: true,
          ).catchError((_) {});
        }
      }
    }
    throw lastError ?? StateError('evento_video_upload_failed:$storagePath');
  }
}
