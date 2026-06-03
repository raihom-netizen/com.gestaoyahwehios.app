import 'dart:async' show unawaited;

import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
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
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) {
    unawaited(_sendTextDirect(
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

  static Future<void> _sendTextDirect({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) async {
    try {
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
      onComplete?.call(true);
    } catch (e, st) {
      YahwehFlowLog.error('CHAT', e, st);
      onError?.call(ChurchChatService.formatInstantSendError(e));
    }
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
    unawaited(
      runChatMediaUploadTask(() async {
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
