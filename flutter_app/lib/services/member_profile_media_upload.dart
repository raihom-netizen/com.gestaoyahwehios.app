import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';

/// Upload foto perfil membro — `igrejas/{churchId}/membros/{folderId}/foto_perfil.jpg`.
///
/// Pipeline único (Controle Total): fachada → Storage → URL → Firestore só link.
abstract final class MemberProfileMediaUpload {
  MemberProfileMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<void> ensureUploadReady({bool requireAuth = true}) async {
    await ChurchMediaUploadFacade.ensureReady(requireAuth: requireAuth);
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

    await ensureUploadReady(requireAuth: requireAuth);
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
    await ensureUploadReady(requireAuth: requireAuth);
    final path = ChurchStorageLayout.memberProfilePhotoPath(
      churchId.trim(),
      storageFolderId.trim(),
    );
    final uploaded = await ChurchCentralStorageUpload.uploadImageAtPath(
      storagePath: path,
      rawBytes: fullBytes,
      logLabel: 'membro_profile',
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
