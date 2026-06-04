import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:video_compress/video_compress.dart';

/// Limite (~50 MB) para escolher 480p em vez de 720p (H.264 + AAC via [video_compress]).
const int kVideoCompress480pThresholdBytes = 50 * 1024 * 1024;

/// H.264 + AAC ~720p (1280×720) — padrão feed/chat/eventos (não enviar original bruto).
VideoQuality get mediaVideoCompressQuality => VideoQuality.Res1280x720Quality;

/// Qualidade adaptativa: ficheiros muito grandes → 480p; resto → 720p.
VideoQuality videoCompressQualityForByteLength(int byteLen) {
  if (byteLen > kVideoCompress480pThresholdBytes) {
    return VideoQuality.Res640x480Quality;
  }
  return VideoQuality.Res1280x720Quality;
}
