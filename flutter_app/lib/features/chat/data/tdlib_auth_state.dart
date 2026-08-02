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
    this.lastMessageDateEpoch,
    this.isGroup = false,
    this.photoFileId,
    this.photoLocalPath,
  });

  final int id;
  final String title;
  final int unreadCount;
  final String? lastMessagePreview;
  final int? lastMessageDateEpoch;
  final bool isGroup;
  final int? photoFileId;
  final String? photoLocalPath;

  TdlibChatPreview copyWith({
    int? id,
    String? title,
    int? unreadCount,
    String? lastMessagePreview,
    int? lastMessageDateEpoch,
    bool? isGroup,
    int? photoFileId,
    String? photoLocalPath,
  }) =>
      TdlibChatPreview(
        id: id ?? this.id,
        title: title ?? this.title,
        unreadCount: unreadCount ?? this.unreadCount,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        lastMessageDateEpoch:
            lastMessageDateEpoch ?? this.lastMessageDateEpoch,
        isGroup: isGroup ?? this.isGroup,
        photoFileId: photoFileId ?? this.photoFileId,
        photoLocalPath: photoLocalPath ?? this.photoLocalPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'unreadCount': unreadCount,
        'lastMessagePreview': lastMessagePreview,
        'lastMessageDateEpoch': lastMessageDateEpoch,
        'isGroup': isGroup,
        'photoFileId': photoFileId,
        'photoLocalPath': photoLocalPath,
      };

  factory TdlibChatPreview.fromJson(Map<String, dynamic> j) => TdlibChatPreview(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        lastMessagePreview: j['lastMessagePreview']?.toString(),
        lastMessageDateEpoch: (j['lastMessageDateEpoch'] as num?)?.toInt(),
        isGroup: j['isGroup'] == true,
        photoFileId: (j['photoFileId'] as num?)?.toInt(),
        photoLocalPath: j['photoLocalPath']?.toString(),
      );
}

enum TdlibSendStatus { sent, sending, failed }

enum TdlibPeerActionKind { typing, recordingVoice, cancel }

class TdlibPeerAction {
  const TdlibPeerAction({
    required this.chatId,
    required this.kind,
    this.actorName,
  });

  final int chatId;
  final TdlibPeerActionKind kind;
  final String? actorName;
}

class TdlibChatMember {
  const TdlibChatMember({
    required this.userId,
    required this.displayName,
    this.phoneDigits,
    this.isAdmin = false,
  });

  final int userId;
  final String displayName;
  final String? phoneDigits;
  final bool isAdmin;
}

class TdlibUserPresence {
  const TdlibUserPresence({
    required this.userId,
    required this.isOnline,
    this.wasOnlineEpoch,
  });

  final int userId;
  final bool isOnline;
  final int? wasOnlineEpoch;

  String get label {
    if (isOnline) return 'online';
    if (wasOnlineEpoch == null || wasOnlineEpoch! <= 0) return 'visto recentemente';
    final dt = DateTime.fromMillisecondsSinceEpoch(wasOnlineEpoch! * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return 'visto há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'visto há ${diff.inHours} h';
    return 'visto ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

class TdlibSessionInfo {
  const TdlibSessionInfo({
    required this.id,
    required this.deviceModel,
    required this.platform,
    required this.appName,
    required this.isCurrent,
    this.ipAddress,
    this.country,
    this.lastActiveEpoch,
  });

  final int id;
  final String deviceModel;
  final String platform;
  final String appName;
  final bool isCurrent;
  final String? ipAddress;
  final String? country;
  final int? lastActiveEpoch;
}

class TdlibSearchHit {
  const TdlibSearchHit({
    required this.chatId,
    required this.chatTitle,
    required this.message,
  });

  final int chatId;
  final String chatTitle;
  final TdlibMessageItem message;
}

class TdlibSyncDashboardStats {
  const TdlibSyncDashboardStats({
    required this.departmentsReady,
    required this.departmentsTotal,
    required this.membersWithPhone,
    required this.membersWithoutPhone,
    required this.membersTotal,
    this.lastSyncLabel = '',
  });

  final int departmentsReady;
  final int departmentsTotal;
  final int membersWithPhone;
  final int membersWithoutPhone;
  final int membersTotal;
  final String lastSyncLabel;
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
    this.mediaThumbFileId,
    this.mediaThumbLocalPath,
    this.replyToMessageId,
    this.isRead = false,
    this.isEdited = false,
    this.isForwarded = false,
    this.isPinned = false,
    this.fileSize,
    this.mimeType,
    this.fileName,
    this.sendStatus = TdlibSendStatus.sent,
    this.replyPreview,
    this.localPendingPath,
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
  final int? mediaThumbFileId;
  final String? mediaThumbLocalPath;

  final int? replyToMessageId;
  final bool isRead;
  final bool isEdited;
  final bool isForwarded;
  final bool isPinned;
  final int? fileSize;
  final String? mimeType;
  final String? fileName;
  final TdlibSendStatus sendStatus;
  final String? replyPreview;
  final String? localPendingPath;

  bool get hasMedia => mediaKind != null;
  bool get isPending => sendStatus == TdlibSendStatus.sending;
  bool get isFailed => sendStatus == TdlibSendStatus.failed;

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
    int? mediaThumbFileId,
    String? mediaThumbLocalPath,
    int? replyToMessageId,
    bool? isRead,
    bool? isEdited,
    bool? isForwarded,
    bool? isPinned,
    int? fileSize,
    String? mimeType,
    String? fileName,
    TdlibSendStatus? sendStatus,
    String? replyPreview,
    String? localPendingPath,
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
        mediaThumbFileId: mediaThumbFileId ?? this.mediaThumbFileId,
        mediaThumbLocalPath:
            mediaThumbLocalPath ?? this.mediaThumbLocalPath,
        replyToMessageId: replyToMessageId ?? this.replyToMessageId,
        isRead: isRead ?? this.isRead,
        isEdited: isEdited ?? this.isEdited,
        isForwarded: isForwarded ?? this.isForwarded,
        isPinned: isPinned ?? this.isPinned,
        fileSize: fileSize ?? this.fileSize,
        mimeType: mimeType ?? this.mimeType,
        fileName: fileName ?? this.fileName,
        sendStatus: sendStatus ?? this.sendStatus,
        replyPreview: replyPreview ?? this.replyPreview,
        localPendingPath: localPendingPath ?? this.localPendingPath,
      );
}
