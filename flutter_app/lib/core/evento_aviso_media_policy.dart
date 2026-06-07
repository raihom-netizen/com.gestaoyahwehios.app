import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxAvisoFeedPhotosPerPost, kMaxEventFeedPhotosPerPost;

/// Avisos: **só fotos**, até [kMaxAvisoFeedPhotosPerPost]. Eventos: até [kMaxEventFeedPhotosPerPost] fotos.
const String kChurchPostTypeAviso = 'aviso';
const String kChurchPostTypeEvento = 'evento';

/// Eventos — 1 vídeo hospedado (90 s, 720p).
const int kMaxEventFeedVideosPerPost = 1;

bool churchPostTypeAllowsHostedVideo(String postType) =>
    postType.trim() != kChurchPostTypeAviso;

int churchPostMaxFeedPhotos(String postType) =>
    postType.trim() == kChurchPostTypeEvento
        ? kMaxEventFeedPhotosPerPost
        : kMaxAvisoFeedPhotosPerPost;

int churchPostMaxFeedVideos(String postType) =>
    postType.trim() == kChurchPostTypeEvento ? kMaxEventFeedVideosPerPost : 0;

/// Remove campos de vídeo ao gravar/publicar aviso (legado YouTube/Vimeo no doc).
Map<String, dynamic> stripVideoFieldsForAvisoPayload(
  Map<String, dynamic> payload, {
  required bool allowDeleteSentinels,
}) {
  final out = Map<String, dynamic>.from(payload);
  final del = FieldValue.delete();
  if (allowDeleteSentinels) {
    out['videoUrl'] = del;
    out['videos'] = del;
  } else {
    out['videoUrl'] = '';
    out['videos'] = <dynamic>[];
  }
  final mi = out['media_info'];
  if (mi is Map<String, dynamic>) {
    final copy = Map<String, dynamic>.from(mi);
    copy['tipo'] = 'image';
    out['media_info'] = copy;
  }
  return out;
}

/// Eventos + avisos — upload e leitura ultrarrápidos.
///
/// Compressão feed avisos/eventos — máx. 1920px, qualidade 75–80% (spec produção).
const int kEventoAvisoFeedEncodeMaxEdgePx = 1920;
const int kEventoAvisoFeedWebpQuality = 78;

/// Teto de decode em RAM no feed (equivalente prático ao `memCacheWidth: 800` do CachedNetworkImage).
const int kEventoAvisoFeedMemCacheMaxPx = 800;

/// Web e mobile alinhados ao teto 1920px.
int eventoAvisoFeedEncodeMaxEdgePx() =>
    kIsWeb ? kEventoAvisoFeedEncodeMaxEdgePx : kEventoAvisoFeedEncodeMaxEdgePx;

int eventoAvisoMemCacheWidthPx(double layoutWidth, double devicePixelRatio) =>
    (layoutWidth * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);

int eventoAvisoMemCacheHeightPx(double layoutHeight, double devicePixelRatio) =>
    (layoutHeight * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);
