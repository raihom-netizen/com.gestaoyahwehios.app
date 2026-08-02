import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:libtdjson/libtdjson.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  final Map<int, TdlibChatPreview> _chatsById = {};
  final Map<int, List<TdlibMessageItem>> _messagesByChat = {};
  int? _activeChatId;
  TdlibAuthSnapshot _snapshot = TdlibAuthSnapshot.idle;

  bool get isInitialized => _service != null;
  String get boundChurchId => _boundChurchId;
  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
  TdlibAuthSnapshot get currentAuth => _snapshot;

  Stream<TdlibAuthSnapshot> get authorizationStateStream =>
      _authController.stream;
  Stream<List<TdlibChatPreview>> get chatsStream => _chatsController.stream;
  Stream<List<TdlibMessageItem>> get messagesStream =>
      _messagesController.stream;

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
    if (kIsWeb) {
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

    try {
      final support = await getApplicationSupportDirectory();
      final churchKey = cid.isEmpty ? 'default' : cid;
      final dbDir =
          Directory(p.join(support.path, 'tdlib', churchKey, 'db'));
      final filesDir =
          Directory(p.join(support.path, 'tdlib', churchKey, 'files'));
      await dbDir.create(recursive: true);
      await filesDir.create(recursive: true);

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
      _emitAuth(TdlibAuthSnapshot(
        phase: TdlibAuthPhase.error,
        message: 'Falha ao carregar libtdjson: $e',
      ));
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
    _activeChatId = null;
    _boundChurchId = '';
    _emitChats();
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
      final preview = _previewFromMessage(
        last is Map ? Map<String, dynamic>.from(last) : null,
      );
      if (prev != null) {
        _chatsById[chatId] = TdlibChatPreview(
          id: chatId,
          title: prev.title,
          unreadCount: prev.unreadCount,
          lastMessagePreview: preview ?? prev.lastMessagePreview,
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
        unawaited(refreshChats());
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
  }) async {
    final svc = _requireService();
    _activeChatId = chatId;
    final result = await svc.sendSync({
      '@type': 'getChatHistory',
      'chat_id': chatId,
      'from_message_id': 0,
      'offset': 0,
      'limit': limit,
      'only_local': false,
    });
    final messages = (result['messages'] as List?) ?? const [];
    final items = <TdlibMessageItem>[];
    for (final raw in messages) {
      if (raw is! Map) continue;
      final item = _messageFromMap(Map<String, dynamic>.from(raw));
      if (item != null) items.add(item);
    }
    items.sort((a, b) => a.id.compareTo(b.id));
    _messagesByChat[chatId] = items;
    _emitMessages(chatId);
    return items;
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
    if (path.isEmpty) return;
    final inputFile = {
      '@type': 'inputFileLocal',
      'path': path,
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
    list.removeWhere((e) => e.id == item.id);
    list.add(item);
    list.sort((a, b) => a.id.compareTo(b.id));
    _messagesByChat[item.chatId] = list;
    if (_activeChatId == item.chatId) {
      _emitMessages(item.chatId);
    }
    final prev = _chatsById[item.chatId];
    if (prev != null) {
      _chatsById[item.chatId] = TdlibChatPreview(
        id: prev.id,
        title: prev.title,
        unreadCount: prev.unreadCount,
        lastMessagePreview: item.preview,
      );
      _emitChats();
    }
  }

  void _applyFileUpdate(Map<String, dynamic> file) {
    final fileId = _asInt(file['id']);
    final local = file['local'];
    if (fileId == null || local is! Map) return;
    final completed = local['is_downloading_completed'] == true;
    final path = (local['path'] ?? '').toString().trim();
    if (!completed || path.isEmpty) return;
    for (final entry in _messagesByChat.entries) {
      var changed = false;
      final next = entry.value.map((message) {
        if (message.mediaFileId != fileId) return message;
        changed = true;
        return message.copyWith(mediaLocalPath: path);
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

    // Extract media info
    String? mediaKind;
    int? mediaFileId;
    String? mediaLocalPath;
    String? mediaRemoteId;
    String? mediaCaption;
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
              final last = sizes.last;
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
      replyToMessageId: replyToId,
      isRead: isRead,
      isEdited: isEdited,
      isForwarded: isForwarded,
      fileSize: fileSize,
      mimeType: mimeType,
      fileName: fileName,
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
    final preview = _previewFromMessage(
      last is Map ? Map<String, dynamic>.from(last) : null,
    );
    _chatsById[id] = TdlibChatPreview(
      id: id,
      title: title,
      unreadCount: unread,
      lastMessagePreview: preview,
    );
    _emitChats();
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

  void _emitChats() {
    final list = _chatsById.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (!_chatsController.isClosed) {
      _chatsController.add(list);
    }
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> dispose() async {
    try {
      await _service?.stop();
    } catch (_) {}
    _service = null;
    _chatsById.clear();
    _messagesByChat.clear();
    await _authController.close();
    await _chatsController.close();
    await _messagesController.close();
  }
}
