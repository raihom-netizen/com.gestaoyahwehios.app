import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        MemberProfilePhotoBytesCache,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/immediate_storage_upload_guard.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_cache.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_keys.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado de upload de foto de perfil do membro (chat + módulo Membros).
class MemberProfilePhotoUpdateResult {
  final String downloadUrl;
  final String storagePath;
  final int cacheRevision;

  const MemberProfilePhotoUpdateResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.cacheRevision,
  });
}

/// Sincroniza foto de perfil: Storage + Firestore + invalidação de cache (lista, chat, web).
class MemberProfilePhotoUpdateService {
  MemberProfilePhotoUpdateService._();

  static const String photoUploadStateField = EntityPublishStatus.photoUploadStateField;
  static const String stateUploading = EntityPublishStatus.uploading;
  static const String statePublished = EntityPublishStatus.published;
  static const String stateError = EntityPublishStatus.error;

  /// Campos para merge imediato no membro (cadastro salvo; foto em background).
  static Map<String, dynamic> pendingUploadPatchFields({int? revision}) {
    final rev = revision ?? DateTime.now().millisecondsSinceEpoch;
    return {
      photoUploadStateField: stateUploading,
      'fotoUrlCacheRevision': rev,
      'photoUploadError': FieldValue.delete(),
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
    };
  }

  /// Remove bytes em RAM / disco e [ImageCache] para a mesma foto após substituição no Storage.
  static void invalidateDisplayCaches({
    String? previousDownloadUrl,
    String? newDownloadUrl,
    String? storagePath,
  }) {
    for (final raw in [previousDownloadUrl, newDownloadUrl]) {
      final u = sanitizeImageUrl(raw);
      if (u.isEmpty) continue;
      MemberProfilePhotoBytesCache.remove(u);
      try {
        NetworkImage(u).evict();
      } catch (_) {}
    }
    final path = (storagePath ?? '').trim();
    if (path.isNotEmpty) {
      MemberProfilePhotoBytesCache.removeByObjectPath(path);
    }
    for (final raw in [previousDownloadUrl, newDownloadUrl]) {
      final p = firebaseStorageObjectPathFromHttpUrl(sanitizeImageUrl(raw));
      if (p != null && p.isNotEmpty) {
        MemberProfilePhotoBytesCache.removeByObjectPath(p);
        unawaited(deleteYahwehMediaBytesDiskKeys(
          YahwehMediaBytesDiskKeys.invalidateKeysForStoragePath(p),
        ));
      }
    }
    final sp = (storagePath ?? '').trim();
    if (sp.isNotEmpty) {
      unawaited(deleteYahwehMediaBytesDiskKeys(
        YahwehMediaBytesDiskKeys.invalidateKeysForStoragePath(sp),
      ));
    }
  }

  /// Localiza o documento do membro logado (CPF, doc id = authUid, ou campo `authUid`).
  static Future<DocumentSnapshot<Map<String, dynamic>>?> resolveMemberDoc({
    required String tenantId,
    required String authUid,
    String? cpfDigits,
  }) async {
    await ensureFirebaseCore(requireAuth: false);
    final base = firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros');
    final digits = (cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    try {
      if (digits.length == 11) {
        final byCpf = await base.doc(digits).get();
        if (byCpf.exists) return byCpf;
      }
      final byUid = await base.doc(authUid).get();
      if (byUid.exists) return byUid;
      final q = await base.where('authUid', isEqualTo: authUid).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first;
    } catch (e, st) {
      YahwehFlowLog.error('MEMBROS', e, st);
    }
    return null;
  }

  /// Firestore primeiro → upload em background (não bloqueia UI).
  /// [requireAuth] false no cadastro público (visitante anónimo).
  static void scheduleBackgroundPhotoUpload({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    bool requireAuth = true,
    void Function(MemberProfilePhotoUpdateResult result)? onSuccess,
    void Function(Object error)? onError,
  }) {
    unawaited(
      () async {
        await ensureFirebaseCore(requireAuth: requireAuth);
        YahwehFlowLog.membrosStart();
        final result = await _uploadAndPatchMemberCore(
          tenantId: tenantId,
          memberDocId: memberDocId,
          memberData: memberData,
          rawBytes: rawBytes,
          requireAuth: requireAuth,
        );
        YahwehFlowLog.membrosSuccess();
        onSuccess?.call(result);
      }().catchError((Object e, StackTrace st) {
        YahwehFlowLog.memberPhotoError(e, st);
        ChurchPublishFlowLog.memberPhotoError(e, st);
        unawaited(_markPhotoUploadError(
          tenantId: tenantId,
          memberDocId: memberDocId,
          memberData: memberData,
          error: e,
        ));
        onError?.call(e);
      }),
    );
  }

  static Future<void> _markPhotoUploadError({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Object error,
  }) async {
    final patch = {
      photoUploadStateField: stateError,
      'photoUploadError': error.toString(),
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
    };
    var tenantIds =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(tenantId);
    if (tenantIds.isEmpty) tenantIds = [tenantId];
    final db = firebaseDefaultFirestore;
    await Future.wait(
      tenantIds.map(
        (tid) => FirestoreWebGuard.runWithWebRecovery(
          () => MembrosOfflineSync.set(
            ref: db
                .collection('igrejas')
                .doc(tid)
                .collection('membros')
                .doc(memberDocId),
            tenantId: tid,
            merge: true,
            data: patch,
          ),
        ),
      ),
    );
  }

  /// Compatível com chamadas síncronas (chat «Guardar»). Preferir [scheduleBackgroundPhotoUpload].
  static Future<MemberProfilePhotoUpdateResult> uploadAndPatchMember({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
  }) async {
    YahwehFlowLog.memberPhotoStart();
    ChurchPublishFlowLog.memberPhotoStart();
    try {
      final r = await _uploadAndPatchMemberCore(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: rawBytes,
      );
      YahwehFlowLog.memberPhotoSuccess();
      ChurchPublishFlowLog.memberPhotoSuccess();
      return r;
    } catch (e, st) {
      YahwehFlowLog.memberPhotoError(e, st);
      ChurchPublishFlowLog.memberPhotoError(e, st);
      rethrow;
    }
  }

  static Future<MemberProfilePhotoUpdateResult> _uploadAndPatchMemberCore({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    bool requireAuth = true,
  }) async {
    await ensureFirebaseCore(requireAuth: requireAuth);
    if (kIsWeb) {
      await FirestoreWebGuard.recoverFirestoreWebSession(
        allowHardReconnect: true,
      );
    }
    YahwehFlowLog.uploadStart('member_profile');
    ChurchPublishFlowLog.uploadStart('member_profile');
    final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));
    final previousThumb = sanitizeImageUrl(
      MemberProfileVariantsService.listPhotoUrl(memberData) ?? '',
    );
    final authUid = (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
        .toString()
        .trim();

    try {
      await FirebaseStorageCleanupService.deleteMemberProfilePhotoArtifactsBeforeReplace(
        tenantId: tenantId,
        memberId: memberDocId,
        data: memberData,
      );
    } catch (e, st) {
      YahwehFlowLog.error('MEMBROS', e, st);
    }

    final tiers = await MemberProfileVariantsService.encodeProfileTiers(rawBytes);
    final uploaded = await MemberProfileVariantsService.uploadProfileVariants(
      tenantId: tenantId,
      memberDocId: memberDocId,
      thumbBytes: tiers.thumb,
      fullBytes: tiers.full,
    );
    final photoUrl = sanitizeImageUrl(uploaded.photoFull);
    final thumbUrl = sanitizeImageUrl(uploaded.photoThumb);
    if (!isValidImageUrl(photoUrl)) {
      throw StateError('URL da foto inválida após upload.');
    }
    if (!isValidImageUrl(thumbUrl)) {
      throw StateError('URL da miniatura inválida após upload.');
    }
    final revision = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{
      YahwehPerformanceV4.profileFullField: photoUrl,
      YahwehPerformanceV4.profileThumbField: thumbUrl,
      'foto_url': photoUrl,
      'FOTO_URL_OU_ID': photoUrl,
      'photoURL': photoUrl,
      YahwehPerformanceV4.profileThumbFieldLegacy: thumbUrl,
      'photoVariants': FieldValue.delete(),
      YahwehPerformanceV4.profileMediumFieldLegacy: FieldValue.delete(),
      'fotoUrlCacheRevision': revision,
      'photoStoragePath': uploaded.fullStoragePath,
      'photoThumbStoragePath': uploaded.thumbStoragePath,
      photoUploadStateField: statePublished,
      'photoUploadError': FieldValue.delete(),
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    YahwehFlowLog.memberPhotoUploadOk();
    ChurchPublishFlowLog.memberPhotoUploadOk();
    YahwehFlowLog.uploadSuccess('member_profile');
    ChurchPublishFlowLog.uploadOk('member_profile');

    var tenantIds =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
            tenantId);
    if (tenantIds.isEmpty) tenantIds = [tenantId];
    final db = firebaseDefaultFirestore;
    await Future.wait(
      tenantIds.map(
        (tid) => FirestoreWebGuard.runWithWebRecovery(
          () => MembrosOfflineSync.set(
            ref: db
                .collection('igrejas')
                .doc(tid)
                .collection('membros')
                .doc(memberDocId),
            tenantId: tid,
            merge: true,
            data: updates,
          ),
        ),
      ),
    );

    if (authUid.isNotEmpty) {
      try {
        await db.collection('users').doc(authUid).set({
          YahwehPerformanceV4.profileFullField: photoUrl,
          YahwehPerformanceV4.profileThumbField: thumbUrl,
          'foto_url': photoUrl,
          'photoURL': photoUrl,
          YahwehPerformanceV4.profileThumbFieldLegacy: thumbUrl,
          'fotoUrlCacheRevision': revision,
        }, SetOptions(merge: true));
      } catch (e, st) {
        YahwehFlowLog.error('MEMBROS', e, st);
      }
    }

    FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload(
      tenantId: tenantId,
      memberId: FirebaseStorageService.memberProfileStorageFolderId(
        memberDocId,
        authUid.isEmpty ? null : authUid,
      ),
    );

    invalidateDisplayCaches(
      previousDownloadUrl: previousUrl,
      newDownloadUrl: photoUrl,
      storagePath: uploaded.fullStoragePath,
    );
    if (previousThumb.isNotEmpty) {
      invalidateDisplayCaches(
        previousDownloadUrl: previousThumb,
        newDownloadUrl: thumbUrl,
        storagePath: uploaded.thumbStoragePath,
      );
    }

    final mergedMember = Map<String, dynamic>.from(memberData)..addAll(updates);
    await syncChatPeerProfilesAfterPhotoUpdate(
      primaryTenantId: tenantId,
      memberDocId: memberDocId,
      memberData: mergedMember,
      photoUrl: photoUrl,
      photoThumbUrl: thumbUrl,
      cacheRevision: revision,
    );

    return MemberProfilePhotoUpdateResult(
      downloadUrl: photoUrl,
      storagePath: uploaded.fullStoragePath,
      cacheRevision: revision,
    );
  }

  /// Espelha foto/nome em `chat_peer_profiles` (chat instantâneo; CF mantém consistência).
  static Future<void> syncChatPeerProfilesAfterPhotoUpdate({
    required String primaryTenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required String photoUrl,
    String? photoThumbUrl,
    required int cacheRevision,
  }) async {
    final authUid = (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
        .toString()
        .trim();
    if (authUid.isEmpty) return;

    final displayName = (memberData['NOME_COMPLETO'] ??
            memberData['nome'] ??
            memberData['name'] ??
            'Membro')
        .toString()
        .trim();
    final url = sanitizeImageUrl(photoUrl);
    final thumb = sanitizeImageUrl(
      photoThumbUrl ??
          MemberProfileVariantsService.listPhotoUrl(memberData) ??
          '',
    );

    var tenantIds =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
            primaryTenantId);
    if (tenantIds.isEmpty) tenantIds = [primaryTenantId];

    final db = firebaseDefaultFirestore;
    final peerPayload = <String, dynamic>{
      'authUid': authUid,
      'memberDocId': memberDocId,
      'displayName': displayName.isEmpty ? 'Membro' : displayName,
      'photoUrl': thumb.isNotEmpty ? thumb : (url.isEmpty ? null : url),
      'photoThumbUrl': thumb.isEmpty ? null : thumb,
      'fotoUrl': url.isEmpty ? null : url,
      'fotoThumbUrl': thumb.isEmpty ? null : thumb,
      'fotoUrlCacheRevision': cacheRevision,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final memberRefData = Map<String, dynamic>.from(memberData)
      ..['authUid'] = authUid
      ..['firebaseUid'] = authUid
      ..['fotoUrlCacheRevision'] = cacheRevision;
    if (url.isNotEmpty) {
      memberRefData['fotoUrl'] = url;
      memberRefData['foto_url'] = url;
      memberRefData['photoURL'] = url;
    }
    if (thumb.isNotEmpty) {
      memberRefData['fotoThumbUrl'] = thumb;
      memberRefData[YahwehPerformanceV4.profileThumbFieldLegacy] = thumb;
    }
    final chatRef = ChurchChatMemberRef(
      memberId: memberDocId,
      data: memberRefData,
      authUid: authUid,
      photoUrl: thumb.isNotEmpty ? thumb : (url.isEmpty ? null : url),
    );

    for (final tid in tenantIds) {
      ChurchChatPeerProfileService.invalidateAuthUid(tid, authUid);
      ChurchChatPeerProfileService.patchCachedMemberRef(tid, chatRef);
    }
    // `chat_peer_profiles` é escrito pelo Admin SDK (CF onIgrejaMembroWriteChatPeerProfile).
    unawaited(
      Future.wait(
        tenantIds.map((tid) async {
          try {
            await db
                .collection('igrejas')
                .doc(tid)
                .collection('chat_peer_profiles')
                .doc(authUid)
                .set(peerPayload, SetOptions(merge: true));
          } catch (_) {}
        }),
      ),
    );

    MemberProfilePhotoSyncNotifier.instance.notifyPhotoUpdated(
      tenantId: primaryTenantId,
      authUid: authUid,
      cacheRevision: cacheRevision,
    );
  }

  /// Revisão actual para [ValueKey] de avatares no chat.
  static int cacheRevisionFromData(Map<String, dynamic> data) =>
      memberPhotoDisplayCacheRevision(data) ?? 0;
}
