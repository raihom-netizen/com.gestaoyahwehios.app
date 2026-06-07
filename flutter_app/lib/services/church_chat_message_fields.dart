/// Campos canónicos de mensagem do Chat Igreja (Firestore).
///
/// Escrita dupla (`senderId`+`senderUid`, `thumbnailUrl`+`thumbUrl`, `status`+`deliveryStatus`)
/// para compatibilidade; leitura usa fallbacks.
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

  static String mediaUrl(Map<String, dynamic> data) =>
      (data['mediaUrl'] ?? data['fileUrl'] ?? '').toString().trim();

  static String thumbnailUrl(Map<String, dynamic> data) =>
      (data['thumbnailUrl'] ??
              data['thumbUrl'] ??
              data['posterUrl'] ??
              '')
          .toString()
          .trim();

  static String status(Map<String, dynamic> data) =>
      (data['status'] ?? data['deliveryStatus'] ?? '').toString().trim();

  static String fileName(Map<String, dynamic> data) =>
      (data['fileName'] ?? '').toString().trim();

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
}
