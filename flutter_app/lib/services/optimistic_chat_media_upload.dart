import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_media_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Upload fire-and-forget — UI mostra bolha local; Storage corre em background.
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
    await ensureFirebaseReadyForChatSend();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
    }
    await ChurchChatMediaSendService.send(
      tenantId: tenantId,
      threadId: threadId,
      pending: pending,
      bytes: bytes,
      localPath: localPath,
      replyTo: replyTo,
      onProgress: onProgress,
      onError: onError,
      onSuccess: onSuccess,
      onReplyCleared: null,
    );
  }
}
