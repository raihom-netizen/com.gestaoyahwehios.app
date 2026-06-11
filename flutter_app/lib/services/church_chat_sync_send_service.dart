import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_chat_linear_media_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Chat mídia — pipeline linear (Storage → Firestore no mobile; stub → Storage na web).
abstract final class ChurchChatSyncSendService {
  ChurchChatSyncSendService._();

  static Future<void> sendMedia({
    required String tenantId,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function()? onSuccess,
  }) async {
    pending.firestoreMessageId = null;
    pending.storagePath = null;
    try {
      await ChurchChatLinearMediaSendService.send(
        tenantId: tenantId,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onError: (msg) => throw StateError(msg),
        onSuccess: onSuccess,
        onReplyCleared: null,
      );
    } catch (e, st) {
      YahwehFlowLog.error('CHAT_SYNC', e, st);
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }
  }
}
