import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// CRUD membro — grava só em `igrejas/{churchId}/membros/{memberId}` com verificação.
abstract final class MembroStrictUpdateService {
  MembroStrictUpdateService._();

  static const String kUpdateVerifyFailedMessage =
      'Alteração não confirmada no Firestore. Tente novamente.';

  static const String kDeleteVerifyFailedMessage =
      'Não foi possível excluir o membro no banco.';

  static DocumentReference<Map<String, dynamic>> _membroDocRef({
    required String igrejaId,
    required String memberDocId,
  }) {
    final ref = ChurchFirestoreAccess.collectionRef(
      igrejaId.trim(),
      ChurchDataPaths.membros,
    ).doc(memberDocId.trim());
    MembroPublishVerificationService.assertMembroDocPath(ref);
    return ref;
  }

  static Future<String> _resolveIgrejaId(String seedTenantId) async {
    final resolved = ChurchContextService.panelChurchId(seedTenantId.trim());
    if (resolved.isEmpty) {
      throw StateError('churchId não resolvido para gravar membro.');
    }
    if (kDebugMode) debugPrint('CHURCH_ID (membro write): $resolved');
    return resolved;
  }

  static Future<void> _prepareWrite() async {
    if (!kIsWeb) return;
    await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
  }

  /// Atualiza ficha e confirma no servidor (sem «salvo com sucesso» falso).
  static Future<void> updateMember({
    required String seedTenantId,
    required String memberDocId,
    required Map<String, dynamic> updates,
    String? userUid,
  }) async {
    final igrejaId = await _resolveIgrejaId(seedTenantId);
    final docRef = _membroDocRef(
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    final payload = Map<String, dynamic>.from(updates);
    payload.putIfAbsent('ATUALIZADO_EM', () => FieldValue.serverTimestamp());
    payload.putIfAbsent('updatedAt', () => FieldValue.serverTimestamp());

    if (kDebugMode) {
      debugPrint('UPDATE MEMBER');
      debugPrint('path=${docRef.path}');
      debugPrint(payload.keys.join(', '));
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'update_before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    await _prepareWrite();

    final existing = await docRef.get(
      const GetOptions(source: Source.serverAndCache),
    );

    await FirestoreWebGuard.runWithWebRecovery(
      () async {
        if (existing.exists) {
          await docRef.update(payload);
        } else {
          await docRef.set(payload, SetOptions(merge: true));
        }
      },
      maxAttempts: kIsWeb ? 3 : 2,
    );

    await _verifySavedFields(docRef, payload);

    unawaited(
      TenantStaleWhileRevalidate.invalidateModule(
        tenantId: igrejaId,
        module: TenantModuleKeys.membros,
      ),
    );
    MembersDirectorySnapshotService.invalidateMemory(igrejaId);
    MembersDirectorySnapshotService.invalidateMemory(seedTenantId.trim());

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
    final igrejaId = await _resolveIgrejaId(seedTenantId);
    final docRef = _membroDocRef(
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    if (kDebugMode) {
      debugPrint('DELETE MEMBER');
      debugPrint('path=${docRef.path}');
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'delete_before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    await _prepareWrite();

    final before = await docRef.get(const GetOptions(source: Source.server));
    if (!before.exists) return;

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.delete(),
      maxAttempts: kIsWeb ? 3 : 2,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      final after = await docRef.get(const GetOptions(source: Source.server));
      if (!after.exists) break;
      if (attempt >= 2) {
        throw StateError(kDeleteVerifyFailedMessage);
      }
      await Future<void>.delayed(Duration(milliseconds: 120 + attempt * 180));
      await FirestoreWebGuard.runWithWebRecovery(() => docRef.delete());
    }

    unawaited(
      TenantStaleWhileRevalidate.invalidateModule(
        tenantId: igrejaId,
        module: TenantModuleKeys.membros,
      ),
    );
    MembersDirectorySnapshotService.invalidateMemory(igrejaId);
    MembersDirectorySnapshotService.invalidateMemory(seedTenantId.trim());

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
        .where((k) => k != 'alias' && k != 'slug' && k != 'tenantId')
        .toList();

    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
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
        if (keysToCheck.isEmpty) return;

        final saved = snap.data() ?? {};
        for (final key in keysToCheck) {
          if (!_fieldMatches(payload[key], saved[key])) {
            throw StateError('$kUpdateVerifyFailedMessage (campo: $key)');
          }
        }
        return;
      } catch (e) {
        last = e;
        if (attempt < 1) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }
    throw last ?? StateError(kUpdateVerifyFailedMessage);
  }

  static String _normScalar(Object? v) {
    if (v == null) return '';
    if (v is Timestamp) return v.millisecondsSinceEpoch.toString();
    if (v is bool || v is num) return v.toString();
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    return s;
  }

  static bool _fieldMatches(Object? sent, Object? got) {
    if (sent == null && got == null) return true;
    if (sent is Timestamp && got is Timestamp) {
      return sent.millisecondsSinceEpoch == got.millisecondsSinceEpoch;
    }
    if (sent is List || got is List) {
      final sa = sent is List
          ? sent.map((e) => e.toString().trim().toLowerCase()).toList()
          : <String>[];
      final ga = got is List
          ? got.map((e) => e.toString().trim().toLowerCase()).toList()
          : <String>[];
      sa.sort();
      ga.sort();
      if (sa.length != ga.length) return false;
      for (var i = 0; i < sa.length; i++) {
        if (sa[i] != ga[i]) return false;
      }
      return true;
    }
    if (sent is bool || got is bool) {
      return sent == got;
    }
    return _normScalar(sent) == _normScalar(got);
  }
}
