import 'package:flutter/foundation.dart' show kIsWeb;

/// Eventos + avisos — upload e leitura ultrarrápidos.
///
/// **Envio:** nunca mandar o original da galeria; comprimir no dispositivo (WebP/JPEG
/// ~1024 px, qualidade ~75%) antes do Firebase Storage (CDN global do Google).
///
/// **Leitura:** usar [SafeNetworkImage] / [StableStorageImage] com [memCacheWidth]
/// limitado (cache em disco + RAM), nunca `Image.network` direto em URLs do Storage na web.
const int kEventoAvisoFeedEncodeMaxEdgePx = 1024;
const int kEventoAvisoFeedWebpQuality = 75;

/// Teto de decode em RAM no feed (equivalente prático ao `memCacheWidth: 800` do CachedNetworkImage).
const int kEventoAvisoFeedMemCacheMaxPx = 800;

/// Web: picker/encode um pouco maior; mobile mantém 1024 para upload rápido em 4G.
int eventoAvisoFeedEncodeMaxEdgePx() => kIsWeb ? 1280 : kEventoAvisoFeedEncodeMaxEdgePx;

int eventoAvisoMemCacheWidthPx(double layoutWidth, double devicePixelRatio) =>
    (layoutWidth * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);

int eventoAvisoMemCacheHeightPx(double layoutHeight, double devicePixelRatio) =>
    (layoutHeight * devicePixelRatio).round().clamp(64, kEventoAvisoFeedMemCacheMaxPx);
