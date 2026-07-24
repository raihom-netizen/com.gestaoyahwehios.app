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

/// Mensagem leve para a thread Yahweh Chat (TDLib).
class TdlibMessageItem {
  const TdlibMessageItem({
    required this.id,
    required this.chatId,
    required this.isOutgoing,
    required this.preview,
    this.dateEpoch,
  });

  final int id;
  final int chatId;
  final bool isOutgoing;
  final String preview;
  final int? dateEpoch;
}
