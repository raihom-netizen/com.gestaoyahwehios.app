import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// CRUD membro — grava só em `igrejas/{churchId}/membros/{memberId}` com verificação.
abstract final class MembroStrictUpdateService {
  MembroStrictUpdateService._();

  static const String kUpdateVerifyFailedMessage =
      'Alteração não confirmada no Firestore. Tente novamente.';

  static const String kDeleteVerifyFailedMessage =
      'Não foi possível excluir o membro no banco.';

  /// Atualiza ficha e confirma no servidor (sem «salvo com sucesso» falso).
  static Future<void> updateMember({
    required String seedTenantId,
    required String memberDocId,
    required Map<String, dynamic> updates,
    String? userUid,
  }) async {
    final igrejaId = await MembroPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = MembroPublishVerificationService.membroDocRef(
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    final payload = Map<String, dynamic>.from(updates);
    payload.putIfAbsent('ATUALIZADO_EM', () => FieldValue.serverTimestamp());
    payload.putIfAbsent('updatedAt', () => FieldValue.serverTimestamp());

    if (kDebugMode) {
      debugPrint('UPDATE MEMBER');
      debugPrint(igrejaId);
      debugPrint(memberDocId);
      debugPrint(payload.keys.join(', '));
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'update_before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload, SetOptions(merge: true)),
    );

    await _verifySavedFields(docRef, payload);

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'update_after',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );
  }

  /// Exclusão real do doc `membros/{id}` com confirmação.
  static Future<void> deleteMember({
    required String seedTenantId,
    required String memberDocId,
    String? userUid,
  }) async {
    final igrejaId = await MembroPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );
    final docRef = MembroPublishVerificationService.membroDocRef(
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    if (kDebugMode) {
      debugPrint('DELETE MEMBER');
      debugPrint(igrejaId);
      debugPrint(memberDocId);
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'delete_before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    final before = await docRef.get(const GetOptions(source: Source.server));
    if (!before.exists) return;

    await FirestoreWebGuard.runWithWebRecovery(() => docRef.delete());

    final after = await docRef.get(const GetOptions(source: Source.server));
    if (after.exists) {
      throw StateError(kDeleteVerifyFailedMessage);
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'delete_after',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );
  }

  static Future<void> _verifySavedFields(
    DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic> payload,
  ) async {
    final keysToCheck = payload.keys
        .where((k) => payload[k] is! FieldValue)
        .where((k) => !k.startsWith('_'))
        .toList();
    if (keysToCheck.isEmpty) {
      final snap = await docRef.get(const GetOptions(source: Source.server));
      if (!snap.exists) {
        throw StateError(MembroPublishVerificationService.kPublishVerifyFailedMessage);
      }
      return;
    }

    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final snap = await docRef.get(
          GetOptions(
            source: attempt == 0 ? Source.serverAndCache : Source.server,
          ),
        );
        if (!snap.exists) {
          throw StateError(
            MembroPublishVerificationService.kPublishVerifyFailedMessage,
          );
        }
        final saved = snap.data() ?? {};
        for (final key in keysToCheck) {
          if (!_fieldMatches(payload[key], saved[key])) {
            throw StateError(
              '$kUpdateVerifyFailedMessage (campo: $key)',
            );
          }
        }
        return;
      } catch (e) {
        last = e;
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
    }
    throw last ?? StateError(kUpdateVerifyFailedMessage);
  }

  static bool _fieldMatches(Object? sent, Object? got) {
    if (sent == null && got == null) return true;
    if (sent is Timestamp && got is Timestamp) {
      return sent.millisecondsSinceEpoch == got.millisecondsSinceEpoch;
    }
    if (sent is List && got is List) {
      if (sent.length != got.length) return false;
      for (var i = 0; i < sent.length; i++) {
        if (sent[i].toString() != got[i].toString()) return false;
      }
      return true;
    }
    if (sent is bool || got is bool) {
      return sent == got;
    }
    final s = sent.toString().trim();
    final g = got.toString().trim();
    return s == g;
  }
}
