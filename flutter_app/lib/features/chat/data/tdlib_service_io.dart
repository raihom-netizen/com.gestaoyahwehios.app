import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:libtdjson/libtdjson.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/features/chat/data/tdlib_background_push.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_chat_local_prefs.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_ios_gate.dart';
import 'package:gestao_yahweh/services/church_chat_alert_notification_service.dart';

import 'tdlib_auth_state.dart';
import 'tdlib_credentials.dart';

/// Motor TDLib (libtdjson) — singleton.
///
/// O pacote [libtdjson] já recebe updates num **Isolate** (`RawService`).
/// Aqui encapsulamos auth + lista de chats para a UI YAHWEH.
class TdLibService {
  TdLibService._();
  static final TdLibService instance = TdLibService._();

  td.Service? _service;
  bool _starting = false;
  String _boundChurchId = '';

  final _authController =
      StreamController<TdlibAuthSnapshot>.broadcast(sync: true);
  final _chatsController =
      StreamController<List<TdlibChatPreview>>.broadcast(sync: true);
  final _messagesController =
      StreamController<List<TdlibMessageItem>>.broadcast(sync: true);
  final _peerActionController =
      StreamController<TdlibPeerAction>.broadcast(sync: true);

  final Map<int, TdlibChatPreview> _chatsById = {};
  final Map<int, List<TdlibMessageItem>> _messagesByChat = {};
  final Map<int, TdlibMessageItem?> _pinnedByChat = {};
  final Map<int, TdlibUserPresence> _presenceByUser = {};
  final Map<int, int> _privateChatUserId = {};
  int? _activeChatId;
  TdlibAuthSnapshot _snapshot = TdlibAuthSnapshot.idle;
  bool _warming = false;
  final _presenceController =
      StreamController<TdlibUserPresence>.broadcast(sync: true);

  bool get isInitialized => _service != null;
  String get boundChurchId => _boundChurchId;
  bool get isSupported {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isMacOS) return true;
    if (Platform.isIOS) return TdlibIosGate.shouldAttemptNativeOnIos;
    return false;
  }
  TdlibAuthSnapshot get currentAuth => _snapshot;
  List<TdlibChatPreview> get cachedChats =>
      List<TdlibChatPreview>.from(_chatsById.values);

  Stream<TdlibAuthSnapshot> get authorizationStateStream =>
      _authController.stream;
  Stream<List<TdlibChatPreview>> get chatsStream => _chatsController.stream;
  Stream<List<TdlibMessageItem>> get messagesStream =>
      _messagesController.stream;
  Stream<TdlibPeerAction> get peerActionsStream =>
      _peerActionController.stream;
  Stream<TdlibUserPresence> get presenceStream => _presenceController.stream;

  /// Inicia o motor com sessão **separada por igreja** (DB local isolado).
  Future<void> init({String churchId = ''}) async {
    final cid = churchId.trim();
    if (_service != null &&
        _boundChurchId == cid &&
        _snapshot.phase != TdlibAuthPhase.closed &&
        _snapshot.phase != TdlibAuthPhase.error) {
      _emitAuth(_snapshot);
      return;
    }
    if (_service != null && _boundChurchId != cid) {
      await _softResetSession();
    }
    if (_starting) {
      _emitAuth(_snapshot);
      return;
    }
    if (kIsWeb || !isSupported) {
      _emitAuth(TdlibAuthSnapshot.unsupported);
      return;
    }
    await ensureTelegramCredentialsLoaded();
    if (!kTelegramCredentialsConfigured) {
      _emitAuth(const TdlibAuthSnapshot(
        phase: TdlibAuthPhase.error,
        message:
            'Credenciais TDLib ausentes. No painel Master → Telegram / TDLib '
            'grave api_id e api_hash (my.telegram.org/apps), ou use '
            'flutter_app/.env / dart-define no build.',
      ));
      return;
    }

    _starting = true;
    _boundChurchId = cid;
    _emitAuth(const TdlibAuthSnapshot(
      phase: TdlibAuthPhase.initializing,
      message: 'Iniciando motor Telegram (TDLib)…',
    ));
    unawaited(_restoreChatListCache(cid));

    try {
      final support = await getApplicationSupportDirectory();
      final churchKey = cid.isEmpty ? 'default' : cid;
      final dbDir =
          Directory(p.join(support.path, 'tdlib', churchKey, 'db'));
      final filesDir =
          Directory(p.join(support.path, 'tdlib', churchKey, 'files'));
      await dbDir.create(recursive: true);
      await filesDir.create(recursive: true);
      unawaited(
        TdlibBackgroundPushStore.saveSessionPaths(
          churchId: cid,
          dbDir: dbDir.path,
          filesDir: filesDir.path,
        ),
      );

      final params = <String, dynamic>{
        'api_id': telegramApiId,
        'api_hash': telegramApiHash,
        'database_directory': dbDir.path,
        'files_directory': filesDir.path,
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': true,
        'use_secret_chats': false,
        'system_language_code': telegramSystemLanguageCode,
        'device_model': telegramDeviceModel,
        'system_version': Platform.operatingSystemVersion,
        'application_version': '11.2.305',
      };

      final useProcess = Platform.isIOS || Platform.isMacOS;
      _service = td.Service(
        tdlibParameters: params,
        file: useProcess ? null : 'libtdjson.so',
        newVerbosityLevel: kDebugMode ? 1 : 0,
        timeout: 10,
        start: true,
        afterReceive: _onReceive,
        onReceiveError: (err) {
          debugPrint('[TdLib] error ${err.code}: ${err.message}');
          if (_snapshot.phase == TdlibAuthPhase.initializing ||
              _snapshot.phase == TdlibAuthPhase.waitPhoneNumber ||
              _snapshot.phase == TdlibAuthPhase.waitCode ||
              _snapshot.phase == TdlibAuthPhase.waitPassword) {
            _emitAuth(_snapshot.copyWith(
              phase: TdlibAuthPhase.error,
              message: err.message.isEmpty
                  ? 'Erro TDLib (${err.code})'
                  : err.message,
            ));
          }
        },
        onStreamError: (e) {
          debugPrint('[TdLib] stream error: $e');
        },
      );
    } catch (e, st) {
      debugPrint('[TdLib] init falhou: $e\n$st');
      // iOS: linker/plugin ausente → fallback Telegram embutido (sem crash).
      if (Platform.isIOS) {
        _emitAuth(TdlibAuthSnapshot.unsupported.copyWith(
          message:
              'TDLib iOS indisponível neste build — usando Telegram embutido '
              '(mesma conta). Android mantém motor nativo.',
        ));
      } else {
        _emitAuth(TdlibAuthSnapshot(
          phase: TdlibAuthPhase.error,
          message: 'Falha ao carregar libtdjson: $e',
        ));
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _softResetSession() async {
    try {
      await _service?.stop();
    } catch (_) {}
    _service = null;
    _chatsById.clear();
    _messagesByChat.clear();
    _pinnedByChat.clear();
    _activeChatId = null;
    _boundChurchId = '';
    _emitChats();
  }

  Future<void> _restoreChatListCache(String churchId) async {
    if (churchId.trim().isEmpty) return;
    final cached = await TdlibChatLocalPrefs.loadChatList(churchId);
    if (cached.isEmpty) return;
    for (final c in cached) {
      _chatsById.putIfAbsent(c.id, () => c);
    }
    _emitChats(persist: false);
  }

  void _onReceive(Map<String, dynamic> obj) {
    final type = obj['@type']?.toString();
    if (type == 'updateAuthorizationState') {
      final auth = obj['authorization_state'];
      if (auth is Map<String, dynamic>) {
        _handleAuthState(auth);
      }
      return;
    }
    if (type == 'updateFile') {
      final file = obj['file'];
      if (file is Map) {
        _applyFileUpdate(Map<String, dynamic>.from(file));
      }
      return;
    }
    if (type == 'updateNewChat' || type == 'updateChatTitle') {
      _ingestChatObject(obj['chat'] is Map
          ? Map<String, dynamic>.from(obj['chat'] as Map)
          : obj);
      return;
    }
    if (type == 'updateChatLastMessage') {
      final chatId = _asInt(obj['chat_id']);
      if (chatId == null) return;
      final prev = _chatsById[chatId];
      final last = obj['last_message'];
      final lastMap =
          last is Map ? Map<String, dynamic>.from(last) : null;
      final preview = _previewFromMessage(lastMap);
      final date = lastMap == null ? null : _asInt(lastMap['date']);
      if (prev != null) {
        _chatsById[chatId] = prev.copyWith(
          lastMessagePreview: preview ?? prev.lastMessagePreview,
          lastMessageDateEpoch: date ?? prev.lastMessageDateEpoch,
        );
        _emitChats();
      }
      return;
    }
    if (type == 'updateNewMessage') {
      final msg = obj['message'];
      if (msg is Map) {
        _ingestMessage(Map<String, dynamic>.from(msg));
      }
      return;
    }
    if (type == 'updateMessageSendSucceeded') {
      final msg = obj['message'];
      if (msg is Map) {
        _ingestMessage(Map<String, dynamic>.from(msg));
      }
      return;
    }
    if (type == 'updateMessageSendFailed') {
      final oldId = _asInt(obj['old_message_id']);
      final chatId = _asInt(obj['message'] is Map
          ? (obj['message'] as Map)['chat_id']
          : obj['chat_id']);
      if (oldId != null && chatId != null) {
        final list = _messagesByChat[chatId];
        if (list != null) {
          _messagesByChat[chatId] = list
              .map(
                (m) => m.id == oldId
                    ? m.copyWith(sendStatus: TdlibSendStatus.failed)
                    : m,
              )
              .toList();
          if (_activeChatId == chatId) _emitMessages(chatId);
        }
      }
      return;
    }
    if (type == 'updateChatAction') {
      final chatId = _asInt(obj['chat_id']);
      if (chatId == null) return;
      final action = obj['action'];
      final actionType =
          action is Map ? (action['@type'] ?? '').toString() : '';
      TdlibPeerActionKind kind;
      if (actionType.contains('Typing')) {
        kind = TdlibPeerActionKind.typing;
      } else if (actionType.contains('RecordingVoice')) {
        kind = TdlibPeerActionKind.recordingVoice;
      } else {
        kind = TdlibPeerActionKind.cancel;
      }
      if (!_peerActionController.isClosed) {
        _peerActionController.add(
          TdlibPeerAction(chatId: chatId, kind: kind),
        );
      }
      return;
    }
    if (type == 'updateUserStatus') {
      final userId = _asInt(obj['user_id']);
      final status = obj['status'];
      if (userId == null || status is! Map) return;
      final st = (status['@type'] ?? '').toString();
      final presence = TdlibUserPresence(
        userId: userId,
        isOnline: st.contains('Online'),
        wasOnlineEpoch: _asInt(status['was_online']),
      );
      _presenceByUser[userId] = presence;
      if (!_presenceController.isClosed) _presenceController.add(presence);
      return;
    }
    if (type == 'updateNotificationGroup') {
      unawaited(_handleNotificationGroup(obj));
      return;
    }
  }

  Future<void> _handleNotificationGroup(Map<String, dynamic> obj) async {
    try {
      final chatId = _asInt(obj['chat_id']) ?? 0;
      if (chatId != 0 && _activeChatId == chatId) return;
      final added = obj['added_notifications'];
      if (added is! List || added.isEmpty) return;
      String title = _chatsById[chatId]?.title ?? 'Yahweh Chat';
      var body = 'Nova mensagem';
      for (final raw in added) {
        if (raw is! Map) continue;
        final type = raw['type'];
        if (type is Map) {
          final t = (type['@type'] ?? '').toString();
          if (t.contains('NewMessage') || t.contains('NewPushMessage')) {
            final msg = type['message'];
            if (msg is Map) {
              body = _previewFromMessage(Map<String, dynamic>.from(msg)) ??
                  body;
            } else {
              final content = type['content'];
              if (content is Map) {
                body = _previewFromMessage({
                      'content': content,
                    }) ??
                    body;
              }
            }
          }
        }
      }
      if (chatId != 0) {
        final churchId = _boundChurchId.trim();
        if (churchId.isNotEmpty &&
            await TdlibChatLocalPrefs.isMuted(churchId, chatId)) {
          return;
        }
      }
      await ChurchChatAlertNotificationService.instance.showTdlibLocalAlert(
        title: title,
        body: body,
        chatId: chatId,
      );
    } catch (e) {
      debugPrint('[TdLib] notificationGroup: $e');
    }
  }

  void _handleAuthState(Map<String, dynamic> auth) {
    final raw = auth['@type']?.toString() ?? '';
    switch (raw) {
      case 'authorizationStateWaitTdlibParameters':
        // Tratado pelo libtdjson.Service
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.initializing,
          rawType: 'authorizationStateWaitTdlibParameters',
          message: 'Configurando parâmetros…',
        ));
        break;
      case 'authorizationStateWaitPhoneNumber':
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.waitPhoneNumber,
          rawType: 'authorizationStateWaitPhoneNumber',
          message: 'Informe o telefone (com DDI, ex.: +5562…)',
        ));
        break;
      case 'authorizationStateWaitCode':
        final info = auth['code_info'];
        String? hint;
        if (info is Map) {
          final type = info['type'];
          if (type is Map) {
            hint = type['@type']?.toString();
          }
        }
        _emitAuth(TdlibAuthSnapshot(
          phase: TdlibAuthPhase.waitCode,
          rawType: raw,
          message: 'Digite o código recebido no Telegram ou por SMS',
          codeInfoHint: hint,
        ));
        break;
      case 'authorizationStateWaitPassword':
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.waitPassword,
          rawType: 'authorizationStateWaitPassword',
          message: 'Senha 2FA (verificação em duas etapas)',
        ));
        break;
      case 'authorizationStateWaitRegistration':
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.waitRegistration,
          rawType: 'authorizationStateWaitRegistration',
          message: 'Conta nova — cadastro ainda não suportado neste fluxo',
        ));
        break;
      case 'authorizationStateWaitOtherDeviceConfirmation':
        final link = auth['link']?.toString();
        _emitAuth(TdlibAuthSnapshot(
          phase: TdlibAuthPhase.waitOtherDeviceConfirmation,
          rawType: raw,
          message: link == null || link.isEmpty
              ? 'Confirme o login em outro dispositivo'
              : 'Confirme o login: $link',
        ));
        break;
      case 'authorizationStateReady':
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.ready,
          rawType: 'authorizationStateReady',
          message: 'Conectado ao Motor YAHWEH',
        ));
        unawaited(refreshChats().then((_) => warmTopChats()));
        break;
      case 'authorizationStateLoggingOut':
        _emitAuth(const TdlibAuthSnapshot(
          phase: TdlibAuthPhase.loggingOut,
          rawType: 'authorizationStateLoggingOut',
        ));
        break;
      case 'authorizationStateClosing':
      case 'authorizationStateClosed':
        _chatsById.clear();
        _emitChats();
        _emitAuth(TdlibAuthSnapshot(
          phase: TdlibAuthPhase.closed,
          rawType: raw,
          message: 'Sessão TDLib encerrada',
        ));
        break;
      default:
        _emitAuth(TdlibAuthSnapshot(
          phase: TdlibAuthPhase.initializing,
          rawType: raw,
          message: 'Estado: $raw',
        ));
    }
  }

  Future<void> sendPhoneNumber(String phone) async {
    final svc = _requireService();
    final normalized = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    await svc.sendSync({
      '@type': 'setAuthenticationPhoneNumber',
      'phone_number': normalized,
      'settings': {
        '@type': 'phoneNumberAuthenticationSettings',
        'allow_flash_call': false,
        'allow_missed_call': false,
        'is_current_phone_number': false,
        'has_unknown_phone_number': false,
        'allow_sms_retriever_api': false,
      },
    });
  }

  Future<void> sendCode(String code) async {
    final svc = _requireService();
    await svc.sendSync({
      '@type': 'checkAuthenticationCode',
      'code': code.trim(),
    });
  }

  Future<void> sendPassword(String password) async {
    final svc = _requireService();
    await svc.sendSync({
      '@type': 'checkAuthenticationPassword',
      'password': password,
    });
  }

  Future<void> refreshChats({int limit = 40}) async {
    final svc = _service;
    if (svc == null || _snapshot.phase != TdlibAuthPhase.ready) return;
    try {
      await svc.sendSync({
        '@type': 'loadChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': limit,
      });
      final result = await svc.sendSync({
        '@type': 'getChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': limit,
      });
      final ids = (result['chat_ids'] as List?) ?? const [];
      for (final rawId in ids) {
        final id = _asInt(rawId);
        if (id == null) continue;
        try {
          final chat = await svc.sendSync({
            '@type': 'getChat',
            'chat_id': id,
          });
          _ingestChatObject(chat);
        } catch (_) {}
      }
      _emitChats();
    } catch (e) {
      debugPrint('[TdLib] refreshChats: $e');
    }
  }

  /// Abre DM pelo telefone do cadastro (sem colar link).
  Future<int> openPrivateChatByPhone(String phoneRaw) async {
    final svc = _requireService();
    if (_snapshot.phase != TdlibAuthPhase.ready) {
      throw StateError('TDLib ainda não está pronto.');
    }
    var digits = phoneRaw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      throw ArgumentError('Telefone inválido para abrir conversa.');
    }
    if (!digits.startsWith('55') && digits.length <= 11) {
      digits = '55$digits';
    }
    final phone = '+$digits';

    final user = await svc.sendSync({
      '@type': 'searchUserByPhoneNumber',
      'phone_number': phone,
    });
    final userId = _asInt(user['id']);
    if (userId == null) {
      throw StateError(
        'Contato não encontrado no Telegram com este telefone.',
      );
    }
    final chat = await svc.sendSync({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': true,
    });
    final chatId = _asInt(chat['id']);
    if (chatId == null) {
      throw StateError('Não foi possível abrir a conversa privada.');
    }
    _ingestChatObject(chat);
    return chatId;
  }

  /// Entra em grupo/canal pelo link de convite (gerado/salvo pela gestão).
  Future<int> joinByInviteLink(String inviteUrl) async {
    final svc = _requireService();
    final chat = await svc.sendSync({
      '@type': 'joinChatByInviteLink',
      'invite_link': inviteUrl.trim(),
    });
    final chatId = _asInt(chat['id']);
    if (chatId == null) {
      throw StateError('Não foi possível entrar no grupo.');
    }
    _ingestChatObject(chat);
    return chatId;
  }

  /// Cria supergrupo do departamento (gestão — sem colar link).
  Future<({int chatId, String? inviteLink})> createDepartmentSupergroup({
    required String title,
    String description = '',
  }) async {
    final svc = _requireService();
    if (_snapshot.phase != TdlibAuthPhase.ready) {
      throw StateError('TDLib ainda não está pronto.');
    }
    final name = title.trim();
    if (name.isEmpty) {
      throw ArgumentError('Nome do grupo vazio.');
    }
    final chat = await svc.sendSync({
      '@type': 'createNewSupergroupChat',
      'title': name,
      'is_forum': false,
      'is_channel': false,
      'description': description.trim(),
      // TDLib exige o campo; null = grupo normal (sem localização).
      'location': null,
      'message_auto_delete_time': 0,
      'for_import': false,
    });
    final chatId = _asInt(chat['id']);
    if (chatId == null) {
      throw StateError('Não foi possível criar o grupo Telegram.');
    }
    _ingestChatObject(chat);

    String? invite;
    try {
      final link = await svc.sendSync({
        '@type': 'createChatInviteLink',
        'chat_id': chatId,
        'name': 'Yahweh',
        'expiration_date': 0,
        'member_limit': 0,
        'creates_join_request': false,
      });
      invite = (link['invite_link'] ?? '').toString().trim();
      if (invite.isEmpty) invite = null;
    } catch (e) {
      debugPrint('[TdLib] createChatInviteLink: $e');
    }
    return (chatId: chatId, inviteLink: invite);
  }

  /// Convida membro ao grupo pelo telefone do cadastro (best-effort).
  Future<bool> addChatMemberByPhone(int chatId, String phoneRaw) async {
    final svc = _requireService();
    var digits = phoneRaw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return false;
    if (!digits.startsWith('55') && digits.length <= 11) {
      digits = '55$digits';
    }
    try {
      final user = await svc.sendSync({
        '@type': 'searchUserByPhoneNumber',
        'phone_number': '+$digits',
      });
      final userId = _asInt(user['id']);
      if (userId == null) return false;
      await svc.sendSync({
        '@type': 'addChatMember',
        'chat_id': chatId,
        'user_id': userId,
        'forward_limit': 0,
      });
      return true;
    } catch (e) {
      debugPrint('[TdLib] addChatMemberByPhone: $e');
      return false;
    }
  }

  Future<List<TdlibMessageItem>> loadChatHistory(
    int chatId, {
    int limit = 40,
    bool preferLocalFirst = true,
    bool setActive = true,
  }) async {
    final svc = _requireService();
    if (setActive) _activeChatId = chatId;

    Future<List<TdlibMessageItem>> fetch(bool onlyLocal) async {
      final result = await svc.sendSync({
        '@type': 'getChatHistory',
        'chat_id': chatId,
        'from_message_id': 0,
        'offset': 0,
        'limit': limit,
        'only_local': onlyLocal,
      });
      final messages = (result['messages'] as List?) ?? const [];
      final items = <TdlibMessageItem>[];
      for (final raw in messages) {
        if (raw is! Map) continue;
        final item = _messageFromMap(Map<String, dynamic>.from(raw));
        if (item != null) items.add(item);
      }
      items.sort((a, b) => a.id.compareTo(b.id));
      return items;
    }

    if (preferLocalFirst) {
      try {
        final local = await fetch(true);
        if (local.isNotEmpty) {
          _messagesByChat[chatId] = local;
          if (setActive || _activeChatId == chatId) _emitMessages(chatId);
        }
      } catch (_) {}
    }

    final remote = await fetch(false);
    _messagesByChat[chatId] = remote;
    if (setActive || _activeChatId == chatId) _emitMessages(chatId);
    unawaited(refreshPinnedMessage(chatId));
    return remote;
  }

  /// Pré-aquece os chats mais recentes (histórico local + foto).
  Future<void> warmTopChats({int count = 8}) async {
    if (_warming || _snapshot.phase != TdlibAuthPhase.ready) return;
    _warming = true;
    try {
      final sorted = _chatsById.values.toList()
        ..sort(
          (a, b) => (b.lastMessageDateEpoch ?? 0)
              .compareTo(a.lastMessageDateEpoch ?? 0),
        );
      for (final c in sorted.take(count)) {
        try {
          await loadChatHistory(
            c.id,
            limit: 24,
            preferLocalFirst: true,
            setActive: false,
          );
        } catch (_) {}
        unawaited(ensureChatPhoto(c.id));
      }
    } finally {
      _warming = false;
    }
  }

  Future<void> ensureChatPhoto(int chatId) async {
    final prev = _chatsById[chatId];
    final fileId = prev?.photoFileId;
    if (fileId == null || fileId == 0) return;
    final path = (prev?.photoLocalPath ?? '').trim();
    if (path.isNotEmpty && await File(path).exists()) return;
    try {
      final result = await _requireService().sendSync({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 8,
        'offset': 0,
        'limit': 0,
        'synchronous': true,
      });
      final local = result['local'];
      if (local is! Map || local['is_downloading_completed'] != true) return;
      final pth = (local['path'] ?? '').toString().trim();
      if (pth.isEmpty || prev == null) return;
      _chatsById[chatId] = prev.copyWith(photoLocalPath: pth);
      _emitChats();
    } catch (e) {
      debugPrint('[TdLib] ensureChatPhoto: $e');
    }
  }

  Future<TdlibMessageItem?> refreshPinnedMessage(int chatId) async {
    try {
      final result = await _requireService().sendSync({
        '@type': 'getChatPinnedMessage',
        'chat_id': chatId,
      });
      final item = _messageFromMap(result)?.copyWith(isPinned: true);
      _pinnedByChat[chatId] = item;
      return item;
    } catch (_) {
      _pinnedByChat[chatId] = null;
      return null;
    }
  }

  TdlibMessageItem? peekPinnedMessage(int chatId) => _pinnedByChat[chatId];

  Future<String?> getOrCreateInviteLink(int chatId) async {
    try {
      final result = await _requireService().sendSync({
        '@type': 'createChatInviteLink',
        'chat_id': chatId,
        'name': 'Yahweh',
        'expiration_date': 0,
        'member_limit': 0,
        'creates_join_request': false,
      });
      final link = (result['invite_link'] ?? '').toString().trim();
      return link.isEmpty ? null : link;
    } catch (e) {
      debugPrint('[TdLib] getOrCreateInviteLink: $e');
      return null;
    }
  }

  /// Solicita o download pelo próprio motor Telegram e devolve o ficheiro
  /// local somente quando o TDLib concluir a transferência.
  Future<String?> ensureMediaDownloaded(
    TdlibMessageItem message, {
    int priority = 16,
  }) async {
    final current = (message.mediaLocalPath ?? '').trim();
    if (current.isNotEmpty && await File(current).exists()) return current;
    final fileId = message.mediaFileId;
    if (fileId == null || fileId == 0) return null;
    final result = await _requireService().sendSync({
      '@type': 'downloadFile',
      'file_id': fileId,
      'priority': priority.clamp(1, 32),
      'offset': 0,
      'limit': 0,
      'synchronous': true,
    });
    _applyFileUpdate(result);
    final local = result['local'];
    if (local is! Map || local['is_downloading_completed'] != true) return null;
    final path = (local['path'] ?? '').toString().trim();
    return path.isEmpty ? null : path;
  }

  Future<void> sendTextMessage(int chatId, String text) async {
    final svc = _requireService();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await svc.sendSync({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': trimmed,
        },
      },
    });
  }

  /// Envia foto/vídeo/arquivo local (motor Telegram).
  Future<void> sendLocalFile(
    int chatId,
    String localPath, {
    required String kind, // photo | video | document | voice
    String caption = '',
    int? replyToMessageId,
  }) async {
    final svc = _requireService();
    final path = localPath.trim();
    if (path.isEmpty) {
      throw StateError(
        'Não foi possível anexar o ficheiro. Escolha a foto ou o vídeo de novo.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError(
        'Não foi possível anexar o ficheiro. Escolha a foto ou o vídeo de novo.',
      );
    }
    final inputFile = {
      '@type': 'inputFileLocal',
      'path': file.absolute.path,
    };
    Map<String, dynamic> content;
    switch (kind) {
      case 'photo':
        content = {
          '@type': 'inputMessagePhoto',
          'photo': inputFile,
          if (caption.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': caption.trim(),
            },
        };
        break;
      case 'video':
        content = {
          '@type': 'inputMessageVideo',
          'video': inputFile,
          if (caption.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': caption.trim(),
            },
        };
        break;
      case 'voice':
        content = {
          '@type': 'inputMessageVoiceNote',
          'voice_note': inputFile,
        };
        break;
      default:
        content = {
          '@type': 'inputMessageDocument',
          'document': inputFile,
          if (caption.trim().isNotEmpty)
            'caption': {
              '@type': 'formattedText',
              'text': caption.trim(),
            },
        };
    }
    await svc.sendSync({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'input_message_content': content,
      if (replyToMessageId != null)
        'reply_to_message_id': replyToMessageId,
    });
  }

  /// Envia texto com reply (resposta a outra mensagem).
  Future<void> sendTextReply(
    int chatId,
    String text, {
    required int replyToMessageId,
  }) async {
    final svc = _requireService();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await svc.sendSync({
      '@type': 'sendMessage',
      'chat_id': chatId,
      'reply_to_message_id': replyToMessageId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': trimmed,
        },
      },
    });
  }

  /// Apaga mensagens para todos (revoke = true).
  Future<void> deleteMessages(int chatId, List<int> messageIds) async {
    final svc = _requireService();
    if (messageIds.isEmpty) return;
    await svc.sendSync({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': messageIds,
      'revoke': true,
    });
  }

  /// Edita texto de mensagem existente.
  Future<void> editMessageText(
    int chatId,
    int messageId,
    String newText,
  ) async {
    final svc = _requireService();
    await svc.sendSync({
      '@type': 'editMessageText',
      'chat_id': chatId,
      'message_id': messageId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {
          '@type': 'formattedText',
          'text': newText.trim(),
        },
      },
    });
  }

  /// Encaminha mensagens de um chat para outro.
  Future<void> forwardMessages(
    int toChatId,
    int fromChatId,
    List<int> messageIds,
  ) async {
    final svc = _requireService();
    if (messageIds.isEmpty) return;
    await svc.sendSync({
      '@type': 'forwardMessages',
      'chat_id': toChatId,
      'from_chat_id': fromChatId,
      'message_ids': messageIds,
    });
  }

  /// Marca mensagens como lidas (viewMessages).
  Future<void> markAsRead(int chatId, List<int> messageIds) async {
    final svc = _service;
    if (svc == null || messageIds.isEmpty) return;
    try {
      await svc.sendSync({
        '@type': 'viewMessages',
        'chat_id': chatId,
        'message_ids': messageIds,
        'force_read': true,
      });
    } catch (_) {}
  }

  /// Envia indicador de digitação / gravação de áudio.
  Future<void> sendChatAction(
    int chatId, {
    bool recordingVoice = false,
  }) async {
    final svc = _service;
    if (svc == null) return;
    try {
      await svc.sendSync({
        '@type': 'sendChatAction',
        'chat_id': chatId,
        'action': {
          '@type': recordingVoice
              ? 'chatActionRecordingVoiceNote'
              : 'chatActionTyping',
        },
      });
    } catch (_) {}
  }

  /// Cancela indicador de digitação.
  Future<void> cancelChatAction(int chatId) async {
    final svc = _service;
    if (svc == null) return;
    try {
      await svc.sendSync({
        '@type': 'sendChatAction',
        'chat_id': chatId,
        'action': {'@type': 'chatActionCancel'},
      });
    } catch (_) {}
  }

  /// Remove membro do grupo.
  Future<void> removeChatMember(int chatId, int userId) async {
    final svc = _requireService();
    await svc.sendSync({
      '@type': 'removeChatMember',
      'chat_id': chatId,
      'user_id': userId,
    });
  }

  void _ingestMessage(Map<String, dynamic> msg) {
    final item = _messageFromMap(msg);
    if (item == null) return;
    final list =
        List<TdlibMessageItem>.from(_messagesByChat[item.chatId] ?? const []);
    // Remove pending otimista com mesmo conteúdo recente.
    list.removeWhere(
      (e) =>
          e.id == item.id ||
          (e.id < 0 &&
              e.isOutgoing &&
              item.isOutgoing &&
              e.preview == item.preview),
    );
    list.add(item);
    list.sort((a, b) => a.id.compareTo(b.id));
    _messagesByChat[item.chatId] = list;
    if (_activeChatId == item.chatId) {
      _emitMessages(item.chatId);
    } else if (!item.isOutgoing) {
      unawaited(_notifyIncomingIfNeeded(item));
    }
    final prev = _chatsById[item.chatId];
    if (prev != null) {
      _chatsById[item.chatId] = prev.copyWith(
        lastMessagePreview: item.preview,
        lastMessageDateEpoch: item.dateEpoch ?? prev.lastMessageDateEpoch,
        unreadCount: item.isOutgoing
            ? prev.unreadCount
            : (_activeChatId == item.chatId
                ? prev.unreadCount
                : prev.unreadCount + 1),
      );
      _emitChats();
    }
  }

  Future<void> _notifyIncomingIfNeeded(TdlibMessageItem item) async {
    try {
      final churchId = _boundChurchId.trim();
      if (churchId.isEmpty) return;
      if (await TdlibChatLocalPrefs.isMuted(churchId, item.chatId)) return;
      final title = _chatsById[item.chatId]?.title ?? 'Yahweh Chat';
      await ChurchChatAlertNotificationService.instance.showTdlibLocalAlert(
        title: title,
        body: item.preview,
        chatId: item.chatId,
      );
    } catch (e) {
      debugPrint('[TdLib] notify: $e');
    }
  }

  void _applyFileUpdate(Map<String, dynamic> file) {
    final fileId = _asInt(file['id']);
    final local = file['local'];
    if (fileId == null || local is! Map) return;
    final completed = local['is_downloading_completed'] == true;
    final path = (local['path'] ?? '').toString().trim();
    if (!completed || path.isEmpty) return;
    var chatPhotoChanged = false;
    for (final entry in _chatsById.entries) {
      if (entry.value.photoFileId == fileId) {
        _chatsById[entry.key] = entry.value.copyWith(photoLocalPath: path);
        chatPhotoChanged = true;
      }
    }
    if (chatPhotoChanged) _emitChats();
    for (final entry in _messagesByChat.entries) {
      var changed = false;
      final next = entry.value.map((message) {
        if (message.mediaFileId == fileId) {
          changed = true;
          return message.copyWith(mediaLocalPath: path);
        }
        if (message.mediaThumbFileId == fileId) {
          changed = true;
          return message.copyWith(mediaThumbLocalPath: path);
        }
        return message;
      }).toList();
      if (!changed) continue;
      _messagesByChat[entry.key] = next;
      if (_activeChatId == entry.key) _emitMessages(entry.key);
    }
  }

  TdlibMessageItem? _messageFromMap(Map<String, dynamic> msg) {
    final id = _asInt(msg['id']);
    final chatId = _asInt(msg['chat_id']);
    if (id == null || chatId == null) return null;
    final outgoing = msg['is_outgoing'] == true;
    final senderId = _asInt(msg['sender_id'] is Map
        ? (msg['sender_id'] as Map)['user_id']
        : msg['sender_id']);
    final content = msg['content'];
    final contentMap = content is Map ? Map<String, dynamic>.from(content) : null;
    final preview = _previewFromMessage(msg) ?? 'Mensagem';
    final isRead = msg['is_outgoing'] == true
        ? (msg['interaction_info'] is Map &&
            (msg['interaction_info'] as Map)['read_date'] != null)
        : false;
    final isEdited = contentMap?['@type']?.toString().contains('Edited') == true;
    final isForwarded = msg['forward_info'] != null;
    final replyTo = msg['reply_to'];
    final replyToId = replyTo is Map ? _asInt(replyTo['message_id']) : null;
    String? replyPreview;
    if (replyToId != null) {
      final existing = _messagesByChat[chatId];
      if (existing != null) {
        for (final m in existing) {
          if (m.id == replyToId) {
            replyPreview = m.text.isNotEmpty ? m.text : m.preview;
            break;
          }
        }
      }
    }

    // Extract media info
    String? mediaKind;
    int? mediaFileId;
    String? mediaLocalPath;
    String? mediaRemoteId;
    String? mediaCaption;
    int? mediaThumbFileId;
    String? mediaThumbLocalPath;
    String? text;
    String? mimeType;
    String? fileName;
    int? fileSize;

    if (contentMap != null) {
      final cType = contentMap['@type']?.toString() ?? '';
      switch (cType) {
        case 'messageText':
          final t = contentMap['text'];
          if (t is Map) text = t['text']?.toString();
          break;
        case 'messagePhoto':
          mediaKind = 'photo';
          final photo = contentMap['photo'];
          if (photo is Map) {
            final sizes = photo['sizes'];
            if (sizes is List && sizes.isNotEmpty) {
              final first = sizes.first;
              final last = sizes.last;
              if (first is Map && first['photo'] is Map) {
                final t = first['photo'] as Map;
                mediaThumbFileId = _asInt(t['id']);
                mediaThumbLocalPath = t['local'] is Map
                    ? (t['local'] as Map)['path']?.toString()
                    : null;
              }
              if (last is Map) {
                final p = last['photo'];
                if (p is Map) {
                  mediaFileId = _asInt(p['id']);
                  mediaLocalPath = p['local'] is Map
                      ? (p['local'] as Map)['path']?.toString()
                      : null;
                  mediaRemoteId = p['remote'] is Map
                      ? (p['remote'] as Map)['id']?.toString()
                      : null;
                }
              }
              // Lista: preferir thumb se full ainda não baixou.
              if ((mediaLocalPath ?? '').trim().isEmpty) {
                mediaLocalPath = mediaThumbLocalPath;
              }
            }
          }
          final cap = contentMap['caption'];
          if (cap is Map) mediaCaption = cap['text']?.toString();
          break;
        case 'messageVideo':
          mediaKind = 'video';
          final video = contentMap['video'];
          if (video is Map) {
            mimeType = video['mime_type']?.toString();
            fileName = video['file_name']?.toString();
            fileSize = _asInt(video['size']);
            if (video['video'] is Map) {
              final v = video['video'] as Map;
              mediaFileId = _asInt(v['id']);
              mediaLocalPath = v['local'] is Map
                  ? (v['local'] as Map)['path']?.toString()
                  : null;
              mediaRemoteId = v['remote'] is Map
                  ? (v['remote'] as Map)['id']?.toString()
                  : null;
            }
          }
          final cap = contentMap['caption'];
          if (cap is Map) mediaCaption = cap['text']?.toString();
          break;
        case 'messageVoiceNote':
          mediaKind = 'voice';
          final vn = contentMap['voice_note'];
          if (vn is Map) {
            mimeType = vn['mime_type']?.toString();
            fileSize = _asInt(vn['size']);
            if (vn['voice'] is Map) {
              final v = vn['voice'] as Map;
              mediaFileId = _asInt(v['id']);
              mediaLocalPath = v['local'] is Map
                  ? (v['local'] as Map)['path']?.toString()
                  : null;
              mediaRemoteId = v['remote'] is Map
                  ? (v['remote'] as Map)['id']?.toString()
                  : null;
            }
          }
          break;
        case 'messageDocument':
          mediaKind = 'document';
          final doc = contentMap['document'];
          if (doc is Map) {
            mimeType = doc['mime_type']?.toString();
            fileName = doc['file_name']?.toString();
            fileSize = _asInt(doc['size']);
            if (doc['document'] is Map) {
              final d = doc['document'] as Map;
              mediaFileId = _asInt(d['id']);
              mediaLocalPath = d['local'] is Map
                  ? (d['local'] as Map)['path']?.toString()
                  : null;
              mediaRemoteId = d['remote'] is Map
                  ? (d['remote'] as Map)['id']?.toString()
                  : null;
            }
          }
          final cap = contentMap['caption'];
          if (cap is Map) mediaCaption = cap['text']?.toString();
          break;
        case 'messageAudio':
          mediaKind = 'audio';
          final audio = contentMap['audio'];
          if (audio is Map) {
            mimeType = audio['mime_type']?.toString();
            fileName = audio['file_name']?.toString();
            fileSize = _asInt(audio['size']);
            if (audio['audio'] is Map) {
              final a = audio['audio'] as Map;
              mediaFileId = _asInt(a['id']);
              mediaLocalPath = a['local'] is Map
                  ? (a['local'] as Map)['path']?.toString()
                  : null;
              mediaRemoteId = a['remote'] is Map
                  ? (a['remote'] as Map)['id']?.toString()
                  : null;
            }
          }
          break;
        case 'messageSticker':
          mediaKind = 'sticker';
          break;
      }
    }

    final sending = msg['sending_state'];
    var sendStatus = TdlibSendStatus.sent;
    if (sending is Map) {
      final st = (sending['@type'] ?? '').toString();
      if (st.contains('Failed')) {
        sendStatus = TdlibSendStatus.failed;
      } else if (st.contains('Pending') || st.isNotEmpty) {
        sendStatus = TdlibSendStatus.sending;
      }
    }

    return TdlibMessageItem(
      id: id,
      chatId: chatId,
      isOutgoing: outgoing,
      preview: preview,
      dateEpoch: _asInt(msg['date']),
      senderId: senderId,
      text: text ?? '',
      mediaKind: mediaKind,
      mediaFileId: mediaFileId,
      mediaLocalPath: mediaLocalPath,
      mediaRemoteId: mediaRemoteId,
      mediaCaption: mediaCaption,
      mediaThumbFileId: mediaThumbFileId,
      mediaThumbLocalPath: mediaThumbLocalPath,
      replyToMessageId: replyToId,
      isRead: isRead,
      isEdited: isEdited,
      isForwarded: isForwarded,
      fileSize: fileSize,
      mimeType: mimeType,
      fileName: fileName,
      sendStatus: sendStatus,
      replyPreview: replyPreview,
    );
  }

  void _emitMessages(int chatId) {
    if (_messagesController.isClosed) return;
    _messagesController.add(
      List<TdlibMessageItem>.from(_messagesByChat[chatId] ?? const []),
    );
  }

  void _ingestChatObject(Map<String, dynamic> chat) {
    final id = _asInt(chat['id']);
    if (id == null) return;
    final title = (chat['title'] ?? chat['id']?.toString() ?? 'Chat').toString();
    final unread = _asInt(chat['unread_count']) ?? 0;
    final last = chat['last_message'];
    final lastMap = last is Map ? Map<String, dynamic>.from(last) : null;
    final preview = _previewFromMessage(lastMap);
    final date = lastMap == null ? null : _asInt(lastMap['date']);
    final type = chat['type'];
    final typeName = type is Map ? (type['@type'] ?? '').toString() : '';
    final isGroup = typeName.contains('Supergroup') ||
        typeName.contains('BasicGroup') ||
        typeName == 'chatTypeSupergroup' ||
        typeName == 'chatTypeBasicGroup';
    if (type is Map &&
        (typeName.contains('Private') || typeName == 'chatTypePrivate')) {
      final uid = _asInt(type['user_id']);
      if (uid != null) _privateChatUserId[id] = uid;
    }
    final prev = _chatsById[id];
    int? photoFileId;
    String? photoLocalPath = prev?.photoLocalPath;
    final photo = chat['photo'];
    if (photo is Map) {
      final small = photo['small'];
      if (small is Map) {
        photoFileId = _asInt(small['id']);
        final local = small['local'];
        if (local is Map) {
          final pth = (local['path'] ?? '').toString().trim();
          if (pth.isNotEmpty) photoLocalPath = pth;
        }
      }
    }
    _chatsById[id] = TdlibChatPreview(
      id: id,
      title: title,
      unreadCount: unread,
      lastMessagePreview: preview ?? prev?.lastMessagePreview,
      lastMessageDateEpoch: date ?? prev?.lastMessageDateEpoch,
      isGroup: isGroup || (prev?.isGroup ?? false),
      photoFileId: photoFileId ?? prev?.photoFileId,
      photoLocalPath: photoLocalPath ?? prev?.photoLocalPath,
    );
    _emitChats();
    if (photoFileId != null) unawaited(ensureChatPhoto(id));
  }

  String? _previewFromMessage(Map<String, dynamic>? msg) {
    if (msg == null) return null;
    final content = msg['content'];
    if (content is! Map) return null;
    final t = content['@type']?.toString();
    if (t == 'messageText') {
      final text = content['text'];
      if (text is Map) return text['text']?.toString();
    }
    if (t == 'messagePhoto') return '📷 Foto';
    if (t == 'messageVoiceNote') return '🎤 Áudio';
    if (t == 'messageVideo') return '🎬 Vídeo';
    if (t == 'messageDocument') return '📎 Arquivo';
    if (t == 'messageSticker') return 'Sticker';
    return t?.replaceFirst('message', '');
  }

  td.Service _requireService() {
    final svc = _service;
    if (svc == null) {
      throw StateError('TdLibService não inicializado. Chame init() antes.');
    }
    return svc;
  }

  void _emitAuth(TdlibAuthSnapshot snap) {
    _snapshot = snap;
    if (!_authController.isClosed) {
      _authController.add(snap);
    }
  }

  void _emitChats({bool persist = true}) {
    final list = _chatsById.values.toList()
      ..sort((a, b) {
        final da = a.lastMessageDateEpoch ?? 0;
        final db = b.lastMessageDateEpoch ?? 0;
        if (db != da) return db.compareTo(da);
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    if (!_chatsController.isClosed) {
      _chatsController.add(list);
    }
    if (persist && _boundChurchId.trim().isNotEmpty) {
      unawaited(TdlibChatLocalPrefs.saveChatList(_boundChurchId, list));
    }
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  /// Pesquisa mensagens no chat (texto).
  Future<List<TdlibMessageItem>> searchChatMessages(
    int chatId,
    String query, {
    int limit = 40,
  }) async {
    final svc = _requireService();
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final result = await svc.sendSync({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': q,
        'from_message_id': 0,
        'offset': 0,
        'limit': limit,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
        'message_thread_id': 0,
      });
      final msgs = result['messages'];
      if (msgs is! List) return const [];
      final out = <TdlibMessageItem>[];
      for (final raw in msgs) {
        if (raw is! Map) continue;
        final item = _messageFromMap(Map<String, dynamic>.from(raw));
        if (item != null) out.add(item);
      }
      return out;
    } catch (e) {
      debugPrint('[TdLib] searchChatMessages: $e');
      return const [];
    }
  }

  /// Membros do grupo (supergroup / basic).
  Future<List<TdlibChatMember>> getChatMembers(
    int chatId, {
    int limit = 100,
  }) async {
    final svc = _requireService();
    try {
      final chat = await svc.sendSync({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      _ingestChatObject(Map<String, dynamic>.from(chat));
      final type = chat['type'];
      if (type is! Map) return const [];
      final typeName = (type['@type'] ?? '').toString();
      final members = <TdlibChatMember>[];

      if (typeName == 'chatTypeSupergroup') {
        final sgId = _asInt(type['supergroup_id']);
        if (sgId == null) return const [];
        final result = await svc.sendSync({
          '@type': 'getSupergroupMembers',
          'supergroup_id': sgId,
          'filter': {'@type': 'supergroupMembersFilterRecent'},
          'offset': 0,
          'limit': limit,
        });
        final list = result['members'];
        if (list is List) {
          for (final raw in list) {
            if (raw is! Map) continue;
            final member = await _memberFromChatMemberMap(
              Map<String, dynamic>.from(raw),
            );
            if (member != null) members.add(member);
          }
        }
      } else if (typeName == 'chatTypeBasicGroup') {
        final bgId = _asInt(type['basic_group_id']);
        if (bgId == null) return const [];
        final full = await svc.sendSync({
          '@type': 'getBasicGroupFullInfo',
          'basic_group_id': bgId,
        });
        final list = full['members'];
        if (list is List) {
          for (final raw in list) {
            if (raw is! Map) continue;
            final member = await _memberFromChatMemberMap(
              Map<String, dynamic>.from(raw),
            );
            if (member != null) members.add(member);
          }
        }
      }
      return members;
    } catch (e) {
      debugPrint('[TdLib] getChatMembers: $e');
      return const [];
    }
  }

  Future<TdlibChatMember?> _memberFromChatMemberMap(
    Map<String, dynamic> raw,
  ) async {
    final svc = _service;
    if (svc == null) return null;
    final memberId = raw['member_id'];
    int? userId;
    if (memberId is Map) {
      userId = _asInt(memberId['user_id'] ?? memberId['id']);
    } else {
      userId = _asInt(raw['user_id']);
    }
    if (userId == null) return null;
    var name = 'Membro';
    String? phone;
    try {
      final user = await svc.sendSync({
        '@type': 'getUser',
        'user_id': userId,
      });
      final first = (user['first_name'] ?? '').toString().trim();
      final last = (user['last_name'] ?? '').toString().trim();
      name = '$first $last'.trim();
      if (name.isEmpty) {
        name = (user['usernames'] is Map
                ? ((user['usernames'] as Map)['editable_username'] ?? '')
                : (user['username'] ?? ''))
            .toString()
            .trim();
      }
      if (name.isEmpty) name = 'Membro $userId';
      phone = (user['phone_number'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (phone.isEmpty) phone = null;
    } catch (_) {}
    final status = (raw['status'] is Map)
        ? ((raw['status'] as Map)['@type'] ?? '').toString()
        : '';
    final isAdmin = status.contains('Administrator') || status.contains('Creator');
    return TdlibChatMember(
      userId: userId,
      displayName: name,
      phoneDigits: phone,
      isAdmin: isAdmin,
    );
  }

  Future<void> setChatMuted(int chatId, bool muted) async {
    final svc = _requireService();
    try {
      await svc.sendSync({
        '@type': 'setChatNotificationSettings',
        'chat_id': chatId,
        'notification_settings': {
          '@type': 'chatNotificationSettings',
          'use_default_mute_for': false,
          'mute_for': muted ? 2147483647 : 0,
          'use_default_sound': true,
          'use_default_show_preview': true,
          'use_default_disable_pinned_message_notifications': true,
          'use_default_disable_mention_notifications': true,
        },
      });
    } catch (e) {
      debugPrint('[TdLib] setChatMuted: $e');
      rethrow;
    }
  }

  /// Injeta mensagem otimista na UI (envio / retry).
  void upsertLocalMessage(TdlibMessageItem item) {
    final list = List<TdlibMessageItem>.from(
      _messagesByChat[item.chatId] ?? const [],
    );
    list.removeWhere((e) => e.id == item.id);
    list.add(item);
    list.sort((a, b) => a.id.compareTo(b.id));
    _messagesByChat[item.chatId] = list;
    if (_activeChatId == item.chatId) _emitMessages(item.chatId);
  }

  void removeLocalMessage(int chatId, int messageId) {
    final list = _messagesByChat[chatId];
    if (list == null) return;
    _messagesByChat[chatId] =
        list.where((m) => m.id != messageId).toList(growable: false);
    if (_activeChatId == chatId) _emitMessages(chatId);
  }

  Future<void> configureNotificationOptions() async {
    final svc = _service;
    if (svc == null) return;
    Future<void> setInt(String name, int value) async {
      try {
        await svc.sendSync({
          '@type': 'setOption',
          'name': name,
          'value': {'@type': 'optionValueInteger', 'value': value},
        });
      } catch (_) {}
    }

    await setInt('notification_group_count_max', 25);
    await setInt('notification_group_size_max', 10);
  }

  Future<void> registerPushDevice(
    String fcmToken, {
    String? apnsTokenHex,
    bool apnsSandbox = false,
  }) async {
    final token = fcmToken.trim();
    try {
      final svc = _requireService();
      if (Platform.isIOS) {
        final apns = (apnsTokenHex ?? '').trim();
        if (apns.isNotEmpty) {
          await svc.sendSync({
            '@type': 'registerDevice',
            'device_token': {
              '@type': 'deviceTokenApplePush',
              'device_token': apns,
              'is_app_sandbox': apnsSandbox,
              'encrypt': true,
            },
            'other_user_ids': <int>[],
          });
        }
        // iOS também regista FCM (Telegram usa bridge Firebase em vários clientes).
        if (token.isNotEmpty) {
          await svc.sendSync({
            '@type': 'registerDevice',
            'device_token': {
              '@type': 'deviceTokenFirebaseCloudMessaging',
              'token': token,
              'encrypt': true,
            },
            'other_user_ids': <int>[],
          });
        }
        return;
      }
      if (token.isEmpty) return;
      await svc.sendSync({
        '@type': 'registerDevice',
        'device_token': {
          '@type': 'deviceTokenFirebaseCloudMessaging',
          'token': token,
          'encrypt': true,
        },
        'other_user_ids': <int>[],
      });
    } catch (e) {
      debugPrint('[TdLib] registerPushDevice: $e');
    }
  }

  Future<void> processPushNotification(String payload) async {
    final p = payload.trim();
    if (p.isEmpty) return;
    try {
      await _requireService().sendSync({
        '@type': 'processPushNotification',
        'payload': p,
      });
    } catch (e) {
      debugPrint('[TdLib] processPushNotification: $e');
      rethrow;
    }
  }

  /// Carrega mensagens mais antigas (scroll infinito).
  Future<List<TdlibMessageItem>> loadOlderMessages(
    int chatId, {
    int limit = 40,
  }) async {
    final svc = _requireService();
    final current = _messagesByChat[chatId] ?? const <TdlibMessageItem>[];
    if (current.isEmpty) {
      return loadChatHistory(chatId, limit: limit, setActive: true);
    }
    final fromId = current.first.id;
    if (fromId <= 0) return current;
    final result = await svc.sendSync({
      '@type': 'getChatHistory',
      'chat_id': chatId,
      'from_message_id': fromId,
      'offset': 0,
      'limit': limit,
      'only_local': false,
    });
    final messages = (result['messages'] as List?) ?? const [];
    final older = <TdlibMessageItem>[];
    for (final raw in messages) {
      if (raw is! Map) continue;
      final item = _messageFromMap(Map<String, dynamic>.from(raw));
      if (item != null) older.add(item);
    }
    if (older.isEmpty) return current;
    final merged = <TdlibMessageItem>[...older, ...current];
    final byId = <int, TdlibMessageItem>{};
    for (final m in merged) {
      byId[m.id] = m;
    }
    final list = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    _messagesByChat[chatId] = list;
    if (_activeChatId == chatId) _emitMessages(chatId);
    return list;
  }

  Future<TdlibUserPresence?> refreshChatPresence(int chatId) async {
    final userId = _privateChatUserId[chatId];
    if (userId == null) return null;
    try {
      final user = await _requireService().sendSync({
        '@type': 'getUser',
        'user_id': userId,
      });
      final status = user['status'];
      if (status is! Map) return _presenceByUser[userId];
      final st = (status['@type'] ?? '').toString();
      final presence = TdlibUserPresence(
        userId: userId,
        isOnline: st.contains('Online'),
        wasOnlineEpoch: _asInt(status['was_online']),
      );
      _presenceByUser[userId] = presence;
      if (!_presenceController.isClosed) _presenceController.add(presence);
      return presence;
    } catch (e) {
      debugPrint('[TdLib] refreshChatPresence: $e');
      return _presenceByUser[userId];
    }
  }

  TdlibUserPresence? peekPresenceForChat(int chatId) {
    final userId = _privateChatUserId[chatId];
    if (userId == null) return null;
    return _presenceByUser[userId];
  }

  Future<List<TdlibSearchHit>> searchMessagesGlobal(
    String query, {
    int limit = 40,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final result = await _requireService().sendSync({
        '@type': 'searchMessages',
        'chat_list': {'@type': 'chatListMain'},
        'query': q,
        'offset_date': 0,
        'offset_chat_id': 0,
        'offset_message_id': 0,
        'limit': limit,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      });
      final messages = (result['messages'] as List?) ?? const [];
      final hits = <TdlibSearchHit>[];
      for (final raw in messages) {
        if (raw is! Map) continue;
        final item = _messageFromMap(Map<String, dynamic>.from(raw));
        if (item == null) continue;
        final title = _chatsById[item.chatId]?.title ?? 'Chat';
        hits.add(
          TdlibSearchHit(
            chatId: item.chatId,
            chatTitle: title,
            message: item,
          ),
        );
      }
      return hits;
    } catch (e) {
      debugPrint('[TdLib] searchMessagesGlobal: $e');
      return const [];
    }
  }

  Future<List<TdlibSessionInfo>> getActiveSessions() async {
    try {
      final result = await _requireService().sendSync({
        '@type': 'getActiveSessions',
      });
      final sessions = (result['sessions'] as List?) ?? const [];
      final out = <TdlibSessionInfo>[];
      for (final raw in sessions) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id = _asInt(m['id']);
        if (id == null) continue;
        out.add(
          TdlibSessionInfo(
            id: id,
            deviceModel: (m['device_model'] ?? 'Aparelho').toString(),
            platform: (m['platform'] ?? '').toString(),
            appName: (m['application_name'] ?? m['app_name'] ?? 'Telegram')
                .toString(),
            isCurrent: m['is_current'] == true,
            ipAddress: m['ip_address']?.toString(),
            country: m['country']?.toString(),
            lastActiveEpoch: _asInt(m['last_active_date']),
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('[TdLib] getActiveSessions: $e');
      return const [];
    }
  }

  Future<void> terminateSession(int sessionId) async {
    await _requireService().sendSync({
      '@type': 'terminateSession',
      'session_id': sessionId,
    });
  }

  Future<void> terminateAllOtherSessions() async {
    await _requireService().sendSync({
      '@type': 'terminateAllOtherSessions',
    });
  }

  Future<void> addMessageReaction(
    int chatId,
    int messageId,
    String emoji,
  ) async {
    final e = emoji.trim();
    if (e.isEmpty) return;
    await _requireService().sendSync({
      '@type': 'addMessageReaction',
      'chat_id': chatId,
      'message_id': messageId,
      'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': e},
      'is_big': false,
      'update_recent_reactions': true,
    });
  }

  Future<void> prefetchChatPhotos({int limit = 20}) async {
    final sorted = _chatsById.values.toList()
      ..sort(
        (a, b) => (b.lastMessageDateEpoch ?? 0)
            .compareTo(a.lastMessageDateEpoch ?? 0),
      );
    for (final c in sorted.take(limit)) {
      unawaited(ensureChatPhoto(c.id));
    }
  }

  Future<void> dispose() async {
    try {
      await _service?.stop();
    } catch (_) {}
    _service = null;
    _chatsById.clear();
    _messagesByChat.clear();
    _pinnedByChat.clear();
    _presenceByUser.clear();
    _privateChatUserId.clear();
    await _authController.close();
    await _chatsController.close();
    await _messagesController.close();
    await _peerActionController.close();
    await _presenceController.close();
  }
}
