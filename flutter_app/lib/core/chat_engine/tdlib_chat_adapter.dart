import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/chat_engine/chat_engine_paths.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';

/// Adaptador TDLib ↔ Chat Engine — converte tipos Telegram para o modelo
/// [ChatThread] / [ChatMessage] existente.
///
/// Quando TDLib está disponível (mobile), o motor usa este adaptador em vez
/// do Firestore direto. Na Web, o motor continua com Firestore.
abstract final class TdlibChatAdapter {
  TdlibChatAdapter._();

  /// `true` quando TDLib está autenticado e pronto para uso.
  static bool get isAvailable {
    if (kIsWeb) return false;
    final svc = TdLibService.instance;
    return svc.isSupported &&
        svc.currentAuth.phase == TdlibAuthPhase.ready;
  }

  /// Stream de mensagens TDLib para um chat → convertido para [ChatMessage].
  static Stream<List<ChatMessage>> watchMessages({
    required String churchId,
    required int tdlibChatId,
  }) {
    return TdLibService.instance.messagesStream.map(
      (items) => items
          .where((m) => m.chatId == tdlibChatId)
          .map((m) => toChatMessage(churchId, tdlibChatId, m))
          .toList(),
    );
  }

  /// Converte [TdlibChatPreview] → [ChatThread].
  static ChatThread toChatThread(
    String churchId,
    TdlibChatPreview preview, {
    String tipo = 'department',
    List<String> participants = const [],
    List<String> admins = const [],
    String foto = '',
  }) {
    return ChatThread(
      chatId: 'tg_${preview.id}',
      churchId: churchId,
      tipo: tipo,
      participants: participants,
      nome: preview.title,
      foto: foto,
      lastMessage: preview.lastMessagePreview ?? '',
      lastSenderId: '',
      lastMessageAt: null,
      memberCount: participants.length,
      admins: admins,
      raw: {
        'tdlibChatId': preview.id,
        'unreadCount': preview.unreadCount,
        'source': 'telegram',
      },
    );
  }

  /// Converte [TdlibMessageItem] → [ChatMessage].
  static ChatMessage toChatMessage(
    String churchId,
    int tdlibChatId,
    TdlibMessageItem item,
  ) {
    final type = _mapMediaType(item.mediaKind);
    final delivery = item.isOutgoing
        ? (item.isRead
            ? ChatDeliveryState.read
            : ChatDeliveryState.sent)
        : ChatDeliveryState.sent;

    return ChatMessage(
      messageId: '${item.id}',
      chatId: 'tg_$tdlibChatId',
      churchId: churchId,
      senderId: item.senderId?.toString() ?? '',
      senderName: item.senderName ?? '',
      type: type,
      text: item.text.isNotEmpty ? item.text : item.preview,
      mediaUrl: item.mediaLocalPath,
      thumbnailUrl: null,
      storagePath: item.mediaRemoteId,
      thumbStoragePath: null,
      fileName: item.fileName,
      fileSize: item.fileSize,
      mimeType: item.mimeType,
      replyTo: item.replyToMessageId != null
          ? {'messageId': '${item.replyToMessageId}'}
          : null,
      forwarded: item.isForwarded,
      edited: item.isEdited,
      deleted: false,
      createdAt: item.dateEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(item.dateEpoch! * 1000)
          : DateTime.now(),
      delivery: delivery,
      readBy: item.isRead ? {'self': DateTime.now()} : const {},
      raw: {
        'tdlibMessageId': item.id,
        'tdlibChatId': item.chatId,
        'source': 'telegram',
        if (item.mediaCaption != null) 'mediaCaption': item.mediaCaption,
      },
    );
  }

  /// Extrai TDLib chat ID do nosso chatId formatado (`tg_XXXXX`).
  static int? extractTdlibChatId(String chatId) {
    if (!chatId.startsWith('tg_')) return null;
    return int.tryParse(chatId.substring(3));
  }

  /// Mapeia tipo de mídia TDLib → [ChatMessageType].
  static ChatMessageType _mapMediaType(String? mediaKind) {
    return switch (mediaKind) {
      'photo' => ChatMessageType.image,
      'video' => ChatMessageType.video,
      'voice' => ChatMessageType.audio,
      'document' => ChatMessageType.document,
      'audio' => ChatMessageType.audio,
      'sticker' => ChatMessageType.sticker,
      _ => ChatMessageType.text,
    };
  }

  // ─── Ações delegadas ao TDLib ───────────────────────────────────────────

  /// Envia texto via TDLib.
  static Future<void> sendText({
    required int tdlibChatId,
    required String text,
    int? replyToMessageId,
  }) async {
    if (replyToMessageId != null) {
      await TdLibService.instance.sendTextReply(
        tdlibChatId,
        text,
        replyToMessageId: replyToMessageId,
      );
    } else {
      await TdLibService.instance.sendTextMessage(tdlibChatId, text);
    }
  }

  /// Envia mídia (foto/vídeo/documento/áudio) via TDLib.
  static Future<void> sendMedia({
    required int tdlibChatId,
    required String localPath,
    required String kind,
    String caption = '',
    int? replyToMessageId,
  }) =>
      TdLibService.instance.sendLocalFile(
        tdlibChatId,
        localPath,
        kind: kind,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );

  /// Apaga mensagens para todos.
  static Future<void> deleteMessages(
    int tdlibChatId,
    List<int> messageIds,
  ) =>
      TdLibService.instance.deleteMessages(tdlibChatId, messageIds);

  /// Edita texto de mensagem.
  static Future<void> editMessage(
    int tdlibChatId,
    int messageId,
    String newText,
  ) =>
      TdLibService.instance.editMessageText(tdlibChatId, messageId, newText);

  /// Encaminha mensagens.
  static Future<void> forwardMessages(
    int toChatId,
    int fromChatId,
    List<int> messageIds,
  ) =>
      TdLibService.instance.forwardMessages(toChatId, fromChatId, messageIds);

  /// Marca mensagens como lidas.
  static Future<void> markAsRead(
    int tdlibChatId,
    List<int> messageIds,
  ) =>
      TdLibService.instance.markAsRead(tdlibChatId, messageIds);

  /// Indicador de digitação.
  static Future<void> setTyping(
    int tdlibChatId, {
    bool recordingVoice = false,
  }) =>
      TdLibService.instance.sendChatAction(
        tdlibChatId,
        recordingVoice: recordingVoice,
      );

  /// Cancela indicador de digitação.
  static Future<void> clearTyping(int tdlibChatId) =>
      TdLibService.instance.cancelChatAction(tdlibChatId);

  /// Carrega histórico de mensagens.
  static Future<List<ChatMessage>> loadHistory({
    required String churchId,
    required int tdlibChatId,
    int limit = 30,
  }) async {
    final items = await TdLibService.instance.loadChatHistory(
      tdlibChatId,
      limit: limit,
    );
    return items
        .map((m) => toChatMessage(churchId, tdlibChatId, m))
        .toList();
  }

  /// Cria grupo de departamento.
  static Future<({int chatId, String? inviteLink})> createDepartmentGroup({
    required String title,
    String description = '',
  }) =>
      TdLibService.instance.createDepartmentSupergroup(
        title: title,
        description: description,
      );

  /// Adiciona membro ao grupo por telefone.
  static Future<bool> addMemberByPhone(
    int tdlibChatId,
    String phone,
  ) =>
      TdLibService.instance.addChatMemberByPhone(tdlibChatId, phone);

  /// Remove membro do grupo.
  static Future<void> removeMember(
    int tdlibChatId,
    int userId,
  ) =>
      TdLibService.instance.removeChatMember(tdlibChatId, userId);

  /// Abre chat privado por telefone.
  static Future<int> openPrivateChat(String phone) =>
      TdLibService.instance.openPrivateChatByPhone(phone);

  /// Entra em grupo por link de convite.
  static Future<int> joinByInvite(String inviteUrl) =>
      TdLibService.instance.joinByInviteLink(inviteUrl);

  /// Atualiza lista de chats.
  static Future<void> refreshChats({int limit = 40}) =>
      TdLibService.instance.refreshChats(limit: limit);
}
