import 'package:gestao_yahweh/services/church_repository.dart';

/// churchId único para gravações — Web / Android / iOS (sem tenant/alias).
abstract final class ChurchPublishContext {
  ChurchPublishContext._();

  static String churchIdForPublish(String seedTenantId) {
    final id = ChurchRepository.churchId(seedTenantId.trim());
    if (id.isEmpty) {
      throw StateError('churchId não resolvido para publicação.');
    }
    return id;
  }

  static Future<String> churchIdForPublishAsync(String seedTenantId) async =>
      churchIdForPublish(seedTenantId);
}
