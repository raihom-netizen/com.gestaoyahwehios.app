/// Serviço de vídeo: seleção, compressão (DefaultQuality), thumbnail e upload.
/// Mobile: video_compress + thumbnail. Web: apenas seleção e upload.
export 'video_handler_service_types.dart';
export 'video_handler_service_stub.dart'
  if (dart.library.io) 'video_handler_service_io.dart';
