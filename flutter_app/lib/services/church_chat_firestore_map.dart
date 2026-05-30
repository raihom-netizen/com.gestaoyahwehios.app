/// Mapa canónico: spec WhatsApp / pedido do cliente ↔ implementação Gestão YAHWEH.
///
/// **Não** duplicar coleções — `chat_threads` é o `conversations` do produto.
abstract final class ChurchChatFirestoreMap {
  ChurchChatFirestoreMap._();

  /// Spec `conversations/{conversationId}` → `igrejas/{tenantId}/chat_threads/{threadId}`
  static const conversationsCollection = 'chat_threads';

  /// Spec `messages/{messageId}` → `…/chat_threads/{threadId}/messages/{messageId}`
  static const messagesSubcollection = 'messages';

  /// Spec `presence/{uid}` → `igrejas/{tenantId}/chat_presence/{uid}`
  static const presenceCollection = 'chat_presence';

  /// Spec `typing/{uid}` → `…/chat_threads/{threadId}/typing/{uid}`
  static const typingSubcollection = 'typing';

  /// Spec `userChats/{uid}` (inbox por utilizador) → cache local
  /// [ChurchChatLocalConversations] + `chat_member_prefs/{uid}`
  static const userChatsLocalCache = 'church_chat_local_conversations_v1';

  /// Spec `chatUploads/{id}` → `igrejas/{tenantId}/chat_uploads/{id}`
  static const chatUploadsCollection = 'chat_uploads';

  /// Storage: `chat_media/{conversationId}/images|videos|audio|documents`
  /// → `igrejas/{tenantId}/chat_media/{threadId}/images|videos|audio|documents/…`
  static const storageChatMediaRoot = 'chat_media';

  /// Campos obrigatórios no doc de conversa (índice da lista):
  static const conversationIndexFields = <String>[
    'lastMessage',
    'lastMessageType',
    'lastMessageAt',
    'lastSenderUid',
    'hasConversation',
  ];
}
