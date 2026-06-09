import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/optimistic_chat_media_upload.dart';

/// Chat estilo WhatsApp — Storage primeiro, Firestore depois (sem stub/fila).
abstract final class ChurchChatSyncSendService {
  ChurchChatSyncSendService._();

  /// Upload → confirma Storage → grava mensagem `sent` (falha = não grava).
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
      await OptimisticChatMediaUpload.flush(
        pending: pending,
        tenantId: tenantId,
        threadId: threadId,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        storageBeforeFirestore: true,
        onProgress: onProgress ?? (_) {},
        onFailed: (msg) => throw StateError(msg),
        onSuccess: () => onSuccess?.call(),
        onReplyCleared: null,
        onWaitingForNetwork: null,
      );
    } catch (e, st) {
      YahwehFlowLog.error('CHAT_SYNC', e, st);
      onError?.call(ChurchChatService.formatInstantSendError(e));
      rethrow;
    }
  }
}
