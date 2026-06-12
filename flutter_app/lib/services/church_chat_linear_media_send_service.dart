import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';
import 'package:gestao_yahweh/services/church_chat_media_storage.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Chat mídia — WhatsApp: stub Firestore (path) → upload → `sent` (só links).
abstract final class ChurchChatLinearMediaSendService {
  ChurchChatLinearMediaSendService._();

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

    try {
      await _sendWhatsappPipeline(
        resolvedTenant: resolvedTenant,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onReplyCleared: onReplyCleared,
      );
      onSuccess?.call();
    } catch (e) {
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }
  }

  /// Stub imediato → upload (miniatura + ficheiro) → finalize só com paths.
  static Future<void> _sendWhatsappPipeline({
    required String resolvedTenant,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function()? onReplyCleared,
  }) async {
    ChurchPublishFlowLog.chatStart();
    ChurchPublishFlowLog.uploadStart('chat_${pending.kind}_whatsapp');
    onProgress?.call(0.03);

    final begun = await ChurchChatService.beginMediaUploadMessage(
      tenantId: resolvedTenant,
      threadId: threadId,
      kind: pending.kind,
      fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
          ? (pending.fileName ?? 'file')
          : 'media.webp',
      replyTo: replyTo,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      albumGroupId: pending.albumGroupId,
      albumIndex: pending.albumIndex,
      albumCount: pending.albumCount,
    ).timeout(const Duration(seconds: 12));

    pending.firestoreMessageId = begun.messageId;
    pending.storagePath = begun.storagePath;
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
      final prepared = await ChurchChatMediaPrepare.prepareImage(
        bytes: uploadBytes != null && uploadBytes.isNotEmpty
            ? Uint8List.fromList(uploadBytes)
            : pending.previewBytes,
        localPath: uploadPath.isNotEmpty && !kIsWeb ? uploadPath : null,
      );
      onProgress?.call(0.16);
      final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);

      Future<String?>? thumbFuture;
      if (prepared.thumbBytes != null && prepared.thumbBytes!.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatImageThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        thumbFuture = ChurchChatMediaStorage.putBytes(
          storagePath: thumbStoragePath,
          bytes: prepared.thumbBytes!,
          contentType: 'image/webp',
          onProgress: (t) => _mapProgress(onProgress, 0.16, 0.42, t),
        ).then((_) => thumbStoragePath);
      }

      final mainFuture = ChurchChatMediaStorage.putBytes(
        storagePath: storagePath,
        bytes: prepared.fullBytes,
        contentType: prepared.fullMime,
        onProgress: (t) => _mapProgress(onProgress, 0.42, 0.9, t),
      );

      if (thumbFuture != null) {
        await Future.wait<Object?>([thumbFuture, mainFuture]);
      } else {
        await mainFuture;
      }
    } else if (pending.kind == 'video' &&
        uploadPath.isNotEmpty &&
        !kIsWeb) {
      final prepared = await ChurchChatMediaPrepare.prepareVideo(
        uploadPath,
        onCompressProgress: (t) => _mapProgress(onProgress, 0.1, 0.35, t),
      );
      final videoPath = prepared?.outputPath ?? uploadPath;
      pending.localPath = videoPath;
      final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);
      Future<String?>? thumbFuture;
      if (prepared?.thumbnailBytes != null &&
          prepared!.thumbnailBytes!.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatVideoThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        thumbFuture = ChurchChatMediaStorage.putBytes(
          storagePath: thumbStoragePath,
          bytes: prepared.thumbnailBytes!,
          contentType: 'image/webp',
          onProgress: (t) => _mapProgress(onProgress, 0.35, 0.45, t),
        ).then((_) => thumbStoragePath);
      }
      final mainFuture = ChurchChatMediaStorage.putFile(
        storagePath: storagePath,
        localPath: videoPath,
        contentType: pending.mime ?? 'video/mp4',
        onProgress: (t) => _mapProgress(onProgress, 0.45, 0.9, t),
      );
      if (thumbFuture != null) {
        await Future.wait<Object?>([thumbFuture, mainFuture]);
      } else {
        await mainFuture;
      }
    } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
      await ChurchChatMediaStorage.putBytes(
        storagePath: storagePath,
        bytes: uploadBytes is Uint8List
            ? uploadBytes
            : Uint8List.fromList(uploadBytes),
        contentType: pending.mime,
        onProgress: (t) => _mapProgress(onProgress, 0.12, 0.9, t),
      );
    } else if (uploadPath.isNotEmpty) {
      await ChurchChatMediaStorage.putFile(
        storagePath: storagePath,
        localPath: uploadPath,
        contentType: pending.mime,
        onProgress: (t) => _mapProgress(onProgress, 0.12, 0.9, t),
      );
    } else {
      throw StateError('Sem dados para enviar.');
    }

    onProgress?.call(0.94);
    await ChurchChatService.completeMediaUploadMessageWithRetry(
      tenantId: resolvedTenant,
      threadId: threadId,
      messageId: begun.messageId,
      storagePath: storagePath,
      fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
          ? pending.fileName
          : null,
      thumbStoragePath: thumbStoragePath,
      fileSize: _byteSize(pending, uploadBytes, uploadPath),
      skipStorageVerify: true,
    );
    ChurchPublishFlowLog.chatFileUploaded();
    ChurchPublishFlowLog.chatFinalOk();
    onProgress?.call(1.0);
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
