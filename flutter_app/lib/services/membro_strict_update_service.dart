import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/tenant_stale_while_revalidate.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
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
    final fromRepo = ChurchRepository.churchId(seedTenantId.trim());
    if (fromRepo.isNotEmpty) {
      if (kDebugMode) debugPrint('CHURCH_ID (membro write): $fromRepo');
      return fromRepo;
    }
    final resolved = ChurchContextService.panelChurchId(seedTenantId.trim());
    if (resolved.isEmpty) {
      throw StateError('churchId não resolvido para gravar membro.');
    }
    if (kDebugMode) debugPrint('CHURCH_ID (membro write): $resolved');
    return resolved;
  }

  static bool _looksLikeFirebaseAuthUid(String id) {
    final s = id.trim();
    return s.length >= 20 &&
        s.length <= 36 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(s);
  }

  static String _cpfDigitsFromMap(Map<String, dynamic> data) =>
      (data['CPF'] ?? data['cpf'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\D'), '');

  static String? _authUidFromMap(Map<String, dynamic> data) {
    for (final k in ['authUid', 'auth_uid', 'firebaseUid', 'uid', 'userId']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.length >= 8) return v;
    }
    return null;
  }

  /// Todos os docs `membros/{id}` que representam a mesma pessoa (CPF, authUid, id da lista).
  static Future<List<DocumentReference<Map<String, dynamic>>>>
      resolveAllMemberDocRefs({
    required String churchId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    final cid = churchId.trim();
    final ids = <String>{memberDocId.trim()};
    final cpf = _cpfDigitsFromMap(memberData);
    if (cpf.length == 11) ids.add(cpf);
    final authUid = _authUidFromMap(memberData);
    if (authUid != null && authUid.isNotEmpty) ids.add(authUid);
    if (_looksLikeFirebaseAuthUid(memberDocId)) ids.add(memberDocId.trim());

    final col = ChurchUiCollections.membros(cid);
    Future<T> guarded<T>(Future<T> Function() op) {
      if (kIsWeb) {
        return FirestoreWebGuard.runWithWebRecovery(op, maxAttempts: 4);
      }
      return op();
    }

    if (authUid != null && authUid.isNotEmpty) {
      try {
        final q = await guarded(
          () => col.where('authUid', isEqualTo: authUid).limit(12).get(),
        );
        for (final d in q.docs) {
          ids.add(d.id);
        }
      } catch (_) {}
    }
    if (cpf.length == 11) {
      for (final field in ['CPF', 'cpf']) {
        try {
          final q = await guarded(
            () => col.where(field, isEqualTo: cpf).limit(8).get(),
          );
          for (final d in q.docs) {
            ids.add(d.id);
          }
        } catch (_) {}
      }
    }

    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      refs.add(col.doc(id));
      refs.add(
        ChurchFirestoreAccess.collectionRef(cid, 'members').doc(id),
      );
    }
    return refs;
  }

  static Future<void> _deleteDocVerified(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    final before = await docRef.get(const GetOptions(source: Source.server));
    if (!before.exists) return;

    await runFirestorePublishWithRecovery(
      () => docRef.delete(),
    );

    for (var attempt = 0; attempt < 4; attempt++) {
      final after = await docRef.get(const GetOptions(source: Source.server));
      if (!after.exists) return;
      await Future<void>.delayed(Duration(milliseconds: 120 + attempt * 160));
      await runFirestorePublishWithRecovery(() => docRef.delete());
    }
    throw StateError(
      '${kDeleteVerifyFailedMessage} (${docRef.path} ainda existe)',
    );
  }

  static Future<void> _invalidateMemberCaches(String churchId, String seed) {
    unawaited(
      TenantStaleWhileRevalidate.invalidateModule(
        tenantId: churchId,
        module: TenantModuleKeys.membros,
      ),
    );
    // Sem isto o membro excluído volta da RAM/Hive do load service.
    unawaited(ChurchMembersLoadService.invalidate(churchId));
    if (seed.trim().isNotEmpty && seed.trim() != churchId) {
      unawaited(ChurchMembersLoadService.invalidate(seed.trim()));
    }
    MembersDirectorySnapshotService.invalidateMemory(churchId);
    MembersDirectorySnapshotService.invalidateMemory(seed.trim());
    return Future.value();
  }

  static Future<Map<String, dynamic>> _purgeMemberViaCallable({
    required String churchId,
    required String seedTenantId,
    required String memberDocId,
    String? authUid,
  }) async {
    final payload = <String, dynamic>{
      'tenantId': churchId.isNotEmpty ? churchId : seedTenantId.trim(),
      'memberId': memberDocId.trim(),
    };
    if (authUid != null && authUid.isNotEmpty) {
      payload['authUid'] = authUid;
    }
    final res = await FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1')
        .httpsCallable('purgeMemberFirebaseLogin')
        .call(payload);
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static bool _isLegacyMembersRef(DocumentReference<Map<String, dynamic>> ref) =>
      ref.path.contains('/members/');

  /// Exclusão total — Storage, todos os docs `membros`, índices e login (Admin SDK via callable).
  static Future<void> purgeMemberCompletely({
    required String seedTenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    Future<void> Function({
      required String churchId,
      required String memberDocId,
      required String? authUid,
    })? purgeAuthLogin,
  }) async {
    final churchId = await _resolveIgrejaId(seedTenantId);
    final mid = memberDocId.trim();
    if (mid.isEmpty) {
      throw StateError('ID do membro vazio.');
    }

    // Lápide ANTES do purge — lista/directory não «ressuscitam» o membro.
    TenantDeletedDocTombstones.mark(churchId, TenantModuleKeys.membros, [mid]);

    final authUid = _authUidFromMap(memberData);
    final cpf = _cpfDigitsFromMap(memberData);

    if (kDebugMode) {
      debugPrint('PURGE MEMBER churchId=$churchId memberId=$mid authUid=$authUid');
    }

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'delete_before',
      igrejaId: churchId,
      memberDocId: mid,
    );

    await _prepareWrite();

    var serverMembroDocsDeleted = 0;
    try {
      if (purgeAuthLogin != null) {
        await purgeAuthLogin(
          churchId: churchId,
          memberDocId: mid,
          authUid: authUid,
        );
      } else {
        final serverResult = await _purgeMemberViaCallable(
          churchId: churchId,
          seedTenantId: seedTenantId,
          memberDocId: mid,
          authUid: authUid,
        );
        serverMembroDocsDeleted =
            (serverResult['membroDocsDeleted'] as num?)?.toInt() ?? 0;
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        rethrow;
      }
      debugPrint('purgeMemberFirebaseLogin ${e.code}: ${e.message}');
    } catch (e, st) {
      debugPrint('purgeMemberFirebaseLogin $e $st');
    }

    await FirebaseStorageCleanupService.deleteMemberRelatedFiles(
      tenantId: churchId,
      memberId: mid,
      data: memberData,
    );

    var deletedAny = serverMembroDocsDeleted > 0;
    final membroRefs = await resolveAllMemberDocRefs(
      churchId: churchId,
      memberDocId: mid,
      memberData: memberData,
    );

    if (!deletedAny) {
      for (final ref in membroRefs) {
        try {
          final exists = (await ref.get(const GetOptions(source: Source.server)))
              .exists;
          if (!exists) continue;
          await _deleteDocVerified(ref);
          if (!_isLegacyMembersRef(ref)) deletedAny = true;
        } catch (e) {
          if (_isLegacyMembersRef(ref)) {
            if (kDebugMode) {
              debugPrint('purgeMember legacy members skip ${ref.path}: $e');
            }
            continue;
          }
          if (kDebugMode) debugPrint('purgeMember delete ${ref.path}: $e');
          rethrow;
        }
      }

      if (!deletedAny) {
        final primary = _membroDocRef(igrejaId: churchId, memberDocId: mid);
        final exists =
            (await primary.get(const GetOptions(source: Source.server))).exists;
        if (exists) {
          await _deleteDocVerified(primary);
          deletedAny = true;
        }
      }
    }

    if (!deletedAny) {
      throw StateError(
        'Membro não encontrado em igrejas/$churchId/membros (já excluído ou id incorreto).',
      );
    }

    final db = firebaseDefaultFirestore;
    final userIds = <String>{};
    if (authUid != null && authUid.isNotEmpty) userIds.add(authUid);
    if (_looksLikeFirebaseAuthUid(mid)) userIds.add(mid);

    for (final uid in userIds) {
      try {
        await runFirestorePublishWithRecovery(
          () => db.collection('users').doc(uid).delete(),
        );
      } catch (_) {}
      try {
        final tokRef = db.collection('users').doc(uid).collection('fcmTokens');
        final tokSnap = await tokRef.get();
        for (final d in tokSnap.docs) {
          await d.reference.delete();
        }
      } catch (_) {}
      try {
        await runFirestorePublishWithRecovery(
          () => ChurchUiCollections.tenantUsers(churchId).doc(uid).delete(),
        );
      } catch (_) {}
      try {
        await runFirestorePublishWithRecovery(
          () => db
              .collection('igrejas')
              .doc(churchId)
              .collection('chat_peer_profiles')
              .doc(uid)
              .delete(),
        );
      } catch (_) {}
    }

    if (cpf.length == 11) {
      try {
        await runFirestorePublishWithRecovery(
          () => ChurchUiCollections.usersIndex(churchId).doc(cpf).delete(),
        );
      } catch (_) {}
    }

    for (final ref in membroRefs) {
      if (_isLegacyMembersRef(ref)) continue;
      final still = await ref.get(const GetOptions(source: Source.server));
      if (still.exists) {
        throw StateError(
          '${kDeleteVerifyFailedMessage} Path: ${ref.path}',
        );
      }
    }

    await _invalidateMemberCaches(churchId, seedTenantId);

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'delete_after',
      igrejaId: churchId,
      memberDocId: mid,
    );
  }

  static Future<void> _prepareWrite() async {
    if (!kIsWeb) return;
    await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
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

    await runFirestorePublishWithRecovery(
      () async {
        if (existing.exists) {
          await docRef.update(payload);
        } else {
          await docRef.set(payload, SetOptions(merge: true));
        }
      },
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

  /// Exclusão real — delega a [purgeMemberCompletely].
  static Future<void> deleteMember({
    required String seedTenantId,
    required String memberDocId,
    Map<String, dynamic> memberData = const {},
    String? userUid,
    Future<void> Function({
      required String churchId,
      required String memberDocId,
      required String? authUid,
    })? purgeAuthLogin,
  }) async {
    await purgeMemberCompletely(
      seedTenantId: seedTenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      purgeAuthLogin: purgeAuthLogin,
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

