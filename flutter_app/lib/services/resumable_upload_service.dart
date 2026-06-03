import 'dart:io';

import 'package:gestao_yahweh/services/upload_bytes_core.dart';

/// Upload resumível — vídeos e ficheiros grandes via [putFile] (SDK retoma chunks).
abstract final class ResumableUploadService {
  ResumableUploadService._();

  static const int filePutThresholdBytes = 2 * 1024 * 1024;

  static bool shouldUseFileUpload(String contentType, int byteLength) {
    if (byteLength >= filePutThresholdBytes) return true;
    final ct = contentType.toLowerCase();
    return ct.startsWith('video/') || ct.contains('mp4');
  }

  static Future<String> uploadLocalFile({
    required String storagePath,
    required String localFilePath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw StateError('ficheiro_local_inexistente');
    }
    return uploadStoragePutFileWithRetry(
      storagePath: storagePath,
      file: file,
      contentType: contentType,
      onProgress: onProgress,
    );
  }
}
