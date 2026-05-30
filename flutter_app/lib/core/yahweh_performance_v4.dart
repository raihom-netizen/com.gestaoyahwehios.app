/// Política global de performance — Gestão YAHWEH V4.
///
/// Uma única fonte de limites (cache, paginação, WebP, chat) usada por painel,
/// site público, feed, chat e upload de mídia — evita «otimizar tela a tela».
abstract final class YahwehPerformanceV4 {
  YahwehPerformanceV4._();

  // ——— Cache HTTP (cached_network_image / flutter_cache_manager) ———
  static const Duration imageCacheStalePeriod = Duration(days: 30);
  static const int imageCacheMaxObjects = 1000;
  static const int feedThumbCacheMaxObjects = 1000;

  // ——— WebP ———
  static const int webpQuality = 70;

  // ——— Fotos de perfil ———
  static const int profileThumbEdge = 200;
  static const int profileMediumEdge = 500;
  static const String profileThumbField = 'photoThumb';
  static const String profileMediumField = 'photoMedium';
  static const String profileThumbFile = 'profile_thumb.webp';
  static const String profileMediumFile = 'profile_medium.webp';

  // ——— Feed / mural (já alinhado a MediaImageVariantsService) ———
  static const int feedThumbEdge = 200;
  static const int feedMediumEdge = 800;
  static const int feedFullEdge = 1920;

  // ——— Paginação Firestore ———
  static const int defaultPageSize = 20;
  static const int publicFeedPageSize = 20;
  static const int chatMessagesPageSize = 30;
  static const int upcomingEventsLimit = 20;
  static const int birthdayQueryLimit = 20;

  // ——— Pré-carregamento ———
  static const int preloadFeedLeadItems = 16;
  static const int preloadFeedItems = 32;
  static const int preloadScreenMaxUrls = 32;

  // ——— Publicação instantânea (avisos / eventos) ———
  /// Alias Firestore: `publishState: uploading` ≡ `status: processing`.
  static const String publishStatusProcessing = 'uploading';
  static const String publishStatusPublished = 'published';

  /// Membro: índice denormalizado para aniversariantes (`birthMonth` 1–12).
  static const String memberBirthMonthField = 'birthMonth';
  static const String memberBirthDayField = 'birthDay';
}
