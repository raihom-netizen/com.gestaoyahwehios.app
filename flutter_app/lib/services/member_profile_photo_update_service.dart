import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart';
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
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
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_cache.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_keys.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/member_profile_photo_save_service.dart';

/// Resultado de upload de foto de perfil do membro (chat + módulo Membros).
class MemberProfilePhotoUpdateResult {
  final String downloadUrl;
  final String storagePath;
  final int cacheRevision;
  final String? thumbDownloadUrl;
  final String? thumbStoragePath;

  const MemberProfilePhotoUpdateResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.cacheRevision,
    this.thumbDownloadUrl,
    this.thumbStoragePath,
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
    String? thumbStoragePath,
    String? tenantId,
    String? memberDocId,
    String? authUid,
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
    final thumbPath = (thumbStoragePath ?? '').trim();
    if (thumbPath.isNotEmpty && thumbPath != path) {
      MemberProfilePhotoBytesCache.removeByObjectPath(thumbPath);
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
    if (thumbPath.isNotEmpty) {
      unawaited(deleteYahwehMediaBytesDiskKeys(
        YahwehMediaBytesDiskKeys.invalidateKeysForStoragePath(thumbPath),
      ));
    }
    final tid = (tenantId ?? '').trim();
    final mid = (memberDocId ?? '').trim();
    if (tid.isNotEmpty && mid.isNotEmpty) {
      FirebaseStorageService.invalidateMemberPhotoCache(
        tenantId: tid,
        memberId: mid,
        authUid: (authUid ?? '').trim().isEmpty ? null : authUid!.trim(),
      );
    }
  }

  /// Localiza o documento do membro logado (CPF, doc id = authUid, ou campo `authUid`).
  static Future<DocumentSnapshot<Map<String, dynamic>>?> resolveMemberDoc({
    required String tenantId,
    required String authUid,
    String? cpfDigits,
  }) async {
    await ensureFirebaseCore(requireAuth: false);
    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) return null;
    final base = ChurchUiCollections.membros(churchId);
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
        final result = await MemberProfilePhotoSaveService.saveInternal(
          tenantId: tenantId,
          memberDocId: memberDocId,
          memberData: memberData,
          rawBytes: rawBytes,
          requireAuth: requireAuth,
        );
        await _afterPhotoSaved(
          tenantId: tenantId,
          memberDocId: memberDocId,
          memberData: memberData,
          result: result,
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
    var tenantIds = <String>[];
    try {
      tenantIds = [ChurchPublishContext.churchIdForPublish(tenantId)];
    } catch (_) {
      tenantIds = [tenantId.trim()];
    }
    if (tenantIds.isEmpty || tenantIds.first.isEmpty) tenantIds = [tenantId];
    final db = firebaseDefaultFirestore;
    await Future.wait(
      tenantIds.map(
        (tid) => FirestoreWebGuard.runWithWebRecovery(
          () async {
            final churchId = ChurchRepository.churchId(tid.trim());
            return MembrosOfflineSync.set(
              ref: ChurchUiCollections.membros(churchId).doc(memberDocId),
              tenantId: churchId,
              merge: true,
              data: patch,
            );
          },
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
    void Function(String phaseLabel)? onPhase,
  }) async {
    YahwehFlowLog.memberPhotoStart();
    ChurchPublishFlowLog.memberPhotoStart();
    final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));
    try {
      final r = await MemberProfilePhotoSaveService.save(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: rawBytes,
        onPhase: onPhase,
      );
      await _afterPhotoSaved(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        result: r,
      );
      invalidateDisplayCaches(
        previousDownloadUrl: previousUrl,
        newDownloadUrl: sanitizeImageUrl(r.downloadUrl),
        storagePath: r.storagePath,
        thumbStoragePath: r.thumbStoragePath,
        tenantId: tenantId,
        memberDocId: memberDocId,
        authUid: (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
            .toString()
            .trim(),
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

  static Future<void> _afterPhotoSaved({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required MemberProfilePhotoUpdateResult result,
  }) async {
    final photoUrl = sanitizeImageUrl(result.downloadUrl);
    final thumbUrl = sanitizeImageUrl(
      result.thumbDownloadUrl ??
          MemberProfileVariantsService.listPhotoUrl(memberData) ??
          photoUrl,
    );
    final authUid = (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
        .toString()
        .trim();

    if (authUid.isNotEmpty) {
      try {
        await firebaseDefaultFirestore.collection('users').doc(authUid).set({
          'photoStoragePath': result.storagePath,
          'photoThumbStoragePath': result.thumbStoragePath,
          'fotoPath': result.storagePath,
          'fotoThumbPath': result.thumbStoragePath,
          'fotoUrlCacheRevision': result.cacheRevision,
        }, SetOptions(merge: true));
      } catch (e, st) {
        YahwehFlowLog.error('MEMBROS', e, st);
      }
    }

    final mergedMember = Map<String, dynamic>.from(memberData)
      ..addAll({
        'photoStoragePath': result.storagePath,
        'photoThumbStoragePath': result.thumbStoragePath,
        'fotoPath': result.storagePath,
        'fotoThumbPath': result.thumbStoragePath,
        'fotoUrlCacheRevision': result.cacheRevision,
      });
    await syncChatPeerProfilesAfterPhotoUpdate(
      primaryTenantId: tenantId,
      memberDocId: memberDocId,
      memberData: mergedMember,
      photoUrl: photoUrl,
      photoThumbUrl: thumbUrl,
      cacheRevision: result.cacheRevision,
      photoStoragePath: result.storagePath,
      photoThumbStoragePath: result.thumbStoragePath,
    );
  }

  static Future<MemberProfilePhotoUpdateResult> _uploadAndPatchMemberCore({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    bool requireAuth = true,
  }) async {
    final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));
    final previousThumb = sanitizeImageUrl(
      MemberProfileVariantsService.listPhotoUrl(memberData) ?? '',
    );
    final result = await MemberProfilePhotoSaveService.saveInternal(
      tenantId: tenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      rawBytes: rawBytes,
      requireAuth: requireAuth,
    );
    await _afterPhotoSaved(
      tenantId: tenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      result: result,
    );
    invalidateDisplayCaches(
      previousDownloadUrl: previousUrl,
      newDownloadUrl: sanitizeImageUrl(result.downloadUrl),
      storagePath: result.storagePath,
      thumbStoragePath: result.thumbStoragePath,
      tenantId: tenantId,
      memberDocId: memberDocId,
      authUid: (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
          .toString()
          .trim(),
    );
    if (previousThumb.isNotEmpty) {
      invalidateDisplayCaches(
        previousDownloadUrl: previousThumb,
        newDownloadUrl: sanitizeImageUrl(
          result.thumbDownloadUrl ?? result.downloadUrl,
        ),
        thumbStoragePath: result.thumbStoragePath,
        tenantId: tenantId,
        memberDocId: memberDocId,
        authUid: (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
            .toString()
            .trim(),
      );
    }
    return result;
  }

  /// Espelha foto/nome em `chat_peer_profiles` (chat instantâneo; CF mantém consistência).
  static Future<void> syncChatPeerProfilesAfterPhotoUpdate({
    required String primaryTenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required String photoUrl,
    String? photoThumbUrl,
    required int cacheRevision,
    String? photoStoragePath,
    String? photoThumbStoragePath,
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

    var tenantIds = <String>[];
    try {
      tenantIds = [ChurchPublishContext.churchIdForPublish(primaryTenantId)];
    } catch (_) {
      tenantIds = [primaryTenantId.trim()];
    }
    if (tenantIds.isEmpty || tenantIds.first.isEmpty) {
      tenantIds = [primaryTenantId];
    }

    final sp = (photoStoragePath ??
            memberData['photoStoragePath'] ??
            memberData['fotoPath'] ??
            '')
        .toString()
        .trim();
    final tsp = (photoThumbStoragePath ??
            memberData['photoThumbStoragePath'] ??
            memberData['fotoThumbPath'] ??
            '')
        .toString()
        .trim();
    final peerPayload = <String, dynamic>{
      'authUid': authUid,
      'memberDocId': memberDocId,
      'displayName': displayName.isEmpty ? 'Membro' : displayName,
      if (sp.isNotEmpty) 'photoStoragePath': sp,
      if (tsp.isNotEmpty) 'photoThumbStoragePath': tsp,
      if (sp.isNotEmpty) 'fotoPath': sp,
      if (tsp.isNotEmpty) 'fotoThumbPath': tsp,
      'fotoUrlCacheRevision': cacheRevision,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final memberRefData = Map<String, dynamic>.from(memberData)
      ..['authUid'] = authUid
      ..['firebaseUid'] = authUid
      ..['fotoUrlCacheRevision'] = cacheRevision;
    if (sp.isNotEmpty) {
      memberRefData['photoStoragePath'] = sp;
      memberRefData['fotoPath'] = sp;
    }
    if (tsp.isNotEmpty) {
      memberRefData['photoThumbStoragePath'] = tsp;
      memberRefData['fotoThumbPath'] = tsp;
    }
    final displayPhoto = tsp.isNotEmpty
        ? tsp
        : (sp.isNotEmpty
            ? sp
            : (thumb.isNotEmpty ? thumb : (url.isEmpty ? null : url)));
    final chatRef = ChurchChatMemberRef(
      memberId: memberDocId,
      data: memberRefData,
      authUid: authUid,
      photoUrl: displayPhoto,
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
            final churchId = ChurchRepository.churchId(tid.trim());
            await ChurchUiCollections.churchDoc(churchId)
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
