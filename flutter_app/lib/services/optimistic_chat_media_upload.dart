import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:gestao_yahweh/services/church_chat_fs.dart'
    show churchChatReadFileBytes;
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/media_image_variants_service.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Chat Igreja estilo WhatsApp: stub Firestore (`uploading`) → compress → Storage → `sent`.
abstract final class OptimisticChatMediaUpload {
  OptimisticChatMediaUpload._();

  static Duration _flushTimeoutFor(String kind) => switch (kind) {
        'video' => const Duration(minutes: 18),
        'audio' => const Duration(minutes: 8),
        _ => const Duration(minutes: 10),
      };

  static void _mapProgress(
    void Function(double progress) onProgress,
    double phaseStart,
    double phaseEnd,
    double t,
  ) {
    onProgress((phaseStart + (phaseEnd - phaseStart) * t).clamp(0.0, 1.0));
  }

  /// Upload em background após bolha local [ChurchChatOutboundPending].
  static Future<void> flush({
    required ChurchChatOutboundPending pending,
    required String tenantId,
    required String threadId,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    required void Function(double progress) onProgress,
    required void Function(String errorMessage) onFailed,
    required VoidCallback onSuccess,
    VoidCallback? onReplyCleared,
  }) async {
    try {
      await _flushCore(
        pending: pending,
        tenantId: tenantId,
        threadId: threadId,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onFailed: onFailed,
        onSuccess: onSuccess,
        onReplyCleared: onReplyCleared,
      ).timeout(
        _flushTimeoutFor(pending.kind),
        onTimeout: () => throw TimeoutException(
          'Envio demorou demais. Verifique a rede e tente de novo.',
        ),
      );
    } on TimeoutException catch (e) {
      await _abandonStub(pending, tenantId, threadId);
      onFailed(formatUploadErrorForUser(e));
    }
  }

  static Future<void> _abandonStub(
    ChurchChatOutboundPending pending,
    String tenantId,
    String threadId,
  ) async {
    final mid = pending.firestoreMessageId;
    if (mid != null && mid.isNotEmpty) {
      await ChurchChatService.abandonMediaUploadMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: mid,
      );
    }
    pending.firestoreMessageId = null;
    pending.storagePath = null;
  }

  static Future<void> _flushCore({
    required ChurchChatOutboundPending pending,
    required String tenantId,
    required String threadId,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    required void Function(double progress) onProgress,
    required void Function(String errorMessage) onFailed,
    required VoidCallback onSuccess,
    VoidCallback? onReplyCleared,
  }) async {
    var messageId = pending.firestoreMessageId;
    var storagePath = pending.storagePath;

    void reportProgress(double p) {
      onProgress(p);
      final mid = messageId;
      if (mid != null && mid.isNotEmpty) {
        unawaited(
          ChurchChatService.patchMediaUploadProgress(
            tenantId: tenantId,
            threadId: threadId,
            messageId: mid,
            progress: p,
          ),
        );
      }
    }

    try {
      await ensureFirebaseInitialized();
      if (messageId == null || messageId.isEmpty) {
        final can = await ChurchChatMemberPrefs.canSendToDmThread(
          tenantId: tenantId,
          threadId: threadId,
        );
        if (!can) {
          onFailed('Envio bloqueado — desbloqueie o contacto.');
          return;
        }
        reportProgress(0.04);
        final begun = await ChurchChatService.beginMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          kind: pending.kind,
          fileName: pending.kind == 'document' ? pending.fileName : null,
          replyTo: replyTo,
          senderDisplayName:
              ChurchChatService.senderDisplayNameForNewMessage(),
        ).timeout(const Duration(seconds: 20));
        messageId = begun.messageId;
        storagePath = begun.storagePath;
        pending.firestoreMessageId = messageId;
        pending.storagePath = storagePath;
        onReplyCleared?.call();
      }

      reportProgress(0.08);
      await FeedPostMediaUpload.warmAuthToken()
          .timeout(const Duration(seconds: 25));

      var uploadPath = localPath;
      List<int>? uploadBytes = bytes;

      if (pending.kind == 'video' &&
          uploadPath != null &&
          uploadPath.isNotEmpty &&
          !kIsWeb) {
        final videoResult = await MediaService.prepareVideoForChatUpload(
          uploadPath,
          onCompressProgress: (t) =>
              _mapProgress(reportProgress, 0.08, 0.42, t),
        );
        if (videoResult != null) {
          uploadPath = videoResult.outputPath;
          pending.localPath = uploadPath;
        }
      } else if (pending.kind == 'image') {
        final mid = messageId;
        if (mid == null || mid.isEmpty) {
          throw StateError('Stub Firestore ausente para foto.');
        }
        final up = await _uploadChatImageWithFallbacks(
          pending: pending,
          tenantId: tenantId,
          threadId: threadId,
          storagePath: storagePath!,
          uploadPath: uploadPath,
          uploadBytes: uploadBytes,
          reportProgress: reportProgress,
        );
        await _finalizeChatMediaUpload(
          tenantId: tenantId,
          threadId: threadId,
          messageId: mid,
          pending: pending,
          downloadUrl: up.url,
          storagePath: up.path,
          thumbUrl: up.thumbUrl,
          reportProgress: reportProgress,
          onSuccess: onSuccess,
        );
        return;
      }

      final ({String url, String path}) up;
      void uploadProgress(double t) =>
          _mapProgress(reportProgress, 0.42, 0.96, t);

      if (uploadBytes != null && uploadBytes.isNotEmpty) {
        up = await ChurchChatService.uploadChatBytes(
          tenantId: tenantId,
          threadId: threadId,
          bytes: uploadBytes,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          onProgress: uploadProgress,
        );
      } else if (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb) {
        up = await ChurchChatService.uploadChatFile(
          tenantId: tenantId,
          threadId: threadId,
          localPath: uploadPath,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          skipRecompress: pending.kind == 'video' || pending.kind == 'audio',
          onProgress: uploadProgress,
        );
      } else {
        throw StateError('Sem dados para enviar.');
      }

      await _finalizeChatMediaUpload(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId!,
        pending: pending,
        downloadUrl: up.url,
        storagePath: up.path,
        reportProgress: reportProgress,
        onSuccess: onSuccess,
      );
    } on FirebaseException catch (e) {
      await _abandonStub(pending, tenantId, threadId);
      onFailed(formatUploadErrorForUser(e));
    } catch (e) {
      await _abandonStub(pending, tenantId, threadId);
      onFailed(formatUploadErrorForUser(e));
    }
  }

  static Future<void> _finalizeChatMediaUpload({
    required String tenantId,
    required String threadId,
    required String messageId,
    required ChurchChatOutboundPending pending,
    required String downloadUrl,
    required String storagePath,
    String? thumbUrl,
    required void Function(double progress) reportProgress,
    required VoidCallback onSuccess,
  }) async {
    reportProgress(0.94);
    await ChurchChatService.completeMediaUploadMessageWithRetry(
      tenantId: tenantId,
      threadId: threadId,
      messageId: messageId,
      downloadUrl: downloadUrl,
      storagePath: storagePath,
      fileName: pending.kind == 'document' ? pending.fileName : null,
      thumbUrl: thumbUrl,
    );
    reportProgress(1.0);
    onSuccess();
  }

  static Future<({String url, String path, String? thumbUrl})>
      _uploadChatImageWithFallbacks({
    required ChurchChatOutboundPending pending,
    required String tenantId,
    required String threadId,
    required String storagePath,
    required String? uploadPath,
    required List<int>? uploadBytes,
    required void Function(double progress) reportProgress,
  }) async {
    void uploadProgress(double t) =>
        _mapProgress(reportProgress, 0.12, 0.90, t);

    Object? lastError;

    // Android/iOS: ficheiro directo primeiro (mesma estabilidade que web após bytes).
    if (!kIsWeb && uploadPath != null && uploadPath.isNotEmpty) {
      try {
        reportProgress(0.14);
        final up = await ChurchChatService.uploadChatFile(
          tenantId: tenantId,
          threadId: threadId,
          localPath: uploadPath,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          skipRecompress: true,
          onProgress: uploadProgress,
        );
        return (url: up.url, path: up.path, thumbUrl: null);
      } catch (e) {
        lastError = e;
      }
    }

    if (!kIsWeb &&
        kMediaTurboEnabled &&
        uploadPath != null &&
        uploadPath.isNotEmpty) {
      try {
        reportProgress(0.20);
        final webp = await IosPublishImagePipeline.compressForPublishFromPath(
          uploadPath,
        );
        if (webp.isNotEmpty) {
          final up = await ChurchChatService.uploadChatBytes(
            tenantId: tenantId,
            threadId: threadId,
            bytes: webp,
            fileName: pending.fileName.replaceAll(
              RegExp(r'\.[a-z0-9]+$', caseSensitive: false),
              '.webp',
            ),
            contentType: 'image/webp',
            storagePathOverride: storagePath,
            skipClientPrepare: true,
            onProgress: uploadProgress,
          );
          return (url: up.url, path: up.path, thumbUrl: null);
        }
      } catch (e) {
        lastError = e;
      }
    }

    try {
      reportProgress(0.32);
      final stem = pending.fileName.replaceAll(RegExp(r'\.[a-z0-9]+$'), '');
      final tiers = await MediaImageVariantsService.encodeChatWebpTiers(
        bytes: uploadBytes != null && uploadBytes.isNotEmpty
            ? Uint8List.fromList(uploadBytes)
            : null,
        localPath: uploadPath,
      );
      final thumbPath = ChurchStorageLayout.chatMediaVariantPath(
        tenantId,
        threadId,
        stem,
        MediaImageVariantsService.tierThumb,
      );
      final fullPath = ChurchStorageLayout.chatMediaVariantPath(
        tenantId,
        threadId,
        stem,
        MediaImageVariantsService.tierFull,
      );
      final chatUp = await MediaImageVariantsService.uploadChatTiers(
        thumbPath: thumbPath,
        fullPath: fullPath,
        thumbBytes: tiers.thumb,
        fullBytes: tiers.full,
        onProgress: uploadProgress,
      );
      return (
        url: chatUp.primaryUrl,
        path: fullPath,
        thumbUrl: chatUp.thumbUrl,
      );
    } catch (e) {
      lastError = e;
    }

    final raw = uploadBytes != null && uploadBytes.isNotEmpty
        ? uploadBytes
        : (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb)
            ? await churchChatReadFileBytes(uploadPath)
            : null;
    if (raw == null || raw.isEmpty) {
      throw lastError ?? StateError('Sem dados para enviar a foto.');
    }
    final up = await ChurchChatService.uploadChatBytes(
      tenantId: tenantId,
      threadId: threadId,
      bytes: raw,
      fileName: pending.fileName,
      contentType: pending.mime,
      storagePathOverride: storagePath,
      onProgress: uploadProgress,
    );
    return (url: up.url, path: up.path, thumbUrl: null);
  }
}
