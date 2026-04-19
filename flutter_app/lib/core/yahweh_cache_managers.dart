import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cache em disco centralizado (HTTP) — alinhado ao [cached_network_image] quando o widget
/// usa [cacheManager] explícito; [ImageHelper.getBytesFromUrl] usa [images].
///
/// **TTL:** imagens 30 dias; vídeos 7 dias (aquecimento/range requests podem reutilizar).
class YahwehCacheManagers {
  YahwehCacheManagers._();

  /// Logos, capas e https não-Storage: disco + TTL — alinhado a listas grandes do painel.
  static final CacheManager images = CacheManager(
    Config(
      'yahweh_images_v1',
      stalePeriod: const Duration(days: 45),
      maxNrOfCacheObjects: 1400,
    ),
  );

  static final CacheManager videos = CacheManager(
    Config(
      'yahweh_videos_v1',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 120,
    ),
  );
}
