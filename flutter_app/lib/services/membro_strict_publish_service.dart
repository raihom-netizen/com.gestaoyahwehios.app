import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Foto de perfil — upload validado → Firestore → confirmação (sem falso sucesso).
abstract final class MembroStrictPublishService {
  MembroStrictPublishService._();

  static Future<MemberProfilePhotoUpdateResult> publishPhoto({
    required String seedTenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    String? userUid,
    bool requireAuth = true,
  }) async {
    final igrejaId = await MembroPublishVerificationService.resolveTenantForPublish(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'before',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    try {
      await FirebaseStorageCleanupService.deleteMemberProfilePhotoArtifactsBeforeReplace(
        tenantId: igrejaId,
        memberId: memberDocId,
        data: memberData,
      );
    } catch (e, st) {
      YahwehFlowLog.error('MEMBROS', e, st);
    }

    final tiers = await MemberProfileVariantsService.encodeProfileTiers(rawBytes);
    final uploaded = await MemberProfileVariantsService.uploadProfileVariants(
      tenantId: igrejaId,
      memberDocId: memberDocId,
      thumbBytes: tiers.thumb,
      fullBytes: tiers.full,
      requireAuth: requireAuth,
    );

    await MembroPublishVerificationService.verifyStorageMetadata(
      fullStoragePath: uploaded.fullStoragePath,
      thumbStoragePath: uploaded.thumbStoragePath,
    );

    final revision = DateTime.now().millisecondsSinceEpoch;
    final updates = <String, dynamic>{
      'photoStoragePath': uploaded.fullStoragePath,
      'photoThumbStoragePath': uploaded.thumbStoragePath,
      'fotoPath': uploaded.fullStoragePath,
      'fotoThumbPath': uploaded.thumbStoragePath,
      MemberProfilePhotoUpdateService.photoUploadStateField:
          EntityPublishStatus.published,
      'photoUploadError': FieldValue.delete(),
      'fotoUrlCacheRevision': revision,
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'ativo': true,
    };

    final docRef = MembroPublishVerificationService.membroDocRef(
      igrejaId: igrejaId,
      memberDocId: memberDocId,
    );

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(updates, SetOptions(merge: true)),
    );

    await MembroPublishVerificationService.verifyDocumentExists(
      docRef,
      expectedStoragePath: uploaded.fullStoragePath,
    );

    await MembroPublishVerificationService.logPublishPhase(
      phase: 'after',
      igrejaId: igrejaId,
      memberDocId: memberDocId,
      storagePath: uploaded.fullStoragePath,
    );

    FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload(
      tenantId: igrejaId,
      memberId: FirebaseStorageService.memberProfileStorageFolderId(
        memberDocId,
        (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
            .toString()
            .trim()
            .isEmpty
            ? null
            : (memberData['authUid'] ?? memberData['firebaseUid'] ?? '')
                .toString()
                .trim(),
      ),
    );

    MemberProfilePhotoUpdateService.invalidateDisplayCaches(
      storagePath: uploaded.fullStoragePath,
      newDownloadUrl: uploaded.photoFull,
    );

    return MemberProfilePhotoUpdateResult(
      downloadUrl: uploaded.photoFull,
      storagePath: uploaded.fullStoragePath,
      cacheRevision: revision,
      thumbDownloadUrl: uploaded.photoThumb,
      thumbStoragePath: uploaded.thumbStoragePath,
    );
  }
}
