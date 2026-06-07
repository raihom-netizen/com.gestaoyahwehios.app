import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';



import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;

import 'package:gestao_yahweh/services/church_chat_fs.dart'

    show churchChatReadFileBytes;

import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';

import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';

import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';

import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';

import 'package:gestao_yahweh/services/church_chat_service.dart';

import 'package:gestao_yahweh/services/church_chat_media_upload_coordinator.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';

import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_apps_diagnostic.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';



/// Chat Igreja estilo WhatsApp: stub Firestore → compress → Storage → `sent`.

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

    VoidCallback? onWaitingForNetwork,

    String? uploadDocId,

  }) async {

    try {
      logFirebaseAppsBeforeOperation('chat_media_flush', module: pending.kind);
      await ChurchChatMediaUploadCoordinator.run(
        () => runChatMediaUploadTask(
          () => _flushCore(
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
            onWaitingForNetwork: onWaitingForNetwork,
            uploadDocId: uploadDocId,
          ).timeout(
            _flushTimeoutFor(pending.kind),
            onTimeout: () => throw TimeoutException(
              'Envio demorou demais. Verifique a rede e tente de novo.',
            ),
          ),
          debugLabel: 'chat_media_flush',
        ),
      );

    } on TimeoutException catch (e) {

      await _deferForRetry(

        pending: pending,

        tenantId: tenantId,

        threadId: threadId,

        uploadDocId: uploadDocId,

        error: e,

        onWaitingForNetwork: onWaitingForNetwork,

        onFailed: onFailed,

      );

    } catch (e) {

      if (isRetryableUploadError(e)) {

        await _deferForRetry(

          pending: pending,

          tenantId: tenantId,

          threadId: threadId,

          uploadDocId: uploadDocId,

          error: e,

          onWaitingForNetwork: onWaitingForNetwork,

          onFailed: onFailed,

        );

      } else {

        await _handleFailure(

          error: e,

          pending: pending,

          tenantId: tenantId,

          threadId: threadId,

          uploadDocId: uploadDocId,

          onWaitingForNetwork: onWaitingForNetwork,

          onFailed: onFailed,

        );

        await ChurchChatMediaOutboxService.clearJob(

          tenantId: tenantId,

          threadId: threadId,

          localId: pending.localId,

          uploadDocId: uploadDocId,

        );

      }

    }

  }



  static Future<void> _abandonStub(

    ChurchChatOutboundPending pending,

    String tenantId,

    String threadId,

    String? uploadDocId,

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

    if (uploadDocId != null && uploadDocId.isNotEmpty) {

      await ChurchChatUploadsService.markFailed(

        tenantId: tenantId,

        uploadId: uploadDocId,

      );

    }

  }



  static Future<void> _deferForRetry({

    required ChurchChatOutboundPending pending,

    required String tenantId,

    required String threadId,

    String? uploadDocId,

    required Object error,

    VoidCallback? onWaitingForNetwork,

    required void Function(String errorMessage) onFailed,

  }) async {

    final mid = pending.firestoreMessageId;

    if (mid != null && mid.isNotEmpty) {

      await ChurchChatService.markMediaUploadQueued(

        tenantId: tenantId,

        threadId: threadId,

        messageId: mid,

      );

    }

    if (uploadDocId != null && uploadDocId.isNotEmpty) {

      await ChurchChatUploadsService.markWaitingNetwork(

        tenantId: tenantId,

        uploadId: uploadDocId,

      );

    }

    Uint8List? cached = pending.previewBytes;
    if (cached == null || cached.isEmpty) {
      final lp = pending.localPath?.trim() ?? '';
      if (lp.isNotEmpty && !kIsWeb) {
        final raw = await churchChatReadFileBytes(lp);
        if (raw != null && raw.isNotEmpty) {
          cached = raw is Uint8List ? raw : Uint8List.fromList(raw);
          pending.previewBytes = cached;
        }
      }
    }
    final pathOk = !kIsWeb &&
        (pending.localPath?.trim().isNotEmpty ?? false) &&
        File(pending.localPath!).existsSync();
    final hasData = cached != null && cached.isNotEmpty;
    if (!hasData && !pathOk) {
      await _abandonStub(pending, tenantId, threadId, uploadDocId);
      onFailed(
        'Não foi possível reenviar — o ficheiro já não está no aparelho. '
        'Envie de novo.',
      );
      return;
    }

    await ChurchChatMediaOutboxService.registerJob(
      tenantId: tenantId,
      threadId: threadId,
      localId: pending.localId,
      kind: pending.kind,
      fileName: pending.fileName,
      mime: pending.mime,
      firestoreMessageId: pending.firestoreMessageId,
      storagePath: pending.storagePath,
      localPath: pending.localPath,
      bytes: cached,
      uploadDocId: uploadDocId,
    );

    if (onWaitingForNetwork != null) {

      onWaitingForNetwork();

    } else {

      onFailed(formatUploadErrorForUser(error));

    }

  }



  static Future<void> _handleFailure({

    required Object error,

    required ChurchChatOutboundPending pending,

    required String tenantId,

    required String threadId,

    String? uploadDocId,

    VoidCallback? onWaitingForNetwork,

    required void Function(String errorMessage) onFailed,

  }) async {

    if (isRetryableUploadError(error)) {

      await _deferForRetry(

        pending: pending,

        tenantId: tenantId,

        threadId: threadId,

        uploadDocId: uploadDocId,

        error: error,

        onWaitingForNetwork: onWaitingForNetwork,

        onFailed: onFailed,

      );

      return;

    }

    await _abandonStub(pending, tenantId, threadId, uploadDocId);

    final sp = pending.storagePath?.trim() ?? '';
    if (sp.isNotEmpty) {
      unawaited(
        PendingUploadsFirestoreService.recordFailedBytesUpload(
          tenantId: tenantId,
          module: 'chat',
          storagePath: sp,
          error: error,
          localPath: pending.localPath,
          meta: {
            'threadId': threadId,
            'localId': pending.localId,
            'source': 'chat_upload_fatal',
          },
        ),
      );
    }

    onFailed(formatUploadErrorForUser(error));

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

    VoidCallback? onWaitingForNetwork,

    String? uploadDocId,

  }) async {

    if (kIsWeb) {
      unawaited(FirestoreWebGuard.prepareForChatWrite().catchError((_) {}));
    } else {
      await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
    }

    var messageId = pending.firestoreMessageId;

    var storagePath = pending.storagePath;

    var activeUploadId = uploadDocId ?? '';

    if ((bytes == null || bytes.isEmpty) &&
        pending.previewBytes != null &&
        pending.previewBytes!.isNotEmpty) {
      bytes = pending.previewBytes;
    }



    void reportProgress(double p) {
      final clamped = p.clamp(0.0, 1.0);
      onProgress(clamped);
      final mid = messageId;
      if (mid != null && mid.isNotEmpty) {
        unawaited(
          ChurchChatService.patchMediaUploadProgress(
            tenantId: tenantId,
            threadId: threadId,
            messageId: mid,
            progress: clamped,
            force: clamped <= 0.02 || clamped >= 0.99,
          ),
        );
      }

      if (activeUploadId.isNotEmpty) {

        unawaited(

          ChurchChatUploadsService.patchProgress(

            tenantId: tenantId,

            uploadId: activeUploadId,

            progress: p,

            status: ChurchChatUploadsService.statusUploading,

          ),

        );

      }

    }



    try {

      activeUploadId = await ChurchChatUploadsService.upsert(

        tenantId: tenantId,

        threadId: threadId,

        kind: pending.kind,

        localId: pending.localId,

        uploadId: activeUploadId.isEmpty ? null : activeUploadId,

        messageId: messageId,

        storagePath: storagePath,

        localPath: localPath ?? pending.localPath,

        fileName: pending.fileName,

        mime: pending.mime,

        progress: 0.02,

        status: ChurchChatUploadsService.statusUploading,

      );



      final midRestore = messageId;
      if (midRestore != null && midRestore.isNotEmpty) {
        await ChurchChatService.markMediaUploadActive(
          tenantId: tenantId,
          threadId: threadId,
          messageId: midRestore,
        );
      }

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

        ChurchPublishFlowLog.chatStart();
        ChurchPublishFlowLog.uploadStart('chat_${pending.kind}');
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

        unawaited(

          ChurchChatMediaOutboxService.updateStub(

            tenantId: tenantId,

            threadId: threadId,

            localId: pending.localId,

            firestoreMessageId: messageId,

            storagePath: storagePath,

            uploadDocId: activeUploadId,

          ),

        );

      }



      reportProgress(0.08);

      unawaited(
        FastMediaPublishBootstrap.warmForChatSend()
            .timeout(const Duration(seconds: 4))
            .catchError((_) {}),
      );



      if (pending.kind == 'image') {

        final mid = messageId;

        if (mid == null || mid.isEmpty) {

          throw StateError('Stub Firestore ausente para foto.');

        }

        final up = await _uploadChatImagePrepared(

          pending: pending,

          tenantId: tenantId,

          threadId: threadId,

          storagePath: storagePath!,

          uploadPath: localPath,

          uploadBytes: bytes,

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

          uploadDocId: activeUploadId,

          reportProgress: reportProgress,

          onSuccess: onSuccess,

        );

        return;

      }



      var uploadPath = localPath;

      List<int>? uploadBytes = bytes;

      String? thumbUrl;



      if (pending.kind == 'video' &&

          uploadPath != null &&

          uploadPath.isNotEmpty &&

          !kIsWeb) {

        final prepared = await ChurchChatMediaPrepare.prepareVideo(

          uploadPath,

          onCompressProgress: (t) =>

              _mapProgress(reportProgress, 0.08, 0.40, t),

        );

        if (prepared != null) {

          uploadPath = prepared.outputPath;

          pending.localPath = uploadPath;

          final ts = ChurchChatService.timestampMsFromChatMediaPath(
            storagePath ?? '',
          );

          Future<String?>? thumbFuture;
          if (prepared.thumbnailBytes != null &&
              prepared.thumbnailBytes!.isNotEmpty) {
            final thumbPath = ChurchChatService.buildChatVideoThumbStoragePath(
              tenantId: tenantId,
              threadId: threadId,
              timestampMs: ts,
            );
            thumbFuture = ChurchChatService.uploadChatBytes(
              tenantId: tenantId,
              threadId: threadId,
              bytes: prepared.thumbnailBytes!,
              fileName: 'thumb.webp',
              contentType: 'image/webp',
              storagePathOverride: thumbPath,
              skipClientPrepare: true,
              onProgress: (t) => _mapProgress(reportProgress, 0.40, 0.48, t),
            ).then((up) => up.url);
          }

          void uploadProgress(double t) =>
              _mapProgress(reportProgress, 0.40, 0.96, t);

          final mainFuture = ChurchChatService.uploadChatFile(
            tenantId: tenantId,
            threadId: threadId,
            localPath: uploadPath,
            fileName: pending.fileName,
            contentType: pending.mime,
            storagePathOverride: storagePath,
            skipRecompress: true,
            onProgress: uploadProgress,
          );

          if (thumbFuture != null) {
            final pair = await Future.wait<Object?>([thumbFuture, mainFuture]);
            thumbUrl = pair[0] as String?;
            final up = pair[1] as ({String url, String path});
            await _finalizeChatMediaUpload(
              tenantId: tenantId,
              threadId: threadId,
              messageId: messageId!,
              pending: pending,
              downloadUrl: up.url,
              storagePath: up.path,
              thumbUrl: thumbUrl,
              uploadDocId: activeUploadId,
              reportProgress: reportProgress,
              onSuccess: onSuccess,
            );
            return;
          }
        }

      }

      final ({String url, String path}) up;

      void uploadProgress(double t) =>
          _mapProgress(reportProgress, 0.48, 0.96, t);



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

        thumbUrl: thumbUrl,

        uploadDocId: activeUploadId,

        reportProgress: reportProgress,

        onSuccess: onSuccess,

      );

    } on FirebaseException catch (e) {

      await _handleFailure(

        error: e,

        pending: pending,

        tenantId: tenantId,

        threadId: threadId,

        uploadDocId: activeUploadId,

        onWaitingForNetwork: onWaitingForNetwork,

        onFailed: onFailed,

      );

    } catch (e) {

      await _handleFailure(

        error: e,

        pending: pending,

        tenantId: tenantId,

        threadId: threadId,

        uploadDocId: activeUploadId,

        onWaitingForNetwork: onWaitingForNetwork,

        onFailed: onFailed,

      );

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

    int? fileSize,

    String? uploadDocId,

    required void Function(double progress) reportProgress,

    required VoidCallback onSuccess,

  }) async {

    reportProgress(0.94);

    final resolvedSize = fileSize ?? _byteSizeForPending(pending);

    await ChurchChatService.completeMediaUploadMessageWithRetry(

      tenantId: tenantId,

      threadId: threadId,

      messageId: messageId,

      downloadUrl: downloadUrl,

      storagePath: storagePath,

      fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
          ? pending.fileName
          : null,

      thumbUrl: thumbUrl,

      fileSize: resolvedSize,

    );
    ChurchPublishFlowLog.chatFileUploaded();
    ChurchPublishFlowLog.chatMessageUpdated();
    ChurchPublishFlowLog.chatFinalOk();

    if (uploadDocId != null && uploadDocId.isNotEmpty) {

      await ChurchChatUploadsService.markDone(

        tenantId: tenantId,

        uploadId: uploadDocId,

      );

    }

    reportProgress(1.0);

    onSuccess();

  }

  static int? _byteSizeForPending(ChurchChatOutboundPending pending) {
    final preview = pending.previewBytes;
    if (preview != null && preview.isNotEmpty) return preview.length;
    if (kIsWeb) return null;
    final path = pending.localPath?.trim() ?? '';
    if (path.isEmpty) return null;
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }



  static Future<({String url, String path, String? thumbUrl})>

      _uploadChatImagePrepared({

    required ChurchChatOutboundPending pending,

    required String tenantId,

    required String threadId,

    required String storagePath,

    required String? uploadPath,

    required List<int>? uploadBytes,

    required void Function(double progress) reportProgress,

  }) async {

    void uploadProgress(double t) =>

        _mapProgress(reportProgress, 0.12, 0.88, t);



    reportProgress(0.10);

    final prepared = await ChurchChatMediaPrepare.prepareImage(

      bytes: uploadBytes != null && uploadBytes.isNotEmpty

          ? Uint8List.fromList(uploadBytes)

          : pending.previewBytes,

      localPath: uploadPath,

    );



    final ts = ChurchChatService.timestampMsFromChatMediaPath(storagePath);

    Future<String?>? thumbFuture;
    if (prepared.thumbBytes != null && prepared.thumbBytes!.isNotEmpty) {
      final thumbPath = ChurchChatService.buildChatImageThumbStoragePath(
        tenantId: tenantId,
        threadId: threadId,
        timestampMs: ts,
      );
      thumbFuture = ChurchChatService.uploadChatBytes(
        tenantId: tenantId,
        threadId: threadId,
        bytes: prepared.thumbBytes!,
        fileName: 'thumb.webp',
        contentType: 'image/webp',
        storagePathOverride: thumbPath,
        skipClientPrepare: true,
        onProgress: (t) => _mapProgress(reportProgress, 0.12, 0.22, t),
      ).then((up) => up.url);
    }

    final fullFuture = ChurchChatService.uploadChatBytes(
      tenantId: tenantId,
      threadId: threadId,
      bytes: prepared.fullBytes,
      fileName: prepared.fullFileName,
      contentType: prepared.fullMime,
      storagePathOverride: storagePath,
      skipClientPrepare: true,
      onProgress: uploadProgress,
    );

    String? thumbUrl;
    late final ({String url, String path}) up;
    if (thumbFuture != null) {
      final pair = await Future.wait<Object?>([thumbFuture, fullFuture]);
      thumbUrl = pair[0] as String?;
      up = pair[1] as ({String url, String path});
    } else {
      up = await fullFuture;
    }

    return (url: up.url, path: up.path, thumbUrl: thumbUrl);

  }

}

