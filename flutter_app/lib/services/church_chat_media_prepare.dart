import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/web_image_compress_service.dart';

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
        try {
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
          return _buildPrepared(full, thumb);
        } catch (_) {
          final raw = await f.readAsBytes();
          if (raw.isEmpty) rethrow;
          return _buildPrepared(raw, null);
        }
      }
    }
    if (bytes != null && bytes.isNotEmpty) {
      final source = Uint8List.fromList(bytes);
      if (kIsWeb) {
        final full = await WebImageCompressService.compressBytes(
          input: source,
          profile: MediaImageProfile.chat,
        );
        final thumb = await WebImageCompressService.compressBytes(
          input: source,
          profile: MediaImageProfile.thumb,
        );
        return _buildPrepared(full, thumb);
      }
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
      return _buildPrepared(full, thumb);
    }
    throw StateError('Sem dados para preparar a foto.');
  }

  static PreparedChatImage _buildPrepared(Uint8List full, Uint8List? thumb) {
    final webp = _bytesLookLikeWebp(full);
    return PreparedChatImage(
      fullBytes: full,
      fullMime: webp ? 'image/webp' : 'image/jpeg',
      fullFileName:
          'chat_${DateTime.now().millisecondsSinceEpoch}.${webp ? 'webp' : 'jpg'}',
      thumbBytes: thumb != null && thumb.isNotEmpty ? thumb : null,
    );
  }

  static bool _bytesLookLikeWebp(Uint8List list) {
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
    if (kIsWeb) {
      return WebImageCompressService.compressBytes(
        input: raw,
        profile: minSide <= thumbEdge
            ? MediaImageProfile.thumb
            : MediaImageProfile.chat,
      );
    }
    for (final format in [CompressFormat.webp, CompressFormat.jpeg]) {
      try {
        final out = await FlutterImageCompress.compressWithList(
          raw,
          quality: quality.clamp(70, 85),
          format: format,
          minWidth: minSide,
          minHeight: minSide,
        );
        if (out.isNotEmpty) return Uint8List.fromList(out);
      } catch (_) {}
    }
    return raw;
  }
}
