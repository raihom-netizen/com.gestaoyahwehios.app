import 'dart:async';

import 'dart:io';

import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/church_tenant_media_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';



/// Upload direto ao Storage com várias tentativas — usado por [MediaUploadService]

/// e pela [StorageUploadQueueService] (sem fila offline no dreno).

Future<String> uploadStoragePutDataWithRetry({

  required String storagePath,

  required Uint8List bytes,

  required String contentType,

  String cacheControl = 'public, max-age=31536000',

  int maxAttempts = 4,

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



/// Ficheiro local → lê bytes → [uploadStoragePutDataWithRetry] (padrão CT: só putData).
Future<String> uploadStoragePutFileWithRetry({
  required String storagePath,
  required File file,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 4,
  void Function(double progress)? onProgress,
  void Function(UploadTask task)? onTaskStarted,
  bool useOfflineQueue = false,
}) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw StateError('Ficheiro vazio — selecione outro.');
  }
  return uploadStoragePutDataWithRetry(
    storagePath: storagePath,
    bytes: bytes,
    contentType: contentType,
    cacheControl: cacheControl,
    maxAttempts: maxAttempts,
    onProgress: onProgress,
    onTaskStarted: onTaskStarted,
    useOfflineQueue: useOfflineQueue,
    localFilePathForRetry: file.path,
  );
}

