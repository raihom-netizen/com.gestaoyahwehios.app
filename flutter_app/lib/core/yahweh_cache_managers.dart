import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Cache em disco centralizado (HTTP) — alinhado ao [cached_network_image] quando o widget
/// usa [cacheManager] explícito; [ImageHelper.getBytesFromUrl] usa [images].
///
/// **TTL:** imagens 30 dias; vídeos 7 dias (aquecimento/range requests podem reutilizar).
/// Limites: [YahwehPerformanceV4] (V4 — 1000 objetos / 30 dias).
class YahwehCacheManagers {
  YahwehCacheManagers._();

  /// Logos, capas e https não-Storage: disco + TTL — alinhado a listas grandes do painel.
  static final CacheManager images = CacheManager(
    Config(
      'yahweh_images_v3',
      stalePeriod: YahwehPerformanceV4.imageCacheStalePeriod,
      maxNrOfCacheObjects: YahwehPerformanceV4.imageCacheMaxObjects,
    ),
  );

  /// Miniaturas de lista (chat hub, avatares pequenos, feed thumb).
  static final CacheManager feedThumbs = CacheManager(
    Config(
      'yahweh_feed_thumbs_v2',
      stalePeriod: YahwehPerformanceV4.imageCacheStalePeriod,
      maxNrOfCacheObjects: YahwehPerformanceV4.feedThumbCacheMaxObjects,
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
