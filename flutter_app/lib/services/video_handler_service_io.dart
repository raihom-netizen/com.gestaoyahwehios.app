import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_event_video_upload.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/video_duration.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'feed_editor_media_service.dart';
import 'firebase_storage_cleanup_service.dart';
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
    Uint8List? precomputedThumbBytes,
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
    final durationSec = await getVideoDurationSeconds(xfile);
    if (durationSec != null && durationSec > kMediaEventVideoMaxSeconds) {
      throw StateError(
        'Vídeo excede o limite de $kMediaEventVideoMaxSeconds segundos.',
      );
    }
    final localPath = await FeedEditorMediaService.persistVideoXFileToTemp(
      xfile,
      prefix: 'gy_event_video',
    );
    if (localPath == null || localPath.isEmpty) {
      throw StateError(
        'Não foi possível ler o vídeo da galeria. Tente outro ficheiro ou grave em MP4.',
      );
    }
    return compressAndUploadFromPath(
      localPath: localPath,
      tenantId: tenantId,
      eventPostDocId: eventPostDocId,
      videoSlotIndex: videoSlotIndex,
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
    final path = localPath;
    if (path.isEmpty || !File(path).existsSync()) return null;

    await EcoFirePublishBootstrap.ensureHard(
      logLabel: 'evento_video_prepare',
      strict: true,
    );

    try {
      final lower = path.toLowerCase();
      final original = File(path);
      final byteLen = await original.length();
      final hardLimitBytes = mediaEventVideoHardMaxBytesEffective;
      // O bruto pode ser grande (2 min de 1080p/4K): quem manda é o ficheiro
      // que sai do encoder. Rejeitar aqui pelo teto pós-compressão barrava
      // vídeos perfeitamente publicáveis.
      final rawLimit = maxRawPickBytes ?? kMediaEventVideoRawMaxBytes;
      if (byteLen > rawLimit) {
        final sizeMb = (byteLen / (1024 * 1024)).toStringAsFixed(1);
        final limitMb = (rawLimit / (1024 * 1024)).round();
        throw StateError(
          'O vídeo pesa ${sizeMb}MB — acima de ${limitMb}MB. '
          'Grave em qualidade menor ou use o campo de link (YouTube / Vimeo).',
        );
      }

      // Só o que já é leve sobe como está. Acima disso o encode por hardware
      // (MediaCodec no Android, AVAssetExportSession no iOS) é muito mais
      // barato do que arrastar o bruto por 4G — inclusive no iOS, que antes
      // nunca transcodificava e por isso subia ficheiros de dezenas de MB.
      final alreadyLight =
          byteLen <= mediaVideoSkipTranscodeMaxBytes &&
          (lower.endsWith('.mp4') ||
              lower.endsWith('.m4v') ||
              (_isIosNative && lower.endsWith('.mov')));

      File compressed = original;
      if (!alreadyLight) {
        File? encoded;
        try {
          final mediaInfo = await MediaService.compressVideo(original)
              .timeout(kMediaVideoTranscodeTimeout, onTimeout: () => null);
          final f = mediaInfo?.file;
          if (f != null && f.existsSync() && await f.length() > 0) {
            encoded = f;
          }
        } catch (_) {
          encoded = null;
        }
        if (encoded != null && await encoded.length() < byteLen) {
          compressed = encoded;
        } else if (byteLen > hardLimitBytes) {
          // Encode falhou/estourou o tempo e o bruto não cabe no Storage.
          final sizeMb = (byteLen / (1024 * 1024)).toStringAsFixed(1);
          final limitMb = (hardLimitBytes / (1024 * 1024)).round();
          throw StateError(
            'Não foi possível comprimir o vídeo (${sizeMb}MB) e o limite de '
            'envio é ${limitMb}MB. Grave mais curto ou em qualidade menor.',
          );
        }
      }
      if (await compressed.length() > hardLimitBytes) {
        final limitMb = (hardLimitBytes / (1024 * 1024)).round();
        throw StateError(
          'Mesmo comprimido o vídeo passa de ${limitMb}MB. '
          'Grave mais curto ou use o campo de link (YouTube / Vimeo).',
        );
      }

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
      final thumbPath = ChurchStorageLayout.eventHostedVideoThumbPath(
        tenantId,
        eventPostDocId,
        slot,
      );

      onUploadProgress?.call(0.0);

      // Miniatura estilo Instagram/YouTube — Android + iOS (falha não bloqueia o vídeo).
      // Gerada e enviada EM PARALELO ao vídeo (não mais depois dele): o
      // vídeo é o upload pesado, a miniatura é rápida — rodar em série só
      // somava tempo de espera sem necessidade.
      Future<String> uploadThumb() async {
        try {
          // O editor já extraiu a miniatura ao anexar — gerar de novo era
          // repetir um decode de vídeo (segundos) por nada.
          var thumbBytes = precomputedThumbBytes;
          if (thumbBytes == null || thumbBytes.isEmpty) {
            final thumbFile = await MediaService.getVideoThumbnail(compressed)
                .timeout(const Duration(seconds: 20), onTimeout: () => null);
            if (thumbFile != null && thumbFile.existsSync()) {
              thumbBytes = await thumbFile.readAsBytes();
            }
          }
          if (thumbBytes != null && thumbBytes.isNotEmpty) {
            return await EcoFireStorageUpload.putData(
              storagePath: thumbPath,
              bytes: thumbBytes,
              mimeType: 'image/jpeg',
            );
          }
        } catch (_) {}
        return '';
      }

      final results = await Future.wait([
        EcoFireEventVideoUpload.putVideoFile(
          storagePath: videoPath,
          file: compressed,
          onProgress: onUploadProgress,
        ),
        uploadThumb(),
      ]);
      final videoUrl = results[0];
      final thumbUrl = results[1];

      return VideoUploadResult(
        videoUrl: videoUrl,
        thumbUrl: thumbUrl,
        videoStoragePath: videoPath,
        thumbStoragePath: thumbPath,
      );
    } finally {
      await VideoCompress.deleteAllCache();
    }
  }
}
