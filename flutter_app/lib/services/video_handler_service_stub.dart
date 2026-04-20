import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';
import 'video_thumb_capture.dart';

/// Web: upload + miniatura via primeiro frame (canvas). Demais plataformas: [video_handler_service_io].
class VideoHandlerService implements IVideoHandlerService {
  VideoHandlerService._();
  static final VideoHandlerService instance = VideoHandlerService._();

  final ImagePicker _picker = ImagePicker();
  @override
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    Duration maxDuration = kMediaVideoMaxDuration,
    void Function(double uploadProgress01)? onUploadProgress,
  }) async {
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
    final hardLimitBytes = mediaVideoHardMaxBytesEffective;
    if (bytes.length > hardLimitBytes) {
      final limitMb = (hardLimitBytes / (1024 * 1024)).round();
      throw StateError(
          'Video muito grande para envio rápido. Reduza para até ${limitMb}MB.');
    }
    await FirebaseAuth.instance.currentUser?.getIdToken();
    final slot = videoSlotIndex.clamp(0, 1);
    await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
      tenantId: tenantId,
      postDocId: eventPostDocId,
      videoSlot: slot,
    );

    final videoPath =
        ChurchStorageLayout.eventHostedVideoMp4Path(tenantId, eventPostDocId, slot);
    final thumbPath =
        ChurchStorageLayout.eventHostedVideoThumbPath(tenantId, eventPostDocId, slot);

    final mime = xfile.mimeType ?? 'video/mp4';
    // Envio do vídeo e extração da miniatura em paralelo (web não comprime no cliente).
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

    return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
  }
}
