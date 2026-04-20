import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Upload direto ao Storage com várias tentativas — usado por [MediaUploadService]
/// e pela [StorageUploadQueueService] (sem fila offline).
Future<String> uploadStoragePutDataWithRetry({
  required String storagePath,
  required Uint8List bytes,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 3,
  void Function(double progress)? onProgress,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: contentType, cacheControl: cacheControl),
      );
      StreamSubscription<TaskSnapshot>? sub;
      if (onProgress != null) {
        sub = task.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          if (total <= 0) return;
          final p = (snapshot.bytesTransferred / total).clamp(0.0, 1.0);
          onProgress(p);
        });
      }
      try {
        final snap = await task;
        onProgress?.call(1.0);
        return await snap.ref.getDownloadURL();
      } finally {
        await sub?.cancel();
      }
    } catch (e) {
      lastError = e;
      if (attempt >= maxAttempts) break;
      await Future.delayed(
          Duration(milliseconds: 400 * math.pow(2, attempt - 1).toInt()));
    }
  }
  throw lastError ?? StateError('Falha de upload');
}

/// Upload de ficheiro local (sem compressão adicional — o chamador prepara se necessário).
Future<String> uploadStoragePutFileWithRetry({
  required String storagePath,
  required File file,
  required String contentType,
  String cacheControl = 'public, max-age=31536000',
  int maxAttempts = 3,
  void Function(double progress)? onProgress,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = ref.putFile(
        file,
        SettableMetadata(contentType: contentType, cacheControl: cacheControl),
      );
      StreamSubscription<TaskSnapshot>? sub;
      if (onProgress != null) {
        sub = task.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          if (total <= 0) return;
          onProgress((snapshot.bytesTransferred / total).clamp(0.0, 1.0));
        });
      }
      try {
        final snap = await task;
        onProgress?.call(1.0);
        return await snap.ref.getDownloadURL();
      } finally {
        await sub?.cancel();
      }
    } catch (e) {
      lastError = e;
      if (attempt >= maxAttempts) break;
      await Future.delayed(
          Duration(milliseconds: 400 * math.pow(2, attempt - 1).toInt()));
    }
  }
  throw lastError ?? StateError('Falha de upload');
}
