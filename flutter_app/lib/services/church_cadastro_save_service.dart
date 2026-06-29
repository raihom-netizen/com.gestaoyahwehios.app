import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Gravação blindada do doc raiz `igrejas/{churchId}` — Cadastro da Igreja.
///
/// Web: CF `gyAdminUpsertChurchRoot` (Admin SDK) com fallback Firestore directo;
/// cancela watches e [prepareForCriticalWrite] antes de gravar.
abstract final class ChurchCadastroSaveService {
  ChurchCadastroSaveService._();

  /// Cancela listeners locais e estabiliza Firestore antes de gravar.
  static Future<void> prepareForSave() async {
    ChurchRepository.cancelAllListeners();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  /// Persiste perfil da igreja — merge no doc raiz.
  static Future<void> saveChurchProfile({
    required String churchId,
    required Map<String, dynamic> data,
    String? seedTenantId,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) {
      throw StateError('Igreja não identificada para salvar.');
    }

    await prepareForSave();

    final payload = FirestoreWriteGuard.stripHeavyFields(
      ChurchTenantFields.stamp(
        cid,
        Map<String, dynamic>.from(data),
      ),
    );
    if (!payload.containsKey('updatedAt')) {
      payload['updatedAt'] = FieldValue.serverTimestamp();
    }

    Future<void> directWrite() => runFirestorePublishWithRecovery(
          () => FirestoreWebGuard.runWithWebRecovery(
            () => ChurchRepository.churchDoc(cid).set(
                  payload,
                  SetOptions(merge: true),
                ),
            maxAttempts: 6,
          ),
          maxAttempts: 6,
          criticalWrite: true,
        );

    await AdminFeedFirestoreBridge.upsertChurchRoot(
      churchId: cid,
      data: payload,
      directWrite: directWrite,
    );

    YahwehModuleCaches.igrejaRoot.invalidate(cid);
    unawaited(YahwehModuleCaches.igrejaRoot.warmUp(cid).catchError((_) {}));

    TenantResolverService.invalidateRegistrationContextCache(
      seedId: seedTenantId ?? cid,
      userUid: firebaseDefaultAuth.currentUser?.uid,
    );
    TenantResolverService.invalidateAliasCache();

    unawaited(
      ChurchPanelLocalCache.saveMap(
        churchId: cid,
        module: ChurchPanelLocalCache.moduleCadastro,
        data: payload,
      ).catchError((_) {}),
    );
    ChurchContextService.bindChurchData(churchId: cid, data: payload);
  }
}

