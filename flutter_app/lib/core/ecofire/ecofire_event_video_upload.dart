import 'dart:io';

import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';

/// Vídeo de evento — bytes → `putData` → URL (padrão CT / EcoFire).
abstract final class EcoFireEventVideoUpload {
  EcoFireEventVideoUpload._();

  static Future<String> putVideoFile({
    required String storagePath,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    LegacyPathGuard.assertCanonicalStoragePath(
      storagePath,
      context: 'EcoFireEventVideoUpload.putVideoFile',
    );
    EcoFireFlow.log('EVENT_VIDEO putData $storagePath');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Vídeo vazio — selecione outro ficheiro.');
    }
    final url = await EcoFireStorageUpload.putData(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: 'video/mp4',
      onProgress: onProgress,
    );
    EcoFireFlow.log('EVENT_VIDEO OK $storagePath');
    return url;
  }
}
