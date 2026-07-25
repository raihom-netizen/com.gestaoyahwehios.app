import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:video_compress/video_compress.dart';

/// Limite (~20 MB) para escolher 480p em vez de 720p — upload mais rápido.
const int kVideoCompress480pThresholdBytes = 20 * 1024 * 1024;

/// H.264 + AAC ~480p (padrão rápido) — 720p só quando explicitamente necessário.
VideoQuality get mediaVideoCompressQuality => VideoQuality.Res640x480Quality;

/// Qualidade adaptativa: >20MB → 480p; resto → 720p.
VideoQuality videoCompressQualityForByteLength(int byteLen) {
  if (byteLen > kVideoCompress480pThresholdBytes) {
    return VideoQuality.Res640x480Quality;
  }
  return VideoQuality.Res1280x720Quality;
}
