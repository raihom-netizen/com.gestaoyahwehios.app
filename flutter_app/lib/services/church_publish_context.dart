import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';

/// churchId único para gravações — Web / Android / iOS (sem tenant/alias).
abstract final class ChurchPublishContext {
  ChurchPublishContext._();

  static String churchIdForPublish(String seedTenantId) {
    final id = ChurchPanelTenant.require(seedTenantId);
    return id;
  }

  static Future<String> churchIdForPublishAsync(String seedTenantId) async =>
      churchIdForPublish(seedTenantId);
}
