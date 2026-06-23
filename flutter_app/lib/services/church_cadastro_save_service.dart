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
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// GravaÃ§Ã£o blindada do doc raiz `igrejas/{churchId}` â€” Cadastro da Igreja.
///
/// Web: cancela watches, [prepareForCriticalWrite] + [runFirestorePublishWithRecovery]
/// para evitar INTERNAL ASSERTION (Firestore JS 12.x + listeners do IndexedStack).
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

  /// Persiste perfil da igreja â€” merge no doc raiz.
  static Future<void> saveChurchProfile({
    required String churchId,
    required Map<String, dynamic> data,
    String? seedTenantId,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) {
      throw StateError('Igreja nÃ£o identificada para salvar.');
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

    await runFirestorePublishWithRecovery(
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

