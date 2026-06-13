import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/services/church_chat_instant_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_chat_sync_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';

/// Chat igreja — envio rápido estilo WhatsApp (texto + mídia).
///
/// Mídia: preview local → Storage → Firestore `sent` (sem stub uploading).
abstract final class ChurchChatFastSendService {
  ChurchChatFastSendService._();

  static DateTime? _lastWarm;
  static Future<void>? _warmInFlight;

  /// Bootstrap Ecofire antes de enviar (evita core/no-app).
  static Future<void> warmSendPipeline({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastWarm != null &&
        now.difference(_lastWarm!) < const Duration(seconds: 20)) {
      return Future<void>.value();
    }
    _warmInFlight ??= EcoFireResilientPublish.prepareForPublish(
      logLabel: 'chat_warm',
    ).whenComplete(() {
      _lastWarm = DateTime.now();
      _warmInFlight = null;
    });
    return _warmInFlight!;
  }

  /// Texto — UI optimista + uma gravação Firestore.
  static Future<void> sendText({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) async {
    try {
      await warmSendPipeline();
    } catch (e) {
      onComplete?.call(false);
      onError?.call(ChurchChatService.formatInstantSendError(e));
      return;
    }
    await ChurchChatInstantSendService.sendTextNow(
      tenantId: tenantId,
      threadId: threadId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// Mídia — Storage → Firestore `sent` (preview local na UI).
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
    await warmSendPipeline();
    await ChurchChatSyncSendService.sendMedia(
      tenantId: tenantId,
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
}
