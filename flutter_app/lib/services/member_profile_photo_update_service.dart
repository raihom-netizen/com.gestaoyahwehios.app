import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/painting.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        MemberProfilePhotoBytesCache,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/services/image_helper.dart';

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
      }
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
    var nome = (memberData['NOME_COMPLETO'] ?? memberData['nome'] ?? '')
        .toString()
        .trim();
    final authUid = (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
        .toString()
        .trim();
    final compressed =
        await ImageHelper.compressMemberProfileForUpload(rawBytes);
    final photoPath = FirebaseStorageService.memberProfilePhotoPath(
      tenantId: tenantId,
      memberDocId: memberDocId,
      nomeCompleto: nome,
      authUid: authUid.isEmpty ? null : authUid,
    );
    final upload = await MediaUploadService.uploadBytesDetailed(
      storagePath: photoPath,
      bytes: compressed,
      contentType: bytesLookLikeWebp(compressed) ? 'image/webp' : 'image/jpeg',
      skipClientPrepare: true,
      deleteFirebaseDownloadUrlsBefore: () {
        if (previousUrl.isEmpty) return null;
        return <String>[previousUrl];
      }(),
      useOfflineQueue: false,
    );
    final photoUrl = sanitizeImageUrl(upload.downloadUrl);
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
      'fotoUrlCacheRevision': revision,
      'photoStoragePath': upload.storagePath,
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
      storagePath: upload.storagePath,
    );

    return MemberProfilePhotoUpdateResult(
      downloadUrl: photoUrl,
      storagePath: upload.storagePath,
      cacheRevision: revision,
    );
  }

  /// Revisão actual para [ValueKey] de avatares no chat.
  static int cacheRevisionFromData(Map<String, dynamic> data) =>
      memberPhotoDisplayCacheRevision(data) ?? 0;
}
