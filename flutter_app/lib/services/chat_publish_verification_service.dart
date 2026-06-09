import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Verificação obrigatória pós-gravação do chat — evita falso sucesso.
abstract final class ChatPublishVerificationService {
  ChatPublishVerificationService._();

  static const String kPublishVerifyFailedMessage =
      'Falha ao enviar mensagem.\nDocumento não localizado no Firestore.';

  static const String kStorageVerifyFailedMessage =
      'Falha ao enviar mídia.\nArquivo não confirmado no Storage.';

  static String? _lastError;

  static String? get lastError => _lastError;

  static void rememberLastError(Object error) {
    _lastError = error.toString();
  }

  static void clearLastError() => _lastError = null;

  static Future<String> resolveTenantForPublish({
    required String seedTenantId,
    String? userUid,
  }) async {
    final resolved = ChurchPublishContext.churchIdForPublish(seedTenantId);
    debugPrint('CHURCH_ID (chat): $resolved');
    return resolved;
  }

  static void assertMessagePath(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length < 6 ||
        parts[0] != 'igrejas' ||
        parts[2] != 'chats' ||
        parts[4] != 'messages') {
      throw StateError(
        'Caminho incorreto para mensagem: ${ref.path}. '
        'Esperado: igrejas/{igrejaId}/chats/{threadId}/messages/{id}',
      );
    }
    if (parts[1].trim().isEmpty) {
      throw StateError('churchId inválido: ${ref.path}');
    }
  }

  static DocumentReference<Map<String, dynamic>> messageDocRef({
    required String igrejaId,
    required String threadId,
    required String messageId,
  }) {
    final ref = ChurchOperationalPaths.churchDoc(igrejaId.trim())
        .collection('chats')
        .doc(threadId.trim())
        .collection('messages')
        .doc(messageId.trim());
    assertMessagePath(ref);
    return ref;
  }

  static String messagesCollectionPath({
    required String igrejaId,
    required String threadId,
  }) =>
      'igrejas/${igrejaId.trim()}/chats/${threadId.trim()}/messages';

  static Future<void> verifyStorageMetadata({
    required String storagePath,
    String? thumbStoragePath,
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertExists(storagePath);
      final thumb = thumbStoragePath?.trim() ?? '';
      if (thumb.isNotEmpty) {
        await ChurchStorageMetadataVerify.assertExists(thumb);
      }
    } catch (e) {
      rememberLastError(kStorageVerifyFailedMessage);
      rethrow;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
  }) async {
    assertMessagePath(docRef);
    final check = await docRef.get(
      GetOptions(
        source: preferServer ? Source.server : Source.serverAndCache,
      ),
    );
    if (!check.exists) {
      rememberLastError(kPublishVerifyFailedMessage);
      throw StateError(kPublishVerifyFailedMessage);
    }
    final data = check.data();
    final sp = (data?['storagePath'] ?? '').toString().trim();
    if (sp.isEmpty &&
        (data?['type'] ?? '').toString() != 'text' &&
        (data?['type'] ?? '').toString() != 'texto') {
      rememberLastError(
        'Mensagem sem storagePath após envio de mídia.',
      );
      throw StateError(kPublishVerifyFailedMessage);
    }
    return check;
  }

  static Future<void> logPublishPhase({
    required String phase,
    required String igrejaId,
    required String threadId,
    required String messageId,
    String? storagePath,
  }) async {
    await SystemLogService.record(
      module: 'chat',
      message: 'publish_$phase',
      tenantId: igrejaId,
      canonicalId: igrejaId,
      severity: phase == 'after' ? 'info' : 'debug',
      extra: <String, dynamic>{
        'igrejaId': igrejaId,
        'threadId': threadId,
        'messageId': messageId,
        if (storagePath != null && storagePath.isNotEmpty)
          'storagePath': storagePath,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
