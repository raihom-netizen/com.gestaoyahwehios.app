import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/media_video_compress_quality.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp, kEffectiveFeedEncodeMaxEdgePx, kEffectiveMuralFeedWebpQuality;
import 'package:gestao_yahweh/services/web_image_compress_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:gestao_yahweh/services/yahweh_isolate_compress.dart';
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

  /// Chat: 800px JPEG ~70% (upload ultra-rápido em 4G).
  static const int chatImageMaxEdge = 800;
  /// Feed (avisos/eventos) ? 1440px WebP ~75% (bom visual + upload leve).
  static const int feedImageMaxEdge = 1440;
  static const int feedImageMaxHeight = 1440;
  static const int thumbMaxEdge = 480;

  static const int chatJpegQuality = 70;
  /// Qualidade feed ? 75% (visual bom, ~50% do tamanho do 85%).
  static const int feedWebpQuality = 75;
  static const int thumbJpegQuality = 72;

  static const int patrimonioImageMaxEdge = 1200;
  static const int patrimonioWebpQuality = 70;

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

  /// Leitura multiplataforma ? preferir isto em vez de `File(path).readAsBytes()`.
  static Future<Uint8List> readXFileBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio ? selecione outro.');
    }
    return bytes;
  }

  /// Compacta [XFile] ? Web (Dart puro) ou mobile (nativo).
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

  /// Comprime [File] de imagem ? reduz ~6 MB para <400 KB mantendo nitidez em smartphones.
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
    // Isolate compression (Controle Total pattern) ? no UI blocking.
    final isolateProfile = _isolateProfileFor(profile);
    final compressed = await YahwehIsolateCompress.compress(input, profile: isolateProfile);
    if (compressed.isNotEmpty && compressed.length < input.length) return compressed;
    // Fallback: platform channel (legacy path).
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

  /// Maps MediaImageProfile to YahwehCompressProfile for isolate compression.
  static YahwehCompressProfile _isolateProfileFor(MediaImageProfile profile) {
    return switch (profile) {
      MediaImageProfile.chat => YahwehCompressProfile.chat,
      MediaImageProfile.feed => YahwehCompressProfile.feed,
      MediaImageProfile.thumb => YahwehCompressProfile.thumb,
      MediaImageProfile.patrimonio => YahwehCompressProfile.patrimonio,
    };
  }

  /// Comprime ficheiro de imagem no disco ? bytes (chat/upload).
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
  /// Um encode de cada vez pode publicar progresso: o `compressProgress$` do
  /// `video_compress` é um StreamController **single-subscription** global —
  /// dois `subscribe` em simultâneo rebentam com «already been listened to».
  static bool _compressProgressBusy = false;

  static Future<MediaInfo?> compressVideo(
    File file, {
    void Function(double progress01)? onProgress,
  }) async {
    if (kIsWeb || !file.existsSync()) return null;
    Subscription? sub;
    try {
      final byteLen = await file.length();
      final quality = videoCompressQualityForByteLength(byteLen);
      // Sem isto o encode era uma caixa-preta: a barra «A publicar mídia…»
      // ficava parada nos 14% durante todo o tempo de transcodificação (que
      // num vídeo de 1–2 min é a maior fatia da espera).
      if (onProgress != null && !_compressProgressBusy) {
        _compressProgressBusy = true;
        sub = VideoCompress.compressProgress$.subscribe((p) {
          final v = p.isNaN ? 0.0 : (p / 100).clamp(0.0, 1.0).toDouble();
          onProgress(v);
        });
      }
      return await VideoCompress.compressVideo(
        file.path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
        // Fixar 30 fps: telemóveis gravam a 60 fps por defeito e isso é o
        // dobro do ficheiro (e do tempo de envio) sem ganho visível no feed.
        frameRate: 30,
      );
    } catch (_) {
      return null;
    } finally {
      if (sub != null) {
        try {
          sub.unsubscribe();
        } catch (_) {}
        _compressProgressBusy = false;
      }
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
        generateThumbnail: false,
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
    final hardMax = mediaVideoHardMaxBytesEffective;

    final skipTranscode = !forceTranscode &&
        byteLen <= mediaVideoSkipTranscodeMaxBytes &&
        (lower.endsWith('.mp4') || lower.endsWith('.m4v'));

    // O bruto de 2 min em 1080p/4K passa fácil dos 100 MB: o teto só pode ser
    // aplicado ao ficheiro que sai do encoder, senão vídeos publicáveis eram
    // rejeitados sem sequer tentar comprimir.
    if (byteLen > (skipTranscode ? hardMax : kMediaEventVideoRawMaxBytes)) {
      final limitMb =
          ((skipTranscode ? hardMax : kMediaEventVideoRawMaxBytes) /
                  (1024 * 1024))
              .round();
      throw StateError(
        'Vídeo muito grande. Reduza para até ${limitMb}MB ou grave mais curto.',
      );
    }

    onCompressProgress?.call(0.05);
    File resolved = file;
    if (!skipTranscode) {
      final info = await compressVideo(file)
          .timeout(kMediaVideoTranscodeTimeout, onTimeout: () => null);
      onCompressProgress?.call(0.75);
      if (info?.file != null && info!.file!.existsSync()) {
        resolved = info.file!;
      }
    }
    if (await resolved.length() > hardMax) {
      final limitMb = (hardMax / (1024 * 1024)).round();
      throw StateError(
        'Mesmo comprimido o vídeo passa de ${limitMb}MB. Grave mais curto '
        'ou em qualidade menor.',
      );
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

    // Skip transcode: MP4/M4V/3GP under skip threshold (16MB turbo).
    final skipTranscode = byteLen <= mediaVideoSkipTranscodeMaxBytes &&
        (lower.endsWith('.mp4') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.3gp'));

    onCompressProgress?.call(0.08);
    File resolved = file;
    if (!skipTranscode && byteLen > 16 * 1024 * 1024) {
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
