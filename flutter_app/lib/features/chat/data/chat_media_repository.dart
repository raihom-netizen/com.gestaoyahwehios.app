import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';import 'package:gestao_yahweh/services/chat_strict_publish_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';

/// Repositório de mídia do chat — Storage → Firestore (sem Firebase na UI).
abstract final class ChatMediaRepository {
  ChatMediaRepository._();

  /// Gate antes de abrir câmara/galeria (evita `core/no-app` no picker).
  static Future<bool> ensureReadyForPick({
    BuildContext? context,
    bool requireAuth = true,
  }) =>
      YahwehModuleMediaGate.ensureReadyForPick(
        context: context,
        module: YahwehMediaModule.chat,
        requireAuth: requireAuth,
      );

  /// Gate obrigatório antes de pick/gravação (evita `core/no-app`).
  static Future<bool> prepareForSend({String logLabel = 'chat_send'}) =>
      YahwehModuleMediaGate.prepareForPublishUpload(
        module: YahwehMediaModule.chat,
        logLabel: logLabel,
        requireAuth: true,
      ).then((ok) => ok);

  static Future<void> recoverAfterError(Object error) =>
      YahwehModuleMediaGate.recoverNoAppAfterPublishError(error);

  static Future<OptimizedMediaPayload> optimizeForChat({
    Uint8List? bytes,
    String? localPath,
  }) =>
      MediaOptimizationService.optimizeForChat(
        bytes: bytes,
        localPath: localPath,
      );

  static Future<Uint8List?> previewFromPath(String path) =>
      MediaOptimizationService.previewFromPath(path);

  static Future<void> sendPending({
    required String tenantId,
    required String threadId,
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
    void Function()? onSuccess,
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
      );

  static Future<void> finalizeUploadedMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    required String storagePath,
    String? fileName,
    String? thumbStoragePath,
    int? fileSize,
  }) =>
      ChatStrictPublishService.finalizeMediaMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        storagePath: storagePath,
        fileName: fileName,
        thumbStoragePath: thumbStoragePath,
        fileSize: fileSize,
      );
}
