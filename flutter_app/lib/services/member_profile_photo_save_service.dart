import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Pipeline único — foto perfil membro: bootstrap → Storage → Firestore.
///
/// Paths: `igrejas/{churchId}/membros/{folderId}/foto_perfil.jpg` + thumb webp.
abstract final class MemberProfilePhotoSaveService {
  MemberProfilePhotoSaveService._();

  static const Duration kPublishTimeout = Duration(seconds: 90);

  static Future<MemberProfilePhotoUpdateResult> save({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    void Function(String phaseLabel)? onPhase,
    bool requireAuth = true,
  }) async {
    return saveInternal(
      tenantId: tenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      rawBytes: rawBytes,
      onPhase: onPhase,
      requireAuth: requireAuth,
    ).timeout(
      kPublishTimeout,
      onTimeout: () => throw TimeoutException(
        'O envio da foto demorou demais. Verifique a rede e tente novamente.',
        kPublishTimeout,
      ),
    );
  }

  static Future<MemberProfilePhotoUpdateResult> saveInternal({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    void Function(String phaseLabel)? onPhase,
    bool requireAuth = true,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = memberDocId.trim();
    if (churchId.isEmpty || docId.isEmpty) {
      throw StateError('Igreja ou membro inválido para gravar a foto.');
    }
    final docRef = ChurchUiCollections.membros(churchId).doc(docId);
    return EcoFireResilientPublish.runOrQueue(
      logLabel: 'membro_foto',
      optimisticResult: MemberProfilePhotoUpdateResult(
        downloadUrl: '',
        storagePath: '',
        cacheRevision: DateTime.now().millisecondsSinceEpoch,
      ),
      onQueue: () => EcoFireResilientPublish.queueMemberPhotoPublish(
        churchId: churchId,
        memberDocId: docId,
        docRef: docRef,
        memberData: memberData,
        rawBytes: rawBytes,
      ),
      action: () => _saveOnline(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: rawBytes,
        onPhase: onPhase,
        requireAuth: requireAuth,
      ),
    );
  }

  static Future<MemberProfilePhotoUpdateResult> _saveOnline({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    void Function(String phaseLabel)? onPhase,
    bool requireAuth = true,
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () async {
        onPhase?.call('A preparar Firebase…');
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'membro_foto',
        );
        await ensureFirebaseReadyForMediaUpload();
        await EcoFirePublishBootstrap.ensureHard(logLabel: 'membro_foto');

        final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
        final docId = memberDocId.trim();
        if (churchId.isEmpty || docId.isEmpty) {
          throw StateError('Igreja ou membro inválido para gravar a foto.');
        }

        onPhase?.call('A comprimir imagem…');
        final authUid = (memberData['authUid'] ??
                memberData['firebaseUid'] ??
                memberData['uid'] ??
                '')
            .toString()
            .trim();
        final storageFolderId =
            FirebaseStorageService.memberProfileStorageFolderId(
          docId,
          authUid.isEmpty ? null : authUid,
        );

        final tiers =
            await MemberProfileVariantsService.encodeProfileTiers(rawBytes);

        onPhase?.call('Salvando…');
        final uploaded =
            await MemberProfileVariantsService.uploadProfileVariants(
          tenantId: churchId,
          storageFolderId: storageFolderId,
          fullBytes: tiers.full,
          thumbBytes: tiers.thumb,
          requireAuth: requireAuth,
          onProgress: (_) {},
        );

        onPhase?.call('A confirmar no Storage…');
        await MembroPublishVerificationService.verifyStorageMetadata(
          fullStoragePath: uploaded.fullStoragePath,
          thumbStoragePath: uploaded.thumbStoragePath,
        ).timeout(const Duration(seconds: 20));

        final revision = YahwehMediaCacheBust.freshRevisionMs();
        final photoUrlRaw = sanitizeImageUrl(uploaded.photoFull.trim());
        final thumbUrlRaw = sanitizeImageUrl(uploaded.photoThumb.trim());
        final photoUrl = photoUrlRaw.isNotEmpty
            ? YahwehMediaCacheBust.apply(photoUrlRaw, revision)
            : '';
        final thumbUrl = thumbUrlRaw.isNotEmpty
            ? YahwehMediaCacheBust.apply(thumbUrlRaw, revision)
            : '';

        final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));
        final previousThumb = sanitizeImageUrl(
          MemberProfileVariantsService.listPhotoUrl(memberData) ?? '',
        );

        final updates = <String, dynamic>{
          'photoStoragePath': uploaded.fullStoragePath,
          'photoThumbStoragePath': uploaded.thumbStoragePath,
          'fotoPath': uploaded.fullStoragePath,
          'fotoThumbPath': uploaded.thumbStoragePath,
          if (photoUrl.isNotEmpty) ...{
            'FOTO_URL_DB': photoUrl,
            'avatarUrl': photoUrl,
            'fotoUrl': photoUrl,
            'FOTO_URL_OU_ID': photoUrl,
            'photoURL': photoUrl,
            'photoUrl': photoUrl,
            'foto_url': photoUrl,
          },
          if (thumbUrl.isNotEmpty && thumbUrl != photoUrl) ...{
            'fotoThumbUrl': thumbUrl,
            'photoThumbUrl': thumbUrl,
          },
          MemberProfilePhotoUpdateService.photoUploadStateField:
              EntityPublishStatus.published,
          'photoUploadError': FieldValue.delete(),
          'fotoUrlCacheRevision': revision,
          'ATUALIZADO_EM': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'ativo': true,
        };

        final docRef = ChurchUiCollections.membros(churchId).doc(docId);
        MembroPublishVerificationService.assertMembroDocPath(docRef);

        onPhase?.call('A gravar cadastro…');
        await FirestoreWebGuard.runWithWebRecovery(
          () => docRef.set(updates, SetOptions(merge: true)),
          maxAttempts: 4,
        );

        await MembroPublishVerificationService.verifyDocumentExists(
          docRef,
          expectedStoragePath: uploaded.fullStoragePath,
          preferServer: false,
        ).timeout(const Duration(seconds: 15));

        FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload(
          tenantId: churchId,
          memberId: storageFolderId,
        );

        MemberProfilePhotoUpdateService.invalidateDisplayCaches(
          previousDownloadUrl: previousUrl,
          newDownloadUrl: photoUrlRaw.isNotEmpty ? photoUrlRaw : photoUrl,
          storagePath: uploaded.fullStoragePath,
          thumbStoragePath: uploaded.thumbStoragePath,
          tenantId: churchId,
          memberDocId: docId,
          authUid: authUid.isEmpty ? null : authUid,
        );
        if (previousThumb.isNotEmpty) {
          MemberProfilePhotoUpdateService.invalidateDisplayCaches(
            previousDownloadUrl: previousThumb,
            newDownloadUrl: thumbUrlRaw.isNotEmpty ? thumbUrlRaw : thumbUrl,
            thumbStoragePath: uploaded.thumbStoragePath,
            tenantId: churchId,
            memberDocId: docId,
            authUid: authUid.isEmpty ? null : authUid,
          );
        }

        unawaited(
          ModuleMediaOutboxService.clearMemberPhoto(
            tenantId: churchId,
            memberDocId: docId,
          ),
        );

        return MemberProfilePhotoUpdateResult(
          downloadUrl: photoUrl.isNotEmpty ? photoUrl : photoUrlRaw,
          storagePath: uploaded.fullStoragePath,
          cacheRevision: revision,
          thumbDownloadUrl: thumbUrl.isNotEmpty
              ? thumbUrl
              : (thumbUrlRaw.isNotEmpty ? thumbUrlRaw : null),
          thumbStoragePath: uploaded.thumbStoragePath,
        );
      },
      debugLabel: 'membro_foto_save',
    );
  }
}
