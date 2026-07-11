import 'dart:async' show TimeoutException;
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Grava assinatura da carteirinha no cadastro do membro (`igrejas/{churchId}/membros`).
abstract final class MemberCardSignService {
  MemberCardSignService._();

  static const int _kBatchChunkSize = kIsWeb ? 25 : 40;
  static const int _kParallelFallback = kIsWeb ? 12 : 16;
  static const Duration _kChunkTimeout =
      Duration(seconds: kIsWeb ? 22 : 18);

  static Duration batchCapFor(int count) {
    if (count <= 0) return const Duration(seconds: 30);
    if (kIsWeb) {
      return Duration(
        seconds: (40 + (count * 1.4).ceil()).clamp(75, 240),
      );
    }
    return Duration(seconds: (50 + count).clamp(90, 300));
  }

  static Future<({int ok, int fail, String? lastError})> signBatch({
    required String tenantId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
    void Function(int done, int total)? onProgress,
  }) async {
    final ids =
        memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return (ok: 0, fail: 0, lastError: null);

    final churchId = MemberCardDirectoryService.resolveChurchId(tenantId.trim());
    if (churchId.isEmpty) {
      return (ok: 0, fail: ids.length, lastError: 'Igreja não identificada.');
    }

    return _signBatchImpl(
      churchId: churchId,
      memberIds: ids,
      signatory: signatory,
      onProgress: onProgress,
    ).timeout(
      batchCapFor(ids.length),
      onTimeout: () => throw TimeoutException(
        'A assinatura demorou demais. Verifique a rede e tente novamente.',
        batchCapFor(ids.length),
      ),
    );
  }

  static Future<({int ok, int fail, String? lastError})> _signBatchImpl({
    required String churchId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
    void Function(int done, int total)? onProgress,
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
    final total = memberIds.length;

    void report() => onProgress?.call(ok + fail, total);

    Future<void> writeOne(String id) async {
      final docRef = col.doc(id);
      await runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: true)),
        maxAttempts: kIsWeb ? 2 : 2,
        criticalWrite: true,
      ).timeout(const Duration(seconds: kIsWeb ? 12 : 10));
    }

    Future<void> writeChunkBatch(List<String> chunk) async {
      final batch = col.firestore.batch();
      for (final id in chunk) {
        batch.set(col.doc(id), payload, SetOptions(merge: true));
      }
      await runFirestorePublishWithRecovery(
        () => batch.commit(),
        maxAttempts: kIsWeb ? 2 : 2,
        criticalWrite: true,
      ).timeout(_kChunkTimeout);
    }

    Future<void> writeChunkParallel(List<String> chunk) async {
      await Future.wait(
        chunk.map((id) async {
          try {
            await writeOne(id);
            ok++;
          } catch (e, st) {
            fail++;
            lastError = e.toString();
            debugPrint('MemberCardSignService write $id: $e\n$st');
          } finally {
            report();
          }
        }),
      );
    }

    for (var i = 0; i < memberIds.length; i += _kBatchChunkSize) {
      final chunk = memberIds.sublist(
        i,
        min(i + _kBatchChunkSize, memberIds.length),
      );
      try {
        await writeChunkBatch(chunk);
        ok += chunk.length;
        report();
      } catch (batchError, batchSt) {
        debugPrint(
          'MemberCardSignService batch chunk fallback ($i): $batchError\n$batchSt',
        );
        for (var j = 0; j < chunk.length; j += _kParallelFallback) {
          final sub = chunk.sublist(
            j,
            min(j + _kParallelFallback, chunk.length),
          );
          await writeChunkParallel(sub);
        }
      }
    }

    if (ok > 0) {
      MembersDirectorySnapshotService.patchMembersSignatureInMemory(
        tenantId: churchId,
        memberIds: memberIds.take(ok).toList(),
        signatureFields: {
          'carteirinhaAssinadaEm': Timestamp.now(),
          'carteirinhaAssinadaPor': signatory.memberId,
          'carteirinhaAssinadaPorNome': signatory.nome,
          'carteirinhaAssinadaPorCargo': signatory.cargo,
          if (signatory.assinaturaUrl != null &&
              signatory.assinaturaUrl!.trim().isNotEmpty)
            'carteirinhaAssinaturaUrl': signatory.assinaturaUrl!.trim(),
        },
      );
    }

    return (ok: ok, fail: fail, lastError: lastError);
  }
}
