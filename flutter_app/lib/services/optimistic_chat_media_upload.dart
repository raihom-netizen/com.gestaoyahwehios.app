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
    var uploadPath = localPath;
    String? messageId = pending.firestoreMessageId;
    String? storagePath = pending.storagePath;

    try {
      final can = await ChurchChatMemberPrefs.canSendToDmThread(
        tenantId: tenantId,
        threadId: threadId,
      );
      if (!can) {
        onFailed('Envio bloqueado — desbloqueie o contacto.');
        return;
      }

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
      }

      List<int>? uploadBytes = bytes;

      if (pending.kind == 'video' &&
          uploadPath != null &&
          uploadPath.isNotEmpty &&
          !kIsWeb) {
        onProgress(0.02);
        final prepared = await Future.wait<Object?>([
          FeedPostMediaUpload.warmAuthToken(),
          MediaService.prepareVideoForUpload(
            uploadPath,
            onCompressProgress: onProgress,
          ),
        ]);
        final videoResult = prepared[1] as MediaVideoPrepareResult?;
        if (videoResult != null) {
          uploadPath = videoResult.outputPath;
          pending.localPath = uploadPath;
        }
      } else if (pending.kind == 'image' &&
          uploadPath != null &&
          uploadPath.isNotEmpty &&
          !kIsWeb &&
          (uploadBytes == null || uploadBytes.isEmpty)) {
        onProgress(0.05);
        await FeedPostMediaUpload.warmAuthToken();
        final compressedFile = await MediaService.compressImage(
          File(uploadPath),
          profile: MediaImageProfile.chat,
        );
        if (compressedFile != null && compressedFile.existsSync()) {
          uploadPath = compressedFile.path;
          pending.localPath = uploadPath;
        }
      } else if (pending.kind == 'image' &&
          uploadBytes != null &&
          uploadBytes.isNotEmpty) {
        onProgress(0.05);
        await FeedPostMediaUpload.warmAuthToken();
        final compressed = await MediaService.compressImageBytes(
          uploadBytes is Uint8List
              ? uploadBytes
              : Uint8List.fromList(uploadBytes),
          profile: MediaImageProfile.chat,
        );
        uploadBytes = compressed;
      } else {
        await FeedPostMediaUpload.warmAuthToken();
      }

      final ({String url, String path}) up;
      if (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb) {
        up = await ChurchChatService.uploadChatFile(
          tenantId: tenantId,
          threadId: threadId,
          localPath: uploadPath,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          onProgress: onProgress,
        );
      } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
        up = await ChurchChatService.uploadChatBytes(
          tenantId: tenantId,
          threadId: threadId,
          bytes: uploadBytes,
          fileName: pending.fileName,
          contentType: pending.mime,
          storagePathOverride: storagePath,
          onProgress: onProgress,
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
