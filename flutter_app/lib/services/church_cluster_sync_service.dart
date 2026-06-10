/// SaaS directo — cada igreja isolada em `igrejas/{churchId}` (sem sync de cluster).
class ChurchClusterSyncService {
  ChurchClusterSyncService._();

  /// No-op — dados já vivem só no doc da igreja.
  static void syncForOperationalTenant(
    String operationalTenantId, {
    bool force = false,
  }) {}

  static Future<void> syncIfNeeded(
    String tenantHint, {
    String? userUid,
    bool force = false,
  }) async {}
}
