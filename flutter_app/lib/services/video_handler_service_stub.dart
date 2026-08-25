import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'firebase_storage_cleanup_service.dart';
import 'media_upload_service.dart';
import 'video_handler_service_types.dart';

/// Web: envio direto do vídeo ao Storage, sem criar arquivo de capa.
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
    Uint8List? precomputedThumbBytes,
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
    await firebaseDefaultAuth.currentUser?.getIdToken();
    final slot = videoSlotIndex.clamp(0, 1);
    await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
      tenantId: tenantId,
      postDocId: eventPostDocId,
      videoSlot: slot,
    );

    final videoPath = slot <= 0
        ? ChurchStorageLayout.eventHostedVideoPrincipalPath(
            tenantId,
            eventPostDocId,
          )
        : ChurchStorageLayout.eventHostedVideoMp4Path(
            tenantId,
            eventPostDocId,
            slot,
          );
    final videoUrl = await MediaUploadService.uploadBytesWithRetry(
      storagePath: videoPath,
      bytes: bytes,
      contentType: mime,
      onProgress: onUploadProgress,
    );

    return VideoUploadResult(
      videoUrl: videoUrl,
      thumbUrl: '',
      videoStoragePath: videoPath,
      thumbStoragePath: '',
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
    Uint8List? precomputedThumbBytes,
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
      precomputedThumbBytes: precomputedThumbBytes,
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
    Uint8List? precomputedThumbBytes,
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
      precomputedThumbBytes: precomputedThumbBytes,
    );
  }
}

