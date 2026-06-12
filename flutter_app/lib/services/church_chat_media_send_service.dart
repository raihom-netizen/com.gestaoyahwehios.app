import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';
import 'package:gestao_yahweh/services/church_chat_media_storage.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Pipeline único — chat mídia estilo WhatsApp: bootstrap → stub → Storage → `sent`.
///
/// Paths: `igrejas/{churchId}/chat_media/…` + `chat_media/thumbs/…`
abstract final class ChurchChatMediaSendService {
  ChurchChatMediaSendService._();

  static const Duration kSendTimeout = Duration(seconds: 90);
  static const Duration kPrepareTimeout = Duration(seconds: 25);
  static const Duration kStubTimeout = Duration(seconds: 12);
  static const Duration kFinalizeTimeout = Duration(seconds: 20);

  static void _mapProgress(
    void Function(double progress)? onProgress,
    double start,
    double end,
    double t,
  ) {
    onProgress?.call((start + (end - start) * t).clamp(0.0, 1.0));
  }

  static Future<void> send({
    required String tenantId,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function()? onSuccess,
    void Function()? onReplyCleared,
  }) async {
    final kindBlocked =
        ChurchChatAttachmentUtils.blockReasonForChatKind(pending.kind);
    if (kindBlocked != null) {
      onError?.call(kindBlocked);
      throw StateError(kindBlocked);
    }

    final resolvedTenant =
        ChurchPublishContext.churchIdForPublish(tenantId.trim());

    if (!await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: resolvedTenant,
      threadId: threadId,
    )) {
      const msg = 'Envio bloqueado — desbloqueie o contacto.';
      onError?.call(msg);
      throw StateError(msg);
    }

    String? messageId;
    try {
      await sendInternal(
        resolvedTenant: resolvedTenant,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onReplyCleared: onReplyCleared,
        onMessageId: (id) => messageId = id,
      ).timeout(
        kSendTimeout,
        onTimeout: () => throw TimeoutException(
          'O envio demorou demais. Verifique a rede e toque em «Tentar de novo».',
          kSendTimeout,
        ),
      );
      onSuccess?.call();
    } catch (e) {
      if (messageId != null && messageId!.isNotEmpty) {
        unawaited(
          ChurchChatService.markMediaUploadFailed(
            tenantId: resolvedTenant,
            threadId: threadId,
            messageId: messageId!,
            errorMessage: e.toString(),
          ).catchError((_) {}),
        );
      }
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }
  }

  static Future<void> sendInternal({
    required String resolvedTenant,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function()? onReplyCleared,
    void Function(String messageId)? onMessageId,
  }) async {
    ChurchPublishFlowLog.chatStart();
    onProgress?.call(0.03);

    await ensureFirebaseReadyForChatSend();

    ChurchPublishFlowLog.uploadStart('chat_${pending.kind}_whatsapp');
    final begun = await ChurchChatService.beginMediaUploadMessage(
      tenantId: resolvedTenant,
      threadId: threadId,
      kind: pending.kind,
      fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
          ? (pending.fileName.isNotEmpty ? pending.fileName : 'file')
          : 'media.webp',
      replyTo: replyTo,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      albumGroupId: pending.albumGroupId,
      albumIndex: pending.albumIndex,
      albumCount: pending.albumCount,
    ).timeout(kStubTimeout);

    pending.firestoreMessageId = begun.messageId;
    pending.storagePath = begun.storagePath;
    onMessageId?.call(begun.messageId);
    onReplyCleared?.call();
    onProgress?.call(0.08);

    final storagePath = begun.storagePath;
    String? thumbStoragePath;
    final uploadPath = (localPath ?? pending.localPath)?.trim() ?? '';
    var uploadBytes = bytes;
    if ((uploadBytes == null || uploadBytes.isEmpty) &&
        pending.previewBytes != null &&
        pending.previewBytes!.isNotEmpty) {
      uploadBytes = pending.previewBytes;
    }

    if (pending.kind == 'image') {
      onProgress?.call(0.1);
      final prepared = await _prepareImageSafe(
        bytes: uploadBytes != null && uploadBytes.isNotEmpty
            ? Uint8List.fromList(uploadBytes)
            : pending.previewBytes,
        localPath: uploadPath.isNotEmpty && !kIsWeb ? uploadPath : null,
      );
      onProgress?.call(0.18);

      final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);

      await ChurchChatMediaStorage.putBytes(
        storagePath: storagePath,
        bytes: prepared.fullBytes,
        contentType: prepared.fullMime,
        onProgress: (t) => _mapProgress(onProgress, 0.18, 0.88, t),
      );

      if (prepared.thumbBytes != null && prepared.thumbBytes!.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatImageThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        try {
          await ChurchChatMediaStorage.putBytes(
            storagePath: thumbStoragePath,
            bytes: prepared.thumbBytes!,
            contentType: 'image/webp',
            onProgress: (t) => _mapProgress(onProgress, 0.88, 0.93, t),
          ).timeout(const Duration(seconds: 25));
        } catch (_) {
          thumbStoragePath = null;
        }
      }
    } else if (pending.kind == 'video' &&
        uploadPath.isNotEmpty &&
        !kIsWeb) {
      final prepared = await ChurchChatMediaPrepare.prepareVideo(
        uploadPath,
        onCompressProgress: (t) => _mapProgress(onProgress, 0.1, 0.35, t),
      ).timeout(kPrepareTimeout);
      final videoPath = prepared?.outputPath ?? uploadPath;
      pending.localPath = videoPath;
      final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);

      await ChurchChatMediaStorage.putFile(
        storagePath: storagePath,
        localPath: videoPath,
        contentType: pending.mime.isNotEmpty ? pending.mime : 'video/mp4',
        onProgress: (t) => _mapProgress(onProgress, 0.35, 0.88, t),
      );

      if (prepared?.thumbnailBytes != null &&
          prepared!.thumbnailBytes!.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatVideoThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        try {
          await ChurchChatMediaStorage.putBytes(
            storagePath: thumbStoragePath,
            bytes: prepared.thumbnailBytes!,
            contentType: 'image/webp',
            onProgress: (t) => _mapProgress(onProgress, 0.88, 0.93, t),
          ).timeout(const Duration(seconds: 25));
        } catch (_) {
          thumbStoragePath = null;
        }
      }
    } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
      await ChurchChatMediaStorage.putBytes(
        storagePath: storagePath,
        bytes: uploadBytes is Uint8List
            ? uploadBytes
            : Uint8List.fromList(uploadBytes),
        contentType: pending.mime,
        onProgress: (t) => _mapProgress(onProgress, 0.12, 0.88, t),
      );
    } else if (uploadPath.isNotEmpty) {
      await ChurchChatMediaStorage.putFile(
        storagePath: storagePath,
        localPath: uploadPath,
        contentType: pending.mime,
        onProgress: (t) => _mapProgress(onProgress, 0.12, 0.88, t),
      );
    } else {
      throw StateError('Sem dados para enviar.');
    }

    onProgress?.call(0.94);
    await ChurchChatService.completeMediaUploadMessageDirect(
      resolvedTenant: resolvedTenant,
      threadId: threadId,
      messageId: begun.messageId,
      storagePath: storagePath,
      fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
          ? pending.fileName
          : null,
      thumbStoragePath: thumbStoragePath,
      fileSize: _byteSize(pending, uploadBytes, uploadPath),
    ).timeout(kFinalizeTimeout);

    ChurchPublishFlowLog.chatFileUploaded();
    ChurchPublishFlowLog.chatFinalOk();
    onProgress?.call(1.0);
  }

  static Future<PreparedChatImage> _prepareImageSafe({
    Uint8List? bytes,
    String? localPath,
  }) async {
    try {
      return await ChurchChatMediaPrepare.prepareImage(
        bytes: bytes,
        localPath: localPath,
      ).timeout(kPrepareTimeout);
    } on TimeoutException {
      if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
        final raw = await SafeImageBytes.fromPath(
          localPath,
          maxEdge: ChurchChatMediaPrepare.imageMaxEdge,
          quality: ChurchChatMediaPrepare.imageQuality,
        ).timeout(const Duration(seconds: 20));
        return PreparedChatImage(
          fullBytes: raw,
          fullMime: 'image/jpeg',
          fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
          thumbBytes: null,
        );
      }
      if (bytes != null && bytes.isNotEmpty) {
        return PreparedChatImage(
          fullBytes: Uint8List.fromList(bytes),
          fullMime: 'image/jpeg',
          fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
          thumbBytes: null,
        );
      }
      rethrow;
    } catch (_) {
      if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
        final f = File(localPath);
        if (await f.exists()) {
          final raw = await f.readAsBytes();
          if (raw.isNotEmpty) {
            return PreparedChatImage(
              fullBytes: Uint8List.fromList(raw),
              fullMime: 'image/jpeg',
              fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
              thumbBytes: null,
            );
          }
        }
      }
      if (bytes != null && bytes.isNotEmpty) {
        return PreparedChatImage(
          fullBytes: Uint8List.fromList(bytes),
          fullMime: 'image/jpeg',
          fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
          thumbBytes: null,
        );
      }
      rethrow;
    }
  }

  static int? _byteSize(
    ChurchChatOutboundPending pending,
    List<int>? bytes,
    String localPath,
  ) {
    if (bytes != null && bytes.isNotEmpty) return bytes.length;
    final preview = pending.previewBytes;
    if (preview != null && preview.isNotEmpty) return preview.length;
    if (kIsWeb || localPath.isEmpty) return null;
    try {
      return File(localPath).lengthSync();
    } catch (_) {
      return null;
    }
  }
}
