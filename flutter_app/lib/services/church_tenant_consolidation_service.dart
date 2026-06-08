import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_firestore_collection_migration_service.dart';
import 'package:gestao_yahweh/services/church_tenant_provisioning_service.dart';
import 'package:gestao_yahweh/services/migrate_members_to_membros_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Garante padrão `igrejas/{igrejaId}/membros|finance|…` para igrejas existentes e novas.
abstract final class ChurchTenantConsolidationService {
  ChurchTenantConsolidationService._();

  static final Set<String> _attempted = <String>{};

  /// Uma vez por sessão — provisiona aliases, consolida cluster e members→membros.
  static void ensureConsolidated(
    String tenantId, {
    bool force = false,
    String source = 'church_panel',
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    if (!force && _attempted.contains(tid)) return;
    _attempted.add(tid);
    unawaited(_run(tid, force: force, source: source));
  }

  static Future<void> _run(
    String tenantId, {
    required bool force,
    required String source,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'ensureChurchTenantConsolidated',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
      );
      await fn.call(<String, dynamic>{
        'tenantId': tenantId,
        'source': source,
        if (force) 'forceCluster': true,
      });
      TenantResolverService.invalidateOperationalChurchDocCache(
        seedId: tenantId,
        userUid: uid,
      );
      TenantResolverService.invalidateRegistrationContextCache(
        seedId: tenantId,
        userUid: uid,
      );
    } catch (e) {
      debugPrint('ChurchTenantConsolidationService callable: $e');
      await ChurchTenantProvisioningService.provisionAfterCadastroSave(tenantId);
      await MigrateMembersToMembrosService.instance.runIfNeeded(tenantId);
      unawaited(
        ChurchFirestoreCollectionMigrationService.ensureTenantMigrated(tenantId),
      );
    }
  }
}
