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

  // ——— WebP (paridade Controle Total) ———
  static const int webpQuality = 80;
  /// Fotos gerais — spec escala (1920px / JPEG 80%).
  static const int uploadMaxEdgePx = 1920;

  // ——— Fotos de perfil (membros) ———
  /// Perfil membro — 512×512.
  static const int profileFullEdge = 512;
  static const int profileThumbEdge = 200;
  static const int profileFullQuality = 80;
  static const int profileThumbQuality = 70;
  /// Campos canónicos Firestore.
  static const String profileThumbField = 'fotoThumbUrl';
  static const String profileFullField = 'fotoUrl';
  /// Legado (leitura).
  static const String profileThumbFieldLegacy = 'photoThumb';
  static const String profileMediumFieldLegacy = 'photoMedium';
  static const String profileThumbFile = 'profile_thumb.webp';
  static const String profileMediumFile = 'profile_medium.webp';

  // ——— Feed / mural (1 ficheiro/slot — ChurchInstantUploadPipeline / EcoFire) ———
  static const int feedThumbEdge = 200;
  static const int feedMediumEdge = 800;
  static const int feedFullEdge = uploadMaxEdgePx;

  // ——— Paginação Firestore ———
  static const int defaultPageSize = 20;
  /// Exportações admin (CSV/PDF) — lote único, não é lista UI.
  static const int adminExportBatchLimit = 500;
  /// Amostra para gráficos/estatísticas do dashboard (não lista paginada).
  static const int dashboardStatsSampleLimit = 100;
  static const int financeChartsSampleLimit = 500;
  static const int financeListInitialLimit = 250;
  static const int financeListPageStep = 100;
  static const int publicFeedPageSize = 20;
  /// Chat — só as 50 mensagens mais recentes (sem histórico inteiro).
  static const int chatMessagesPageSize = 40;
  static const int chatThreadsListLimit = 50;
  static const int chatThreadsFallbackLimit = 30;
  static const int upcomingEventsLimit = 20;
  static const int birthdayQueryLimit = 20;
  static const int masterChurchesPageSize = 25;
  /// Listagens master (utilizadores, pesquisa, cache fallback).
  static const int masterUsersPageSize = 50;
  static const int masterChurchesListLimit = 100;
  static const int masterStorageEstimateSampleLimit = 100;
  static const int masterPaymentsSampleLimit = 100;
  static const int masterAnalyticsSampleLimit = 100;
  static const int masterAuditLogLimit = 100;
  static const int masterGlobalSearchScanLimit = 100;
  static const int masterAdminUsersLimit = 100;
  static const int masterCacheAlertsLimit = 50;
  static const int masterCachePaymentsLimit = 100;
  static const int masterCacheChurchesScanLimit = 100;
  static const int memberCardListPageSize = 40;
  static const int memberCardSignatoryQueryLimit = 24;
  static const int memberCardPdfPhotoParallel = 8;
  static const int patrimonioListPageSize = 20;
  static const int financeSummaryFirstLimit = 20;

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
