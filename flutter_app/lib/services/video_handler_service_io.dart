import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'media_upload_service.dart';
import 'video_handler_service_types.dart';

/// Mobile (IO): compressão com video_compress (MediumQuality) e geração de thumbnail.
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
    if (xfile == null || xfile.path.isEmpty) return null;

    final path = xfile.path;
    if (!File(path).existsSync()) return null;

    try {
      // 1. Compressão — equilíbrio ideal entre peso e qualidade visual.
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (mediaInfo == null || mediaInfo.file == null) return null;

      // 2. Thumbnail — preview instantâneo no feed/listas.
      File? thumbFile;
      try {
        thumbFile = await VideoCompress.getFileThumbnail(path);
      } catch (_) {}

      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // 3. Upload do vídeo comprimido
      final videoUrl = await MediaUploadService.uploadFileWithRetry(
        storagePath: 'igrejas/$tenantId/eventos/videos/$timestamp.mp4',
        file: mediaInfo.file!,
        contentType: 'video/mp4',
      );

      // 4. Upload da miniatura
      String thumbUrl = '';
      if (thumbFile != null && thumbFile.existsSync()) {
        thumbUrl = await MediaUploadService.uploadFileWithRetry(
          storagePath: 'igrejas/$tenantId/eventos/thumbs/$timestamp.jpg',
          file: thumbFile,
          contentType: 'image/jpeg',
        );
      }

      return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
    } finally {
      // Evita ocupar armazenamento local após compressões sucessivas.
      await VideoCompress.deleteAllCache();
    }
  }
}
