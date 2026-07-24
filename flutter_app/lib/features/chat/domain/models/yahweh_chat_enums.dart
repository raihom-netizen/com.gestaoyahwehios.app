/// Tipos e estados do **YAHWEH CHAT** (domínio).
///
/// Infraestrutura: Firebase Auth + Firestore + Storage + FCM.
/// Sem Telegram / TDLib / WebView.
library;

/// Tipo de conversa.
enum YahwehChatType {
  /// Chat 1–1 entre membros.
  direct,

  /// Grupo bidirecional (= departamento).
  group,

  /// Canal oficial (só pastoral/secretaria publica).
  channel,

  /// Avisos (broadcast institucional).
  announcements,
}

/// Tipo de conteúdo da mensagem.
enum YahwehMessageType {
  text,
  image,
  video,
  audio,
  document,
  pdf,
  contact,
  location,
  link,
  gif,
  system,
}

/// Estado de entrega (estilo mensageiro moderno).
enum YahwehMessageStatus {
  local,
  sending,
  uploading,
  queued,
  sent,
  delivered,
  read,
  failed,
}

extension YahwehChatTypeX on YahwehChatType {
  String get wire {
    switch (this) {
      case YahwehChatType.direct:
        return 'direct';
      case YahwehChatType.group:
        return 'group';
      case YahwehChatType.channel:
        return 'channel';
      case YahwehChatType.announcements:
        return 'announcements';
    }
  }

  static YahwehChatType fromWire(String? raw, {String? chatId}) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'direct':
      case 'dm':
      case 'private':
        return YahwehChatType.direct;
      case 'group':
      case 'department':
      case 'dept':
        return YahwehChatType.group;
      case 'channel':
        return YahwehChatType.channel;
      case 'announcements':
      case 'avisos':
        return YahwehChatType.announcements;
    }
    final id = (chatId ?? '').trim();
    if (id.startsWith('dept_')) return YahwehChatType.group;
    if (id.startsWith('channel_') || id.startsWith('canal_')) {
      return YahwehChatType.channel;
    }
    if (id.startsWith('dm_') || id.startsWith('priv_')) {
      return YahwehChatType.direct;
    }
    return YahwehChatType.direct;
  }
}

extension YahwehMessageTypeX on YahwehMessageType {
  String get wire {
    switch (this) {
      case YahwehMessageType.text:
        return 'text';
      case YahwehMessageType.image:
        return 'image';
      case YahwehMessageType.video:
        return 'video';
      case YahwehMessageType.audio:
        return 'audio';
      case YahwehMessageType.document:
        return 'document';
      case YahwehMessageType.pdf:
        return 'pdf';
      case YahwehMessageType.contact:
        return 'contact';
      case YahwehMessageType.location:
        return 'location';
      case YahwehMessageType.link:
        return 'link';
      case YahwehMessageType.gif:
        return 'gif';
      case YahwehMessageType.system:
        return 'system';
    }
  }

  static YahwehMessageType fromWire(String? raw) {
    final v = (raw ?? 'text').trim().toLowerCase();
    switch (v) {
      case 'image':
      case 'photo':
        return YahwehMessageType.image;
      case 'video':
        return YahwehMessageType.video;
      case 'audio':
      case 'voice':
      case 'ptt':
        return YahwehMessageType.audio;
      case 'document':
      case 'file':
      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
      case 'zip':
        return YahwehMessageType.document;
      case 'pdf':
        return YahwehMessageType.pdf;
      case 'contact':
        return YahwehMessageType.contact;
      case 'location':
        return YahwehMessageType.location;
      case 'link':
        return YahwehMessageType.link;
      case 'gif':
        return YahwehMessageType.gif;
      case 'system':
        return YahwehMessageType.system;
      default:
        return YahwehMessageType.text;
    }
  }

  bool get isMedia =>
      this == YahwehMessageType.image ||
      this == YahwehMessageType.video ||
      this == YahwehMessageType.audio ||
      this == YahwehMessageType.gif;

  bool get isFile =>
      this == YahwehMessageType.document || this == YahwehMessageType.pdf;
}

extension YahwehMessageStatusX on YahwehMessageStatus {
  String get wire {
    switch (this) {
      case YahwehMessageStatus.local:
        return 'local';
      case YahwehMessageStatus.sending:
        return 'sending';
      case YahwehMessageStatus.uploading:
        return 'uploading';
      case YahwehMessageStatus.queued:
        return 'queued';
      case YahwehMessageStatus.sent:
        return 'sent';
      case YahwehMessageStatus.delivered:
        return 'delivered';
      case YahwehMessageStatus.read:
        return 'read';
      case YahwehMessageStatus.failed:
        return 'failed';
    }
  }

  static YahwehMessageStatus fromWire(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'local':
        return YahwehMessageStatus.local;
      case 'sending':
        return YahwehMessageStatus.sending;
      case 'uploading':
        return YahwehMessageStatus.uploading;
      case 'queued':
        return YahwehMessageStatus.queued;
      case 'sent':
        return YahwehMessageStatus.sent;
      case 'delivered':
        return YahwehMessageStatus.delivered;
      case 'read':
        return YahwehMessageStatus.read;
      case 'failed':
      case 'error':
        return YahwehMessageStatus.failed;
      default:
        return YahwehMessageStatus.sent;
    }
  }
}
