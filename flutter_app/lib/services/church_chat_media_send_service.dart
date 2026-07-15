import 'dart:async' show TimeoutException, unawaited;
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/media_optimization_profile.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_optimized_payload_cache.dart';
import 'package:gestao_yahweh/services/church_chat_media_prepare.dart';
import 'package:gestao_yahweh/services/church_chat_media_storage.dart';
import 'package:gestao_yahweh/services/church_chat_media_upload_coordinator.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Chat mídia estilo WhatsApp — Ecofire: Firebase OK → Storage → Firestore **uma vez** (`sent`).
///
/// Sem stub `uploading` no Firestore (evita spinner infinito na bolha).
/// Path: `igrejas/{churchId}/chat_media/…`
abstract final class ChurchChatMediaSendService {
  ChurchChatMediaSendService._();

  static Future<Uint8List> _readLocalPathBytes(String path) async {
    final p = path.trim();
    if (p.isEmpty) return Uint8List(0);
    if (kIsWeb) {
      final raw = await XFile(p).readAsBytes();
      return raw is Uint8List ? raw : Uint8List.fromList(raw);
    }
    return Uint8List.fromList(await File(p).readAsBytes());
  }

  static const Duration kPrepareTimeout = Duration(seconds: 20);
  static const Duration kStorageImageTimeout = Duration(minutes: 3);
  static const Duration kStorageThumbTimeout = Duration(seconds: 30);
  static const Duration kStorageVideoTimeout = Duration(minutes: 3);
  static const Duration kStorageAudioTimeout = Duration(minutes: 3);
  static const Duration kStorageDocumentTimeout = Duration(minutes: 3);

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

    // Offline real → fila imediata (Telegram), sem esperar ensureReady.
    if (!AppConnectivityService.instance.isOnline) {
      await EcoFireResilientPublish.queueChatMedia(
        tenantId: resolvedTenant,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
      );
      pending.offlineQueued = true;
      EcoFireResilientPublish.scheduleSync(reason: 'chat_media_offline');
      onProgress?.call(1.0);
      onSuccess?.call();
      return;
    }

    try {
      // Telegram: gate curto — se Firebase atraso, vai para a fila (bolha fica).
      try {
        await DirectStorageUrlPublish.ensureReady(requireAuth: true)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        if (e is TimeoutException ||
            isFirebaseNoAppError(e) ||
            EcoFireResilientPublish.shouldQueueSilently(e) ||
            EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
          try {
            await EcoFireDirectFirebase.ensureDefaultApp();
            await DirectStorageUrlPublish.ensureReady(requireAuth: true)
                .timeout(const Duration(seconds: 2));
          } catch (e2) {
            if (e2 is TimeoutException ||
                EcoFireResilientPublish.shouldQueueFeedPublish(e2) ||
                EcoFireResilientPublish.shouldQueueSilently(e2)) {
              await EcoFireResilientPublish.queueChatMedia(
                tenantId: resolvedTenant,
                threadId: threadId,
                pending: pending,
                bytes: bytes,
                localPath: localPath,
              );
              pending.offlineQueued = true;
              EcoFireResilientPublish.scheduleSync(reason: 'chat_media_gate_queue');
              onProgress?.call(1.0);
              onSuccess?.call();
              return;
            }
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      await ChurchChatMediaUploadCoordinator.run(() => sendInternal(
        resolvedTenant: resolvedTenant,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onReplyCleared: onReplyCleared,
      ));
      onSuccess?.call();
    } catch (e) {
      // Fila silenciosa: só offline real ou erro que [shouldQueueSilently] aceita.
      final queueSilently = EcoFireResilientPublish.shouldQueueSilently(e) ||
          EcoFireResilientPublish.shouldQueueFeedPublish(e) ||
          (!AppConnectivityService.instance.isOnline);
      if (queueSilently) {
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
      final uploadId = pending.firestoreMessageId?.trim() ?? '';
      if (uploadId.isNotEmpty) {
        unawaited(
          ChurchChatUploadsService.markFailed(
            tenantId: resolvedTenant,
            uploadId: uploadId,
            error: e.toString(),
          ),
        );
      }
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
    // Gate já feito em [send] — não repetir (atrasava «A confirmar envio»).

    final displayName = ChurchChatMessageFields.isDocumentType(pending.kind)
        ? (pending.fileName.isNotEmpty ? pending.fileName : 'file')
        : 'media.webp';

    final messageId = (pending.firestoreMessageId ?? '').trim().isNotEmpty
        ? pending.firestoreMessageId!.trim()
        : ChurchChatService.allocateMediaMessageId(
            tenantId: resolvedTenant,
            threadId: threadId,
          );
    pending.firestoreMessageId = messageId;

    final storagePath = (pending.storagePath ?? '').trim().isNotEmpty
        ? pending.storagePath!.trim()
        : ChurchChatService.buildChatMediaStoragePathForMessage(
            tenantId: resolvedTenant,
            messageId: messageId,
            kind: pending.kind,
            fileName: displayName,
          );
    pending.storagePath = storagePath;

    final uploadPath = (localPath ?? pending.localPath)?.trim() ?? '';
    final uploadBytes = bytes;

    unawaited(
      ChurchChatUploadsService.upsert(
        tenantId: resolvedTenant,
        threadId: threadId,
        kind: pending.kind,
        localId: pending.localId,
        uploadId: messageId,
        messageId: messageId,
        storagePath: storagePath,
        localPath: uploadPath.isNotEmpty ? uploadPath : null,
        fileName: pending.fileName,
        mime: pending.mime,
        progress: 0.05,
        status: ChurchChatUploadsService.statusUploading,
      ),
    );
    await ChurchChatMediaOutboxService.registerJob(
      tenantId: resolvedTenant,
      threadId: threadId,
      localId: pending.localId,
      kind: pending.kind,
      fileName: pending.fileName,
      mime: pending.mime,
      firestoreMessageId: messageId,
      storagePath: storagePath,
      localPath: uploadPath.isNotEmpty ? uploadPath : null,
      bytes: uploadBytes != null && uploadBytes.isNotEmpty
          ? (uploadBytes is Uint8List
              ? uploadBytes
              : Uint8List.fromList(uploadBytes))
          : null,
      uploadDocId: messageId,
    );

    void reportProgress(double t) {
      onProgress?.call(t);
      unawaited(
        ChurchChatUploadsService.patchProgress(
          tenantId: resolvedTenant,
          uploadId: messageId,
          progress: t,
          status: ChurchChatUploadsService.statusUploading,
        ),
      );
    }

    reportProgress(0.08);

    String? thumbStoragePath;
    String? mediaUrl;
    String? thumbUrl;
    int? fileSize;

    if (pending.kind == 'image') {
        reportProgress(0.12);
        final prepared = await _prepareImageSafe(
          pending: pending,
          bytes: uploadBytes != null && uploadBytes.isNotEmpty
              ? Uint8List.fromList(uploadBytes)
              : null,
          localPath: uploadPath.isNotEmpty ? uploadPath : null,
        );
        fileSize = prepared.fullBytes.length;
        reportProgress(0.2);

        mediaUrl = await ChurchChatMediaStorage.putBytesFast(
          storagePath: storagePath,
          bytes: prepared.fullBytes,
          contentType: prepared.fullMime,
          onProgress: (t) => _mapProgress(reportProgress, 0.2, 0.78, t),
        ).timeout(
          kStorageImageTimeout,
          onTimeout: () => throw TimeoutException(
            'O envio demorou demais. Verifique a rede e toque em «Tentar de novo».',
            kStorageImageTimeout,
          ),
        );
        reportProgress(0.82);

        // Thumb truly non-blocking — fire-and-forget; message goes immediately.
        if (prepared.thumbBytes != null && prepared.thumbBytes!.isNotEmpty) {
          thumbStoragePath =
              ChurchChatService.buildChatImageThumbStoragePathForMessage(
            tenantId: resolvedTenant,
            messageId: messageId,
          );
          unawaited(
            ChurchChatMediaStorage.putBytesFast(
              storagePath: thumbStoragePath,
              bytes: prepared.thumbBytes!,
              contentType: 'image/webp',
            ).timeout(kStorageThumbTimeout).then(
              (url) => thumbUrl = url,
              onError: (_) {
                thumbStoragePath = null;
                thumbUrl = null;
              },
            ),
          );
        }
        reportProgress(0.88);
      } else if (pending.kind == 'video') {
        final mime = pending.mime.isNotEmpty ? pending.mime : 'video/mp4';
        PreparedChatVideo? preparedVideo;
        if (!kIsWeb && uploadPath.isNotEmpty) {
          preparedVideo = await ChurchChatMediaPrepare.prepareVideo(
            uploadPath,
            onCompressProgress: (t) => _mapProgress(reportProgress, 0.12, 0.3, t),
          );
        }

        final videoLocalPath = preparedVideo?.outputPath ?? uploadPath;
        if (!kIsWeb &&
            (preparedVideo?.thumbnailBytes != null) &&
            preparedVideo!.thumbnailBytes!.isNotEmpty &&
            (pending.previewBytes == null || pending.previewBytes!.isEmpty)) {
          pending.previewBytes = preparedVideo.thumbnailBytes;
        }
        fileSize = preparedVideo?.byteLength;

        if (uploadBytes != null &&
            uploadBytes.isNotEmpty &&
            videoLocalPath.isEmpty) {
          final u8 = uploadBytes is Uint8List
              ? uploadBytes
              : Uint8List.fromList(uploadBytes);
          fileSize = u8.length;
          mediaUrl = await ChurchChatMediaStorage.putBytesFast(
            storagePath: storagePath,
            bytes: u8,
            contentType: mime,
            onProgress: (t) => _mapProgress(reportProgress, 0.3, 0.85, t),
          ).timeout(kStorageVideoTimeout);
        } else if (videoLocalPath.isNotEmpty) {
          final videoBytes = await _readLocalPathBytes(videoLocalPath);
          if (videoBytes.isEmpty) {
            throw StateError('Vídeo vazio — selecione outro ficheiro.');
          }
          fileSize = videoBytes.length;
          mediaUrl = await ChurchChatMediaStorage.putBytesFast(
            storagePath: storagePath,
            bytes: videoBytes,
            contentType: mime,
            onProgress: (t) => _mapProgress(reportProgress, 0.3, 0.85, t),
          ).timeout(kStorageVideoTimeout);
        } else {
          throw StateError('Sem vídeo para enviar.');
        }

        final thumbBytes = preparedVideo?.thumbnailBytes;
        if (thumbBytes != null && thumbBytes.isNotEmpty) {
          thumbStoragePath =
              ChurchChatService.buildChatVideoThumbStoragePathForMessage(
            tenantId: resolvedTenant,
            messageId: messageId,
          );
          unawaited(
            ChurchChatMediaStorage.putBytesFast(
              storagePath: thumbStoragePath,
              bytes: thumbBytes,
              contentType: 'image/jpeg',
            ).timeout(kStorageThumbTimeout).then(
              (url) => thumbUrl = url,
              onError: (_) {
                thumbStoragePath = null;
                thumbUrl = null;
              },
            ),
          );
        }
      } else if (pending.kind == 'audio') {
        final mime = pending.mime.isNotEmpty ? pending.mime : 'audio/mp4';
        if (uploadBytes != null && uploadBytes.isNotEmpty) {
          final u8 = uploadBytes is Uint8List
              ? uploadBytes
              : Uint8List.fromList(uploadBytes);
          fileSize = u8.length;
          mediaUrl = await ChurchChatMediaStorage.putBytesFast(
            storagePath: storagePath,
            bytes: u8,
            contentType: mime,
            onProgress: (t) => _mapProgress(reportProgress, 0.15, 0.85, t),
          ).timeout(kStorageAudioTimeout, onTimeout: () => throw TimeoutException(
            'O envio do áudio demorou demais. Verifique a rede e toque em «Tentar de novo».',
            kStorageAudioTimeout,
          ));
        } else if (uploadPath.isNotEmpty) {
          final audioBytes = await _readLocalPathBytes(uploadPath);
          if (audioBytes.isEmpty) {
            throw StateError('Áudio vazio — selecione outro ficheiro.');
          }
          fileSize = audioBytes.length;
          mediaUrl = await ChurchChatMediaStorage.putBytesFast(
            storagePath: storagePath,
            bytes: audioBytes,
            contentType: mime,
            onProgress: (t) => _mapProgress(reportProgress, 0.15, 0.85, t),
          ).timeout(kStorageAudioTimeout, onTimeout: () => throw TimeoutException(
            'O envio do áudio demorou demais. Verifique a rede e toque em «Tentar de novo».',
            kStorageAudioTimeout,
          ));
        } else {
          throw StateError('Sem áudio para enviar.');
        }
      } else if (uploadBytes != null && uploadBytes.isNotEmpty) {
        final u8 = uploadBytes is Uint8List
            ? uploadBytes
            : Uint8List.fromList(uploadBytes);
        fileSize = u8.length;
        mediaUrl = await ChurchChatMediaStorage.putBytesFast(
          storagePath: storagePath,
          bytes: u8,
          contentType: pending.mime.isNotEmpty
              ? pending.mime
              : 'application/octet-stream',
          onProgress: (t) => _mapProgress(reportProgress, 0.15, 0.85, t),
        ).timeout(kStorageDocumentTimeout);
      } else if (uploadPath.isNotEmpty) {
        final docBytes = await _readLocalPathBytes(uploadPath);
        if (docBytes.isEmpty) {
          throw StateError('Ficheiro vazio — selecione outro.');
        }
        fileSize = docBytes.length;
        mediaUrl = await ChurchChatMediaStorage.putBytesFast(
          storagePath: storagePath,
          bytes: docBytes,
          contentType: pending.mime.isNotEmpty
              ? pending.mime
              : 'application/octet-stream',
          onProgress: (t) => _mapProgress(reportProgress, 0.15, 0.85, t),
        ).timeout(kStorageDocumentTimeout);
      } else {
        throw StateError('Sem dados para enviar.');
      }

    if ((mediaUrl == null || mediaUrl.isEmpty) && storagePath.isNotEmpty) {
      try {
        mediaUrl = await DirectStorageUrlPublish.resolveUrl(storagePath);
      } catch (_) {}
    }

    reportProgress(0.9);
    ChurchPublishFlowLog.uploadOk('chat_${pending.kind}');

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
    }
    reportProgress(0.92);

    final written = await _writeFirestoreAfterUploadWithRetry(
      resolvedTenant: resolvedTenant,
      threadId: threadId,
      pending: pending,
      messageId: messageId,
      storagePath: storagePath,
      thumbStoragePath: thumbStoragePath,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      fileSize: fileSize,
      replyTo: replyTo,
    );

    if (!written.allowed || written.messageId.isEmpty) {
      throw StateError('Não foi possível gravar a mensagem no chat.');
    }

    reportProgress(0.98);
    pending.firestoreMessageId = written.messageId;
    onReplyCleared?.call();
    reportProgress(1.0);
    unawaited(
      ChurchChatUploadsService.markDone(
        tenantId: resolvedTenant,
        uploadId: messageId,
      ),
    );
    unawaited(
      ChurchChatMediaOutboxService.clearJob(
        tenantId: resolvedTenant,
        threadId: threadId,
        localId: pending.localId,
        uploadDocId: messageId,
      ),
    );
    ChurchPublishFlowLog.chatFileUploaded();
    ChurchPublishFlowLog.chatFinalOk();
  }

  static Future<({String messageId, bool allowed})> _writeFirestoreAfterUpload({
    required String resolvedTenant,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required String messageId,
    required String storagePath,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    int? fileSize,
    Map<String, dynamic>? replyTo,
  }) async {
    await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
    Future<({String messageId, bool allowed})> writeOnce() =>
        ChurchChatService.writeMediaMessageFirestoreOnce(
          tenantId: resolvedTenant,
          threadId: threadId,
          kind: pending.kind,
          storagePath: storagePath,
          thumbStoragePath: thumbStoragePath,
          mediaUrl: mediaUrl,
          thumbUrl: thumbUrl,
          fileName: ChurchChatMessageFields.isDocumentType(pending.kind)
              ? pending.fileName
              : null,
          fileSize: fileSize,
          voiceDurationMs: pending.voiceDurationMs,
          replyTo: replyTo,
          messageId: messageId,
          senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
          albumGroupId: pending.albumGroupId,
          albumIndex: pending.albumIndex,
          albumCount: pending.albumCount,
          skipStorageVerify: true,
        );

    if (kIsWeb) {
      return FirestoreWebGuard.runChatWriteWithRecovery(writeOnce);
    }
    return writeOnce();
  }

  static Future<({String messageId, bool allowed})>
      _writeFirestoreAfterUploadWithRetry({
    required String resolvedTenant,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required String messageId,
    required String storagePath,
    String? thumbStoragePath,
    String? mediaUrl,
    String? thumbUrl,
    int? fileSize,
    Map<String, dynamic>? replyTo,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          await EcoFireDirectFirebase.ensureDefaultApp();
          await Future<void>.delayed(
            Duration(milliseconds: 100 * attempt),
          );
        }
        return await _writeFirestoreAfterUpload(
          resolvedTenant: resolvedTenant,
          threadId: threadId,
          pending: pending,
          messageId: messageId,
          storagePath: storagePath,
          thumbStoragePath: thumbStoragePath,
          mediaUrl: mediaUrl,
          thumbUrl: thumbUrl,
          fileSize: fileSize,
          replyTo: replyTo,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Gravação demorou demais. Verifique a rede e tente novamente.',
            const Duration(seconds: 30),
          ),
        );
      } catch (e) {
        last = e;
        if (attempt < 2 &&
            (isFirebaseNoAppError(e) ||
                FirestoreWebGuard.isInternalAssertionError(e) ||
                FirestoreWebGuard.isClientTerminated(e) ||
                e is FirebaseException &&
                    (e.code == 'unavailable' ||
                        e.code == 'deadline-exceeded' ||
                        e.code == 'cancelled'))) {
          continue;
        }
        rethrow;
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
    if (kIsWeb &&
        localPath != null &&
        localPath.isNotEmpty &&
        (bytes == null || bytes.isEmpty)) {
      try {
        final raw = await _readLocalPathBytes(localPath);
        if (raw.isNotEmpty) {
          bytes = raw;
        }
      } catch (_) {}
    }
    // Telegram/CT: se ainda não comprimiu, envia JPEG leve do path sem bloquear 25s.
    if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      try {
        final quick = await SafeImageBytes.fromPath(
          localPath,
          maxEdge: MediaOptimizationLimits.chatMaxEdge,
          quality: MediaOptimizationLimits.chatQuality,
        ).timeout(const Duration(seconds: 20));
        if (quick.isNotEmpty) {
          return PreparedChatImage(
            fullBytes: quick,
            fullMime: 'image/jpeg',
            fullFileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
            thumbBytes: null,
          );
        }
      } catch (_) {}
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
