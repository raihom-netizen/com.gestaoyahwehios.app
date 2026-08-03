import 'dart:async';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_chat_local_prefs.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_temp_file.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_user_facing_error.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_group_members_page.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_local_media.dart';
import 'package:gestao_yahweh/services/audio_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_voice_mic_button.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Página de thread do chat — motor TDLib (Telegram).
class TdlibChatThreadPage extends StatefulWidget {
  const TdlibChatThreadPage({
    super.key,
    required this.chatId,
    required this.title,
    this.churchId = '',
    this.isGroup = false,
    this.departmentId = '',
    this.departmentName = '',
  });

  final int chatId;
  final String title;
  final String churchId;
  final bool isGroup;
  final String departmentId;
  final String departmentName;

  @override
  State<TdlibChatThreadPage> createState() => _TdlibChatThreadPageState();
}

class _TdlibChatThreadPageState extends State<TdlibChatThreadPage> {
  static const _accent = Color(0xFF0D9488);

  final _textCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _chatAudio = ChatAudioService();

  List<TdlibMessageItem> _messages = const [];
  List<TdlibMessageItem>? _searchHits;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _searchOpen = false;
  bool _showScrollFab = false;
  bool _muted = false;
  bool _voiceRecording = false;
  bool _voiceSlideCancel = false;
  double _voiceSlideOffset = 0;
  Duration _voiceElapsed = Duration.zero;
  Timer? _voiceTicker;
  Future<void>? _voiceStartFuture;
  Timer? _draftSaveTimer;
  Timer? _peerActionClearTimer;

  bool _selecting = false;
  final Set<int> _selectedIds = {};
  TdlibPeerActionKind? _peerAction;
  TdlibMessageItem? _pinned;
  TdlibUserPresence? _presence;
  int? _presenceUserId;

  StreamSubscription<List<TdlibMessageItem>>? _sub;
  StreamSubscription<TdlibPeerAction>? _peerSub;
  StreamSubscription<TdlibUserPresence>? _presenceSub;
  int? _replyToId;
  String? _replyToPreview;
  int _tempIdSeq = -1;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    unawaited(_loadDraft());
    _loadHistory();
    _loadMute();
    if (!widget.isGroup) {
      unawaited(_initPresence());
    }
    _sub = TdLibService.instance.messagesStream.listen((list) {
      if (!mounted) return;
      setState(() {
        _messages = list.where((m) => m.chatId == widget.chatId).toList();
        _loading = false;
      });
    });
    _peerSub = TdLibService.instance.peerActionsStream.listen((action) {
      if (!mounted || action.chatId != widget.chatId) return;
      if (action.kind == TdlibPeerActionKind.cancel) {
        setState(() => _peerAction = null);
        return;
      }
      setState(() => _peerAction = action.kind);
      _peerActionClearTimer?.cancel();
      _peerActionClearTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _peerAction = null);
      });
    });
  }

  Future<void> _loadDraft() async {
    final churchId = widget.churchId.trim();
    if (churchId.isEmpty) return;
    final draft = await TdlibChatLocalPrefs.getDraft(churchId, widget.chatId);
    if (mounted && draft.isNotEmpty) {
      _textCtrl.text = draft;
      setState(() {});
    }
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 400), () {
      final churchId = widget.churchId.trim();
      if (churchId.isEmpty) return;
      unawaited(
        TdlibChatLocalPrefs.setDraft(
          churchId,
          widget.chatId,
          _textCtrl.text,
        ),
      );
    });
  }

  void _clearDraft() {
    final churchId = widget.churchId.trim();
    if (churchId.isEmpty) return;
    unawaited(TdlibChatLocalPrefs.setDraft(churchId, widget.chatId, ''));
  }

  String? get _peerActionLabel => switch (_peerAction) {
        TdlibPeerActionKind.typing => 'digitando…',
        TdlibPeerActionKind.recordingVoice => 'gravando áudio…',
        _ => null,
      };

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _enterSelection(TdlibMessageItem msg) {
    if (msg.id <= 0) return;
    setState(() {
      _selecting = true;
      _selectedIds.add(msg.id);
    });
  }

  void _toggleSelection(int messageId) {
    if (messageId <= 0) return;
    setState(() {
      if (_selectedIds.contains(messageId)) {
        _selectedIds.remove(messageId);
        if (_selectedIds.isEmpty) _selecting = false;
      } else {
        _selectedIds.add(messageId);
      }
    });
  }

  TdlibMessageItem? _messageById(int id) {
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool _canEditMessage(TdlibMessageItem msg) =>
      msg.isOutgoing &&
      msg.id > 0 &&
      !msg.isFailed &&
      msg.mediaKind == null &&
      msg.text.trim().isNotEmpty;

  Future<void> _loadMute() async {
    final churchId = widget.churchId.trim();
    if (churchId.isEmpty) return;
    final muted = await TdlibChatLocalPrefs.isMuted(churchId, widget.chatId);
    if (mounted) setState(() => _muted = muted);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final show = _scrollCtrl.offset > 220;
    if (show != _showScrollFab && mounted) {
      setState(() => _showScrollFab = show);
    }
    if (_hasMore && !_loadingOlder && _searchHits == null) {
      final pos = _scrollCtrl.position;
      if (pos.pixels >= pos.maxScrollExtent - 80) {
        unawaited(_loadOlder());
      }
    }
  }

  Future<void> _initPresence() async {
    final p = await TdLibService.instance.refreshChatPresence(widget.chatId);
    if (!mounted) return;
    if (p != null) {
      setState(() {
        _presence = p;
        _presenceUserId = p.userId;
      });
    }
    _presenceSub = TdLibService.instance.presenceStream.listen((presence) {
      if (!mounted ||
          _presenceUserId == null ||
          presence.userId != _presenceUserId) {
        return;
      }
      setState(() => _presence = presence);
    });
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _loading) return;
    setState(() => _loadingOlder = true);
    final before = _messages.length;
    try {
      final items = await TdLibService.instance.loadOlderMessages(
        widget.chatId,
      );
      if (!mounted) return;
      final filtered =
          items.where((m) => m.chatId == widget.chatId).toList();
      setState(() {
        _messages = filtered;
        if (filtered.length <= before) _hasMore = false;
      });
    } catch (_) {
      // mantém _hasMore para retry no próximo scroll
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _showTelegramCallHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Chamadas de voz/vídeo usam o app Telegram — abra a conversa lá para ligar.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadHistory() async {
    // Pinta RAM/warm na hora — evita spinner se o chat já foi aquecido.
    final cached = TdLibService.instance.cachedMessages(widget.chatId);
    final peekPinned = TdLibService.instance.peekPinnedMessage(widget.chatId);
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _messages = cached;
        _pinned = peekPinned;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final items = await TdLibService.instance.loadChatHistory(
        widget.chatId,
        limit: 40,
      );
      if (mounted) {
        setState(() {
          _messages = items;
          _loading = false;
        });
        final pinned = await TdLibService.instance.refreshPinnedMessage(
          widget.chatId,
        );
        if (mounted) setState(() => _pinned = pinned);
        if (items.isNotEmpty) {
          unawaited(
            TdLibService.instance.markAsRead(
              widget.chatId,
              items.map((m) => m.id).toList(),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _voiceTicker?.cancel();
    _draftSaveTimer?.cancel();
    _peerActionClearTimer?.cancel();
    unawaited(_chatAudio.dispose());
    _sub?.cancel();
    _peerSub?.cancel();
    _presenceSub?.cancel();
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    unawaited(
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    final replyId = _replyToId;
    final replyPreview = _replyToPreview;
    _clearReply();
    final tempId = _tempIdSeq--;
    final optimistic = TdlibMessageItem(
      id: tempId,
      chatId: widget.chatId,
      isOutgoing: true,
      preview: text,
      text: text,
      dateEpoch: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      replyToMessageId: replyId,
      replyPreview: replyPreview,
      sendStatus: TdlibSendStatus.sending,
    );
    TdLibService.instance.upsertLocalMessage(optimistic);
    setState(() => _sending = true);
    try {
      if (replyId != null) {
        await TdLibService.instance.sendTextReply(
          widget.chatId,
          text,
          replyToMessageId: replyId,
        );
      } else {
        await TdLibService.instance.sendTextMessage(widget.chatId, text);
      }
      TdLibService.instance.removeLocalMessage(widget.chatId, tempId);
      _clearDraft();
    } catch (e) {
      TdLibService.instance.upsertLocalMessage(
        optimistic.copyWith(sendStatus: TdlibSendStatus.failed),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retryMessage(TdlibMessageItem msg) async {
    if (!msg.isFailed) return;
    TdLibService.instance.removeLocalMessage(widget.chatId, msg.id);
    if (msg.mediaKind != null &&
        (msg.localPendingPath ?? msg.mediaLocalPath ?? '').isNotEmpty) {
      final path = (msg.localPendingPath ?? msg.mediaLocalPath)!.trim();
      await _sendPath(
        path,
        kind: msg.mediaKind!,
        replyId: msg.replyToMessageId,
        caption: msg.mediaCaption ?? '',
      );
      return;
    }
    if (msg.text.trim().isEmpty) return;
    _textCtrl.text = msg.text;
    _replyToId = msg.replyToMessageId;
    _replyToPreview = msg.replyPreview;
    await _sendText();
  }

  Future<void> _pickAndSendMedia({
    required ImageSource source,
    required String kind,
  }) async {
    try {
      final XFile? file;
      if (kind == 'video') {
        file = await _picker.pickVideo(source: source);
      } else {
        file = await _picker.pickImage(
          source: source,
          maxWidth: 1280,
          imageQuality: 80,
        );
      }
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ok = await _confirmMediaSend(
        label: kind == 'video' ? 'Enviar este vídeo?' : 'Enviar esta foto?',
        previewBytes: kind == 'photo' ? bytes : null,
        fileName: file.name,
      );
      if (!ok) return;
      final localPath = await materializeTdlibLocalPath(
        path: file.path,
        bytes: bytes,
        fileName: file.name.trim().isEmpty ? 'media.bin' : file.name,
      );
      if (localPath == null || localPath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.errorSnackBarWithRetry(
              'Não foi possível anexar o ficheiro. Escolha a foto ou o vídeo de novo.',
            ),
          );
        }
        return;
      }
      await _sendPath(localPath, kind: kind, replyId: _replyToId);
      _clearReply();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await YahwehFilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: true,
      );
      final files = result?.files ?? const [];
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = file.bytes;
      final path = file.path;
      final ok = await _confirmMediaSend(
        label: 'Enviar «${file.name}»?',
        fileName: file.name,
      );
      if (!ok) return;
      final localPath = await materializeTdlibLocalPath(
        path: path,
        bytes: bytes,
        fileName: file.name,
      );
      if (localPath == null || localPath.isEmpty) {
        throw StateError('Arquivo inválido');
      }
      await _sendPath(localPath, kind: 'document', replyId: _replyToId);
      _clearReply();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<bool> _confirmMediaSend({
    required String label,
    Uint8List? previewBytes,
    String? fileName,
  }) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pré-visualizar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (previewBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  previewBytes,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              )
            else
              Icon(Icons.insert_drive_file_rounded, size: 48, color: _accent),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center),
            if ((fileName ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                fileName!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _sendPath(
    String localPath, {
    required String kind,
    int? replyId,
    String caption = '',
  }) async {
    final tempId = _tempIdSeq--;
    final optimistic = TdlibMessageItem(
      id: tempId,
      chatId: widget.chatId,
      isOutgoing: true,
      preview: switch (kind) {
        'photo' => '📷 Foto',
        'video' => '🎬 Vídeo',
        'voice' => '🎤 Áudio',
        _ => '📎 Arquivo',
      },
      mediaKind: kind,
      mediaLocalPath: localPath,
      localPendingPath: localPath,
      mediaCaption: caption,
      dateEpoch: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      replyToMessageId: replyId,
      replyPreview: _replyToPreview,
      sendStatus: TdlibSendStatus.sending,
    );
    TdLibService.instance.upsertLocalMessage(optimistic);
    setState(() => _sending = true);
    try {
      await TdLibService.instance.sendLocalFile(
        widget.chatId,
        localPath,
        kind: kind,
        caption: caption,
        replyToMessageId: replyId,
      );
      TdLibService.instance.removeLocalMessage(widget.chatId, tempId);
    } catch (e) {
      TdLibService.instance.upsertLocalMessage(
        optimistic.copyWith(sendStatus: TdlibSendStatus.failed),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startVoiceRecording() async {
    if (_voiceRecording || _voiceStartFuture != null) return;
    final start = _startVoiceRecordingImpl();
    _voiceStartFuture = start;
    await start;
    _voiceStartFuture = null;
  }

  Future<void> _startVoiceRecordingImpl() async {
    if (mounted) {
      setState(() {
        _voiceRecording = true;
        _voiceElapsed = Duration.zero;
        _voiceSlideCancel = false;
        _voiceSlideOffset = 0;
      });
    }
    unawaited(
      TdLibService.instance.sendChatAction(
        widget.chatId,
        recordingVoice: true,
      ),
    );
    try {
      final startedPath = await _chatAudio.startRecording();
      if (startedPath == null) {
        if (mounted) {
          setState(() {
            _voiceRecording = false;
            _voiceElapsed = Duration.zero;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.errorSnackBarWithRetry(
              'Permissão de microfone necessária para gravar.',
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _voiceRecording = false;
          _voiceElapsed = Duration.zero;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            e is ChatMicrophonePermissionException
                ? e.toString()
                : formatTdlibErrorForUser(e),
          ),
        );
      }
      return;
    }
    _voiceTicker?.cancel();
    _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _voiceElapsed += const Duration(seconds: 1);
        if (_voiceElapsed.inSeconds >= 120) {
          _voiceTicker?.cancel();
          unawaited(_finishVoiceRecording(send: true));
        }
      });
    });
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    _voiceTicker?.cancel();
    _voiceTicker = null;
    if (_voiceStartFuture != null) {
      try {
        await _voiceStartFuture!.timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    final recordedMs = _voiceElapsed.inMilliseconds;
    unawaited(TdLibService.instance.cancelChatAction(widget.chatId));
    if (mounted) {
      setState(() {
        _voiceRecording = false;
        _voiceElapsed = Duration.zero;
        _voiceSlideCancel = false;
        _voiceSlideOffset = 0;
      });
    }
    if (!send) {
      await _chatAudio.stopRecording(send: false);
      return;
    }
    if (recordedMs < 800) {
      await _chatAudio.stopRecording(send: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gravação muito curta. Segure o microfone um pouco mais.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final voicePath = await _chatAudio.stopRecording(send: true);
    if (kIsWeb) {
      final bytes = _chatAudio.takeWebRecordingBytes();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.errorSnackBarWithRetry(
              'Não foi possível obter o áudio. Tente de novo.',
            ),
          );
        }
        return;
      }
      final path = await materializeTdlibLocalPath(
        bytes: bytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      if (path == null) return;
      await _sendPath(path, kind: 'voice', replyId: _replyToId);
      _clearReply();
      return;
    }
    if (voicePath == null || voicePath.isEmpty) return;
    await _sendPath(voicePath, kind: 'voice', replyId: _replyToId);
    _clearReply();
  }

  String get _voiceElapsedLabel {
    final m = _voiceElapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _voiceElapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchHits = null);
      return;
    }
    final hits = await TdLibService.instance.searchChatMessages(
      widget.chatId,
      q,
    );
    if (mounted) setState(() => _searchHits = hits);
  }

  void _setReply(TdlibMessageItem msg) {
    setState(() {
      _replyToId = msg.id;
      _replyToPreview = msg.text.isNotEmpty ? msg.text : msg.preview;
    });
  }

  void _clearReply() {
    setState(() {
      _replyToId = null;
      _replyToPreview = null;
    });
  }

  Future<void> _deleteMessage(TdlibMessageItem msg) async {
    try {
      await TdLibService.instance.deleteMessages(widget.chatId, [msg.id]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    try {
      await TdLibService.instance.deleteMessages(widget.chatId, ids);
      _exitSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _editMessage(TdlibMessageItem msg) async {
    if (!_canEditMessage(msg)) return;
    final editCtrl = TextEditingController(text: msg.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: editCtrl,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Nova mensagem…',
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    editCtrl.dispose();
    if (newText == null || newText.isEmpty || newText == msg.text.trim()) {
      return;
    }
    try {
      await TdLibService.instance.editMessageText(
        widget.chatId,
        msg.id,
        newText,
      );
      if (_selecting) _exitSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _forwardMessages(List<int> messageIds) async {
    final ids = messageIds.where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    final chats = TdLibService.instance.cachedChats
        .where((c) => c.id != widget.chatId && c.id > 0)
        .toList();
    if (!mounted) return;
    if (chats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma conversa disponível para encaminhar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final toChatId = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Encaminhar para…',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (_, i) {
                  final chat = chats[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _accent.withValues(alpha: 0.12),
                      child: Icon(
                        chat.isGroup
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                        color: _accent,
                        size: 20,
                      ),
                    ),
                    title: Text(chat.title),
                    subtitle: chat.isGroup ? const Text('Grupo') : null,
                    onTap: () => Navigator.pop(ctx, chat.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (toChatId == null) return;
    try {
      await TdLibService.instance.forwardMessages(
        toChatId,
        widget.chatId,
        ids,
      );
      _exitSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mensagem encaminhada.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _copyInviteLink() async {
    try {
      final link = await TdLibService.instance.getOrCreateInviteLink(
        widget.chatId,
      );
      if (!mounted) return;
      if (link == null || link.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            'Não foi possível obter o link do grupo.',
          ),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: link.trim()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link do grupo copiado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  void _scrollToPinnedMessage() {
    final pinned = _pinned;
    if (pinned == null) return;
    final idx = _messages.indexWhere((m) => m.id == pinned.id);
    if (idx < 0 || !_scrollCtrl.hasClients) return;
    final target = (_messages.length - 1 - idx) * 72.0;
    unawaited(
      _scrollCtrl.animateTo(
        target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _showMessageOptions(TdlibMessageItem msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Responder'),
              onTap: () {
                Navigator.pop(ctx);
                _setReply(msg);
              },
            ),
            if (_canEditMessage(msg))
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_editMessage(msg));
                },
              ),
            if (msg.id > 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '🙏', '🔥', '😂']
                      .map(
                        (emoji) => IconButton(
                          tooltip: 'Reagir $emoji',
                          onPressed: () {
                            Navigator.pop(ctx);
                            unawaited(
                              TdLibService.instance.addMessageReaction(
                                widget.chatId,
                                msg.id,
                                emoji,
                              ),
                            );
                          },
                          icon: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (!msg.isFailed)
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Encaminhar'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_forwardMessages([msg.id]));
                  },
                ),
            ],
            if (msg.id > 0)
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Selecionar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelection(msg);
                },
              ),
            if (msg.isFailed)
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: Colors.orange),
                title: const Text('Reenviar'),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_retryMessage(msg));
                },
              ),
            if (msg.isOutgoing && !msg.isFailed && msg.id > 0)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: Colors.red),
                title: const Text('Apagar para todos'),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_deleteMessage(msg));
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    final churchId = widget.churchId.trim();
    final next = !_muted;
    setState(() => _muted = next);
    if (churchId.isNotEmpty) {
      await TdlibChatLocalPrefs.setMuted(churchId, widget.chatId, next);
    }
    try {
      await TdLibService.instance.setChatMuted(widget.chatId, next);
    } catch (_) {}
  }

  void _openMembers() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TdlibGroupMembersPage(
          chatId: widget.chatId,
          title: widget.title,
          churchId: widget.churchId,
          departmentId: widget.departmentId,
          departmentName: widget.departmentName,
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.green),
                title: const Text('Câmera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(source: ImageSource.camera, kind: 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Galeria (Foto)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(source: ImageSource.gallery, kind: 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('Vídeo (Galeria)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendMedia(source: ImageSource.gallery, kind: 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file, color: Colors.orange),
                title: const Text('Documento'),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_pickDocument());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selecting) {
      final selected = _selectedIds.toList();
      final single = selected.length == 1 ? _messageById(selected.first) : null;
      final canEdit = single != null && _canEditMessage(single);
      return AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelection,
        ),
        title: Text('${_selectedIds.length} selecionada(s)'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => unawaited(_editMessage(single)),
            ),
          IconButton(
            tooltip: 'Encaminhar',
            icon: const Icon(Icons.forward_rounded),
            onPressed: selected.isEmpty
                ? null
                : () => unawaited(_forwardMessages(selected)),
          ),
          IconButton(
            tooltip: 'Apagar',
            icon: const Icon(Icons.delete_rounded),
            onPressed: selected.isEmpty ? null : () => unawaited(_deleteSelected()),
          ),
        ],
      );
    }

    final peerLabel = _peerActionLabel;
    return AppBar(
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      title: _searchOpen
          ? TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                hintText: 'Buscar na conversa…',
                hintStyle: TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
              onChanged: (v) => unawaited(_runSearch(v)),
            )
          : InkWell(
              onTap: widget.isGroup ? _openMembers : null,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Icon(
                      widget.isGroup
                          ? Icons.groups_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          peerLabel ??
                              _presence?.label ??
                              (widget.isGroup
                                  ? 'Grupo · toque para participantes'
                                  : 'Conversa privada'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.85),
                            fontStyle: peerLabel != null
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        IconButton(
          tooltip: _searchOpen ? 'Fechar busca' : 'Buscar',
          icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () {
            setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtrl.clear();
                _searchHits = null;
              }
            });
          },
        ),
        if (widget.isGroup)
          IconButton(
            tooltip: 'Participantes',
            icon: const Icon(Icons.groups_rounded),
            onPressed: _openMembers,
          ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'mute') unawaited(_toggleMute());
            if (v == 'refresh') unawaited(_loadHistory());
            if (v == 'members' && widget.isGroup) _openMembers();
            if (v == 'invite' && widget.isGroup) unawaited(_copyInviteLink());
            if (v == 'call' && !widget.isGroup) _showTelegramCallHint();
          },
          itemBuilder: (_) => [
            if (!widget.isGroup)
              const PopupMenuItem(
                value: 'call',
                child: Text('Ligar no Telegram'),
              ),
            PopupMenuItem(
              value: 'mute',
              child: Text(_muted ? 'Ativar notificações' : 'Silenciar'),
            ),
            if (widget.isGroup)
              const PopupMenuItem(
                value: 'members',
                child: Text('Participantes'),
              ),
            if (widget.isGroup)
              const PopupMenuItem(
                value: 'invite',
                child: Text('Link do grupo'),
              ),
            const PopupMenuItem(value: 'refresh', child: Text('Atualizar')),
          ],
        ),
      ],
    );
  }

  Widget _buildPinnedBanner() {
    final pinned = _pinned;
    if (pinned == null) return const SizedBox.shrink();
    final preview = pinned.text.trim().isNotEmpty
        ? pinned.text.trim()
        : pinned.preview.trim();
    if (preview.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      elevation: 1,
      child: InkWell(
        onTap: _scrollToPinnedMessage,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _accent.withValues(alpha: 0.18)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 18, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mensagem fixada',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _searchHits ?? _messages;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: _buildAppBar(),
      floatingActionButton: _showScrollFab
          ? FloatingActionButton.small(
              heroTag: 'tdlib_scroll_fab',
              backgroundColor: _accent,
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          if (_loading || _sending)
            LinearProgressIndicator(
              minHeight: 2,
              color: _accent,
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          if (_muted)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEF3C7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text(
                'Conversas silenciadas neste aparelho',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          if (_voiceRecording)
            ChurchChatVoiceRecordingBar(
              elapsedLabel: _voiceElapsedLabel,
              slideCancelArmed: _voiceSlideCancel,
              onCancel: () => unawaited(_finishVoiceRecording(send: false)),
              onSend: () => unawaited(_finishVoiceRecording(send: true)),
            ),
          if (!_selecting && !_searchOpen) _buildPinnedBanner(),
          Expanded(
            child: visible.isEmpty && !_loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _searchHits != null
                                  ? Icons.search_off_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              size: 36,
                              color: _accent,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _searchHits != null
                                ? 'Nenhum resultado'
                                : 'Nenhuma mensagem ainda',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _searchHits != null
                                ? 'Tente outra palavra.'
                                : 'Envie um oi, uma foto ou um áudio para começar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: visible.length + (_loadingOlder ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_loadingOlder && i == visible.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _accent,
                              ),
                            ),
                          ),
                        );
                      }
                      final msg = visible[visible.length - 1 - i];
                      final selected = _selectedIds.contains(msg.id);
                      return Dismissible(
                        key: ValueKey(msg.id),
                        direction: DismissDirection.startToEnd,
                        confirmDismiss: (_) async {
                          if (!_selecting) _setReply(msg);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 18),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.reply_rounded, color: _accent),
                        ),
                        child: _MessageBubble(
                          message: msg,
                          accent: _accent,
                          selecting: _selecting,
                          selected: selected,
                          onReply: () => _setReply(msg),
                          onDelete: () => unawaited(_deleteMessage(msg)),
                          onRetry: () => unawaited(_retryMessage(msg)),
                          onShowOptions: () => _showMessageOptions(msg),
                          onEnterSelection: () => _enterSelection(msg),
                          onToggleSelect: () => _toggleSelection(msg.id),
                        ),
                      );
                    },
                  ),
          ),
          if (_replyToId != null) _buildReplyBar(theme),
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildReplyBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Respondendo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _replyToPreview ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _clearReply,
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    final hasText = _textCtrl.text.trim().isNotEmpty;
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.only(
          left: 6,
          right: 8,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 8,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Anexar',
              icon: const Icon(Icons.attach_file_rounded, color: _accent),
              onPressed: _voiceRecording ? null : _showAttachmentSheet,
            ),
            IconButton(
              tooltip: 'Foto',
              icon: const Icon(Icons.photo_camera_rounded, color: _accent),
              onPressed: _voiceRecording
                  ? null
                  : () => _pickAndSendMedia(
                        source: ImageSource.camera,
                        kind: 'photo',
                      ),
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                enabled: !_voiceRecording,
                textInputAction: TextInputAction.send,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _voiceRecording ? 'Gravando…' : 'Mensagem…',
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendText(),
                onChanged: (_) {
                  setState(() {});
                  _scheduleDraftSave();
                  unawaited(
                    TdLibService.instance.sendChatAction(widget.chatId),
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            if (hasText && !_voiceRecording)
              CircleAvatar(
                radius: 22,
                backgroundColor: _accent,
                child: IconButton(
                  icon: const Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  onPressed: _sendText,
                ),
              )
            else
              ChurchChatVoiceMicButton(
                recording: _voiceRecording,
                slideCancelArmed: _voiceSlideCancel,
                slideOffsetDx: _voiceSlideOffset,
                onWebTap: () => unawaited(
                  _voiceRecording
                      ? _finishVoiceRecording(send: true)
                      : _startVoiceRecording(),
                ),
                onLongPressStart: (_) => unawaited(_startVoiceRecording()),
                onLongPressMoveUpdate: (d) {
                  final dx = d.offsetFromOrigin.dx;
                  setState(() {
                    _voiceSlideOffset = dx;
                    _voiceSlideCancel = dx < -56;
                  });
                },
                onLongPressEnd: (_) => unawaited(
                  _finishVoiceRecording(send: !_voiceSlideCancel),
                ),
                onLongPressCancel: () =>
                    unawaited(_finishVoiceRecording(send: false)),
                onTapWhileRecording: () =>
                    unawaited(_finishVoiceRecording(send: true)),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.accent,
    required this.selecting,
    required this.selected,
    required this.onReply,
    required this.onDelete,
    required this.onRetry,
    required this.onShowOptions,
    required this.onEnterSelection,
    required this.onToggleSelect,
  });

  final TdlibMessageItem message;
  final Color accent;
  final bool selecting;
  final bool selected;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback onShowOptions;
  final VoidCallback onEnterSelection;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final failed = message.isFailed;
    final pending = message.isPending;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          if (selecting) {
            onToggleSelect();
          } else if (message.id > 0) {
            onEnterSelection();
          } else {
            onShowOptions();
          }
        },
        onTap: () {
          if (selecting) {
            onToggleSelect();
            return;
          }
          if (failed) {
            onRetry();
            return;
          }
          onShowOptions();
        },
        child: Opacity(
          opacity: pending ? 0.72 : 1,
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selecting) ...[
                Padding(
                  padding: EdgeInsets.only(right: isMe ? 0 : 8, left: isMe ? 8 : 0),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? accent : Colors.grey.shade400,
                    size: 22,
                  ),
                ),
              ],
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.18)
                        : failed
                            ? const Color(0xFFFEE2E2)
                            : (isMe ? accent : Colors.white),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: selected
                        ? Border.all(color: accent, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!isMe &&
                          (message.senderName ?? '').trim().isNotEmpty) ...[
                        Text(
                          message.senderName!.trim(),
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      if ((message.replyPreview ?? '').trim().isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: (isMe && !failed)
                                ? Colors.white.withValues(alpha: 0.18)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: isMe && !failed ? Colors.white : accent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            message.replyPreview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isMe && !failed
                                  ? Colors.white.withValues(alpha: 0.92)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                      if (message.mediaKind != null) _buildMediaPreview(theme),
                      if (message.text.isNotEmpty)
                        Text(
                          message.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: failed
                                ? const Color(0xFF7F1D1D)
                                : (isMe
                                    ? Colors.white
                                    : const Color(0xFF0F172A)),
                            height: 1.35,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (failed) ...[
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 14,
                              color: Color(0xFFB91C1C),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Falhou · toque p/ reenviar',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ] else ...[
                            if (message.isEdited)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  'editada',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isMe
                                        ? Colors.white.withValues(alpha: 0.75)
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            if (message.dateEpoch != null)
                              Text(
                                _formatTime(message.dateEpoch!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isMe
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              if (pending)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                  ),
                                )
                              else
                                Icon(
                                  message.isRead
                                      ? Icons.done_all_rounded
                                      : Icons.done_rounded,
                                  size: 14,
                                  color: message.isRead
                                      ? const Color(0xFFBFDBFE)
                                      : Colors.white70,
                                ),
                            ],
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TdlibLocalMedia(message: message, outgoing: message.isOutgoing),
          if ((message.mediaCaption ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(message.mediaCaption!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }

  String _formatTime(int epoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
