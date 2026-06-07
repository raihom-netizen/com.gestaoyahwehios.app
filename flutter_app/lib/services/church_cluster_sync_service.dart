import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Sincroniza dados do cluster (doc legado → operacional `_sistema`) no servidor.
class ChurchClusterSyncService {
  ChurchClusterSyncService._();

  static final Set<String> _attempted = <String>{};

  static bool _isBpcCluster(String tenantId) {
    final t = tenantId.trim().toLowerCase();
    return t.contains('brasilparacristo') ||
        t.contains('brasil_para_cristo') ||
        t.contains('iobpc');
  }

  /// Uma vez por sessão — cópia em background (web / Android / iOS); não bloqueia UI.
  static void syncForOperationalTenant(
    String operationalTenantId, {
    bool force = false,
  }) {
    final tid = operationalTenantId.trim();
    if (tid.isEmpty || !_isBpcCluster(tid)) return;
    if (!force && _attempted.contains(tid)) return;
    _attempted.add(tid);
    unawaited(_callClusterSync(tid, force: force));
    unawaited(_callMpSync(tid));
  }

  /// Resolve tenant canónico e dispara sync (ex.: doações MP).
  static Future<void> syncIfNeeded(
    String tenantHint, {
    String? userUid,
    bool force = false,
  }) async {
    final seed = tenantHint.trim();
    if (seed.isEmpty) return;

    String operational = seed;
    try {
      operational = await TenantResolverService.resolveOperationalChurchDocId(
        seed,
        userUid: userUid,
      );
    } catch (_) {}

    final tid = operational.trim().isEmpty ? seed : operational.trim();
    if (!_isBpcCluster(tid) && !_isBpcCluster(seed)) return;
    syncForOperationalTenant(tid, force: force);
  }

  static Future<void> _callClusterSync(String tenantId, {bool force = false}) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'syncChurchClusterDataFromRichest',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      await fn.call(<String, dynamic>{
        'tenantId': tenantId,
        if (force) 'force': true,
      });
      TenantResolverService.invalidateOperationalChurchDocCache(seedId: tenantId);
      TenantResolverService.invalidateRegistrationContextCache(seedId: tenantId);
    } catch (_) {}
  }

  static Future<void> _callMpSync(String tenantId) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'syncChurchMercadoPagoFromCluster',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 50)),
      );
      await fn.call(<String, dynamic>{'tenantId': tenantId});
    } catch (_) {}
  }
}
