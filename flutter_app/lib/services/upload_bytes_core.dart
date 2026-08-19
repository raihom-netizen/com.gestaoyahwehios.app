import 'dart:async';

import 'dart:io';

import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/storage_upload_metadata.dart';
import 'package:gestao_yahweh/core/constants/yahweh_storage.dart';
import 'package:gestao_yahweh/services/church_tenant_media_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload direto ao Storage com várias tentativas — usado por [MediaUploadService]

/// e pela [StorageUploadQueueService] (sem fila offline no dreno).

Future<String> uploadStoragePutDataWithRetry({
  required String storagePath,

  required Uint8List bytes,

  required String contentType,

  String cacheControl = 'public, max-age=31536000',

  int maxAttempts = 3,

  void Function(double progress)? onProgress,

  void Function(UploadTask task)? onTaskStarted,

  bool useOfflineQueue = false,

  String? localFilePathForRetry,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Ficheiro vazio — selecione outro.');
  }
  if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
    await ensureUploadBootstrapForStoragePath(storagePath);
  }
  try {
    await ChurchTenantMediaService.assertUploadPathFromResolvedTenant(
      storagePath: storagePath,
    );
  } on ChurchTenantMediaException catch (e) {
    ChurchTenantMediaActivity.recordError(e.toString());
    rethrow;
  }
  try {
    final url = await YahwehMediaUploadPipeline.uploadPreparedBytes(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      maxAttempts: maxAttempts,
      onProgress: onProgress,
      onUploadTaskCreated: onTaskStarted,
    );
    ChurchTenantMediaActivity.recordUpload(storagePath);
    return url;
  } catch (e) {
    ChurchTenantMediaActivity.recordError(e.toString());
    rethrow;
  }
}

/// Ficheiro local grande → upload nativo resumível. Web continua exclusivamente
/// em [uploadStoragePutDataWithRetry].
Future<String> uploadStoragePutFileWithRetry({
  required String storagePath,
  required File file,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 3,
  void Function(double progress)? onProgress,
  void Function(UploadTask task)? onTaskStarted,
  bool useOfflineQueue = false,
}) async {
  if (!await file.exists()) {
    throw StateError('Ficheiro não encontrado no aparelho.');
  }
  final length = await file.length();
  if (length <= 0) {
    throw StateError('Ficheiro vazio — selecione outro.');
  }
  if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
    await ensureUploadBootstrapForStoragePath(storagePath);
  }
  await ChurchTenantMediaService.assertUploadPathFromResolvedTenant(
    storagePath: storagePath,
  );

  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final ref = firebaseDefaultStorage.ref(storagePath);
      final task = ref.putFile(
        file,
        SettableMetadata(
          contentType: StorageUploadMetadata.contentTypeForPut(
            contentType: contentType,
            storagePath: storagePath,
          ),
          cacheControl: cacheControl,
        ),
      );
      onTaskStarted?.call(task);
      final snap = await awaitStorageUploadTask(
        task,
        payloadBytes: length,
        onProgress: onProgress,
      );
      onProgress?.call(1);
      ChurchTenantMediaActivity.recordUpload(storagePath);
      // Mídia da igreja: URL montada na hora. Este ramo nem timeout externo
      // tinha — `storageDownloadUrlWithRetry` são 8 s × 2 tentativas, ou seja
      // até ~16 s de espera por ficheiro com os bytes já no bucket.
      final imediata = YahwehStorage.publicChurchMediaUrlOrNull(storagePath);
      if (imediata != null && imediata.isNotEmpty) return imediata;
      final url = await storageDownloadUrlOrNull(snap.ref);
      if (url != null && url.isNotEmpty) return url;
      return YahwehStorage.downloadUrlForObjectPath(storagePath);
    } catch (e) {
      lastError = e;
      final canceled = e.toString().toLowerCase().contains('cancel');
      if (canceled || !isRetryableUploadError(e) || attempt >= maxAttempts) {
        ChurchTenantMediaActivity.recordError(e.toString());
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
  }
  throw lastError ?? StateError('Falha ao enviar ficheiro.');
}
