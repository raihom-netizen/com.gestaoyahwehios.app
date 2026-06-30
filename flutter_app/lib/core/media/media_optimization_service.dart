import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:gestao_yahweh/core/media/media_optimization_isolate.dart';
import 'package:gestao_yahweh/core/media/media_optimization_profile.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/yahweh_heavy_work.dart';
import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/web_image_compress_service.dart';

/// Resultado da otimização — pronto para upload ou preview otimista.
class OptimizedMediaPayload {
  const OptimizedMediaPayload({
    required this.fullBytes,
    required this.fullMime,
    required this.fullFileName,
    this.thumbBytes,
    this.previewBytes,
    this.optimizedLocalPath,
  });

  final Uint8List fullBytes;
  final String fullMime;
  final String fullFileName;
  final Uint8List? thumbBytes;

  /// Miniatura leve para bolha instantânea (≤320px).
  final Uint8List? previewBytes;

  /// Path local do vídeo já comprimido (mobile).
  final String? optimizedLocalPath;
}

/// Camada única de compressão pré-upload — **fora da main thread** quando possível.
abstract final class MediaOptimizationService {
  MediaOptimizationService._();

  static bool _looksLikeWebp(Uint8List list) {
    return list.length >= 12 &&
        list[0] == 0x52 &&
        list[1] == 0x49 &&
        list[2] == 0x46 &&
        list[3] == 0x46 &&
        list[8] == 0x57 &&
        list[9] == 0x45 &&
        list[10] == 0x42 &&
        list[11] == 0x50;
  }

  static String _mimeFor(Uint8List bytes) =>
      _looksLikeWebp(bytes) ? 'image/webp' : 'image/jpeg';

  static String _fileNameFor(Uint8List bytes, {String prefix = 'media'}) {
    final ext = _looksLikeWebp(bytes) ? 'webp' : 'jpg';
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  /// Compressão genérica — isolate em mobile, inline na web.
  static Future<Uint8List> optimizeImageBytes(
    Uint8List raw, {
    MediaOptimizationProfile profile = MediaOptimizationProfile.general,
  }) async {
    if (raw.isEmpty) return raw;
    if (kIsWeb) {
      return _optimizeWeb(raw, profile);
    }
    final msg = profileToMessage(raw, profile);
    return YahwehHeavyWork.run(mediaOptimizeImageIsolate, msg);
  }

  static Future<Uint8List> _optimizeWeb(
    Uint8List raw,
    MediaOptimizationProfile profile,
  ) async {
    final webProfile = switch (profile) {
      MediaOptimizationProfile.chat => MediaImageProfile.chat,
      MediaOptimizationProfile.profile => MediaImageProfile.patrimonio,
      MediaOptimizationProfile.receipt => MediaImageProfile.patrimonio,
      MediaOptimizationProfile.thumbPreview ||
      MediaOptimizationProfile.thumbUpload =>
        MediaImageProfile.thumb,
      _ => MediaImageProfile.feed,
    };
    return WebImageCompressService.compressBytes(
      input: raw,
      profile: webProfile,
    );
  }

  /// Chat — full ~150 KB + thumb + preview instantâneo (WhatsApp-style).
  static Future<OptimizedMediaPayload> optimizeForChat({
    Uint8List? bytes,
    String? localPath,
  }) async {
    Uint8List source;
    if (bytes != null && bytes.isNotEmpty) {
      source = Uint8List.fromList(bytes);
    } else if (!kIsWeb && localPath != null && localPath.trim().isNotEmpty) {
      source = await YahwehHeavyWork.readFileBytes(localPath.trim())
          .then((b) => Uint8List.fromList(b));
    } else {
      throw StateError('Sem dados para otimizar imagem do chat.');
    }

    final preview = await optimizeImageBytes(
      source,
      profile: MediaOptimizationProfile.thumbPreview,
    );

    final full = await optimizeImageBytes(
      source,
      profile: MediaOptimizationProfile.chat,
    );
    final thumb = await optimizeImageBytes(
      source,
      profile: MediaOptimizationProfile.thumbUpload,
    );

    return OptimizedMediaPayload(
      fullBytes: full,
      fullMime: _mimeFor(full),
      fullFileName: _fileNameFor(full, prefix: 'chat'),
      thumbBytes: thumb.isNotEmpty ? thumb : null,
      previewBytes: preview.isNotEmpty ? preview : full,
    );
  }

  /// Comprovante financeiro / foto patrimonial — 1280px, 75% (isolate em mobile).
  static Future<Uint8List> optimizeForReceipt(Uint8List raw) async {
    if (raw.isEmpty) return raw;
    return optimizeImageBytes(raw, profile: MediaOptimizationProfile.receipt);
  }

  /// Compressão de ficheiro em isolate — retorna JPEG otimizado no diretório temp.
  static Future<File> compressReceiptImage(File file) async {
    final raw = await file.readAsBytes();
    if (raw.isEmpty) {
      throw StateError('Ficheiro de comprovante vazio.');
    }
    if (kIsWeb) {
      final optimized = await optimizeForReceipt(raw);
      final tempDir = await getTemporaryDirectory();
      final out = File(
        '${tempDir.path}/optimized_rcpt_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(optimized, flush: true);
      return out;
    }
    final tempDir = await getTemporaryDirectory();
    final args = <String, dynamic>{
      'raw': raw,
      'tempDir': tempDir.path,
    };
    final outputPath = await compute(_isolateCompressReceiptHandler, args);
    return File(outputPath);
  }

  static Future<String> _isolateCompressReceiptHandler(
    Map<String, dynamic> args,
  ) async {
    final raw = args['raw'] as Uint8List;
    final tempDir = args['tempDir'] as String;
    final optimized = mediaOptimizeImageIsolate(
      profileToMessage(raw, MediaOptimizationProfile.receipt),
    );
    if (optimized.isEmpty) {
      throw StateError('Falha na compressão isolada do documento.');
    }
    final targetPath =
        '$tempDir/optimized_rcpt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(targetPath).writeAsBytes(optimized, flush: true);
    return targetPath;
  }

  /// Foto de perfil — 512×512.
  static Future<OptimizedMediaPayload> optimizeForProfile(Uint8List raw) async {
    final full = await optimizeImageBytes(
      raw,
      profile: MediaOptimizationProfile.profile,
    );
    final thumb = await optimizeImageBytes(
      raw,
      profile: MediaOptimizationProfile.thumbUpload,
    );
    return OptimizedMediaPayload(
      fullBytes: full,
      fullMime: _mimeFor(full),
      fullFileName: _fileNameFor(full, prefix: 'profile'),
      thumbBytes: thumb.isNotEmpty ? thumb : null,
      previewBytes: thumb.isNotEmpty ? thumb : full,
    );
  }

  /// Vídeo chat — transcode + thumbnail (delega [ChurchChatMediaPrepare]).
  static Future<OptimizedMediaPayload?> optimizeVideoForChat(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
  }) async {
    if (kIsWeb || inputPath.trim().isEmpty) return null;
    final prepared = await ChurchChatMediaPrepare.prepareVideo(
      inputPath,
      onCompressProgress: onCompressProgress,
    );
    if (prepared == null) return null;
    return OptimizedMediaPayload(
      fullBytes: Uint8List(0),
      fullMime: 'video/mp4',
      fullFileName: 'video.mp4',
      thumbBytes: prepared.thumbnailBytes,
      previewBytes: prepared.thumbnailBytes,
      optimizedLocalPath: prepared.outputPath,
    );
  }

  /// Preview rápido a partir de path (bolha local antes da compressão full).
  static Future<Uint8List?> previewFromPath(String path) async {
    if (path.trim().isEmpty) return null;
    try {
      return await SafeImageBytes.fromPath(
        path,
        maxEdge: MediaOptimizationLimits.thumbPreviewEdge,
        quality: MediaOptimizationLimits.thumbPreviewQuality,
      );
    } catch (_) {
      return null;
    }
  }

  /// Converte [PreparedChatImage] legado → payload unificado.
  static OptimizedMediaPayload fromPreparedChatImage(PreparedChatImage p) =>
      OptimizedMediaPayload(
        fullBytes: p.fullBytes,
        fullMime: p.fullMime,
        fullFileName: p.fullFileName,
        thumbBytes: p.thumbBytes,
        previewBytes: p.thumbBytes ?? p.fullBytes,
      );
}
