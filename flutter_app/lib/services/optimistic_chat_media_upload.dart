import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:gestao_yahweh/services/church_chat_fs.dart';
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
        void uploadProgress(double t) =>
            _mapProgress(reportProgress, 0.15, 0.96, t);
        // Mobile: 1× WebP leve (turbo) ou ficheiro direto — evita 2 tiers + 2 uploads.
        if (!kIsWeb &&
            uploadPath != null &&
            uploadPath.isNotEmpty &&
            messageId != null &&
            messageId.isNotEmpty) {
          try {
            if (kMediaTurboEnabled) {
              reportProgress(0.22);
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
                await ChurchChatService.completeMediaUploadMessage(
                  tenantId: tenantId,
                  threadId: threadId,
                  messageId: messageId,
                  downloadUrl: up.url,
                  storagePath: up.path,
                  fileName: pending.fileName,
                );
                reportProgress(1.0);
                onSuccess();
                return;
              }
            }
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
            await ChurchChatService.completeMediaUploadMessage(
              tenantId: tenantId,
              threadId: threadId,
              messageId: messageId,
              downloadUrl: up.url,
              storagePath: up.path,
              fileName: pending.fileName,
            );
            reportProgress(1.0);
            onSuccess();
            return;
          } catch (_) {
            // Fallback: variantes WebP abaixo.
          }
        }
        reportProgress(0.38);
        final stem = pending.fileName.replaceAll(RegExp(r'\.[a-z0-9]+$'), '');
        try {
          final tiers = await MediaImageVariantsService.encodeChatWebpTiers(
            bytes: uploadBytes is Uint8List && uploadBytes.isNotEmpty
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
          await ChurchChatService.completeMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: messageId,
            downloadUrl: chatUp.primaryUrl,
            storagePath: fullPath,
            fileName: pending.fileName,
            thumbUrl: chatUp.thumbUrl,
          );
          reportProgress(1.0);
          onSuccess();
          return;
        } catch (_) {
          // Fallback: JPEG/PNG original (web ou compressão WebP indisponível).
          final raw = uploadBytes is Uint8List && uploadBytes.isNotEmpty
              ? uploadBytes
              : (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb)
                  ? await churchChatReadFileBytes(uploadPath)
                  : null;
          if (raw == null || raw.isEmpty) {
            rethrow;
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
          await ChurchChatService.completeMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: messageId,
            downloadUrl: up.url,
            storagePath: up.path,
            fileName: pending.fileName,
          );
          reportProgress(1.0);
          onSuccess();
          return;
        }
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

      await ChurchChatService.completeMediaUploadMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        downloadUrl: up.url,
        storagePath: up.path,
        fileName: pending.kind == 'document' ? pending.fileName : null,
      );
      reportProgress(1.0);
      onSuccess();
    } on FirebaseException catch (e) {
      await _abandonStub(pending, tenantId, threadId);
      onFailed(formatUploadErrorForUser(e));
    } catch (e) {
      await _abandonStub(pending, tenantId, threadId);
      onFailed(formatUploadErrorForUser(e));
    }
  }
}
