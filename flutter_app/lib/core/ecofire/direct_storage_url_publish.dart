import 'dart:typed_data';

import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Upload direto Storage → URL https — padrão Wisdom / Controle Total / EcoFire.
///
/// 1. `putData` no bucket (`igrejas/{churchId}/…`)
/// 2. `getDownloadURL` após upload
/// 3. Gravar URL no Firestore (painel, chat, site público)
abstract final class DirectStorageUrlPublish {
  DirectStorageUrlPublish._();

  /// Envia bytes e devolve URL https pronta para Firestore/UI.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) =>
      EcoFireStorageUpload.putData(
        storagePath: storagePath,
        bytes: bytes,
        mimeType: mimeType,
        onProgress: onProgress,
      );

  /// Resolve URL de objeto já existente no Storage (retry curto).
  static Future<String> resolveUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw ArgumentError('storagePath vazio.');
    }
    final ref = firebaseDefaultStorage.ref(path);
    return storageDownloadUrlWithRetry(ref);
  }
}
