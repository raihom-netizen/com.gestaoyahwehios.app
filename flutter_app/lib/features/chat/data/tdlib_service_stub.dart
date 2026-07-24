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

  TdlibAuthSnapshot _snapshot = TdlibAuthSnapshot.unsupported;
  String _boundChurchId = '';

  bool get isInitialized => false;
  bool get isSupported => false;
  String get boundChurchId => _boundChurchId;
  TdlibAuthSnapshot get currentAuth => _snapshot;

  Stream<TdlibAuthSnapshot> get authorizationStateStream =>
      _authController.stream;
  Stream<List<TdlibChatPreview>> get chatsStream => _chatsController.stream;
  Stream<List<TdlibMessageItem>> get messagesStream =>
      _messagesController.stream;

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
  }) async {
    throw UnsupportedError('TDLib não disponível na Web');
  }

  Future<void> dispose() async {
    await _authController.close();
    await _chatsController.close();
    await _messagesController.close();
  }
}
