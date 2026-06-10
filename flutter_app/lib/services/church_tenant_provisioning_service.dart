import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Provisiona doc raiz `igrejas/{id}` e pastas Storage directas após cadastro.
abstract final class ChurchTenantProvisioningService {
  ChurchTenantProvisioningService._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Idempotente — pode chamar após cada save do cadastro da igreja.
  static Future<void> provisionAfterCadastroSave(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      await _fn.httpsCallable('provisionChurchTenantCallable').call({
        'tenantId': tid,
        'source': 'igreja_cadastro_page',
      });
    } catch (e, st) {
      debugPrint('ChurchTenantProvisioningService: $e\n$st');
    }
  }
}
