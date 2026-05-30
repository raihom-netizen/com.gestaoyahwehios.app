import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/media_service.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';

/// Mobile (IO): MP4 pequeno envia direto (sem re-encoding); caso contrário **720p HD** (equilíbrio nitidez/tempo).
/// Thumb + uploads em paralelo; progresso de rede opcional.
class VideoHandlerService implements IVideoHandlerService {
  VideoHandlerService._();
  static final VideoHandlerService instance = VideoHandlerService._();

  static bool get _isIosNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final ImagePicker _picker = ImagePicker();

  @override
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    Duration maxDuration = kMediaVideoMaxDuration,
    void Function(double uploadProgress01)? onUploadProgress,
    int? maxRawPickBytes,
  }) async {
    final effectiveMaxDuration =
        maxDuration < mediaVideoMaxDurationEffective
            ? maxDuration
            : mediaVideoMaxDurationEffective;
    final xfile = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: effectiveMaxDuration,
    );
    if (xfile == null || xfile.path.isEmpty) return null;
    return compressAndUploadFromPath(
      localPath: xfile.path,
      tenantId: tenantId,
      eventPostDocId: eventPostDocId,
      videoSlotIndex: videoSlotIndex,
      onUploadProgress: onUploadProgress,
      maxRawPickBytes: maxRawPickBytes,
    );
  }

  @override
  Future<VideoUploadResult?> compressAndUploadFromPath({
    required String localPath,
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    void Function(double uploadProgress01)? onUploadProgress,
    int? maxRawPickBytes,
  }) async {
    final path = localPath;
    if (path.isEmpty || !File(path).existsSync()) return null;

    await ensureFirebaseReadyForMediaUpload();

    try {
      final lower = path.toLowerCase();
      final byteLen = await File(path).length();
      final hardLimitBytes = mediaVideoHardMaxBytesEffective;
      final pickLimit = maxRawPickBytes ?? hardLimitBytes;
      if (byteLen > pickLimit) {
        final sizeMb = (byteLen / (1024 * 1024)).toStringAsFixed(1);
        final limitMb = (pickLimit / (1024 * 1024)).round();
        throw StateError(
          'O vídeo pesa ${sizeMb}MB. Para manter a velocidade igual à Web, '
          'selecione vídeos de até ${limitMb}MB ou grave em qualidade menor.',
        );
      }
      final useOriginal = _isIosNative
          ? byteLen <= hardLimitBytes &&
              (lower.endsWith('.mp4') ||
                  lower.endsWith('.m4v') ||
                  lower.endsWith('.mov'))
          : byteLen <= mediaVideoSkipTranscodeMaxBytes &&
              (lower.endsWith('.mp4') || lower.endsWith('.m4v'));

      late final File compressed;
      if (useOriginal) {
        compressed = File(path);
      } else if (_isIosNative) {
        // iOS: evita transcode pesado no aparelho — CF gera thumb depois.
        compressed = File(path);
      } else {
        final mediaInfo = await MediaService.compressVideo(File(path));
        if (mediaInfo == null || mediaInfo.file == null) return null;
        compressed = mediaInfo.file!;
      }

      await firebaseDefaultAuth.currentUser?.getIdToken();
      final slot = videoSlotIndex.clamp(0, 1);
      await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
        tenantId: tenantId,
        postDocId: eventPostDocId,
        videoSlot: slot,
      );

      final videoPath =
          FeedTenantStorageMap.feedEventoHostedVideoMp4Path(
            tenantId,
            eventPostDocId,
            slot,
          );
      final thumbPath = FeedTenantStorageMap.feedEventoHostedVideoThumbPath(
        tenantId,
        eventPostDocId,
        slot,
      );

      onUploadProgress?.call(0.0);
      final videoUrl = await MediaUploadService.uploadFileWithRetry(
        storagePath: videoPath,
        file: compressed,
        contentType: 'video/mp4',
        onProgress: onUploadProgress,
      );

      String thumbUrl = '';
      if (!_isIosNative) {
        final thumbFile = await MediaService.getVideoThumbnail(compressed);
        if (thumbFile != null && thumbFile.existsSync()) {
          thumbUrl = await MediaUploadService.uploadFileWithRetry(
            storagePath: thumbPath,
            file: thumbFile,
            contentType: 'image/jpeg',
          );
        }
      }

      return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
    } finally {
      await VideoCompress.deleteAllCache();
    }
  }
}
