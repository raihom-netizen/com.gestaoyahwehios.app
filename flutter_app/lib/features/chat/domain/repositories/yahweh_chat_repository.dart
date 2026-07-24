import 'package:gestao_yahweh/features/chat/domain/models/yahweh_chat_conversation.dart';
import 'package:gestao_yahweh/features/chat/domain/models/yahweh_chat_message.dart';
import 'package:gestao_yahweh/features/chat/domain/models/yahweh_chat_user.dart';

/// Contrato de domínio do YAHWEH CHAT (Passo 3: implementação em `data/`).
///
/// Paths canónicos:
/// - Conversas: `igrejas/{churchId}/chats/{chatId}`
/// - Mensagens: `igrejas/{churchId}/chats/{chatId}/messages/{messageId}`
/// - Mídia: Storage `igrejas/{churchId}/chat_media/...`
abstract class YahwehChatRepository {
  /// Lista / observa conversas do utilizador autenticado.
  Stream<List<YahwehChatConversation>> watchConversations({
    required String churchId,
    required String uid,
  });

  Future<List<YahwehChatConversation>> loadConversations({
    required String churchId,
    required String uid,
  });

  /// Página recente de mensagens (padrão: 20).
  Stream<List<YahwehChatMessage>> watchRecentMessages({
    required String churchId,
    required String conversationId,
    int pageSize = 20,
  });

  Future<List<YahwehChatMessage>> loadOlderMessages({
    required String churchId,
    required String conversationId,
    required String beforeMessageId,
    int pageSize = 20,
  });

  Future<void> sendText({
    required String churchId,
    required String conversationId,
    required String text,
    String? replyToId,
  });

  Future<YahwehChatConversation?> openOrCreateDirect({
    required String churchId,
    required String myUid,
    required YahwehChatUser peer,
  });

  Future<YahwehChatConversation?> openDepartmentGroup({
    required String churchId,
    required String departmentId,
  });
}
