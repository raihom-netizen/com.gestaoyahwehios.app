import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// churchId único para gravações — Web / Android / iOS (sem tenant/alias).
abstract final class ChurchPublishContext {
  ChurchPublishContext._();

  static String churchIdForPublish(String seedTenantId) =>
      ChurchRepository.requireChurchId(seedTenantId);

  static Future<String> churchIdForPublishAsync(String seedTenantId) async =>
      churchIdForPublish(seedTenantId);
}
