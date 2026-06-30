import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart'
    show mediaChatVideoHardMaxBytesEffective;
import 'package:gestao_yahweh/services/media_service.dart';

/// Compressão obrigatória para fotos do Chat Igreja (nunca envia original).
class PreparedChatImage {
  PreparedChatImage({
    required this.fullBytes,
    required this.fullMime,
    required this.fullFileName,
    this.thumbBytes,
  });

  final Uint8List fullBytes;
  final String fullMime;
  final String fullFileName;
  final Uint8List? thumbBytes;
}

/// Vídeo comprimido + miniatura para preview no chat.
class PreparedChatVideo {
  PreparedChatVideo({
    required this.outputPath,
    this.thumbnailBytes,
    this.durationSeconds,
    this.byteLength,
  });

  final String outputPath;
  final Uint8List? thumbnailBytes;
  final int? durationSeconds;
  final int? byteLength;
}

/// Prepara mídia do chat antes do upload ao Firebase Storage.
abstract final class ChurchChatMediaPrepare {
  ChurchChatMediaPrepare._();

  static Future<PreparedChatImage> prepareImage({
    Uint8List? bytes,
    String? localPath,
  }) async {
    final payload = await MediaOptimizationService.optimizeForChat(
      bytes: bytes,
      localPath: localPath,
    );
    return PreparedChatImage(
      fullBytes: payload.fullBytes,
      fullMime: payload.fullMime,
      fullFileName: payload.fullFileName,
      thumbBytes: payload.thumbBytes,
    );
  }

  static Future<PreparedChatVideo?> prepareVideo(
    String inputPath, {
    void Function(double progress)? onCompressProgress,
  }) async {
    if (kIsWeb || inputPath.isEmpty) {
      return PreparedChatVideo(outputPath: inputPath);
    }
    final file = File(inputPath);
    if (!file.existsSync()) return null;

    final byteLen = await file.length();
    if (byteLen > mediaChatVideoHardMaxBytesEffective) {
      final limitMb =
          (mediaChatVideoHardMaxBytesEffective / (1024 * 1024)).round();
      throw StateError(
        'Vídeo muito grande. Reduza para até ${limitMb}MB ou grave mais curto.',
      );
    }

    final result = await MediaService.prepareVideoForChatUpload(
      inputPath,
      onCompressProgress: onCompressProgress,
    );
    if (result == null) return null;

    final outFile = File(result.outputPath);
    final outLen = outFile.existsSync() ? await outFile.length() : byteLen;

    return PreparedChatVideo(
      outputPath: result.outputPath,
      thumbnailBytes: result.thumbnailBytes,
      byteLength: outLen,
    );
  }
}
