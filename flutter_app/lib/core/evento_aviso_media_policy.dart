import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxAvisoFeedPhotosPerPost, kMaxEventFeedPhotosPerPost;

/// Avisos: fotos (estilo Instagram) + 1 vídeo (YouTube ou hospedado).
/// Eventos: até [kMaxEventFeedPhotosPerPost] fotos + 1 vídeo.
const String kChurchPostTypeAviso = 'aviso';
const String kChurchPostTypeEvento = 'evento';

/// Eventos / avisos — 1 vídeo hospedado (90 s, 720p) ou link YouTube.
const int kMaxEventFeedVideosPerPost = 1;
const int kMaxAvisoFeedVideosPerPost = 1;

bool churchPostTypeAllowsHostedVideo(String postType) => true;

int churchPostMaxFeedPhotos(String postType) =>
    postType.trim() == kChurchPostTypeEvento
        ? kMaxEventFeedPhotosPerPost
        : kMaxAvisoFeedPhotosPerPost;

int churchPostMaxFeedVideos(String postType) =>
    postType.trim() == kChurchPostTypeEvento
        ? kMaxEventFeedVideosPerPost
        : kMaxAvisoFeedVideosPerPost;

/// Mantido por compatibilidade — avisos agora **aceitam** vídeo/YouTube.
@Deprecated('Avisos aceitam vídeo; não remova campos de vídeo.')
Map<String, dynamic> stripVideoFieldsForAvisoPayload(
  Map<String, dynamic> payload, {
  required bool allowDeleteSentinels,
}) {
  return Map<String, dynamic>.from(payload);
}

/// Eventos + avisos — upload rápido + visual aceitável (padrão Controle Total).
///
/// Compressão feed: máx. **1200px**, JPEG ~**72%**, alvo **~500 KB**.
const int kEventoAvisoFeedEncodeMaxEdgePx = 1200;
const int kEventoAvisoFeedJpegQuality = 72;
const int kEventoAvisoFeedWebpQuality = 72;
const int kEventoAvisoFeedTargetMaxBytes = 500 * 1024;

/// Capa de aviso — teto por foto (~500 KB) — upload rápido.
const int kAvisoCapaMaxUploadBytes = 500 * 1024;

/// Fotos de evento — mesmo teto (~500 KB) por slot.
const int kEventoFotoMaxUploadBytes = 500 * 1024;

/// Teto de decode em RAM no feed (listas leves; full no tap/zoom).
const int kEventoAvisoFeedMemCacheMaxPx = 900;

/// Web e mobile alinhados ao teto 1920px.
int eventoAvisoFeedEncodeMaxEdgePx() =>
    kIsWeb ? kEventoAvisoFeedEncodeMaxEdgePx : kEventoAvisoFeedEncodeMaxEdgePx;

int eventoAvisoMemCacheWidthPx(double layoutWidth, double devicePixelRatio) =>
    (layoutWidth * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);

int eventoAvisoMemCacheHeightPx(double layoutHeight, double devicePixelRatio) =>
    (layoutHeight * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);
