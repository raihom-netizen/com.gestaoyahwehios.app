import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';
import 'video_thumb_capture.dart';

/// Web: upload + miniatura via primeiro frame (canvas). Demais plataformas: [video_handler_service_io].
class VideoHandlerService implements IVideoHandlerService {
  VideoHandlerService._();
  static final VideoHandlerService instance = VideoHandlerService._();

  final ImagePicker _picker = ImagePicker();

  Future<VideoUploadResult?> _uploadVideoBytes({
    required Uint8List bytes,
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    required String mime,
    void Function(double uploadProgress01)? onUploadProgress,
    int? maxRawPickBytes,
  }) async {
    final hardLimitBytes = mediaVideoHardMaxBytesEffective;
    final pickLimit = maxRawPickBytes ?? hardLimitBytes;
    if (bytes.length > pickLimit) {
      final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      final limitMb = (pickLimit / (1024 * 1024)).round();
      throw StateError(
        'O vídeo pesa ${sizeMb}MB. Para manter a velocidade igual à Web, '
        'selecione vídeos de até ${limitMb}MB ou grave em qualidade menor.',
      );
    }
    await FirebaseAuth.instance.currentUser?.getIdToken();
    final slot = videoSlotIndex.clamp(0, 1);
    await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
      tenantId: tenantId,
      postDocId: eventPostDocId,
      videoSlot: slot,
    );

    final videoPath = FeedTenantStorageMap.feedEventoHostedVideoMp4Path(
      tenantId,
      eventPostDocId,
      slot,
    );
    final thumbPath = FeedTenantStorageMap.feedEventoHostedVideoThumbPath(
      tenantId,
      eventPostDocId,
      slot,
    );

    final videoFuture = MediaUploadService.uploadBytesWithRetry(
      storagePath: videoPath,
      bytes: bytes,
      contentType: mime,
      onProgress: onUploadProgress,
    );
    final thumbBytesFuture = kIsWeb
        ? captureVideoFirstFrameJpeg(bytes, mimeType: mime)
        : Future<Uint8List?>.value(null);
    final done = await Future.wait<Object?>([videoFuture, thumbBytesFuture]);
    final videoUrl = done[0]! as String;
    final thumbBytes = done[1] as Uint8List?;

    String thumbUrl = '';
    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      try {
        thumbUrl = await MediaUploadService.uploadBytesWithRetry(
          storagePath: thumbPath,
          bytes: thumbBytes,
          contentType: 'image/jpeg',
        );
      } catch (_) {}
    }

    return VideoUploadResult(
      videoUrl: videoUrl,
      thumbUrl: thumbUrl,
      videoStoragePath: videoPath,
      thumbStoragePath: thumbPath,
    );
  }

  @override
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    Duration maxDuration = kMediaVideoMaxDuration,
    void Function(double uploadProgress01)? onUploadProgress,
    int? maxRawPickBytes,
  }) async {
    await ensureFirebaseInitialized();
    final effectiveMaxDuration =
        maxDuration < mediaVideoMaxDurationEffective
            ? maxDuration
            : mediaVideoMaxDurationEffective;
    final xfile = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: effectiveMaxDuration,
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();
    return _uploadVideoBytes(
      bytes: bytes,
      tenantId: tenantId,
      eventPostDocId: eventPostDocId,
      videoSlotIndex: videoSlotIndex,
      mime: xfile.mimeType ?? 'video/mp4',
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
    if (localPath.isEmpty) return null;
    final bytes = await XFile(localPath).readAsBytes();
    return _uploadVideoBytes(
      bytes: bytes,
      tenantId: tenantId,
      eventPostDocId: eventPostDocId,
      videoSlotIndex: videoSlotIndex,
      mime: 'video/mp4',
      onUploadProgress: onUploadProgress,
      maxRawPickBytes: maxRawPickBytes,
    );
  }
}
