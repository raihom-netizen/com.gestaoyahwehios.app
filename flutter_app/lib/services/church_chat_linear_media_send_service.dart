import 'package:gestao_yahweh/services/church_chat_media_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';

/// Chat mídia — delega ao pipeline único [ChurchChatMediaSendService].
abstract final class ChurchChatLinearMediaSendService {
  ChurchChatLinearMediaSendService._();

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
  }) =>
      ChurchChatMediaSendService.send(
        tenantId: tenantId,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onError: onError,
        onSuccess: onSuccess,
        onReplyCleared: onReplyCleared,
      );
}
