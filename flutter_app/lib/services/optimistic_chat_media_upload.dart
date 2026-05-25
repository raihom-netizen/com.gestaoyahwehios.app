import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Envio de mídia no Chat Igreja — mesma base de Eventos/Avisos v11.2.295+1555:
/// aquece token Firebase → [MediaUploadService] via [ChurchChatService] → mensagem no Firestore.
abstract final class OptimisticChatMediaUpload {
  OptimisticChatMediaUpload._();

  static Duration _flushTimeoutFor(String kind) => switch (kind) {
        'video' => const Duration(minutes: 6),
        'audio' => const Duration(minutes: 4),
        _ => const Duration(minutes: 3),
      };

  static Future<void> _warmAuthToken() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  /// Upload em background após bolha local [ChurchChatOutboundPending].
  static Future<void> flush({
    required ChurchChatOutboundPending pending,
    required String tenantId,
    required String threadId,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    required void Function(double progress) onProgress,
    required void Function(String errorMessage) onFailed,
    required VoidCallback onSuccess,
    VoidCallback? onReplyCleared,
  }) async {
    try {
      await _flushCore(
        pending: pending,
        tenantId: tenantId,
        threadId: threadId,
        bytes: bytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: onProgress,
        onFailed: onFailed,
        onSuccess: onSuccess,
        onReplyCleared: onReplyCleared,
      ).timeout(
        _flushTimeoutFor(pending.kind),
        onTimeout: () => throw TimeoutException(
          'Envio demorou demais. Verifique a rede e tente de novo.',
        ),
      );
    } on TimeoutException catch (e) {
      onFailed(e.message ?? '$e');
    }
  }

  static Future<void> _flushCore({
    required ChurchChatOutboundPending pending,
    required String tenantId,
    required String threadId,
    required List<int>? bytes,
    required String? localPath,
    Map<String, dynamic>? replyTo,
    required void Function(double progress) onProgress,
    required void Function(String errorMessage) onFailed,
    required VoidCallback onSuccess,
    VoidCallback? onReplyCleared,
  }) async {
    try {
      final can = await ChurchChatMemberPrefs.canSendToDmThread(
        tenantId: tenantId,
        threadId: threadId,
      );
      if (!can) {
        onFailed('Envio bloqueado — desbloqueie o contacto.');
        return;
      }

      onProgress(0.05);
      await _warmAuthToken();
      onProgress(0.12);

      final uploadPath = localPath;
      final ({String url, String path}) up;

      if (uploadPath != null && uploadPath.isNotEmpty && !kIsWeb) {
        up = await ChurchChatService.uploadChatFile(
          tenantId: tenantId,
          threadId: threadId,
          localPath: uploadPath,
          fileName: pending.fileName,
          contentType: pending.mime,
          skipRecompress: pending.kind == 'video' || pending.kind == 'audio',
          onProgress: onProgress,
        );
      } else if (bytes != null && bytes.isNotEmpty) {
        up = await ChurchChatService.uploadChatBytes(
          tenantId: tenantId,
          threadId: threadId,
          bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          fileName: pending.fileName,
          contentType: pending.mime,
          onProgress: onProgress,
        );
      } else {
        throw StateError('Sem dados para enviar.');
      }

      final ok = await ChurchChatService.sendMediaMessage(
        tenantId: tenantId,
        threadId: threadId,
        downloadUrl: up.url,
        storagePath: up.path,
        kind: pending.kind,
        fileName: pending.kind == 'document' ? pending.fileName : null,
        replyTo: replyTo,
        senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      );

      if (!ok) {
        onFailed('Envio bloqueado para este contacto.');
        return;
      }

      onReplyCleared?.call();
      onProgress(1.0);
      onSuccess();
    } on FirebaseException catch (e) {
      onFailed(e.message ?? e.code);
    } catch (e) {
      onFailed('$e');
    }
  }
}
