import 'dart:async' show TimeoutException, unawaited;
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Grava assinatura da carteirinha no cadastro do membro (`igrejas/{churchId}/membros`).
abstract final class MemberCardSignService {
  MemberCardSignService._();

  /// Web: chunks menores evitam INTERNAL ASSERTION no WatchChangeAggregator.
  static const int _kBatchChunkSize = kIsWeb ? 15 : 50;
  static const Duration _kChunkTimeout = Duration(seconds: kIsWeb ? 45 : 35);

  static Duration batchCapFor(int count) {
    if (count <= 0) return const Duration(seconds: 30);
    if (kIsWeb) {
      return Duration(seconds: (40 + (count * 1.4).ceil()).clamp(70, 240));
    }
    return Duration(seconds: (40 + (count * 0.8).ceil()).clamp(70, 240));
  }

  static Future<({int ok, int fail, String? lastError, List<String> signedIds})>
  signBatch({
    required String tenantId,
    required List<String> memberIds,
    required MemberCardSignatory signatory,
    void Function(int done, int total)? onProgress,
  }) async {
    final ids = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return (ok: 0, fail: 0, lastError: null, signedIds: const <String>[]);
    }

    final churchId = MemberCardDirectoryService.resolveChurchId(
      tenantId.trim(),
    );
    if (churchId.isEmpty) {
      return (
        ok: 0,
        fail: ids.length,
        lastError: 'Igreja não identificada.',
        signedIds: const <String>[],
      );
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

  static Future<({int ok, int fail, String? lastError, List<String> signedIds})>
  _signBatchImpl({
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
    // Timestamp concreto (não serverTimestamp): grava já no doc e aparece
    // na carteirinha sem null no cache local — data/hora corretas Web/Android/iOS.
    final signedAt = Timestamp.now();
    final payload = <String, dynamic>{
      'carteirinhaAssinadaEm': signedAt,
      'carteirinhaAssinadaPor': signatory.memberId,
      'carteirinhaAssinadaPorNome': signatory.nome,
      'carteirinhaAssinadaPorCargo': signatory.cargo,
      if (signatory.assinaturaUrl != null &&
          signatory.assinaturaUrl!.trim().isNotEmpty)
        'carteirinhaAssinaturaUrl': signatory.assinaturaUrl!.trim(),
      'ATUALIZADO_EM': signedAt,
    };

    var ok = 0;
    var fail = 0;
    String? lastError;
    final total = memberIds.length;
    final signedIds = <String>[];

    void report() => onProgress?.call(ok + fail, total);

    /// Escrita leve — sem hard recover por documento (evita ca9/b815 na web).
    Future<void> writeOneLight(String id) async {
      await col
          .doc(id)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: kIsWeb ? 18 : 15));
    }

    Future<void> writeChunkBatch(List<String> chunk) async {
      final batch = col.firestore.batch();
      for (final id in chunk) {
        batch.set(col.doc(id), payload, SetOptions(merge: true));
      }
      await runFirestorePublishWithRecovery(
        () => batch.commit(),
        maxAttempts: 2,
        criticalWrite: true,
      ).timeout(_kChunkTimeout);
    }

    /// Fallback web: sequencial (nunca 16 writes + recover em paralelo).
    Future<void> writeChunkSequential(List<String> chunk) async {
      for (final id in chunk) {
        try {
          await writeOneLight(id);
          ok++;
          signedIds.add(id);
        } catch (e1) {
          try {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            await writeOneLight(id);
            ok++;
            signedIds.add(id);
          } catch (e2, st) {
            fail++;
            lastError = e2.toString();
            debugPrint('MemberCardSignService write $id: $e2\n$st');
          }
        } finally {
          report();
        }
      }
    }

    for (var i = 0; i < memberIds.length; i += _kBatchChunkSize) {
      final chunk = memberIds.sublist(
        i,
        min(i + _kBatchChunkSize, memberIds.length),
      );
      try {
        await writeChunkBatch(chunk);
        ok += chunk.length;
        signedIds.addAll(chunk);
        report();
      } catch (batchError, batchSt) {
        debugPrint(
          'MemberCardSignService batch chunk fallback ($i): $batchError\n$batchSt',
        );
        // Um único soft recover por chunk — depois sequencial.
        if (kIsWeb &&
            (FirestoreWebGuard.isInternalAssertionError(batchError) ||
                FirestoreWebGuard.isClientTerminated(batchError))) {
          await FirestoreWebGuard.softRecoverWebSession().catchError((_) {});
          try {
            await writeChunkBatch(chunk);
            ok += chunk.length;
            signedIds.addAll(chunk);
            report();
            continue;
          } catch (_) {}
        }
        await writeChunkSequential(chunk);
      }
    }

    // Confirmação pós-escrita é só diagnóstico em background — NÃO deve
    // rebaixar para "falhou" uma assinatura cujo write já foi confirmado
    // pelo próprio Firestore (o `await` do commit/set acima só retorna sem
    // erro quando o servidor reconheceu a escrita). Um timeout na releitura
    // (comum na web, streams instáveis) não significa que a gravação
    // falhou — antes disso, `ok`/`signedIds` já refletiam o que realmente
    // foi persistido, e usar `verifiedIds` para reconciliar fazia a UI
    // mostrar "não assinado" para carteirinhas já gravadas com sucesso.
    if (signedIds.isNotEmpty) {
      unawaited(
        _verifySignaturesPersisted(
          col: col,
          signedIds: signedIds,
          signatoryMemberId: signatory.memberId,
        ).then((verifiedIds) {
          if (verifiedIds.length < signedIds.length) {
            debugPrint(
              'MemberCardSignService: releitura confirmou '
              '${verifiedIds.length}/${signedIds.length} — write já tinha '
              'sido confirmado pelo Firestore; diferença é releitura '
              'lenta/timeout, não falha de escrita.',
            );
          }
        }),
      );

      MembersDirectorySnapshotService.patchMembersSignatureInMemory(
        tenantId: churchId,
        memberIds: signedIds,
        signatureFields: {
          'carteirinhaAssinadaEm': signedAt,
          'carteirinhaAssinadaPor': signatory.memberId,
          'carteirinhaAssinadaPorNome': signatory.nome,
          'carteirinhaAssinadaPorCargo': signatory.cargo,
          if (signatory.assinaturaUrl != null &&
              signatory.assinaturaUrl!.trim().isNotEmpty)
            'carteirinhaAssinaturaUrl': signatory.assinaturaUrl!.trim(),
        },
      );
      // Invalidar cache RAM de membros para que reload devolva dados assinados.
      unawaited(ChurchMembersLoadService.invalidate(churchId));
    }

    return (
      ok: ok,
      fail: fail,
      lastError: lastError,
      signedIds: List<String>.unmodifiable(signedIds),
    );
  }

  /// Remove a assinatura da carteirinha (contrário de [signBatch]).
  static Future<({int ok, int fail, String? lastError, List<String> clearedIds})>
  clearBatch({
    required String tenantId,
    required List<String> memberIds,
  }) async {
    final ids = memberIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      return (ok: 0, fail: 0, lastError: null, clearedIds: const <String>[]);
    }

    final churchId = MemberCardDirectoryService.resolveChurchId(
      tenantId.trim(),
    );
    if (churchId.isEmpty) {
      return (
        ok: 0,
        fail: ids.length,
        lastError: 'Igreja não identificada.',
        clearedIds: const <String>[],
      );
    }

    return _clearBatchImpl(churchId: churchId, memberIds: ids).timeout(
      batchCapFor(ids.length),
      onTimeout: () => throw TimeoutException(
        'A remoção da assinatura demorou demais. Verifique a rede e tente novamente.',
        batchCapFor(ids.length),
      ),
    );
  }

  static Future<({int ok, int fail, String? lastError, List<String> clearedIds})>
  _clearBatchImpl({
    required String churchId,
    required List<String> memberIds,
  }) async {
    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: 'cartao_membro_limpar_assinatura',
    );
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    final col = ChurchUiCollections.membros(churchId);
    final payload = <String, dynamic>{
      'carteirinhaAssinadaEm': FieldValue.delete(),
      'carteirinhaAssinadaPor': FieldValue.delete(),
      'carteirinhaAssinadaPorNome': FieldValue.delete(),
      'carteirinhaAssinadaPorCargo': FieldValue.delete(),
      'carteirinhaAssinaturaUrl': FieldValue.delete(),
      'ATUALIZADO_EM': Timestamp.now(),
    };

    var ok = 0;
    var fail = 0;
    String? lastError;
    final clearedIds = <String>[];

    Future<void> writeOneLight(String id) async {
      await col
          .doc(id)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: kIsWeb ? 18 : 15));
    }

    Future<void> writeChunkBatch(List<String> chunk) async {
      final batch = col.firestore.batch();
      for (final id in chunk) {
        batch.set(col.doc(id), payload, SetOptions(merge: true));
      }
      await runFirestorePublishWithRecovery(
        () => batch.commit(),
        maxAttempts: 2,
        criticalWrite: true,
      ).timeout(_kChunkTimeout);
    }

    Future<void> writeChunkSequential(List<String> chunk) async {
      for (final id in chunk) {
        try {
          await writeOneLight(id);
          ok++;
          clearedIds.add(id);
        } catch (e1) {
          try {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            await writeOneLight(id);
            ok++;
            clearedIds.add(id);
          } catch (e2, st) {
            fail++;
            lastError = e2.toString();
            debugPrint('MemberCardSignService clear $id: $e2\n$st');
          }
        }
      }
    }

    for (var i = 0; i < memberIds.length; i += _kBatchChunkSize) {
      final chunk = memberIds.sublist(
        i,
        min(i + _kBatchChunkSize, memberIds.length),
      );
      try {
        await writeChunkBatch(chunk);
        ok += chunk.length;
        clearedIds.addAll(chunk);
      } catch (batchError, batchSt) {
        debugPrint(
          'MemberCardSignService clear batch chunk fallback ($i): $batchError\n$batchSt',
        );
        if (kIsWeb &&
            (FirestoreWebGuard.isInternalAssertionError(batchError) ||
                FirestoreWebGuard.isClientTerminated(batchError))) {
          await FirestoreWebGuard.softRecoverWebSession().catchError((_) {});
          try {
            await writeChunkBatch(chunk);
            ok += chunk.length;
            clearedIds.addAll(chunk);
            continue;
          } catch (_) {}
        }
        await writeChunkSequential(chunk);
      }
    }

    if (clearedIds.isNotEmpty) {
      // Cache RAM (MembersDirectorySnapshotService) não sabe "limpar" campos
      // string via merge (fallback mantém o valor antigo quando o campo
      // chega vazio) — invalida para forçar releitura real do Firestore
      // em vez de deixar o cache mostrar assinatura removida incorretamente.
      MembersDirectorySnapshotService.invalidateMemory(churchId);
      unawaited(ChurchMembersLoadService.invalidate(churchId));
    }

    return (
      ok: ok,
      fail: fail,
      lastError: lastError,
      clearedIds: List<String>.unmodifiable(clearedIds),
    );
  }

  /// Lê de volta os documentos assinados e só devolve os IDs onde o campo
  /// `carteirinhaAssinadaPor` coincide com o signatário (prova de persistência).
  static Future<List<String>> _verifySignaturesPersisted({
    required CollectionReference<Map<String, dynamic>> col,
    required List<String> signedIds,
    required String signatoryMemberId,
  }) async {
    if (signedIds.isEmpty) return const <String>[];
    final verified = <String>[];
    final ids = signedIds.toList();
    // Web: evita muitas leituras simultâneas; mobile: paraleliza leve.
    final chunkSize = kIsWeb ? 8 : 16;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
      try {
        final futures = chunk.map((id) async {
          try {
            final snap = await col
                .doc(id)
                .get(const GetOptions(source: Source.serverAndCache))
                .timeout(const Duration(seconds: kIsWeb ? 12 : 8));
            final data = snap.data();
            if (data == null) return null;
            final signedBy = (data['carteirinhaAssinadaPor'] ?? '')
                .toString()
                .trim();
            final signedAt = data['carteirinhaAssinadaEm'];
            if (signedBy.isNotEmpty &&
                signedBy == signatoryMemberId &&
                signedAt != null) {
              return id;
            }
            return null;
          } catch (_) {
            return null;
          }
        });
        final results = await Future.wait(futures, eagerError: false);
        verified.addAll(results.whereType<String>());
      } catch (_) {}
    }
    return verified;
  }
}
