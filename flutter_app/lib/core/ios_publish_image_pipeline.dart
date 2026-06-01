import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';

/// Feed nativo (iOS/Android) — evita 3× WebP + 3 uploads no telemóvel.
///
/// Fluxo: comprimir para WebP ≤1080px (q75, igual web) → 1 upload → CF gera variantes.
abstract final class IosPublishImagePipeline {
  IosPublishImagePipeline._();

  static bool get _isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Avisos/eventos no app — mesmo caminho rápido que a PWA (1 ficheiro por foto).
  static bool get useNativeFastFeedUpload => _isNativeMobile;

  /// Retrocompat.
  static bool get useIosLightweightPublish => useNativeFastFeedUpload;

  static const int publishMaxEdge = kEventoAvisoFeedEncodeMaxEdgePx;
  static const int publishWebpQuality = kEventoAvisoFeedWebpQuality;
  static const int previewDecodeWidth = 300;

  /// Miniatura leve no editor (evita decode 12–48 MP no iPhone).
  static Widget fileThumbnail({
    required File file,
    required double size,
  }) {
    if (useNativeFastFeedUpload) {
      return Image(
        image: ResizeImage(
          FileImage(file),
          width: previewDecodeWidth,
          height: previewDecodeWidth,
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: previewDecodeWidth,
      filterQuality: FilterQuality.medium,
    );
  }

  static Future<Uint8List> compressForPublishFromPath(String path) async {
    if (kIsWeb) return Uint8List(0);
    if (useNativeFastFeedUpload) {
      return compute(_compressFileIsolate, path);
    }
    return _compressFileInline(path);
  }

  static Future<Uint8List> compressForPublishBytes(Uint8List raw) async {
    if (raw.isEmpty) return raw;
    if (useNativeFastFeedUpload) {
      return compute(_compressBytesIsolate, raw);
    }
    return _compressBytesInline(raw);
  }

  static Future<Uint8List> _compressFileInline(String path) async {
    try {
      final out = await FlutterImageCompress.compressWithFile(
        path,
        quality: publishWebpQuality,
        minWidth: publishMaxEdge,
        minHeight: publishMaxEdge,
        format: CompressFormat.webp,
        autoCorrectionAngle: true,
      );
      if (out != null && out.isNotEmpty) return Uint8List.fromList(out);
    } catch (e, st) {
      await YahwehTelemetry.recordNonFatal(e, st, reason: 'ios_compress_file');
    }
    final f = File(path);
    if (await f.exists()) {
      final raw = await f.readAsBytes();
      if (raw.length > 6 * 1024 * 1024) {
        throw StateError(
          'Imagem muito grande. Escolha outra foto ou reduza a resolução.',
        );
      }
      return raw;
    }
    return Uint8List(0);
  }

  static Future<Uint8List> _compressBytesInline(Uint8List raw) async {
    try {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        quality: publishWebpQuality,
        minWidth: publishMaxEdge,
        minHeight: publishMaxEdge,
        format: CompressFormat.webp,
      );
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (e, st) {
      await YahwehTelemetry.recordNonFatal(e, st, reason: 'ios_compress_bytes');
    }
    return raw;
  }

  /// Um único ficheiro no path canónico (CF `optimizeImage` gera thumb/medium/full).
  static Future<({
    String primaryUrl,
    Map<String, dynamic> imageVariants,
  })> uploadFeedPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    final Uint8List prepared;
    if (localPath != null && localPath.isNotEmpty) {
      prepared = await compressForPublishFromPath(localPath);
    } else if (bytes != null && bytes.isNotEmpty) {
      // Web: fotos já vêm em WebP do picker — não recomprimir (lentidão + erros).
      if (kIsWeb && bytesLookLikeWebp(bytes)) {
        prepared = bytes;
      } else {
        prepared = await compressForPublishBytes(bytes);
      }
    } else {
      throw StateError('Sem imagem para enviar.');
    }
    if (prepared.isEmpty) {
      throw StateError('Falha ao preparar imagem para envio.');
    }

    final storagePath = FeedTenantStorageMap.feedPhotoPath(
      postType: postType,
      tenantId: tenantId,
      postDocId: postId,
      slotIndex: slotIndex,
    );

    final contentType =
        bytesLookLikeWebp(prepared) ? 'image/webp' : 'image/jpeg';

    final url = await UnifiedUploadService.uploadImage(
      storagePath: storagePath,
      bytes: prepared,
      contentType: contentType,
      localPath: localPath,
      module: postType == 'aviso'
          ? YahwehUploadModule.aviso
          : YahwehUploadModule.evento,
      skipClientPrepare: true,
      onProgress: onProgress,
      maxAttempts: 3,
    );
    return (primaryUrl: url, imageVariants: const <String, dynamic>{});
  }
}

Future<Uint8List> _compressFileIsolate(String path) async {
  return IosPublishImagePipeline._compressFileInline(path);
}

Future<Uint8List> _compressBytesIsolate(Uint8List raw) async {
  return IosPublishImagePipeline._compressBytesInline(raw);
}

/// Libera RAM de decode após lote de uploads (evita Jetsam no iPhone).
abstract final class IosPublishMemory {
  IosPublishMemory._();

  static Future<void> releaseAfterHeavyWork() async {
    if (!IosPublishImagePipeline.useNativeFastFeedUpload) return;
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {}
  }
}
