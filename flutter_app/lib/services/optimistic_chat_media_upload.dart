import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_fast_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';

/// Upload otimista estilo WhatsApp — bootstrap seguro antes do Storage.
///
/// A UI enfileira [ChurchChatOutboundPending] e chama [upload] em background;
/// este serviço garante sessão Firebase (`no-app`) e delega ao pipeline canónico.
abstract final class OptimisticChatMediaUpload {
  OptimisticChatMediaUpload._();

  static Future<void> upload({
    required String tenantId,
    required String threadId,
    required ChurchChatOutboundPending pending,
    List<int>? bytes,
    String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function()? onSuccess,
  }) async {
    await AppFinalizeBootstrap.ensureSessionForPublish(logLabel: 'chat_media');
    await ensureFirebaseReadyForMediaUpload();
    await runChatMediaUploadTask(
      () => ChurchChatFastSendService.sendMedia(
        tenantId: tenantId,
        threadId: threadId,
        pending: pending,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onError: onError,
        onSuccess: onSuccess,
      ),
      debugLabel: 'optimistic_chat_media',
    );
  }
}
