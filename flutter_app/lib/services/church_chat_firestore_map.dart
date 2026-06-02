/// Mapa canónico Firestore do chat: `chats/{chatId}/messages/{messageId}`.
abstract final class ChurchChatFirestoreMap {
  ChurchChatFirestoreMap._();

  /// Coleção de conversas sob `igrejas/{tenantId}/chats`.
  static const String conversationsCollection = 'chats';

  /// Legado (pré-migração v1).
  static const String legacyConversationsCollection = 'chat_threads';

  static const String messagesSubcollection = 'messages';

  static const String presenceCollection = 'chat_presence';

  static const String typingSubcollection = 'typing';

  static const String userChatsLocalCache = 'church_chat_local_conversations_v1';

  static const String chatUploadsCollection = 'chat_uploads';

  static const String storageChatMediaRoot = 'chat_media';

  static const List<String> conversationIndexFields = <String>[
    'lastMessage',
    'lastMessageType',
    'lastMessageAt',
    'lastSenderUid',
    'hasConversation',
  ];
}
