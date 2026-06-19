import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
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
      await AppFinalizeBootstrap.ensureSessionForPublish(
        logLabel: 'membro_foto',
      );
      await ensureFirebaseReadyForMediaUpload();
    } else {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
    }
    await EcoFirePublishBootstrap.ensureHard(
      logLabel: 'membro_foto',
      strict: requireAuth,
    );
    if (requireAuth && !FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: true,
      );
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

    return FirebaseBootstrapService.runGuarded(
      () async {
        await ensureUploadReady(requireAuth: requireAuth);
        return UnifiedUploadService.uploadImage(
          storagePath: storagePath,
          bytes: bytes,
          contentType: contentType,
          module: YahwehUploadModule.generic,
          skipClientPrepare: true,
          onProgress: onProgress,
          maxAttempts: 4,
        ).timeout(
          uploadTimeout,
          onTimeout: () => throw TimeoutException(
            'Upload da foto demorou demais. Verifique a rede.',
          ),
        );
      },
      debugLabel: 'membro_profile_photo',
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
