import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart';
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
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_cache.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_keys.dart';

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
    final base = FirebaseFirestore.instance
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
    } catch (_) {}
    return null;
  }

  /// Envia foto e grava nos mesmos campos do módulo Membros (`fotoUrl`, `fotoUrlCacheRevision`, etc.).
  static Future<MemberProfilePhotoUpdateResult> uploadAndPatchMember({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
  }) async {
    final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));
    final authUid = (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
        .toString()
        .trim();
    final tiers = await MemberProfileVariantsService.encodeProfileTiers(rawBytes);
    final uploaded = await MemberProfileVariantsService.uploadProfileVariants(
      tenantId: tenantId,
      memberDocId: memberDocId,
      thumbBytes: tiers.thumb,
      mediumBytes: tiers.medium,
      fullBytes: tiers.full,
    );
    final photoUrl = sanitizeImageUrl(uploaded.photoFull);
    if (!isValidImageUrl(photoUrl)) {
      throw StateError('URL da foto inválida após upload.');
    }
    final revision = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{
      'foto_url': photoUrl,
      'FOTO_URL_OU_ID': photoUrl,
      'fotoUrl': photoUrl,
      'photoURL': photoUrl,
      'photoVariants': FieldValue.delete(),
      YahwehPerformanceV4.profileThumbField: uploaded.photoThumb,
      YahwehPerformanceV4.profileMediumField: uploaded.photoMedium,
      'fotoUrlCacheRevision': revision,
      'photoStoragePath': uploaded.fullStoragePath,
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
    };

    var tenantIds =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
            tenantId);
    if (tenantIds.isEmpty) tenantIds = [tenantId];
    final db = FirebaseFirestore.instance;
    await Future.wait(
      tenantIds.map(
        (tid) => db
            .collection('igrejas')
            .doc(tid)
            .collection('membros')
            .doc(memberDocId)
            .set(updates, SetOptions(merge: true)),
      ),
    );

    if (authUid.isNotEmpty) {
      try {
        await db.collection('users').doc(authUid).set({
          'foto_url': photoUrl,
          'photoURL': photoUrl,
          'fotoUrl': photoUrl,
          YahwehPerformanceV4.profileThumbField: uploaded.photoThumb,
          YahwehPerformanceV4.profileMediumField: uploaded.photoMedium,
          'fotoUrlCacheRevision': revision,
        }, SetOptions(merge: true));
      } catch (_) {}
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

    final mergedMember = Map<String, dynamic>.from(memberData)..addAll(updates);
    await syncChatPeerProfilesAfterPhotoUpdate(
      primaryTenantId: tenantId,
      memberDocId: memberDocId,
      memberData: mergedMember,
      photoUrl: photoUrl,
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

    var tenantIds =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(
            primaryTenantId);
    if (tenantIds.isEmpty) tenantIds = [primaryTenantId];

    final db = FirebaseFirestore.instance;
    final peerPayload = <String, dynamic>{
      'authUid': authUid,
      'memberDocId': memberDocId,
      'displayName': displayName.isEmpty ? 'Membro' : displayName,
      'photoUrl': url.isEmpty ? null : url,
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
    final chatRef = ChurchChatMemberRef(
      memberId: memberDocId,
      data: memberRefData,
      authUid: authUid,
      photoUrl: url.isEmpty ? null : url,
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
