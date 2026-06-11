import 'package:flutter/foundation.dart' show debugPrint;

/// Legado — provisionamento automático descontinuado (SaaS directo `igrejas/{id}`).
abstract final class ChurchTenantProvisioningService {
  ChurchTenantProvisioningService._();

  /// No-op — o cadastro grava directamente em `igrejas/{churchId}`.
  static Future<void> provisionAfterCadastroSave(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    debugPrint(
      'ChurchTenantProvisioningService: skip (direct igrejas/$tid)',
    );
  }
}
