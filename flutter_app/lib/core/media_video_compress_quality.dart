import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:video_compress/video_compress.dart';

/// H.264 + AAC ~720p (1280×720) — padrão feed/chat/eventos (não enviar original bruto).
VideoQuality get mediaVideoCompressQuality => VideoQuality.Res1280x720Quality;
