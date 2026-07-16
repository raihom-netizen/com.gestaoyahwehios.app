import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart'
    show kEventoAvisoFeedEncodeMaxEdgePx, kEventoAvisoFeedWebpQuality;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/media_video_compress_quality.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp, kEffectiveFeedEncodeMaxEdgePx, kEffectiveMuralFeedWebpQuality;
import 'package:gestao_yahweh/services/web_image_compress_service.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';

/// Perfil de compressão — nitidez alta em telas mobile, ficheiros leves para upload rápido.
enum MediaImageProfile {
  /// Chat: 1280px, JPEG ~80% (~200–400 KB típico).
  chat,

  /// Avisos/eventos mural: WebP Full HD 1920px, quality ~85%.
  feed,

  /// Miniaturas / previews.
  thumb,

  /// Patrimônio: WebP 1920px, quality ~78%.
  patrimonio,
}

/// Resultado da preparação de vídeo antes do upload.
class MediaVideoPrepareResult {
  const MediaVideoPrepareResult({
    required this.outputPath,
    this.thumbnailBytes,
    this.thumbnailFile,
  });

  final String outputPath;
  final Uint8List? thumbnailBytes;
  final File? thumbnailFile;
}

/// Compressão centralizada (imagens, vídeos, áudio) — WhatsApp-style, sem bloquear UI.
///
/// **Envio instantâneo do chat** (stub Firestore + background): [ChurchChatInstantSendService].
abstract final class MediaService {
  MediaService._();

  static const int chatImageMaxEdge = 1024;
  /// Feed (avisos/eventos) — alinhado a [kEventoAvisoFeedEncodeMaxEdgePx] (1920).
  static const int feedImageMaxEdge = kEventoAvisoFeedEncodeMaxEdgePx;
  static const int feedImageMaxHeight = kEventoAvisoFeedEncodeMaxEdgePx;
  static const int thumbMaxEdge = 480;

  static const int chatJpegQuality = kStandardUploadImageQuality;
  /// Qualidade feed — alinhada a [kEventoAvisoFeedWebpQuality] (85).
  static const int feedWebpQuality = kEventoAvisoFeedWebpQuality;
  static const int thumbJpegQuality = 78;

  static const int patrimonioImageMaxEdge = kStandardUploadImageMaxEdge;
  static const int patrimonioWebpQuality = kStandardUploadImageQuality;

  static int _edgeFor(MediaImageProfile profile) => switch (profile) {
        MediaImageProfile.chat => chatImageMaxEdge,
        MediaImageProfile.feed =>
          kEffectiveFeedEncodeMaxEdgePx.clamp(960, feedImageMaxEdge),
        MediaImageProfile.thumb => thumbMaxEdge,
        MediaImageProfile.patrimonio => patrimonioImageMaxEdge,
      };

  static int _qualityFor(MediaImageProfile profile) => switch (profile) {
        MediaImageProfile.chat => chatJpegQuality,
        MediaImageProfile.feed =>
          kEffectiveMuralFeedWebpQuality.clamp(74, feedWebpQuality),
        MediaImageProfile.thumb => thumbJpegQuality,
        MediaImageProfile.patrimonio => patrimonioWebpQuality,
      };

  static CompressFormat _formatFor(MediaImageProfile profile) {
    return profile == MediaImageProfile.feed ||
            profile == MediaImageProfile.patrimonio ||
            profile == MediaImageProfile.thumb
        ? CompressFormat.webp
        : CompressFormat.jpeg;
  }

  static String _fileExtFor(MediaImageProfile profile) {
    return profile == MediaImageProfile.feed ||
            profile == MediaImageProfile.patrimonio ||
            profile == MediaImageProfile.thumb
        ? 'webp'
        : 'jpg';
  }

  /// MIME de saída após compactação — Web tende a JPEG; mobile feed/património WebP.
  static String contentTypeForProfile(
    MediaImageProfile profile,
    Uint8List bytes,
  ) {
    if (bytesLookLikeWebp(bytes)) return 'image/webp';
    if (kIsWeb) return 'image/jpeg';
    return _formatFor(profile) == CompressFormat.webp ? 'image/webp' : 'image/jpeg';
  }

  /// Leitura multiplataforma — preferir isto em vez de `File(path).readAsBytes()`.
  static Future<Uint8List> readXFileBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    return bytes;
  }

  /// Compacta [XFile] — Web (Dart puro) ou mobile (nativo).
  static Future<({Uint8List bytes, String contentType})> compressXFile(
    XFile file, {
    MediaImageProfile profile = MediaImageProfile.feed,
  }) async {
    final raw = await readXFileBytes(file);
    final bytes = await compressImageBytes(raw, profile: profile);
    return (
      bytes: bytes,
      contentType: contentTypeForProfile(profile, bytes),
    );
  }

  /// Comprime [File] de imagem — reduz ~6 MB para <400 KB mantendo nitidez em smartphones.
  static Future<File?> compressImage(
    File file, {
    MediaImageProfile profile = MediaImageProfile.feed,
  }) async {
    if (kIsWeb || !file.existsSync()) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;
      // Só compressão por bytes (Web = Android = iOS). Sem compressAndGetFile.
      try {
        final compressed = await compressImageBytes(raw, profile: profile);
        if (compressed.isNotEmpty) {
          final ext = _formatFor(profile) == CompressFormat.webp ? 'webp' : 'jpg';
          final targetPath =
              '${tempDir.path}/gy_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final out = File(targetPath);
          await out.writeAsBytes(compressed, flush: true);
          if (out.existsSync() && out.lengthSync() > 0) return out;
        }
      } catch (_) {}

      final fallbackPath =
          '${tempDir.path}/gy_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fallback = File(fallbackPath);
      await fallback.writeAsBytes(raw, flush: true);
      return fallback.existsSync() && fallback.lengthSync() > 0 ? fallback : null;
    } catch (_) {
      return null;
    }
  }

  /// Comprime bytes de imagem conforme [profile].
  ///
  /// **Web:** [WebImageCompressService] (pacote `image`, Dart puro).
  /// **Mobile:** `flutter_image_compress` (nativo, mais rápido).
  static Future<Uint8List> compressImageBytes(
    Uint8List input, {
    MediaImageProfile profile = MediaImageProfile.chat,
  }) async {
    if (input.isEmpty) return input;
    if (kIsWeb) {
      return WebImageCompressService.compressBytes(
        input: input,
        profile: profile,
      );
    }
    if (profile == MediaImageProfile.feed && bytesLookLikeWebp(input)) {
      return input;
    }

    final edge = _edgeFor(profile);
    final quality = _qualityFor(profile);
    final formats = <CompressFormat>[
      _formatFor(profile),
      if (_formatFor(profile) != CompressFormat.jpeg) CompressFormat.jpeg,
    ];
    for (final format in formats) {
      try {
        final out = await FlutterImageCompress.compressWithList(
          input,
          minWidth: edge,
          minHeight: edge,
          quality: quality,
          format: format,
        );
        if (out.isNotEmpty) return Uint8List.fromList(out);
      } catch (_) {}
    }
    return input;
  }

  /// Comprime ficheiro de imagem no disco → bytes (chat/upload).
  static Future<Uint8List?> compressImageFile(
    String path, {
    MediaImageProfile profile = MediaImageProfile.chat,
  }) async {
    if (path.isEmpty || kIsWeb) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    final compressed = await compressImage(file, profile: profile);
    if (compressed == null) {
      final raw = await file.readAsBytes();
      return raw.isEmpty ? null : raw;
    }
    final bytes = await compressed.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  /// Comprime vídeo (H.264/AAC) — 720p ou 480p conforme tamanho do ficheiro.
  ///
  /// **Web:** não transcodifica (`video_compress` é nativo) — envia ficheiro original
  /// ou bloqueia no picker conforme o módulo.
  static Future<MediaInfo?> compressVideo(File file) async {
    if (kIsWeb || !file.existsSync()) return null;
    try {
      final byteLen = await file.length();
      final quality = videoCompressQualityForByteLength(byteLen);
      return await VideoCompress.compressVideo(
        file.path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Eventos (até 2×90s): sempre transcode H.264/AAC 720p/480p + miniatura antes do upload.
  static Future<MediaVideoPrepareResult?> prepareEventVideoForUpload(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
  }) =>
      prepareVideoForUpload(
        inputPath,
        onCompressProgress: onCompressProgress,
        generateThumbnail: true,
        forceTranscode: true,
      );

  /// Miniatura instantânea do vídeo (chat/eventos).
  static Future<File?> getVideoThumbnail(
    File file, {
    int quality = 50,
  }) async {
    if (kIsWeb || !file.existsSync()) return null;
    try {
      return await VideoCompress.getFileThumbnail(
        file.path,
        quality: quality,
        position: -1,
      );
    } catch (_) {
      return null;
    }
  }

  /// Vídeo: transcode leve + miniatura (mobile).
  static Future<MediaVideoPrepareResult?> prepareVideoForUpload(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
    bool generateThumbnail = true,
    bool forceTranscode = false,
  }) async {
    if (kIsWeb || inputPath.isEmpty) {
      return MediaVideoPrepareResult(outputPath: inputPath);
    }
    final file = File(inputPath);
    if (!file.existsSync()) return null;

    final lower = inputPath.toLowerCase();
    final byteLen = await file.length();
    if (byteLen > mediaVideoHardMaxBytesEffective) {
      final limitMb = (mediaVideoHardMaxBytesEffective / (1024 * 1024)).round();
      throw StateError(
        'Vídeo muito grande. Reduza para até ${limitMb}MB ou grave mais curto.',
      );
    }

    final skipTranscode = !forceTranscode &&
        byteLen <= mediaVideoSkipTranscodeMaxBytes &&
        (lower.endsWith('.mp4') || lower.endsWith('.m4v'));

    onCompressProgress?.call(0.05);
    File resolved = file;
    if (!skipTranscode) {
      final info = await compressVideo(file)
          .timeout(const Duration(minutes: 4), onTimeout: () => null);
      onCompressProgress?.call(0.75);
      if (info?.file != null && info!.file!.existsSync()) {
        resolved = info.file!;
      }
    }

    File? thumbFile;
    if (generateThumbnail) {
      thumbFile = await getVideoThumbnail(resolved)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
    }
    Uint8List? thumbBytes;
    if (thumbFile != null && thumbFile.existsSync()) {
      thumbBytes = await thumbFile.readAsBytes();
    }
    onCompressProgress?.call(1.0);
    return MediaVideoPrepareResult(
      outputPath: resolved.path,
      thumbnailBytes: thumbBytes,
      thumbnailFile: thumbFile,
    );
  }

  /// Chat: compressão leve + miniatura (preview antes de abrir o vídeo).
  static Future<MediaVideoPrepareResult?> prepareVideoForChatUpload(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
  }) async {
    if (kIsWeb || inputPath.isEmpty) {
      return MediaVideoPrepareResult(outputPath: inputPath);
    }
    final file = File(inputPath);
    if (!file.existsSync()) return null;

    final lower = inputPath.toLowerCase();
    final byteLen = await file.length();
    if (byteLen > mediaChatVideoHardMaxBytesEffective) {
      final limitMb =
          (mediaChatVideoHardMaxBytesEffective / (1024 * 1024)).round();
      throw StateError(
        'Vídeo muito grande. Reduza para até ${limitMb}MB ou grave mais curto.',
      );
    }

    final skipTranscode = byteLen <= mediaVideoSkipTranscodeMaxBytes &&
        (lower.endsWith('.mp4') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.3gp'));

    onCompressProgress?.call(0.08);
    File resolved = file;
    if (!skipTranscode && byteLen > 8 * 1024 * 1024) {
      final info = await compressVideo(file).timeout(
        const Duration(minutes: 2),
        onTimeout: () => null,
      );
      onCompressProgress?.call(0.55);
      if (info?.file != null && info!.file!.existsSync()) {
        resolved = info.file!;
      }
    }
    onCompressProgress?.call(0.58);
    File? thumbFile;
    thumbFile = await getVideoThumbnail(resolved)
        .timeout(const Duration(seconds: 25), onTimeout: () => null);
    Uint8List? thumbBytes;
    if (thumbFile != null && thumbFile.existsSync()) {
      thumbBytes = await thumbFile.readAsBytes();
    }
    onCompressProgress?.call(0.62);
    return MediaVideoPrepareResult(
      outputPath: resolved.path,
      thumbnailBytes: thumbBytes,
      thumbnailFile: thumbFile,
    );
  }

  /// Config recomendada para gravação de voz no chat (AAC/M4A compacto).
  static RecordConfig chatVoiceRecordConfig({required AudioEncoder encoder}) {
    return RecordConfig(
      encoder: encoder,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
    );
  }
}
