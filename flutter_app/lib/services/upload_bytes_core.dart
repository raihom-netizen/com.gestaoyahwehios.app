import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Upload direto ao Storage com várias tentativas — usado por [MediaUploadService]
/// e pela [StorageUploadQueueService] (sem fila offline).
Future<String> uploadStoragePutDataWithRetry({
  required String storagePath,
  required Uint8List bytes,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 4,
  void Function(double progress)? onProgress,
  void Function(UploadTask task)? onTaskStarted,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: contentType, cacheControl: cacheControl),
      );
      onTaskStarted?.call(task);
      final snap = await awaitStorageUploadTask(
        task,
        payloadBytes: bytes.length,
        onProgress: onProgress,
      );
      onProgress?.call(1.0);
      return await storageDownloadUrlWithRetry(snap.ref);
    } catch (e) {
      lastError = e;
      final isCanceled = e is FirebaseException && e.code == 'canceled';
      if (isCanceled) break;
      if (attempt >= maxAttempts) break;
      onProgress?.call(0);
      await Future.delayed(
          Duration(milliseconds: 120 * math.pow(2, attempt - 1).toInt()));
    }
  }
  throw lastError ?? StateError('Falha de upload');
}

/// Upload de ficheiro local via [Reference.putFile] — o SDK Firebase usa upload
/// resumível por chunks (retoma após falhas de rede dentro da mesma sessão).
Future<String> uploadStoragePutFileWithRetry({
  required String storagePath,
  required File file,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 4,
  void Function(double progress)? onProgress,
  void Function(UploadTask task)? onTaskStarted,
}) async {
  final byteLen = await file.length();
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = ref.putFile(
        file,
        SettableMetadata(contentType: contentType, cacheControl: cacheControl),
      );
      onTaskStarted?.call(task);
      final snap = await awaitStorageUploadTask(
        task,
        payloadBytes: byteLen,
        onProgress: onProgress,
      );
      onProgress?.call(1.0);
      return await storageDownloadUrlWithRetry(snap.ref);
    } catch (e) {
      lastError = e;
      final isCanceled = e is FirebaseException && e.code == 'canceled';
      if (isCanceled) break;
      if (attempt >= maxAttempts) break;
      onProgress?.call(0);
      await Future.delayed(
          Duration(milliseconds: 120 * math.pow(2, attempt - 1).toInt()));
    }
  }
  throw lastError ?? StateError('Falha de upload');
}
