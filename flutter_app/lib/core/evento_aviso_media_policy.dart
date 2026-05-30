import 'package:flutter/foundation.dart' show kIsWeb;

/// Eventos + avisos — upload e leitura ultrarrápidos.
///
/// Compressão feed avisos/eventos — máx. 1920px, qualidade ~80% (spec produção).
const int kEventoAvisoFeedEncodeMaxEdgePx = 1920;
const int kEventoAvisoFeedWebpQuality = 80;

/// Teto de decode em RAM no feed (equivalente prático ao `memCacheWidth: 800` do CachedNetworkImage).
const int kEventoAvisoFeedMemCacheMaxPx = 800;

/// Web e mobile alinhados ao teto 1920px.
int eventoAvisoFeedEncodeMaxEdgePx() =>
    kIsWeb ? kEventoAvisoFeedEncodeMaxEdgePx : kEventoAvisoFeedEncodeMaxEdgePx;

int eventoAvisoMemCacheWidthPx(double layoutWidth, double devicePixelRatio) =>
    (layoutWidth * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);

int eventoAvisoMemCacheHeightPx(double layoutHeight, double devicePixelRatio) =>
    (layoutHeight * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);
