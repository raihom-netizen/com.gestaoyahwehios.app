import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';

/// Mobile (IO): compressão rápida para feed (960×540), thumb do MP4 comprimido, uploads em paralelo.
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
    if (xfile == null || xfile.path.isEmpty) return null;

    final path = xfile.path;
    if (!File(path).existsSync()) return null;

    try {
      // 1. Compressão — 960×540: bem mais rápido que Medium/720p e suficiente para vídeos até 60s no mural.
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.Res960x540Quality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (mediaInfo == null || mediaInfo.file == null) return null;

      final compressed = mediaInfo.file!;

      // 2. Thumbnail a partir do MP4 já comprimido (ficheiro menor → extração mais leve).
      File? thumbFile;
      try {
        thumbFile = await VideoCompress.getFileThumbnail(compressed.path);
      } catch (_) {}

      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final slot = videoSlotIndex.clamp(0, 1);
      await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
        tenantId: tenantId,
        postDocId: eventPostDocId,
        videoSlot: slot,
      );

      final videoPath =
          ChurchStorageLayout.eventHostedVideoMp4Path(tenantId, eventPostDocId, slot);
      final thumbPath = ChurchStorageLayout.eventHostedVideoThumbPath(
          tenantId, eventPostDocId, slot);

      // 3. Upload vídeo + miniatura em paralelo (menos tempo total na rede).
      final videoFuture = MediaUploadService.uploadFileWithRetry(
        storagePath: videoPath,
        file: compressed,
        contentType: 'video/mp4',
      );
      final thumbFuture = (thumbFile != null && thumbFile.existsSync())
          ? MediaUploadService.uploadFileWithRetry(
              storagePath: thumbPath,
              file: thumbFile,
              contentType: 'image/jpeg',
            )
          : Future<String>.value('');
      final results = await Future.wait([videoFuture, thumbFuture]);
      final videoUrl = results[0];
      final thumbUrl = results[1];

      return VideoUploadResult(videoUrl: videoUrl, thumbUrl: thumbUrl);
    } finally {
      // Evita ocupar armazenamento local após compressões sucessivas.
      await VideoCompress.deleteAllCache();
    }
  }
}
