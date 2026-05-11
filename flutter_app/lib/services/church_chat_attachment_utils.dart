import 'package:path/path.dart' as p;

/// MIME e tipo de mensagem no chat (Firestore `type`: text | image | video | audio | document).
class ChurchChatAttachmentUtils {
  ChurchChatAttachmentUtils._();

  static String extensionOf(String name) {
    final e = p.extension(name).toLowerCase();
    return e.startsWith('.') ? e : '.$e';
  }

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
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
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
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.txt':
        return 'text/plain';
      case '.csv':
        return 'text/csv';
      case '.rtf':
        return 'application/rtf';
      case '.zip':
        return 'application/zip';
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
    const img = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
    const vid = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v'};
    const aud = {'.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus', '.flac'};
    if (img.contains(ext)) return 'image';
    if (vid.contains(ext)) return 'video';
    if (aud.contains(ext)) return 'audio';
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
        final n = (fileName ?? 'Documento').trim();
        if (n.isEmpty) return '📎 Documento';
        return n.length > 42 ? '📎 ${n.substring(0, 39)}…' : '📎 $n';
      default:
        return '📎 Ficheiro';
    }
  }
}
