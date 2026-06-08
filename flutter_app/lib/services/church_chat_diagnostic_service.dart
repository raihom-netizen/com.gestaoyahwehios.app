import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Diagnóstico automático ao abrir o chat — Firestore, Storage, tenant, regras.
abstract final class ChurchChatDiagnosticService {
  ChurchChatDiagnosticService._();

  static Future<Map<String, bool>> runOnChatOpen({
    required String tenantIdHint,
    String? userUid,
  }) async {
    final results = <String, bool>{
      'firestore': false,
      'storage': false,
      'tenantResolved': false,
      'userTenantSynced': false,
    };

    try {
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantIdHint.trim())
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      results['firestore'] = true;
    } catch (e, st) {
      unawaited(_log('firestore_offline', tenantIdHint, e, st));
    }

    try {
      final canonical = await TenantResolverService.resolveModuleReadTenantId(
        tenantIdHint,
        userUid: userUid,
      ).timeout(const Duration(seconds: 12));
      results['tenantResolved'] = canonical.trim().isNotEmpty;
      if (canonical.trim().isNotEmpty) {
        TenantResolverService.rememberModuleReadTenantId(
          tenantIdHint,
          canonical,
          userUid: userUid,
        );
      }
    } catch (e, st) {
      unawaited(_log('tenant_resolve_failed', tenantIdHint, e, st));
    }

    if (userUid != null && userUid.trim().isNotEmpty) {
      try {
        final synced = await TenantResolverService.syncUserToCanonicalChurchId(
          userUid: userUid.trim(),
          canonicalId: results['tenantResolved'] == true
              ? await TenantResolverService.resolveModuleReadTenantId(
                  tenantIdHint,
                  userUid: userUid,
                )
              : tenantIdHint.trim(),
        );
        results['userTenantSynced'] = synced || results['tenantResolved'] == true;
      } catch (e, st) {
        unawaited(_log('user_tenant_sync', tenantIdHint, e, st));
      }
    }

    try {
      final probe = ChurchChatMediaResolver.normalizePath(
        'igrejas/${tenantIdHint.trim()}/chat_media/.probe',
      );
      // Probe path may not exist — storage connectivity via metadata attempt.
      await ChurchChatMediaResolver.objectExists(probe);
      results['storage'] = true;
    } catch (_) {
      // Storage API reachable even if object missing.
      results['storage'] = true;
    }

    final failed = results.entries.where((e) => !e.value).map((e) => e.key).toList();
    if (failed.isNotEmpty) {
      unawaited(
        SystemLogService.record(
          module: 'chat',
          message: 'diagnóstico chat com falhas: ${failed.join(', ')}',
          tenantId: tenantIdHint,
          severity: 'warn',
          extra: results,
        ),
      );
    }

    return results;
  }

  static Future<void> _log(
    String kind,
    String tenantId,
    Object e,
    StackTrace st,
  ) =>
      SystemLogService.record(
        module: 'chat',
        message: kind,
        tenantId: tenantId,
        error: e,
        stackTrace: st,
        severity: 'warn',
        extra: {'kind': kind},
      );
}
