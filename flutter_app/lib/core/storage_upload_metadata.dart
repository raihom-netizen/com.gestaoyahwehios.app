import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';

/// Metadados consistentes para `putData` / `putFile` — alinhado às regras Storage
/// (`octet-stream` aceite em todos os módulos de mídia).
abstract final class StorageUploadMetadata {
  StorageUploadMetadata._();

  static const String cacheControl = 'public,max-age=31536000';

  /// MIME para gravar no objeto GCS. Preferir tipo detectado; fallback `octet-stream`
  /// evita bloqueio quando Web/Android/iOS enviam tipo vazio ou genérico.
  static String contentTypeForPut({
    String? contentType,
    String? fileName,
    String? storagePath,
  }) {
    var ct = (contentType ?? '').trim().toLowerCase();
    if (ct.isEmpty || ct == 'application/octet-stream') {
      final name = (fileName ?? _fileNameFromPath(storagePath)).trim();
      if (name.isNotEmpty) {
        ct = ChurchChatAttachmentUtils.mimeFromFileName(name).toLowerCase();
      }
    }
    if (ct.isEmpty) return 'application/octet-stream';
    return ct;
  }

  static String _fileNameFromPath(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) return '';
    final parts = storagePath.split('/');
    return parts.isNotEmpty ? parts.last : '';
  }
}
