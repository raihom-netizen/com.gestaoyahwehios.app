import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_send_callbacks.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Chat texto — Firestore directo (padrão Controle Total), sem fila/outbox/guard.
///
/// Caminhos: `igrejas/{tenantId}/chats/{threadId}/messages`.
abstract final class ChurchChatInstantSendService {
  ChurchChatInstantSendService._();

  static const String statusSending = ChurchChatService.deliverySending;
  static const String statusUploading = ChurchChatService.deliveryUploading;
  static const String statusSent = ChurchChatService.deliverySent;

  /// Texto: `messageRef.set` + índice do thread — uma gravação, `status: sent`.
  static void enqueueText({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    ChurchChatSendCompleteCallback? onComplete,
    ChurchChatSendErrorCallback? onError,
  }) {
    unawaited(sendTextNow(
      tenantId: tenantId,
      threadId: threadId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
      onComplete: onComplete,
      onError: onError,
    ));
  }

  /// Envio awaitable — usado pelo pipeline WhatsApp-fast.
  static Future<void> sendTextNow({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    ChurchChatSendCompleteCallback? onComplete,
    ChurchChatSendErrorCallback? onError,
  }) =>
      _sendTextDirect(
        tenantId: tenantId,
        threadId: threadId,
        text: text,
        replyTo: replyTo,
        forwardedFrom: forwardedFrom,
        senderDisplayName: senderDisplayName,
        mentionedUids: mentionedUids,
        onComplete: onComplete,
        onError: onError,
      );

  static Future<void> _sendTextDirect({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    ChurchChatSendCompleteCallback? onComplete,
    ChurchChatSendErrorCallback? onError,
  }) async {
    try {
      await ensureFirebaseReadyForChatSend();
      final r = await ChurchChatService.writeTextMessageFirestoreOnce(
        tenantId: tenantId,
        threadId: threadId,
        text: text,
        replyTo: replyTo,
        forwardedFrom: forwardedFrom,
        senderDisplayName: senderDisplayName,
        mentionedUids: mentionedUids,
      );
      if (!r.allowed) {
        onComplete?.call(false);
        onError?.call(
          'Não é possível enviar — desbloqueie o contacto nas opções da conversa.',
        );
        return;
      }
      onComplete?.call(true, messageId: r.messageId);
    } catch (e, st) {
      YahwehFlowLog.error('CHAT', e, st);
      onComplete?.call(false);
      onError?.call(
        ChurchChatService.formatInstantSendError(e),
      );
    }
  }

  /// Figurinha (URL já no Storage): stub `sending` → `sent` em background.
  static void enqueueSticker({
    required String tenantId,
    required String threadId,
    required String storagePath,
    String stickerSource = 'upload',
    Map<String, dynamic>? replyTo,
    String? senderDisplayName,
    ChurchChatSendCompleteCallback? onComplete,
    ChurchChatSendErrorCallback? onError,
  }) {
    unawaited(
      runChatMediaUploadTask(() async {
        var messageId = '';
        try {
          final begun = await ChurchChatService.beginStickerMessage(
            tenantId: tenantId,
            threadId: threadId,
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
            storagePath: storagePath,
            stickerSource: stickerSource,
          );
          onComplete?.call(
            true,
            messageId: messageId.isEmpty ? null : messageId,
          );
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
          if (messageId.isNotEmpty) {
            await ChurchChatService.abandonMediaUploadMessage(
              tenantId: tenantId,
              threadId: threadId,
              messageId: messageId,
            );
          }
          onError?.call(ChurchChatService.formatInstantSendError(e));
        }
      }, debugLabel: 'chat_sticker_send').catchError((Object e, StackTrace st) {
        YahwehFlowLog.error('CHAT', e, st);
        onError?.call(ChurchChatService.formatInstantSendError(e));
      }),
    );
  }
}
