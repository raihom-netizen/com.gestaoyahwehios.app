import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';

/// Upload padronizado — grava apenas [storagePath] no Firestore (nunca URL fixa).
abstract final class ChurchStorageService {
  ChurchStorageService._();

  static const Duration kUploadTimeout = Duration(seconds: 15);

  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw StateError('storagePath vazio.');
    }
    await UnifiedUploadService.uploadImage(
      storagePath: path,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
      maxAttempts: 3,
    ).timeout(kUploadTimeout);
    await ChurchStorageMetadataVerify.assertExists(path);
    return path;
  }

  static String churchLogoPath(String churchId) =>
      ChurchStorageLayout.churchIdentityLogoPath(churchId.trim());

  static String churchRoot(String churchId) =>
      ChurchStorageLayout.churchRoot(churchId.trim());
}
