import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload foto perfil membro — `igrejas/{churchId}/membros/{folderId}/foto_perfil.jpg`.
///
/// Compressão obrigatória (via [MemberProfileVariantsService.encodeProfileTiers])
/// + [UnifiedUploadService] (anti `firebase_core/no-app`).
abstract final class MemberProfileMediaUpload {
  MemberProfileMediaUpload._();

  static const Duration uploadTimeout = Duration(seconds: 60);

  static Future<void> ensureUploadReady({bool requireAuth = true}) async {
    if (requireAuth) {
      await EcoFireDirectFirebase.ensureForStoragePut();
    } else {
      await FirebaseBootstrap.ensureInitialized();
      await EcoFireDirectFirebase.ensureStorageLinked();
    }
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
    return YahwehMediaUploadPipeline.uploadPreparedBytes(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      maxAttempts: 4,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto demorou demais. Verifique a rede.',
      ),
    );
  }

  static Future<String> uploadProfileFull({
    required String churchId,
    required String storageFolderId,
    required Uint8List fullBytes,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    final path = ChurchStorageLayout.memberProfilePhotoPath(
      churchId.trim(),
      storageFolderId.trim(),
    );
    return uploadProfileBytes(
      storagePath: path,
      bytes: fullBytes,
      contentType: 'image/jpeg',
      requireAuth: requireAuth,
      onProgress: onProgress,
    );
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
