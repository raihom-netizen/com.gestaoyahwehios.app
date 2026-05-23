import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/media_service.dart';

/// Pipeline de envio otimista no Chat Igreja (stub Firestore → compress → Storage → sent).
abstract final class OptimisticChatMediaUpload {
  OptimisticChatMediaUpload._();

  static Duration _flushTimeoutFor(String kind) => switch (kind) {
        'video' => const Duration(minutes: 9),
        'audio' => const Duration(minutes: 4),
        _ => const Duration(minutes: 3),
      };

  static void _mapProgress(
    void Function(double progress) onProgress,
    double phaseStart,
    double phaseEnd,
    double t,
  ) {
    final p = (phaseStart + (phaseEnd - phaseStart) * t).clamp(0.0, 1.0);
    onProgress(p);
  }

  /// Upload em background após [ChurchChatOutboundPending] já visível na UI.
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
      onFailed(e.message ?? '$e');
    }
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
    var uploadPath = localPath;
    String? messageId = pending.firestoreMessageId;
    String? storagePath = pending.storagePath;

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
      final can = await ChurchChatMemberPrefs.canSendToDmThread(
        tenantId: tenantId,
        threadId: threadId,
      );
      if (!can) {
        onFailed('Envio bloqueado — desbloqueie o contacto.');
        return;
      }

      reportProgress(0.02);

      if (messageId == null || messageId.isEmpty) {
        final begun = await ChurchChatService.beginMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          kind: pending.kind,
          fileName: pending.kind == 'document' ? pending.fileName : null,
          replyTo: replyTo,
          senderDisplayName:
              ChurchChatService.senderDisplayNameForNewMessage(),
        );
        messageId = begun.messageId;
        storagePath = begun.storagePath;
        pending.firestoreMessageId = messageId;
        pending.storagePath = storagePath;
        onReplyCleared?.call();
        reportProgress(0.08);
      }

      reportProgress(0.1);

      List<int>? uploadBytes = bytes;
      var alreadyCompressedImage = false;

      if (pending.kind == 'video' &&
          uploadPath != null &&
          uploadPath.isNotEmpty &&
          !kIsWeb) {
        await FeedPostMediaUpload.warmAuthToken();
        final videoResult = await MediaService.prepareVideoForChatUpload(
          uploadPath,
          onCompressProgress: (t) =>
              _mapProgress(reportProgress, 0.05, 0.45, t),
        );
        if (videoResult != null) {
          uploadPath = videoResult.outputPath;
          pending.localPath = uploadPath;
        }
      } else if (pending.kind == 'image' &&
          uploadPath != null &&
          uploadPath.isNotEmpty &&
          !kIsWeb &&
          (uploadBytes == null || uploadBytes.isEmpty)) {
        await FeedPostMediaUpload.warmAuthToken();
        final compressedFile = await MediaService.compressImage(
          File(uploadPath),
          profile: MediaImageProfile.chat,
        );
        if (compressedFile != null && compressedFile.existsSync()) {
          uploadPath = compressedFile.path;
          pending.localPath = uploadPath;
          alreadyCompressedImage = true;
        }
        reportProgress(0.35);
      } else if (pending.kind == 'image' &&
          uploadBytes != null &&
          uploadBytes.isNotEmpty) {
        await FeedPostMediaUpload.warmAuthToken();
        final compressed = await MediaService.compressImageBytes(
          uploadBytes is Uint8List
              ? uploadBytes
              : Uint8List.fromList(uploadBytes),
          profile: MediaImageProfile.chat,
        );
        uploadBytes = compressed;
        alreadyCompressedImage = true;
        reportProgress(0.35);
      } else {
        await FeedPostMediaUpload.warmAuthToken();
        reportProgress(0.2);
      }

      final ({String url, String path}) up;
      void uploadProgress(double t) =>
          _mapProgress(reportProgress, 0.4, 0.98, t);

      if (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb) {
        up = await ChurchChatService.uploadChatFile(
          tenantId: tenantId,
          threadId: threadId,
          localPath: uploadPath,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          skipRecompress: alreadyCompressedImage ||
              pending.kind == 'video' ||
              pending.kind == 'audio',
          onProgress: uploadProgress,
        );
      } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
        up = await ChurchChatService.uploadChatBytes(
          tenantId: tenantId,
          threadId: threadId,
          bytes: uploadBytes,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          onProgress: uploadProgress,
        );
      } else {
        throw StateError('Sem dados para enviar.');
      }

      await ChurchChatService.completeMediaUploadMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId!,
        downloadUrl: up.url,
        storagePath: up.path,
        fileName: pending.kind == 'document' ? pending.fileName : null,
      );
      reportProgress(1.0);
      onSuccess();
    } on FirebaseException catch (e) {
      if (messageId != null && messageId.isNotEmpty) {
        await ChurchChatService.abandonMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
        );
      }
      pending.firestoreMessageId = null;
      pending.storagePath = null;
      onFailed(e.message ?? e.code);
    } catch (e) {
      if (messageId != null && messageId.isNotEmpty) {
        await ChurchChatService.abandonMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
        );
      }
      pending.firestoreMessageId = null;
      pending.storagePath = null;
      onFailed('$e');
    }
  }
}
