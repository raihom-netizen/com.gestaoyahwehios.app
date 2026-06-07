import 'package:path/path.dart' as p;

/// MIME, tipos permitidos e bloqueio de executáveis no chat igreja.
class ChurchChatAttachmentUtils {
  ChurchChatAttachmentUtils._();

  /// Extensões bloqueadas no chat (pedido: não aceitar `.exe`).
  static const Set<String> blockedExtensions = {'.exe'};

  /// Sem ponto — [FilePicker] `allowedExtensions` (documentos / ficheiros).
  static const List<String> documentPickerExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'xlsm',
    'ppt',
    'pptx',
    'pptm',
    'txt',
    'csv',
    'rtf',
    'odt',
    'ods',
    'odp',
    'zip',
    'rar',
    '7z',
    'war',
  ];

  static String extensionOf(String name) {
    final e = p.extension(name).toLowerCase();
    return e.startsWith('.') ? e : '.$e';
  }

  /// `null` se permitido; mensagem para o utilizador se bloqueado.
  static String? blockReasonForFileName(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) return null;
    final ext = extensionOf(trimmed);
    if (blockedExtensions.contains(ext)) {
      return 'Ficheiros .exe não são permitidos no chat.';
    }
    final lower = trimmed.toLowerCase();
    if (lower.endsWith('.exe')) {
      return 'Ficheiros .exe não são permitidos no chat.';
    }
    return null;
  }

  static bool isBlockedFileName(String fileName) =>
      blockReasonForFileName(fileName) != null;

  static String mimeFromFileName(String fileName) {
    switch (extensionOf(fileName)) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.avi':
        return 'video/x-msvideo';
      case '.mkv':
        return 'video/x-matroska';
      case '.m4v':
        return 'video/x-m4v';
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
      case '.docm':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
      case '.xlsm':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
      case '.pptm':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.odt':
        return 'application/vnd.oasis.opendocument.text';
      case '.ods':
        return 'application/vnd.oasis.opendocument.spreadsheet';
      case '.odp':
        return 'application/vnd.oasis.opendocument.presentation';
      case '.txt':
        return 'text/plain';
      case '.csv':
        return 'text/csv';
      case '.rtf':
        return 'application/rtf';
      case '.zip':
        return 'application/zip';
      case '.rar':
        return 'application/vnd.rar';
      case '.7z':
        return 'application/x-7z-compressed';
      case '.war':
        return 'application/java-archive';
      default:
        return 'application/octet-stream';
    }
  }

  /// Define o campo `type` em Firestore para anexos (não texto).
  static String messageKindForAttachment({
    required String fileName,
    required String mime,
  }) {
    final m = mime.toLowerCase().trim();
    if (m.startsWith('image/')) return 'image';
    if (m.startsWith('video/')) return 'video';
    if (m.startsWith('audio/')) return 'audio';
    final ext = extensionOf(fileName);
    const img = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif'};
    const vid = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v'};
    const aud = {'.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus', '.flac'};
    if (img.contains(ext)) return 'image';
    if (vid.contains(ext)) return 'video';
    if (aud.contains(ext)) return 'audio';
    if (ext == '.pdf') return 'pdf';
    if (ext == '.doc' || ext == '.docx' || ext == '.docm' || ext == '.odt') {
      return 'doc';
    }
    if (ext == '.xls' ||
        ext == '.xlsx' ||
        ext == '.xlsm' ||
        ext == '.ods' ||
        ext == '.csv') {
      return 'xls';
    }
    if (ext == '.zip' || ext == '.rar' || ext == '.7z') return 'zip';
    return 'document';
  }

  static String previewForThreadLastMessage({
    required String kind,
    String? fileName,
  }) {
    switch (kind) {
      case 'audio':
        return '🎤 Áudio';
      case 'video':
        return '🎬 Vídeo';
      case 'image':
        return '📷 Foto';
      case 'sticker':
        return '🎨 Figurinha';
      case 'document':
      case 'pdf':
      case 'doc':
      case 'xls':
      case 'zip':
        final n = (fileName ?? 'Documento').trim();
        if (n.isEmpty) return '📎 Documento';
        return n.length > 42 ? '📎 ${n.substring(0, 39)}…' : '📎 $n';
      default:
        return '📎 Ficheiro';
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
