import 'package:gestao_yahweh/core/yahweh_data_engine_fetcher.dart';

/// Fachada de compatibilidade — **não** usa tenant fixo nem `FirebaseFirestore.instance`.
///
/// Delega 100% a [YahwehDataEngineFetcher] + load services canónicos
/// (`igrejas/{churchId}/…` via [ChurchRepository.churchId]).
///
/// Preferir nas telas:
/// ```dart
/// YahwehDataEngineFetcher.readModuleCacheFirst(
///   collectionName: 'cargos',
///   churchIdHint: widget.tenantId,
/// );
/// ```
abstract final class YahwehUnifiedDatabaseEngine {
  YahwehUnifiedDatabaseEngine._();

  /// [churchIdHint] — ID da igreja logada (`widget.tenantId`), nunca hardcoded.
  static Stream<List<Map<String, dynamic>>> watchModule({
    required String subCollectionPath,
    required String churchIdHint,
    String filterField = 'ativo',
    dynamic activeValue = true,
    int limitCount = 120,
  }) =>
      YahwehDataEngineFetcher.fetchCollection(
        targetModule: subCollectionPath,
        churchIdHint: churchIdHint,
        limitCount: limitCount,
        filterActiveOnly: true,
      );

  /// `igrejas/{churchId}/config/mercado_pago` (ou doc pedido em [configDocId]).
  static Stream<Map<String, dynamic>?> watchIntegrationSettings({
    required String churchIdHint,
    String configDocId = 'mercado_pago',
  }) =>
      YahwehDataEngineFetcher.watchMercadoPagoConfig(
        churchIdHint: churchIdHint,
        configDocId: configDocId,
      );
}
