import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/media_video_compress_quality.dart';
import 'package:video_compress/video_compress.dart';

/// Comprime vídeo da galeria/câmara antes do upload no Chat Igreja (mobile).
class ChurchChatVideoPrepare {
  ChurchChatVideoPrepare._();

  static Future<String> preparePathForUpload(String inputPath) async {
    if (kIsWeb) return inputPath;
    final file = File(inputPath);
    if (!file.existsSync()) return inputPath;

    final lower = inputPath.toLowerCase();
    final byteLen = await file.length();
    if (byteLen > mediaVideoHardMaxBytesEffective) {
      final limitMb = (mediaVideoHardMaxBytesEffective / (1024 * 1024)).round();
      throw StateError(
        'Vídeo muito grande. Reduza para até ${limitMb}MB ou grave mais curto.',
      );
    }

    if (byteLen <= mediaVideoSkipTranscodeMaxBytes &&
        (lower.endsWith('.mp4') || lower.endsWith('.m4v'))) {
      return inputPath;
    }

    final info = await VideoCompress.compressVideo(
      inputPath,
      quality: mediaVideoCompressQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    final out = info?.file?.path;
    if (out == null || out.isEmpty || !File(out).existsSync()) {
      return inputPath;
    }
    return out;
  }
}
