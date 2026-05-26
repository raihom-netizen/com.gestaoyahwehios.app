import 'dart:async' show unawaited;

import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Chat estilo WhatsApp: mensagem no Firestore primeiro (`sending`), finalize em background.
///
/// Caminhos: `igrejas/{tenantId}/chat_threads/{threadId}/messages`.
abstract final class ChurchChatInstantSendService {
  ChurchChatInstantSendService._();

  static const String statusSending = ChurchChatService.deliverySending;
  static const String statusUploading = ChurchChatService.deliveryUploading;
  static const String statusSent = ChurchChatService.deliverySent;

  /// Texto: aparece na thread via StreamBuilder; não bloqueia o composer.
  static void enqueueText({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) {
    unawaited(Future<void>(() async {
      var messageId = '';
      try {
        final begun = await ChurchChatService.beginTextMessage(
          tenantId: tenantId,
          threadId: threadId,
          text: text,
          replyTo: replyTo,
          forwardedFrom: forwardedFrom,
          senderDisplayName: senderDisplayName,
          mentionedUids: mentionedUids,
        );
        if (!begun.allowed) {
          onComplete?.call(false);
          onError?.call(
            'Não é possível enviar — desbloqueie o contacto nas opções da conversa.',
          );
          return;
        }
        messageId = begun.messageId;
        await ChurchChatService.finalizeTextMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
          text: text,
          replyTo: replyTo,
          forwardedFrom: forwardedFrom,
        );
        onComplete?.call(true);
      } catch (e) {
        if (messageId.isNotEmpty) {
          await ChurchChatService.abandonTextMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: messageId,
          );
        }
        onError?.call(ChurchChatService.formatInstantSendError(e));
      }
    }));
  }

  /// Figurinha (URL já no Storage): stub `sending` → `sent` em background.
  static void enqueueSticker({
    required String tenantId,
    required String threadId,
    required String downloadUrl,
    String? storagePath,
    String stickerSource = 'upload',
    Map<String, dynamic>? replyTo,
    String? senderDisplayName,
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) {
    unawaited(Future<void>(() async {
      var messageId = '';
      try {
        final begun = await ChurchChatService.beginStickerMessage(
          tenantId: tenantId,
          threadId: threadId,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          stickerSource: stickerSource,
          replyTo: replyTo,
          senderDisplayName: senderDisplayName,
        );
        if (!begun.allowed) {
          onComplete?.call(false);
          onError?.call(
            'Não é possível enviar — desbloqueie o contacto nas opções.',
          );
          return;
        }
        messageId = begun.messageId;
        await ChurchChatService.finalizeStickerMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          stickerSource: stickerSource,
        );
        onComplete?.call(true);
      } catch (e) {
        if (messageId.isNotEmpty) {
          await ChurchChatService.abandonMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: messageId,
          );
        }
        onError?.call(ChurchChatService.formatInstantSendError(e));
      }
    }));
  }
}
