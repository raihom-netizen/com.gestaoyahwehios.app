import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/media_optimization_profile.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_optimized_payload_cache.dart';
import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';
import 'package:gestao_yahweh/services/church_chat_media_storage.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Chat mídia estilo WhatsApp — Ecofire: Firebase OK → Storage → Firestore **uma vez** (`sent`).
///
/// Sem stub `uploading` no Firestore (evita spinner infinito na bolha).
/// Path: `igrejas/{churchId}/chat_media/…`
abstract final class ChurchChatMediaSendService {
  ChurchChatMediaSendService._();

  static const Duration kSendTimeout = Duration(seconds: 90);
  static const Duration kPrepareTimeout = Duration(seconds: 25);

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
      await ensureFirebaseReadyForChatSend();
    } catch (e) {
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }

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
      ).timeout(
        kSendTimeout,
        onTimeout: () => throw TimeoutException(
          'O envio demorou demais. Verifique a rede e toque em «Tentar de novo».',
          kSendTimeout,
        ),
      );
      onSuccess?.call();
    } catch (e) {
      if (EcoFireResilientPublish.shouldQueueSilently(e)) {
        try {
          await EcoFireResilientPublish.queueChatMedia(
            tenantId: resolvedTenant,
            threadId: threadId,
            pending: pending,
            bytes: bytes,
            localPath: localPath,
          );
          pending.offlineQueued = true;
          EcoFireResilientPublish.scheduleSync(reason: 'chat_media_queued');
          onProgress?.call(1.0);
          onSuccess?.call();
          return;
        } catch (_) {}
      }
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }
  }

  /// Storage concluído → [writeMediaMessageFirestoreOnce] (sem doc fantasma).
  static Future<void> sendInternal({
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
    onProgress?.call(0.04);

    unawaited(
      EcoFireResilientPublish.prepareForPublish(logLabel: 'chat_media_send')
          .timeout(const Duration(seconds: 4))
          .catchError((_) {}),
    );
    onProgress?.call(0.08);

    final displayName = ChurchChatMessageFields.isDocumentType(pending.kind)
        ? (pending.fileName.isNotEmpty ? pending.fileName : 'file')
        : 'media.webp';

    final storagePath = ChurchChatService.buildChatMediaStoragePath(
      tenantId: resolvedTenant,
      threadId: threadId,
      kind: pending.kind,
      fileName: displayName,
    );
    pending.storagePath = storagePath;
    final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);

    final uploadPath = (localPath ?? pending.localPath)?.trim() ?? '';
    final uploadBytes = bytes;

    String? thumbStoragePath;
    int? fileSize;

    if (pending.kind == 'image') {
      onProgress?.call(0.12);
      final prepared = await _prepareImageSafe(
        pending: pending,
        bytes: uploadBytes != null && uploadBytes.isNotEmpty
            ? Uint8List.fromList(uploadBytes)
            : null,
        localPath: uploadPath.isNotEmpty && !kIsWeb ? uploadPath : null,
      );
      fileSize = prepared.fullBytes.length;
      onProgress?.call(0.2);

      await UnifiedUploadService.uploadImage(
        storagePath: storagePath,
        bytes: prepared.fullBytes,
        contentType: prepared.fullMime,
        module: YahwehUploadModule.chat,
        skipClientPrepare: true,
        chatJpegFast: true,
        onProgress: (t) => _mapProgress(onProgress, 0.2, 0.82, t),
      );

      if (prepared.thumbBytes != null && prepared.thumbBytes!.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatImageThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        try {
          await UnifiedUploadService.uploadImage(
            storagePath: thumbStoragePath,
            bytes: prepared.thumbBytes!,
            contentType: 'image/webp',
            module: YahwehUploadModule.chat,
            skipClientPrepare: true,
            chatJpegFast: true,
            onProgress: (t) => _mapProgress(onProgress, 0.82, 0.88, t),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {
          thumbStoragePath = null;
        }
      }
    } else if (pending.kind == 'video') {
      final mime = pending.mime.isNotEmpty ? pending.mime : 'video/mp4';
      PreparedChatVideo? preparedVideo;
      if (!kIsWeb && uploadPath.isNotEmpty) {
        preparedVideo = await ChurchChatMediaPrepare.prepareVideo(
          uploadPath,
          onCompressProgress: (t) => _mapProgress(onProgress, 0.12, 0.3, t),
        );
      }

      final videoLocalPath = preparedVideo?.outputPath ?? uploadPath;
      if (!kIsWeb &&
          (preparedVideo?.thumbnailBytes != null) &&
          preparedVideo!.thumbnailBytes!.isNotEmpty &&
          (pending.previewBytes == null || pending.previewBytes!.isEmpty)) {
        // Preview otimista da bolha local para vídeo (estilo WhatsApp).
        pending.previewBytes = preparedVideo.thumbnailBytes;
      }
      fileSize = preparedVideo?.byteLength;

      if (uploadBytes != null && uploadBytes.isNotEmpty && videoLocalPath.isEmpty) {
        final u8 = uploadBytes is Uint8List
            ? uploadBytes
            : Uint8List.fromList(uploadBytes);
        fileSize = u8.length;
        await ChurchChatMediaStorage.putBytesFast(
          storagePath: storagePath,
          bytes: u8,
          contentType: mime,
          onProgress: (t) => _mapProgress(onProgress, 0.3, 0.85, t),
        );
      } else if (videoLocalPath.isNotEmpty) {
        await ChurchChatMediaStorage.putFile(
          storagePath: storagePath,
          localPath: videoLocalPath,
          contentType: mime,
          onProgress: (t) => _mapProgress(onProgress, 0.3, 0.85, t),
        );
        if (fileSize == null) {
          try {
            fileSize = await File(videoLocalPath).length();
          } catch (_) {}
        }
      } else {
        throw StateError('Sem vídeo para enviar.');
      }

      final thumbBytes = preparedVideo?.thumbnailBytes;
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        thumbStoragePath = ChurchChatService.buildChatVideoThumbStoragePath(
          tenantId: resolvedTenant,
          threadId: threadId,
          timestampMs: ts,
        );
        try {
          await ChurchChatMediaStorage.putBytesFast(
            storagePath: thumbStoragePath,
            bytes: thumbBytes,
            contentType: 'image/jpeg',
            onProgress: (t) => _mapProgress(onProgress, 0.85, 0.9, t),
          ).timeout(const Duration(seconds: 15));
        } catch (_) {
          thumbStoragePath = null;
        }
      }
    } else if (pending.kind == 'audio') {
      final mime = pending.mime.isNotEmpty ? pending.mime : 'audio/mp4';
      if (uploadBytes != null && uploadBytes.isNotEmpty) {
        final u8 = uploadBytes is Uint8List
            ? uploadBytes
            : Uint8List.fromList(uploadBytes);
        fileSize = u8.length;
        await UnifiedUploadService.uploadChatMediaBytes(
          storagePath: storagePath,
          bytes: u8,
          contentType: mime,
          onProgress: (t) => _mapProgress(onProgress, 0.15, 0.85, t),
        );
      } else if (uploadPath.isNotEmpty) {
        await UnifiedUploadService.uploadFile(
          storagePath: storagePath,
          localPath: uploadPath,
          contentType: mime,
          module: YahwehUploadModule.chat,
          onProgress: (t) => _mapProgress(onProgress, 0.15, 0.85, t),
        );
        try {
          fileSize = await File(uploadPath).length();
        } catch (_) {}
      } else {
        throw StateError('Sem áudio para enviar.');
      }
    } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
      final u8 = uploadBytes is Uint8List
          ? uploadBytes
          : Uint8List.fromList(uploadBytes);
      fileSize = u8.length;
      await ChurchChatMediaStorage.putBytesFast(
        storagePath: storagePath,
        bytes: u8,
        contentType:
            pending.mime.isNotEmpty ? pending.mime : 'application/octet-stream',
        onProgress: (t) => _mapProgress(onProgress, 0.15, 0.85, t),
      );
    } else if (uploadPath.isNotEmpty) {
      await ChurchChatMediaStorage.putFile(
        storagePath: storagePath,
        localPath: uploadPath,
        contentType: pending.mime,
        onProgress: (t) => _mapProgress(onProgress, 0.15, 0.85, t),
      );
      try {
        fileSize = await File(uploadPath).length();
      } catch (_) {}
    } else {
      throw StateError('Sem dados para enviar.');
    }

    onProgress?.call(0.9);
    ChurchPublishFlowLog.uploadOk('chat_${pending.kind}');

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
    }
    onProgress?.call(0.92);

    final written = await _writeFirestoreAfterUpload(
      resolvedTenant: resolvedTenant,
      threadId: threadId,
      pending: pending,
      storagePath: storagePath,
      thumbStoragePath: thumbStoragePath,
      fileSize: fileSize,
      replyTo: replyTo,
    );

    if (!written.allowed || written.messageId.isEmpty) {
      throw StateError('Não foi possível gravar a mensagem no chat.');
    }

    onProgress?.call(0.98);
    pending.firestoreMessageId = written.messageId;
    onReplyCleared?.call();
    onProgress?.call(1.0);
    ChurchPublishFlowLog.chatFileUploaded();
    ChurchPublishFlowLog.chatFinalOk();
  }

  static Future<({String messageId, bool allowed})> _writeFirestoreAfterUpload({
    required String resolvedTenant,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required String storagePath,
    String? thumbStoragePath,
    int? fileSize,
    Map<String, dynamic>? replyTo,
  }) async {
    Future<({String messageId, bool allowed})> writeOnce() =>
        ChurchChatService.writeMediaMessageFirestoreOnce(
          tenantId: resolvedTenant,
          threadId: threadId,
          kind: pending.kind,
          storagePath: storagePath,
          thumbStoragePath: thumbStoragePath,
          fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
              ? pending.fileName
              : null,
          fileSize: fileSize,
          voiceDurationMs: pending.voiceDurationMs,
          replyTo: replyTo,
          senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
          albumGroupId: pending.albumGroupId,
          albumIndex: pending.albumIndex,
          albumCount: pending.albumCount,
          skipStorageVerify: true,
        );

    Object? last;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        if (kIsWeb) {
          return await FirestoreWebGuard.runWithWebRecovery(
            writeOnce,
            maxAttempts: 2,
          );
        }
        return await writeOnce();
      } catch (e) {
        last = e;
        if (attempt < 4) {
          await Future<void>.delayed(Duration(milliseconds: 280 * attempt));
        }
      }
    }
    throw last ?? StateError('Não foi possível gravar a mensagem no chat.');
  }

  static Future<PreparedChatImage> _prepareImageSafe({
    ChurchChatOutboundPending? pending,
    Uint8List? bytes,
    String? localPath,
  }) async {
    final cached = pending != null
        ? ChurchChatOptimizedPayloadCache.peek(pending.localId)
        : null;
    if (cached != null) {
      return PreparedChatImage(
        fullBytes: cached.fullBytes,
        fullMime: cached.fullMime,
        fullFileName: cached.fullFileName,
        thumbBytes: cached.thumbBytes,
      );
    }
    try {
      return await ChurchChatMediaPrepare.prepareImage(
        bytes: bytes,
        localPath: localPath,
      ).timeout(kPrepareTimeout);
    } on TimeoutException {
      if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
        final raw = await SafeImageBytes.fromPath(
          localPath,
          maxEdge: MediaOptimizationLimits.chatMaxEdge,
          quality: MediaOptimizationLimits.chatQuality,
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
}
