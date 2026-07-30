/// Estados de autorização expostos pelo motor TDLib (mapa 1:1 com `@type` TDLib).
enum TdlibAuthPhase {
  idle,
  initializing,
  waitPhoneNumber,
  waitCode,
  waitPassword,
  waitRegistration,
  waitOtherDeviceConfirmation,
  ready,
  loggingOut,
  closed,
  unsupported,
  error,
}

class TdlibAuthSnapshot {
  const TdlibAuthSnapshot({
    required this.phase,
    this.rawType,
    this.message,
    this.codeInfoHint,
  });

  final TdlibAuthPhase phase;
  final String? rawType;
  final String? message;

  /// Ex.: "Telegram app" / SMS — dica da waitCode.
  final String? codeInfoHint;

  static const idle = TdlibAuthSnapshot(phase: TdlibAuthPhase.idle);

  static const unsupported = TdlibAuthSnapshot(
    phase: TdlibAuthPhase.unsupported,
    message:
        'TDLib nativo no Android/iOS. Na web o chat usa Telegram embutido '
        '(mesma conta / telefone do cadastro).',
  );

  TdlibAuthSnapshot copyWith({
    TdlibAuthPhase? phase,
    String? rawType,
    String? message,
    String? codeInfoHint,
  }) {
    return TdlibAuthSnapshot(
      phase: phase ?? this.phase,
      rawType: rawType ?? this.rawType,
      message: message ?? this.message,
      codeInfoHint: codeInfoHint ?? this.codeInfoHint,
    );
  }
}

class TdlibChatPreview {
  const TdlibChatPreview({
    required this.id,
    required this.title,
    this.unreadCount = 0,
    this.lastMessagePreview,
  });

  final int id;
  final String title;
  final int unreadCount;
  final String? lastMessagePreview;
}

/// Mensagem completa para a thread Yahweh Chat (TDLib).
class TdlibMessageItem {
  const TdlibMessageItem({
    required this.id,
    required this.chatId,
    required this.isOutgoing,
    required this.preview,
    this.dateEpoch,
    this.senderId,
    this.senderName,
    this.text = '',
    this.mediaKind,
    this.mediaFileId,
    this.mediaLocalPath,
    this.mediaRemoteId,
    this.mediaCaption,
    this.replyToMessageId,
    this.isRead = false,
    this.isEdited = false,
    this.isForwarded = false,
    this.fileSize,
    this.mimeType,
    this.fileName,
  });

  final int id;
  final int chatId;
  final bool isOutgoing;
  final String preview;
  final int? dateEpoch;
  final int? senderId;
  final String? senderName;
  final String text;

  /// 'photo' | 'video' | 'voice' | 'document' | 'audio' | 'sticker' | null
  final String? mediaKind;
  final int? mediaFileId;
  final String? mediaLocalPath;
  final String? mediaRemoteId;
  final String? mediaCaption;

  final int? replyToMessageId;
  final bool isRead;
  final bool isEdited;
  final bool isForwarded;
  final int? fileSize;
  final String? mimeType;
  final String? fileName;

  bool get hasMedia => mediaKind != null;

  TdlibMessageItem copyWith({
    int? id,
    int? chatId,
    bool? isOutgoing,
    String? preview,
    int? dateEpoch,
    int? senderId,
    String? senderName,
    String? text,
    String? mediaKind,
    int? mediaFileId,
    String? mediaLocalPath,
    String? mediaRemoteId,
    String? mediaCaption,
    int? replyToMessageId,
    bool? isRead,
    bool? isEdited,
    bool? isForwarded,
    int? fileSize,
    String? mimeType,
    String? fileName,
  }) =>
      TdlibMessageItem(
        id: id ?? this.id,
        chatId: chatId ?? this.chatId,
        isOutgoing: isOutgoing ?? this.isOutgoing,
        preview: preview ?? this.preview,
        dateEpoch: dateEpoch ?? this.dateEpoch,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        text: text ?? this.text,
        mediaKind: mediaKind ?? this.mediaKind,
        mediaFileId: mediaFileId ?? this.mediaFileId,
        mediaLocalPath: mediaLocalPath ?? this.mediaLocalPath,
        mediaRemoteId: mediaRemoteId ?? this.mediaRemoteId,
        mediaCaption: mediaCaption ?? this.mediaCaption,
        replyToMessageId: replyToMessageId ?? this.replyToMessageId,
        isRead: isRead ?? this.isRead,
        isEdited: isEdited ?? this.isEdited,
        isForwarded: isForwarded ?? this.isForwarded,
        fileSize: fileSize ?? this.fileSize,
        mimeType: mimeType ?? this.mimeType,
        fileName: fileName ?? this.fileName,
      );
}
