import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/chat_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Chat mídia — Storage confirmado → Firestore `sent` → verificação (sem falso sucesso).
abstract final class ChatStrictPublishService {
  ChatStrictPublishService._();

  /// Após upload no bucket: metadata → patch Firestore → confirma `sent` no servidor.
  static Future<void> finalizeMediaMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String storagePath,
    String? fileName,
    String? thumbStoragePath,
    int? fileSize,
    bool skipStorageVerify = false,
    bool skipServerRecheck = false,
  }) async {
    await ensureFirebaseReadyForChatSend();
    if (!skipStorageVerify) {
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded();
    }

    final resolvedTenant = ChurchPublishContext.churchIdForPublish(
      tenantId.trim(),
    );

    if (!skipStorageVerify) {
      await ChatPublishVerificationService.logPublishPhase(
        phase: 'storage_verify',
        igrejaId: resolvedTenant,
        threadId: threadId,
        messageId: messageId,
        storagePath: storagePath,
      );

      await ChatPublishVerificationService.verifyStorageMetadata(
        storagePath: storagePath,
        thumbStoragePath: thumbStoragePath,
      );
    }

    if (!skipStorageVerify) {
      await ChatPublishVerificationService.logPublishPhase(
        phase: 'before',
        igrejaId: resolvedTenant,
        threadId: threadId,
        messageId: messageId,
        storagePath: storagePath,
      );
    }

    await ChurchChatService.completeMediaUploadMessageDirect(
      resolvedTenant: resolvedTenant,
      threadId: threadId,
      messageId: messageId,
      storagePath: storagePath,
      fileName: fileName,
      thumbStoragePath: thumbStoragePath,
      fileSize: fileSize,
    );

    if (!skipServerRecheck) {
      final ref = ChatPublishVerificationService.messageDocRef(
        igrejaId: resolvedTenant,
        threadId: threadId,
        messageId: messageId,
      );
      await _verifyMessageSentOnServer(ref);
    }

    if (!skipStorageVerify) {
      await ChatPublishVerificationService.logPublishPhase(
        phase: 'after',
        igrejaId: resolvedTenant,
        threadId: threadId,
        messageId: messageId,
        storagePath: storagePath,
      );
    }
  }

  /// Mensagem com ficheiro no Storage mas Firestore ainda em `uploading` — tenta finalizar.
  static Future<bool> tryFinalizeIfStorageReady({
    required String tenantId,
    required String threadId,
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    if (!ChurchChatMessageFields.isUploadInProgress(data)) return false;
    final sp = ChurchChatMessageFields.storagePath(data);
    if (sp.isEmpty) return false;
    final thumb = ChurchChatMessageFields.thumbStoragePath(data);
    try {
      await finalizeMediaMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        storagePath: sp,
        fileName: ChurchChatMessageFields.fileName(data).isEmpty
            ? null
            : ChurchChatMessageFields.fileName(data),
        thumbStoragePath: thumb.isEmpty ? null : thumb,
        fileSize: ChurchChatMessageFields.fileSize(data),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _verifyMessageSentOnServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    Object? last;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final snap = await ref.get(
          GetOptions(
            source: attempt == 0 ? Source.serverAndCache : Source.server,
          ),
        );
        if (!snap.exists) {
          throw StateError(
            ChatPublishVerificationService.kPublishVerifyFailedMessage,
          );
        }
        final data = snap.data() ?? {};
        final ds = ChurchChatMessageFields.status(data);
        if (ds == ChurchChatService.deliverySent &&
            data['uploadCompleted'] == true) {
          return;
        }
        last = StateError(
          'Mensagem ainda não confirmada (status=$ds, uploadCompleted=${data['uploadCompleted']}).',
        );
      } catch (e) {
        last = e;
      }
      if (attempt < 4) {
        await Future.delayed(Duration(milliseconds: 220 * (attempt + 1)));
      }
    }
    throw last ??
        StateError(ChatPublishVerificationService.kPublishVerifyFailedMessage);
  }
}
