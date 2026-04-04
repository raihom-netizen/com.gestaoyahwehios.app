/// Tipos compartilhados do serviço de vídeo (evita import circular).
class VideoUploadResult {
  final String videoUrl;
  final String thumbUrl;
  const VideoUploadResult({required this.videoUrl, required this.thumbUrl});
}

abstract class IVideoHandlerService {
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    Duration maxDuration = const Duration(seconds: 60),
  });
}
