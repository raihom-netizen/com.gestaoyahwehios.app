import 'dart:async';

import 'tdlib_auth_state.dart';

/// Stub Web / plataformas sem FFI — mesma API pública do IO.
class TdLibService {
  TdLibService._();
  static final TdLibService instance = TdLibService._();

  final _authController =
      StreamController<TdlibAuthSnapshot>.broadcast(sync: true);
  final _chatsController =
      StreamController<List<TdlibChatPreview>>.broadcast(sync: true);
  final _messagesController =
      StreamController<List<TdlibMessageItem>>.broadcast(sync: true);
  final _peerActionController =
      StreamController<TdlibPeerAction>.broadcast(sync: true);
  final _presenceController =
      StreamController<TdlibUserPresence>.broadcast(sync: true);

  TdlibAuthSnapshot _snapshot = TdlibAuthSnapshot.unsupported;
  String _boundChurchId = '';

  bool get isInitialized => false;
  bool get isSupported => false;
  String get boundChurchId => _boundChurchId;
  TdlibAuthSnapshot get currentAuth => _snapshot;
  List<TdlibChatPreview> get cachedChats => const [];

  Stream<TdlibAuthSnapshot> get authorizationStateStream =>
      _authController.stream;
  Stream<List<TdlibChatPreview>> get chatsStream => _chatsController.stream;
  Stream<List<TdlibMessageItem>> get messagesStream =>
      _messagesController.stream;
  Stream<TdlibPeerAction> get peerActionsStream =>
      _peerActionController.stream;
  Stream<TdlibUserPresence> get presenceStream => _presenceController.stream;

  Future<void> init({String churchId = ''}) async {
    _boundChurchId = churchId.trim();
    _snapshot = TdlibAuthSnapshot.unsupported;
    _authController.add(_snapshot);
  }

  Future<void> sendPhoneNumber(String phone) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> sendCode(String code) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> sendPassword(String password) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> refreshChats({int limit = 40}) async {}

  Future<void> warmTopChats({int count = 8}) async {}

  Future<void> ensureChatPhoto(int chatId) async {}

  Future<TdlibMessageItem?> refreshPinnedMessage(int chatId) async => null;

  TdlibMessageItem? peekPinnedMessage(int chatId) => null;

  Future<String?> getOrCreateInviteLink(int chatId) async => null;

  Future<int> openPrivateChatByPhone(String phoneRaw) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<int> joinByInviteLink(String inviteUrl) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<({int chatId, String? inviteLink})> createDepartmentSupergroup({
    required String title,
    String description = '',
  }) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<bool> addChatMemberByPhone(int chatId, String phoneRaw) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<List<TdlibMessageItem>> loadChatHistory(
    int chatId, {
    int limit = 40,
    bool preferLocalFirst = true,
    bool setActive = true,
  }) async =>
      const [];

  Future<void> sendTextMessage(int chatId, String text) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> sendLocalFile(
    int chatId,
    String localPath, {
    required String kind,
    String caption = '',
    int? replyToMessageId,
  }) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> sendTextReply(
    int chatId,
    String text, {
    required int replyToMessageId,
  }) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> deleteMessages(int chatId, List<int> messageIds) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> editMessageText(
    int chatId,
    int messageId,
    String newText,
  ) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> forwardMessages(
    int toChatId,
    int fromChatId,
    List<int> messageIds,
  ) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<String?> ensureMediaDownloaded(
    TdlibMessageItem message, {
    int priority = 16,
  }) async {
    final path = (message.mediaLocalPath ?? '').trim();
    return path.isEmpty ? null : path;
  }

  Future<void> markAsRead(int chatId, List<int> messageIds) async {}

  Future<void> sendChatAction(
    int chatId, {
    bool recordingVoice = false,
  }) async {}

  Future<void> cancelChatAction(int chatId) async {}

  Future<void> removeChatMember(int chatId, int userId) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<List<TdlibMessageItem>> searchChatMessages(
    int chatId,
    String query, {
    int limit = 40,
  }) async =>
      const [];

  Future<List<TdlibChatMember>> getChatMembers(
    int chatId, {
    int limit = 100,
  }) async =>
      const [];

  Future<void> setChatMuted(int chatId, bool muted) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  void upsertLocalMessage(TdlibMessageItem item) {}

  void removeLocalMessage(int chatId, int messageId) {}

  Future<void> configureNotificationOptions() async {}

  Future<void> registerPushDevice(
    String fcmToken, {
    String? apnsTokenHex,
    bool apnsSandbox = false,
  }) async {}

  Future<void> processPushNotification(String payload) async {}

  Future<List<TdlibMessageItem>> loadOlderMessages(
    int chatId, {
    int limit = 40,
  }) async =>
      const [];

  Future<TdlibUserPresence?> refreshChatPresence(int chatId) async => null;

  TdlibUserPresence? peekPresenceForChat(int chatId) => null;

  Future<List<TdlibSearchHit>> searchMessagesGlobal(
    String query, {
    int limit = 40,
  }) async =>
      const [];

  Future<List<TdlibSessionInfo>> getActiveSessions() async => const [];

  Future<void> terminateSession(int sessionId) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> terminateAllOtherSessions() async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> addMessageReaction(
    int chatId,
    int messageId,
    String emoji,
  ) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> prefetchChatPhotos({int limit = 20}) async {}

  Future<void> dispose() async {
    await _authController.close();
    await _chatsController.close();
    await _messagesController.close();
    await _peerActionController.close();
    await _presenceController.close();
  }
}
