import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    Duration maxDuration = const Duration(seconds: 60),
  }) async {
    final xfile = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: maxDuration,
    );
    if (xfile == null) return null;

    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final bytes = await xfile.readAsBytes();
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

    final videoUrl = await MediaUploadService.uploadBytesWithRetry(
      storagePath: videoPath,
      bytes: bytes,
      contentType: xfile.mimeType ?? 'video/mp4',
    );

    String thumbUrl = '';
    if (kIsWeb) {
      final mime = xfile.mimeType ?? 'video/mp4';
      final thumbBytes = await captureVideoFirstFrameJpeg(bytes, mimeType: mime);
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        try {
          thumbUrl = await MediaUploadService.uploadBytesWithRetry(
            storagePath: thumbPath,
            bytes: thumbBytes,
            contentType: 'image/jpeg',
          );
        } catch (_) {}
      }
    }

    return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
  }
}
