import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/core/yahweh_unified_image_pipeline.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Foto enfileirada localmente — upload automático quando houver rede (padrão CT).
class MemberProfilePhotoQueuedLocally implements Exception {
  const MemberProfilePhotoQueuedLocally();
}

/// Pipeline único — foto perfil membro (padrão Controle Total):
/// 1 compressão → 1 upload Storage (path fixo, sobrescreve) → 1 merge Firestore (só link).
abstract final class MemberProfilePhotoSaveService {
  MemberProfilePhotoSaveService._();

  /// Timeout só no putData — sem cap global que trava «A enviar…».
  static const Duration kUploadTimeout = Duration(seconds: 38);

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
  }) =>
      saveInternal(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: rawBytes,
        onPhase: onPhase,
        onProgress: onProgress,
        requireAuth: requireAuth,
      );

  /// Só Storage (cadastro público grava Firestore no submit).
  static Future<({String url, String storagePath})> uploadStorageOnlyControleTotal({
    required String tenantId,
    required String memberDocId,
    required Uint8List rawBytes,
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = memberDocId.trim();
    if (churchId.isEmpty || docId.isEmpty || rawBytes.isEmpty) {
      throw StateError('Dados inválidos para enviar foto.');
    }
    final storageFolderId = FirebaseStorageService.memberProfileStorageFolderId(
      docId,
      null,
    );
    final fullPath = ChurchStorageLayout.memberProfilePhotoPath(
      churchId,
      storageFolderId,
    );
    await DirectStorageUrlPublish.ensureReady(requireAuth: requireAuth);
    onProgress?.call(0.12);
    final fullBytes = await _prepareFullBytes(rawBytes);
    onProgress?.call(0.18);
    final mime = _mimeForBytes(fullBytes);
    final url = await DirectStorageUrlPublish.uploadBytes(
      storagePath: fullPath,
      bytes: fullBytes,
      mimeType: mime,
      requireAuth: requireAuth,
      onProgress: (p) => onProgress?.call(0.18 + p * 0.72),
    ).timeout(
      kUploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto demorou demais. Verifique a rede.',
        kUploadTimeout,
      ),
    );
    if (url.trim().isEmpty) {
      throw StateError('Upload concluiu sem URL.');
    }
    FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload(
      tenantId: churchId,
      memberId: storageFolderId,
    );
    onProgress?.call(1.0);
    return (url: sanitizeImageUrl(url), storagePath: fullPath);
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
    onPhase?.call('A preparar…');
    onProgress?.call(0.05);

    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final docId = memberDocId.trim();
    final authUid = (memberData['authUid'] ??
            memberData['firebaseUid'] ??
            memberData['uid'] ??
            '')
        .toString()
        .trim();
    final storageFolderId = FirebaseStorageService.memberProfileStorageFolderId(
      docId,
      authUid.isEmpty ? null : authUid,
    );
    final fullPath = ChurchStorageLayout.memberProfilePhotoPath(
      churchId,
      storageFolderId,
    );

    try {
      await DirectStorageUrlPublish.ensureReady(requireAuth: requireAuth);
      onPhase?.call('A enviar…');
      onProgress?.call(0.10);

      final fullBytes = await _prepareFullBytes(rawBytes);
      onProgress?.call(0.15);
      final mime = _mimeForBytes(fullBytes);

      final uploadedUrl = await DirectStorageUrlPublish.uploadBytes(
        storagePath: fullPath,
        bytes: fullBytes,
        mimeType: mime,
        requireAuth: requireAuth,
        onProgress: (p) => onProgress?.call(0.15 + p * 0.60),
      ).timeout(
        kUploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload da foto demorou demais. Verifique a rede.',
          kUploadTimeout,
        ),
      );
      if (uploadedUrl.trim().isEmpty) {
        throw StateError('Upload da foto concluiu sem URL de download.');
      }

      final revision = YahwehMediaCacheBust.freshRevisionMs();
      final photoUrlRaw = sanitizeImageUrl(uploadedUrl);
      final photoUrl = photoUrlRaw.isNotEmpty
          ? YahwehMediaCacheBust.apply(photoUrlRaw, revision)
          : '';

      final previousUrl = sanitizeImageUrl(imageUrlFromMap(memberData));

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
    } catch (e) {
      if (!kIsWeb && _shouldQueueOffline(e)) {
        final fullBytes = await _prepareFullBytes(rawBytes);
        await MuralPostPendingMediaCache.put(
          tenantId: churchId,
          postId: 'membro_$docId',
          images: [fullBytes],
        );
        await ModuleMediaOutboxService.registerMemberPhoto(
          tenantId: churchId,
          memberDocId: docId,
          memberData: memberData,
        );
        final docRef = ChurchUiCollections.membros(churchId).doc(docId);
        await runFirestorePublishWithRecovery(
          () => docRef.set(
            MemberProfilePhotoUpdateService.pendingUploadPatchFields(),
            SetOptions(merge: true),
          ),
        ).catchError((_) {});
        throw const MemberProfilePhotoQueuedLocally();
      }
      rethrow;
    }
  }

  static bool _shouldQueueOffline(Object e) {
    final msg = e.toString().toLowerCase();
    return e is TimeoutException ||
        msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('unavailable') ||
        msg.contains('connection') ||
        msg.contains('offline') ||
        msg.contains('failed host lookup');
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

  static String _mimeForBytes(Uint8List b) {
    if (_looksLikeWebp(b)) return 'image/webp';
    if (_looksLikeJpeg(b)) return 'image/jpeg';
    return 'image/jpeg';
  }
}
