import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

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
    Duration maxDuration = const Duration(seconds: 60),
  }) async {
    final xfile = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: maxDuration,
    );
    if (xfile == null) return null;

    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final bytes = await xfile.readAsBytes();
    final ext = xfile.mimeType?.toString().contains('mp4') == true ? 'mp4' : 'mp4';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final videoUrl = await MediaUploadService.uploadBytesWithRetry(
      storagePath: 'igrejas/$tenantId/eventos/videos/${ts}_video.$ext',
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
            storagePath: 'igrejas/$tenantId/eventos/thumbs/${ts}_thumb.jpg',
            bytes: thumbBytes,
            contentType: 'image/jpeg',
          );
        } catch (_) {}
      }
    }

    return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
  }
}
