import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';

/// Mobile (IO): MP4 pequeno envia direto (sem re-encoding); caso contrário 640×480 (mais rápido que 960).
/// Thumb + uploads em paralelo; progresso de rede opcional.
class VideoHandlerService implements IVideoHandlerService {
  VideoHandlerService._();
  static final VideoHandlerService instance = VideoHandlerService._();

  final ImagePicker _picker = ImagePicker();

  /// Acima disto o cliente re-encode para reduzir tempo de upload (HEVC/MOV grandes).
  static const int _maxBytesSkipTranscode = 26 * 1024 * 1024;

  @override
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    Duration maxDuration = const Duration(seconds: 60),
    void Function(double uploadProgress01)? onUploadProgress,
  }) async {
    final xfile = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: maxDuration,
    );
    if (xfile == null || xfile.path.isEmpty) return null;

    final path = xfile.path;
    if (!File(path).existsSync()) return null;

    try {
      final lower = path.toLowerCase();
      final byteLen = await File(path).length();
      final useOriginal = byteLen <= _maxBytesSkipTranscode &&
          (lower.endsWith('.mp4') || lower.endsWith('.m4v'));

      late final File compressed;
      if (useOriginal) {
        // Evita minutos de CPU em telemóveis: envia o ficheiro já em H.264/AAC típico da galeria.
        compressed = File(path);
      } else {
        // 640×480: transcodifica mais depressa e gera ficheiro menor (menos tempo na rede) que 960×540.
        final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.Res640x480Quality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (mediaInfo == null || mediaInfo.file == null) return null;
        compressed = mediaInfo.file!;
      }

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

      onUploadProgress?.call(0.0);
      final videoFuture = MediaUploadService.uploadFileWithRetry(
        storagePath: videoPath,
        file: compressed,
        contentType: 'video/mp4',
        onProgress: onUploadProgress,
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
      await VideoCompress.deleteAllCache();
    }
  }
}
