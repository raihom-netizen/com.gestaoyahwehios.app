import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:video_compress/video_compress.dart';

/// Qualidade de transcodificação — 540p em release mobile (mais rápido), 720p no resto.
VideoQuality get mediaVideoCompressQuality =>
    kMediaTurboMobilePreset
        ? VideoQuality.Res960x540Quality
        : VideoQuality.Res1280x720Quality;
