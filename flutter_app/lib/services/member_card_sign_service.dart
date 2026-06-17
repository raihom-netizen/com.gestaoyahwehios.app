import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Grava assinatura da carteirinha no cadastro do membro (`igrejas/{churchId}/membros`).
abstract final class MemberCardSignService {
  MemberCardSignService._();

  static Future<({int ok, int fail, String? lastError})> signBatch({
    required String tenantId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
  }) async {
    final ids = memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return (ok: 0, fail: 0, lastError: null);

    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) {
      return (ok: 0, fail: ids.length, lastError: 'Igreja não identificada.');
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
    };

    var ok = 0;
    var fail = 0;
    String? lastError;
    const chunkSize = 400;

    Future<void> commitChunk(List<String> chunk) async {
      await FirestoreWebGuard.runWithWebRecovery(() async {
        final batch = firebaseDefaultFirestore.batch();
        for (final id in chunk) {
          batch.set(col.doc(id), payload, SetOptions(merge: true));
        }
        await batch.commit();
      });
    }

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        await commitChunk(chunk);
        ok += chunk.length;
      } catch (e, st) {
        debugPrint('MemberCardSignService batch: $e\n$st');
        lastError = e.toString();
        for (final id in chunk) {
          try {
            await FirestoreWebGuard.runWithWebRecovery(
              () => col.doc(id).set(payload, SetOptions(merge: true)),
            );
            ok++;
          } catch (e2) {
            fail++;
            lastError = e2.toString();
          }
        }
      }
    }
    return (ok: ok, fail: fail, lastError: lastError);
  }
}
