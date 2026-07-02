import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';

/// Upload foto perfil membro — `igrejas/{churchId}/membros/{folderId}/foto_perfil.jpg`.
///
/// Pipeline único: [ChurchCentralStorageUpload] → URL https → Firestore.
abstract final class MemberProfileMediaUpload {
  MemberProfileMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<void> ensureUploadReady({bool requireAuth = true}) async {
    await DirectStorageUrlPublish.ensureReady(requireAuth: requireAuth);
  }

  static Future<String> uploadProfileBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    LegacyPathGuard.assertCanonicalStoragePath(
      storagePath,
      context: 'membro_profile_photo',
    );

    final uploaded = await ChurchCentralStorageUpload.uploadImageAtPath(
      storagePath: storagePath,
      rawBytes: bytes,
      logLabel: 'membro_profile_photo',
      alreadyCompressed: true,
      compressForFeed: false,
      onProgress: onProgress,
      requireAuth: requireAuth,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto demorou demais. Verifique a rede.',
      ),
    );
    return uploaded.downloadUrl;
  }

  static Future<String> uploadProfileFull({
    required String churchId,
    required String storageFolderId,
    required Uint8List fullBytes,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = await ChurchCentralStorageUpload.uploadMemberProfilePhoto(
      churchId: churchId.trim(),
      storageFolderId: storageFolderId.trim(),
      fullBytes: fullBytes,
      onProgress: onProgress,
    );
    return uploaded.downloadUrl;
  }

  static Future<String> uploadProfileThumb({
    required String churchId,
    required String storageFolderId,
    required Uint8List thumbBytes,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    final path = ChurchStorageLayout.memberProfileThumbPathFlatWebpLegacy(
      churchId.trim(),
      storageFolderId.trim(),
    );
    return uploadProfileBytes(
      storagePath: path,
      bytes: thumbBytes,
      contentType: 'image/webp',
      requireAuth: requireAuth,
      onProgress: onProgress,
    );
  }
}
