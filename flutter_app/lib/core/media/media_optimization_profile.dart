/// Perfis de compressão pré-upload — única fonte de verdade para limites de mídia.
enum MediaOptimizationProfile {
  /// Chat / avisos / feed — 1080px, qualidade 80, teto ~150 KB.
  chat,

  /// Foto de perfil membro — 512×512, qualidade 80.
  profile,

  /// Património / comprovante foto — 1080px.
  general,

  /// Comprovante financeiro / foto patrimonial — 1280px, qualidade 75.
  receipt,

  /// Miniatura instantânea (bolha otimista / listas).
  thumbPreview,

  /// Miniatura persistida no Storage.
  thumbUpload,
}

abstract final class MediaOptimizationLimits {
  MediaOptimizationLimits._();

  static const int chatMaxEdge = 1080;
  static const int chatQuality = 80;
  static const int chatFullMaxBytes = 150 * 1024;
  static const int chatThumbMaxBytes = 15 * 1024;

  static const int profileMaxEdge = 512;
  static const int profileQuality = 80;

  static const int generalMaxEdge = 1080;
  static const int generalQuality = 80;

  static const int receiptMaxEdge = 1280;
  static const int receiptQuality = 75;

  static const int thumbPreviewEdge = 320;
  static const int thumbPreviewQuality = 62;

  static const int thumbUploadEdge = 120;
  static const int thumbUploadQuality = 58;
}
