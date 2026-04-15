/// Tipos compartilhados do serviço de vídeo (evita import circular).
class VideoUploadResult {
  final String videoUrl;
  final String thumbUrl;
  const VideoUploadResult({required this.videoUrl, required this.thumbUrl});
}

abstract class IVideoHandlerService {
  /// [eventPostDocId] = id do documento do evento em `noticias` (estável desde o rascunho).
  /// [videoSlotIndex] 0 ou 1 — paths fixos em `igrejas/…/eventos/videos/` (substitui o anterior).
  /// [onUploadProgress]: 0.0–1.0 durante o upload ao Storage (após preparar o ficheiro).
  Future<VideoUploadResult?> pickCompressAndUpload({
    required String tenantId,
    required String eventPostDocId,
    required int videoSlotIndex,
    Duration maxDuration = const Duration(seconds: 60),
    void Function(double uploadProgress01)? onUploadProgress,
  });
}
