import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
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

  static const int imageMaxEdge = SafeImageBytes.defaultMaxEdge;
  static const int imageQuality = SafeImageBytes.defaultQuality;
  static const int thumbEdge = 320;
  static const int thumbQuality = 72;

  static Future<PreparedChatImage> prepareImage({
    Uint8List? bytes,
    String? localPath,
  }) async {
    if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (await f.exists() && await f.length() > 0) {
        final full = await SafeImageBytes.fromPath(
          localPath,
          maxEdge: imageMaxEdge,
          quality: imageQuality,
        );
        final thumb = await _encodeWebp(
          full,
          minSide: thumbEdge,
          quality: thumbQuality,
        );
        return PreparedChatImage(
          fullBytes: full,
          fullMime: 'image/webp',
          fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.webp',
          thumbBytes: thumb.isNotEmpty ? thumb : null,
        );
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      final source = Uint8List.fromList(bytes);
      final full = await _encodeWebp(
        source,
        minSide: imageMaxEdge,
        quality: imageQuality,
      );
      final thumb = await _encodeWebp(
        source,
        minSide: thumbEdge,
        quality: thumbQuality,
      );
      return PreparedChatImage(
        fullBytes: full,
        fullMime: 'image/webp',
        fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.webp',
        thumbBytes: thumb.isNotEmpty ? thumb : null,
      );
    }
    throw StateError('Sem dados para preparar a foto.');
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

  static Future<Uint8List> _encodeWebp(
    Uint8List raw, {
    required int minSide,
    required int quality,
  }) async {
    if (raw.isEmpty) return raw;
    try {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        quality: quality.clamp(70, 85),
        format: CompressFormat.webp,
        minWidth: minSide,
        minHeight: minSide,
      );
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}
    return raw;
  }
}
