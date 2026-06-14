import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_messaging_engine.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_sync_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_send_callbacks.dart';

/// Chat Igreja — **fachada fina** (sem tenant fixo; delega motor existente).
///
/// Firestore mensagens: `igrejas/{churchId}/chats/{chatId}/messages`
/// Preferências grupos: `igrejas/{churchId}/chat_member_prefs/{uid}.departmentGroupOrderIds`
/// Storage mídia: `igrejas/{churchId}/chat_media/{images|videos|audio|documents}/`
abstract final class YahwehChatEngineService {
  YahwehChatEngineService._();

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  /// IDs dos grupos de departamento visíveis para o membro logado.
  static Stream<List<String>> watchMemberDepartmentGroupIds(
    String churchIdHint,
  ) =>
      ChurchChatMemberPrefs.watch(churchIdHint).map(
        (snap) => ChurchChatMemberPrefs.parse(snap).departmentGroupOrderIds,
      );

  static Future<List<String>> loadMemberDepartmentGroupIds(
    String churchIdHint,
  ) async {
    final prefs = await ChurchChatMemberPrefs.loadResilient(churchIdHint);
    return prefs.departmentGroupOrderIds;
  }

  static Future<ChurchChatMemberPrefsModel> loadMemberPrefs(
    String churchIdHint,
  ) =>
      ChurchChatMemberPrefs.loadResilient(churchIdHint);

  /// Mensagens recentes — porta única [ChatMessagingEngine].
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentMessages({
    required String churchIdHint,
    required String chatId,
    int? pageSize,
  }) {
    final churchId = resolveChurchId(churchIdHint);
    return ChatMessagingEngine.watchRecentMessages(
      churchId: churchId,
      chatId: chatId,
      pageSize: pageSize,
    );
  }

  /// Texto instantâneo (Firestore local + sync silencioso).
  static void sendText({
    required String churchIdHint,
    required String chatId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    ChurchChatSendCompleteCallback? onComplete,
    ChurchChatSendErrorCallback? onError,
  }) {
    ChatMessagingEngine.sendText(
      churchId: resolveChurchId(churchIdHint),
      chatId: chatId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// Mídia (foto, áudio, ficheiro) — Storage → Firestore via pipeline existente.
  static Future<void> sendMedia({
    required String churchIdHint,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function()? onSuccess,
  }) =>
      ChurchChatSyncSendService.sendMedia(
        tenantId: resolveChurchId(churchIdHint),
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onError: onError,
        onSuccess: onSuccess,
      );
}
