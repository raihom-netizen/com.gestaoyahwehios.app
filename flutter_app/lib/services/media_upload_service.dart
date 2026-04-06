import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_storage_cleanup_service.dart';
import 'image_helper.dart';

/// Uploads com [getDownloadURL] no fim do fluxo — URLs prontas para Firestore (https).
/// Política global: [church_media_publish_policy.dart] + [StorageMediaService.publishableHttpsUrlForFirestore].
class MediaUploadService {
  MediaUploadService._();

  static bool _shouldCompressJpeg(String contentType) {
    final ct = contentType.toLowerCase().trim();
    return ct == 'image/jpeg' || ct == 'image/jpg';
  }

  static Future<Uint8List> _prepareBytesForUpload({
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_shouldCompressJpeg(contentType)) return bytes;
    return ImageHelper.compressImage(
      bytes,
      minWidth: 800,
      minHeight: 600,
      quality: 70,
    );
  }

  /// Resultado padrão de upload para persistir no Firestore:
  /// - [downloadUrl] URL completa `getDownloadURL()` (com token) — gravar em `foto_url` / `FOTO_URL_OU_ID` / `fotoUrl`
  /// - [storagePath] para fallback/refresh de token
  /// - [contentType] para diagnóstico e processamento
  static MediaUploadResult _result({
    required String downloadUrl,
    required String storagePath,
    required String contentType,
  }) =>
      MediaUploadResult(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        contentType: contentType,
      );

  static Future<String> uploadBytesWithRetry({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,

    /// Remove estes ficheiros no Storage antes do novo upload (substituição).
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,

    /// Quando true, envia [bytes] sem segunda compressão JPEG em [_prepareBytesForUpload]
    /// (ex.: já passaram por [ImageHelper.compressMemberProfileForUpload]).
    bool skipClientPrepare = false,
  }) async {
    final preparedBytes = skipClientPrepare
        ? bytes
        : await _prepareBytesForUpload(
            bytes: bytes,
            contentType: contentType,
          );
    if (deleteFirebaseDownloadUrlsBefore != null) {
      for (final u in deleteFirebaseDownloadUrlsBefore) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
      }
    }
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final ref = FirebaseStorage.instance.ref(storagePath);
        final task = ref.putData(
          preparedBytes,
          SettableMetadata(
              contentType: contentType, cacheControl: cacheControl),
        );
        if (onProgress != null) {
          task.snapshotEvents.listen((snapshot) {
            final total = snapshot.totalBytes;
            if (total <= 0) return;
            final p = (snapshot.bytesTransferred / total).clamp(0.0, 1.0);
            onProgress(p);
          });
        }
        final snap = await task;
        onProgress?.call(1.0);
        return await snap.ref.getDownloadURL();
      } catch (e) {
        lastError = e;
        if (attempt >= maxAttempts) break;
        await Future.delayed(
            Duration(milliseconds: 400 * math.pow(2, attempt - 1).toInt()));
      }
    }
    throw lastError ?? StateError('Falha de upload');
  }

  static Future<MediaUploadResult> uploadBytesDetailed({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
    void Function(double progress)? onProgress,
    bool skipClientPrepare = false,
  }) async {
    final url = await uploadBytesWithRetry(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      cacheControl: cacheControl,
      maxAttempts: maxAttempts,
      deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
      onProgress: onProgress,
      skipClientPrepare: skipClientPrepare,
    );
    return _result(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: contentType,
    );
  }

  static Future<String> uploadFileWithRetry({
    required String storagePath,
    required File file,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
  }) async {
    if (_shouldCompressJpeg(contentType)) {
      final fileBytes = await file.readAsBytes();
      final preparedBytes = await _prepareBytesForUpload(
        bytes: fileBytes,
        contentType: contentType,
      );
      return uploadBytesWithRetry(
        storagePath: storagePath,
        bytes: preparedBytes,
        contentType: contentType,
        cacheControl: cacheControl,
        maxAttempts: maxAttempts,
        deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
      );
    }
    if (deleteFirebaseDownloadUrlsBefore != null) {
      for (final u in deleteFirebaseDownloadUrlsBefore) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
      }
    }
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final ref = FirebaseStorage.instance.ref(storagePath);
        final task = ref.putFile(
          file,
          SettableMetadata(
              contentType: contentType, cacheControl: cacheControl),
        );
        final snap = await task;
        return await snap.ref.getDownloadURL();
      } catch (e) {
        lastError = e;
        if (attempt >= maxAttempts) break;
        await Future.delayed(
            Duration(milliseconds: 400 * math.pow(2, attempt - 1).toInt()));
      }
    }
    throw lastError ?? StateError('Falha de upload');
  }

  static Future<MediaUploadResult> uploadFileDetailed({
    required String storagePath,
    required File file,
    required String contentType,
    String cacheControl = 'public, max-age=31536000',
    int maxAttempts = 3,
    Iterable<String>? deleteFirebaseDownloadUrlsBefore,
  }) async {
    final url = await uploadFileWithRetry(
      storagePath: storagePath,
      file: file,
      contentType: contentType,
      cacheControl: cacheControl,
      maxAttempts: maxAttempts,
      deleteFirebaseDownloadUrlsBefore: deleteFirebaseDownloadUrlsBefore,
    );
    return _result(
      downloadUrl: url,
      storagePath: storagePath,
      contentType: contentType,
    );
  }

  /// Salva variantes de imagem (thumb/card/full). **Não** usar para foto de perfil de membro:
  /// o canónico é só `foto_perfil.jpg`. Após upload, use
  /// [FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload] para remover
  /// `thumb_foto_perfil.jpg` etc. (ex.: extensão Resize Images no Console).
  static Future<Map<String, MediaUploadResult>> uploadImageVariants({
    required String basePathWithoutExt,
    required Uint8List imageBytes,
    String ext = 'jpg',
    String contentType = 'image/jpeg',
    String cacheControl = 'public, max-age=31536000',
  }) async {
    final cleanExt = ext.replaceAll('.', '').toLowerCase();
    final variants = <String, String>{
      'thumb': '${basePathWithoutExt}_thumb.$cleanExt',
      'card': '${basePathWithoutExt}_card.$cleanExt',
      'full': '${basePathWithoutExt}_full.$cleanExt',
    };
    final entries = variants.entries.toList();
    final results = await Future.wait(
      entries.map(
        (entry) => uploadBytesDetailed(
          storagePath: entry.value,
          bytes: imageBytes,
          contentType: contentType,
          cacheControl: cacheControl,
        ),
      ),
    );
    return Map<String, MediaUploadResult>.fromIterables(
      entries.map((e) => e.key),
      results,
    );
  }
}

class MediaUploadResult {
  final String downloadUrl;
  final String storagePath;
  final String contentType;

  const MediaUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
  });

  Map<String, dynamic> toJson() => {
        'url': downloadUrl,
        'storagePath': storagePath,
        'contentType': contentType,
      };
}
