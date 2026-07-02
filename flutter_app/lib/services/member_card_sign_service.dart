import 'dart:async' show TimeoutException;
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Grava assinatura da carteirinha no cadastro do membro (`igrejas/{churchId}/membros`).
abstract final class MemberCardSignService {
  MemberCardSignService._();

  static const Duration kSignWriteTimeout =
      Duration(seconds: kIsWeb ? 18 : 28);
  static const Duration kSignBatchCap = Duration(seconds: kIsWeb ? 45 : 90);

  static Future<({int ok, int fail, String? lastError})> signBatch({
    required String tenantId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
  }) async {
    final ids = memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return (ok: 0, fail: 0, lastError: null);

    final churchId = MemberCardDirectoryService.resolveChurchId(tenantId.trim());
    if (churchId.isEmpty) {
      return (ok: 0, fail: ids.length, lastError: 'Igreja não identificada.');
    }

    return _signBatchImpl(
      churchId: churchId,
      memberIds: ids,
      signatory: signatory,
    ).timeout(
      kSignBatchCap,
      onTimeout: () => throw TimeoutException(
        'A assinatura demorou demais. Verifique a rede e tente novamente.',
        kSignBatchCap,
      ),
    );
  }

  static Future<({int ok, int fail, String? lastError})> _signBatchImpl({
    required String churchId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
  }) async {
    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: 'cartao_membro_assinar',
    );
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    final col = ChurchUiCollections.membros(churchId);
    final payload = <String, dynamic>{
      'carteirinhaAssinadaEm': FieldValue.serverTimestamp(),
      'carteirinhaAssinadaPor': signatory.memberId,
      'carteirinhaAssinadaPorNome': signatory.nome,
      'carteirinhaAssinadaPorCargo': signatory.cargo,
      if (signatory.assinaturaUrl != null &&
          signatory.assinaturaUrl!.trim().isNotEmpty)
        'carteirinhaAssinaturaUrl': signatory.assinaturaUrl!.trim()
      else
        'carteirinhaAssinaturaUrl': FieldValue.delete(),
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
    };

    var ok = 0;
    var fail = 0;
    String? lastError;

    Future<void> writeOne(String id) async {
      final docRef = col.doc(id);
      await AdminFeedFirestoreBridge.upsertDocRef(
        docRef: docRef,
        data: payload,
        isNewDoc: false,
        directWrite: () => runFirestorePublishWithRecovery(
          () => docRef.set(payload, SetOptions(merge: true)),
          maxAttempts: kIsWeb ? 4 : 2,
          criticalWrite: true,
        ),
      ).timeout(kSignWriteTimeout);
    }

    // Web: gravações individuais em paralelo (batch.commit costuma travar no SDK JS).
    final parallel = kIsWeb ? 4 : 8;
    for (var i = 0; i < memberIds.length; i += parallel) {
      final chunk = memberIds.sublist(i, min(i + parallel, memberIds.length));
      await Future.wait(
        chunk.map((id) async {
          try {
            await writeOne(id);
            ok++;
          } catch (e, st) {
            fail++;
            lastError = e.toString();
            debugPrint('MemberCardSignService write $id: $e\n$st');
          }
        }),
      );
    }

    return (ok: ok, fail: fail, lastError: lastError);
  }
}
