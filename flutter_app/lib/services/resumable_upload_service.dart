import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:gestao_yahweh/services/upload_bytes_core.dart';

/// Upload resumível de ficheiro local no Android/iOS.
abstract final class ResumableUploadService {
  ResumableUploadService._();

  static const int filePutThresholdBytes = 2 * 1024 * 1024;

  /// Teto total para um upload resumível (vídeo/ficheiro grande no chat).
  /// O watchdog interno cancela antes quando não há avanço por 35 segundos.
  /// Sem isto, uma sessão resumível que trava (rede caiu no meio, etc.)
  /// ficava à espera para sempre — sem nunca cair no estado de erro que a
  /// UI já sabe mostrar ("Falha no envio" + tentar de novo).
  static const Duration uploadTotalTimeout = Duration(minutes: 3);

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
    ).timeout(
      uploadTotalTimeout,
      onTimeout: () => throw TimeoutException(
        'Envio demorou demais — verifique a rede e tente de novo.',
        uploadTotalTimeout,
      ),
    );
  }
}
