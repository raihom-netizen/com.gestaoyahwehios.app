import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';

/// Campos canónicos de mensagem do Chat Igreja (Firestore).
///
/// Escrita: [ChurchCanonicalMediaContract.chatMediaWritePatch] (path-only).
/// Leitura: delega ao contrato canónico partilhado.
abstract final class ChurchChatMessageFields {
  ChurchChatMessageFields._();

  static String senderId(Map<String, dynamic> data) =>
      (data['senderId'] ?? data['senderUid'] ?? '').toString().trim();

  static String senderName(Map<String, dynamic> data) =>
      (data['senderName'] ??
              data['senderDisplayName'] ??
              '')
          .toString()
          .trim();

  static String? senderPhoto(Map<String, dynamic> data) {
    final p = (data['senderPhoto'] ?? data['senderPhotoUrl'] ?? '')
        .toString()
        .trim();
    return p.isEmpty ? null : p;
  }

  /// Legado — novas mensagens usam só [storagePath]; URL gerada na exibição.
  static String mediaUrl(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.chatLegacyMediaUrl(data);

  /// Caminho canónico no bucket (`igrejas/{id}/chat_media/...`).
  static String storagePath(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.chatStoragePath(data);

  static String thumbStoragePath(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.chatThumbStoragePath(data);

  /// Legado — preferir [thumbStoragePath] + resolver dinâmico.
  static String thumbnailUrl(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.resolveChat(data).thumbDownloadUrl;

  static bool hasResolvableMedia(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.hasViewableChatMedia(data);

  static bool uploadCompleted(Map<String, dynamic> data) =>
      data['uploadCompleted'] == true;

  static bool storageVerified(Map<String, dynamic> data) =>
      data['storageVerified'] == true;

  /// Verdadeiro enquanto o envio não foi confirmado no Firestore.
  static bool isUploadInProgress(Map<String, dynamic> data) {
    if (uploadCompleted(data)) return false;
    final ds = status(data);
    if (ds == 'sent' || ds == 'delivered' || ds == 'read') return false;
    return ds == 'uploading' || ds == 'queued' || ds == 'sending';
  }

  static String status(Map<String, dynamic> data) =>
      (data['status'] ?? data['deliveryStatus'] ?? '').toString().trim();

  static String fileName(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.resolveChat(data).fileName;

  static int? fileSize(Map<String, dynamic> data) {
    final raw = data['fileSize'] ?? data['size'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static int? durationSeconds(Map<String, dynamic> data) {
    final raw = data['duration'] ?? data['durationSeconds'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static bool isDocumentType(String type) {
    switch (type) {
      case 'document':
      case 'pdf':
      case 'doc':
      case 'xls':
      case 'zip':
        return true;
      default:
        return false;
    }
  }

  /// Patch Firestore com aliases canónicos + legado.
  static Map<String, dynamic> withCanonicalAliases(
    Map<String, dynamic> patch,
  ) {
    final out = Map<String, dynamic>.from(patch);
    if (out.containsKey('senderUid') && !out.containsKey('senderId')) {
      out['senderId'] = out['senderUid'];
    }
    if (out.containsKey('senderId') && !out.containsKey('senderUid')) {
      out['senderUid'] = out['senderId'];
    }
    if (out.containsKey('deliveryStatus') && !out.containsKey('status')) {
      out['status'] = out['deliveryStatus'];
    }
    if (out.containsKey('status') && !out.containsKey('deliveryStatus')) {
      out['deliveryStatus'] = out['status'];
    }
    if (out.containsKey('thumbUrl') && !out.containsKey('thumbnailUrl')) {
      out['thumbnailUrl'] = out['thumbUrl'];
    }
    if (out.containsKey('thumbnailUrl') && !out.containsKey('thumbUrl')) {
      out['thumbUrl'] = out['thumbnailUrl'];
    }
    if (out.containsKey('size') && !out.containsKey('fileSize')) {
      out['fileSize'] = out['size'];
    }
    return out;
  }

  /// Campos de mídia canónicos (Storage path + metadados).
  static Map<String, dynamic> mediaWritePatch({
    required String storagePath,
    String? thumbStoragePath,
    String? fileName,
    int? fileSize,
    int? voiceDurationSeconds,
    String deliveryStatus = 'sent',
  }) =>
      withCanonicalAliases(
        ChurchCanonicalMediaContract.chatMediaWritePatch(
          storagePath: storagePath,
          thumbStoragePath: thumbStoragePath,
          fileName: fileName,
          fileSize: fileSize,
          voiceDurationSeconds: voiceDurationSeconds,
          deliveryStatus: deliveryStatus,
        ),
      );
}
