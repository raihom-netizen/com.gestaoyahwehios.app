import 'package:flutter/foundation.dart' show kIsWeb;

/// Eventos + avisos — upload e leitura ultrarrápidos.
///
/// Equivalente Dart ao canvas 1080px + `toBlob(..., 0.75)` do browser.
const int kEventoAvisoFeedEncodeMaxEdgePx = 1080;
const int kEventoAvisoFeedWebpQuality = 75;

/// Teto de decode em RAM no feed (equivalente prático ao `memCacheWidth: 800` do CachedNetworkImage).
const int kEventoAvisoFeedMemCacheMaxPx = 800;

/// Web: picker/encode um pouco maior; mobile mantém 1024 para upload rápido em 4G.
int eventoAvisoFeedEncodeMaxEdgePx() => kIsWeb ? 1280 : kEventoAvisoFeedEncodeMaxEdgePx;

int eventoAvisoMemCacheWidthPx(double layoutWidth, double devicePixelRatio) =>
    (layoutWidth * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);

int eventoAvisoMemCacheHeightPx(double layoutHeight, double devicePixelRatio) =>
    (layoutHeight * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);
