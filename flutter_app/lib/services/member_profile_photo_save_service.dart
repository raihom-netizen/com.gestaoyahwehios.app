import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/core/yahweh_unified_image_pipeline.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_media_upload.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Pipeline único — foto perfil membro (padrão Controle Total):
/// 1 compressão → 1 upload Storage (path fixo, sobrescreve) → 1 merge Firestore (só link).
///
/// Path: `igrejas/{churchId}/membros/{folderId}/foto_perfil.jpg` — **uma foto por membro**.
abstract final class MemberProfilePhotoSaveService {
  MemberProfilePhotoSaveService._();

  /// Timeout curto — caminho quente sem verify bloqueante.
  static const Duration kPublishTimeout = Duration(seconds: 45);

  /// Se o pick já entregou WebP/JPEG leve, não recomprimir de novo.
  static const int _kSkipReencodeMaxBytes = 420 * 1024;

  static Future<MemberProfilePhotoUpdateResult> save({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    void Function(String phaseLabel)? onPhase,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    return saveInternal(
      tenantId: tenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      rawBytes: rawBytes,
      onPhase: onPhase,
      onProgress: onProgress,
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
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = memberDocId.trim();
    if (churchId.isEmpty || docId.isEmpty) {
      throw StateError('Igreja ou membro inválido para gravar a foto.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    return _saveOnline(
      tenantId: tenantId,
      memberDocId: memberDocId,
      memberData: memberData,
      rawBytes: rawBytes,
      onPhase: onPhase,
      onProgress: onProgress,
      requireAuth: requireAuth,
    );
  }

  static Future<MemberProfilePhotoUpdateResult> _saveOnline({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
    void Function(String phaseLabel)? onPhase,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () async {
        onPhase?.call('A preparar…');
        onProgress?.call(0.05);
        if (requireAuth) {
          await ChurchMediaUploadFacade.ensureModuleReady(
            YahwehMediaModule.membros,
          );
        } else {
          await DirectStorageUrlPublish.ensureReady(requireAuth: false);
        }

        final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
        final docId = memberDocId.trim();
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

        onPhase?.call('A preparar imagem…');
        onProgress?.call(0.12);
        final fullBytes = await _prepareFullBytes(rawBytes);

        onPhase?.call('A enviar…');
        onProgress?.call(0.20);
        // Path fixo = uma foto por membro (overwrite no Storage).
        final uploaded = await MemberProfileMediaUpload.uploadProfileFull(
          churchId: churchId,
          storageFolderId: storageFolderId,
          fullBytes: fullBytes,
          requireAuth: requireAuth,
          onProgress: (p) => onProgress?.call(0.20 + p * 0.55),
        );
        if (uploaded.trim().isEmpty) {
          throw StateError('Upload da foto concluiu sem URL de download.');
        }

        final fullPath = ChurchStorageLayout.memberProfilePhotoPath(
          churchId,
          storageFolderId,
        );

        final revision = YahwehMediaCacheBust.freshRevisionMs();
        final photoUrlRaw = sanitizeImageUrl(uploaded);
        final photoUrl = photoUrlRaw.isNotEmpty
            ? YahwehMediaCacheBust.apply(photoUrlRaw, revision)
            : '';

        final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));

        // Firestore: só links/paths (padrão CT). Thumb = mesmo ficheiro.
        final updates = <String, dynamic>{
          'photoStoragePath': fullPath,
          'photoThumbStoragePath': fullPath,
          'fotoPath': fullPath,
          'fotoThumbPath': fullPath,
          if (photoUrl.isNotEmpty) ...{
            'FOTO_URL_DB': photoUrl,
            'avatarUrl': photoUrl,
            'fotoUrl': photoUrl,
            'FOTO_URL_OU_ID': photoUrl,
            'photoURL': photoUrl,
            'photoUrl': photoUrl,
            'foto_url': photoUrl,
            'fotoThumbUrl': photoUrl,
            'photoThumbUrl': photoUrl,
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

        onPhase?.call('A gravar…');
        onProgress?.call(0.82);
        if (kIsWeb) {
          await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
        }
        await AdminFeedFirestoreBridge.upsertDocRef(
          docRef: docRef,
          data: updates,
          isNewDoc: false,
          directWrite: () => runFirestorePublishWithRecovery(
            () => docRef.set(updates, SetOptions(merge: true)),
          ),
        );

        onProgress?.call(0.95);

        // Pós-processamento em background (não bloqueia UI).
        unawaited(
          Future(() async {
            FirebaseStorageCleanupService
                .scheduleCleanupAfterMemberProfilePhotoUpload(
              tenantId: churchId,
              memberId: storageFolderId,
            );
            MemberProfilePhotoUpdateService.invalidateDisplayCaches(
              previousDownloadUrl: previousUrl,
              newDownloadUrl: photoUrlRaw.isNotEmpty ? photoUrlRaw : photoUrl,
              storagePath: fullPath,
              thumbStoragePath: fullPath,
              tenantId: churchId,
              memberDocId: docId,
              authUid: authUid.isEmpty ? null : authUid,
            );
            await ModuleMediaOutboxService.clearMemberPhoto(
              tenantId: churchId,
              memberDocId: docId,
            );
          }),
        );

        onPhase?.call('Concluído');
        onProgress?.call(1.0);
        return MemberProfilePhotoUpdateResult(
          downloadUrl: photoUrl.isNotEmpty ? photoUrl : photoUrlRaw,
          storagePath: fullPath,
          cacheRevision: revision,
          thumbDownloadUrl: photoUrl.isNotEmpty ? photoUrl : photoUrlRaw,
          thumbStoragePath: fullPath,
        );
      },
      debugLabel: 'membro_foto_save',
    );
  }

  /// Evita compressão dupla quando o pick já entregou WebP/JPEG leve.
  static Future<Uint8List> _prepareFullBytes(Uint8List raw) async {
    if (raw.length <= _kSkipReencodeMaxBytes &&
        (_looksLikeWebp(raw) || _looksLikeJpeg(raw))) {
      return raw;
    }
    return YahwehUnifiedImagePipeline.prepareMemberFull(raw);
  }

  static bool _looksLikeWebp(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;

  static bool _looksLikeJpeg(Uint8List b) =>
      b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;
}
