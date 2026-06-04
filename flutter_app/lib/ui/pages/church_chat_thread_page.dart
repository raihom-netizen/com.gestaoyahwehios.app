import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/church_chat_album_utils.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_album_grid.dart';
import 'package:gestao_yahweh/services/church_chat_expression_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_fs.dart'
    show churchChatReadFileBytes;
import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_moderation.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_date_separator.dart';
import 'package:gestao_yahweh/services/church_chat_instant_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/optimistic_chat_media_upload.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_delivery_status.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_media_preview_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_forward_sheet.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_expression_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_chat_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_inline_audio_player.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_upload_progress.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_starred_messages_sheet.dart';
import 'package:gestao_yahweh/services/church_chat_stuck_cleanup_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_pending_status_banner.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_sender_palette.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_peer_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_profile_photo_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_save_media.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';

class _ReplyDraft {
  final String messageId;
  final String senderUid;
  final String preview;
  final String contentType;

  const _ReplyDraft({
    required this.messageId,
    required this.senderUid,
    required this.preview,
    required this.contentType,
  });

  Map<String, dynamic> toReplyPayload() => {
        'messageId': messageId,
        'senderUid': senderUid,
        'preview': preview,
        'type': contentType,
      };

  static _ReplyDraft fromMessageDoc(String id, Map<String, dynamic> m) {
    final type = (m['type'] ?? 'text').toString();
    String preview;
    switch (type) {
      case 'text':
        preview = (m['text'] ?? '').toString().trim();
        if (preview.length > 120) {
          preview = '${preview.substring(0, 117)}…';
        }
        if (preview.isEmpty) preview = 'Mensagem';
        break;
      case 'image':
        preview = '📷 Imagem';
        break;
      case 'video':
        preview = '🎬 Vídeo';
        break;
      case 'document':
        final n = (m['fileName'] ?? '').toString().trim();
        preview = n.isEmpty ? '📎 Documento' : '📎 $n';
        if (preview.length > 120) preview = '${preview.substring(0, 117)}…';
        break;
      case 'audio':
        preview = '🎵 Áudio';
        break;
      case 'sticker':
        preview = '🎨 Figurinha';
        break;
      default:
        preview = 'Mensagem';
    }
    return _ReplyDraft(
      messageId: id,
      senderUid: (m['senderUid'] ?? '').toString(),
      preview: preview,
      contentType: type,
    );
  }
}

/// Conversa fullscreen estilo WhatsApp.
class ChurchChatThreadPage extends StatefulWidget {
  final String tenantId;
  final String threadId;
  final String title;
  final bool isDepartment;
  final String? peerUid;
  /// Papel do utilizador no painel (ex.: `IgrejaCleanShell`) — moderação de mensagens.
  final String memberRole;
  /// CPF só dígitos — líder de departamento por CPF.
  final String memberCpfDigits;
  /// Doc `departamentos/{id}` quando [isDepartment].
  final String? departmentId;

  /// Texto inicial no campo de mensagem (ex.: parabéns de aniversário).
  final String? initialDraftText;

  const ChurchChatThreadPage({
    super.key,
    required this.tenantId,
    required this.threadId,
    required this.title,
    required this.isDepartment,
    this.peerUid,
    this.memberRole = '',
    this.memberCpfDigits = '',
    this.departmentId,
    this.initialDraftText,
  });

  @override
  State<ChurchChatThreadPage> createState() => _ChurchChatThreadPageState();
}

class _ChurchChatThreadPageState extends State<ChurchChatThreadPage>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _msgSearchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _searchingMessages = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deptSub;
  Map<String, dynamic>? _departmentData;
  ChurchChatMemberPrefsModel _prefs = const ChurchChatMemberPrefsModel();

  static const int _maxVoiceSeconds = 600;

  final ChatAudioService _chatAudio = ChatAudioService();
  bool _voiceRecording = false;
  Timer? _voiceTicker;
  Duration _voiceElapsed = Duration.zero;

  _ReplyDraft? _replyDraft;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _olderMessageDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestRecentDocs = const [];
  Timer? _messagesPrimeFallbackTimer;
  bool _messagesPrimeInFlight = false;
  bool _loadingMoreHistory = false;
  bool _hasMoreOlderHistory = true;
  int _olderPagesLoaded = 0;
  DateTime? _lastHistoryLoadBump;
  Timer? _typingDebounce;
  Timer? _typingIdleTimer;
  Timer? _msgSearchDebounce;
  String _messageSearchQuery = '';

  /// Streams estáveis — não recriar em cada [setState] (evita re-subscribe / jank).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _threadStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _threadSub;
  Map<String, String> _titlesByUid = const {};
  bool _messagesStreamReady = false;
  Timestamp? _threadPeerSeenAt;

  /// Uids mencionados nesta composição (picker @) — enviados em [mentionedUids] no texto.
  final Set<String> _mentionedUidsPending = <String>{};

  /// Avatares por `authUid` — `chat_peer_profiles` (sem stream de 800 membros).
  Map<String, ChurchChatMemberRef> _senderMemberByUid = {};
  bool _peerOnline = false;
  Timer? _peerPresencePoll;
  int? _lastPeerReadSyncMs;
  late final VoidCallback _photoSyncListener;
  final List<ChurchChatOutboundPending> _pendingOutbound = [];

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('chat_thread');
    unawaited(
      AppResumeStateService.saveChatThread(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
      ),
    );
    unawaited(
      ImmediateMediaWarm.warmFeed().catchError((_) {}),
    );
    unawaited(
      ensureFirebaseReadyForChatSend().catchError((_) {}),
    );
    unawaited(
      FastMediaPublishBootstrap.warmForChatSend()
          .timeout(const Duration(seconds: 4))
          .catchError((_) {}),
    );
    _photoSyncListener = _onMemberProfilePhotoSynced;
    MemberProfilePhotoSyncNotifier.instance.addListener(_photoSyncListener);
    WidgetsBinding.instance.addObserver(this);
    final draft = widget.initialDraftText?.trim();
    if (draft != null && draft.isNotEmpty) {
      _ctrl.text = draft;
    }
    _scroll.addListener(_onScrollPagination);
    _ctrl.addListener(_onComposeTyping);
    _messagesStream = ChurchChatService.recentMessagesStream(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    _threadStream = ChurchChatService.threadSnapshots(
      widget.tenantId,
      widget.threadId,
    );
    _messagesSub = _messagesStream.listen(
      _onMessagesStreamEvent,
      onError: (_, __) {
        if (mounted && _latestRecentDocs.isEmpty) {
          setState(() => _messagesStreamReady = true);
        }
      },
    );
    _threadSub = _threadStream.listen(_onThreadStreamEvent);
    _prefsSub =
        ChurchChatMemberPrefs.watch(widget.tenantId).listen((snap) {
      if (!mounted) return;
      setState(() => _prefs = ChurchChatMemberPrefs.parse(snap));
    });
    _msgSearchCtrl.addListener(_onMessageSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ChurchChatService.markThreadLastSeen(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
        ),
      );
    });
    unawaited(_loadInitialSenderProfiles());
    unawaited(_primeRecentMessagesFromCacheOrServer());
    _messagesPrimeFallbackTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_latestRecentDocs.isEmpty) {
        unawaited(_primeRecentMessagesFromCacheOrServer());
      }
    });
    _startPeerPresencePoll();
    if (widget.isDepartment &&
        widget.departmentId != null &&
        widget.departmentId!.isNotEmpty) {
      _deptSub = FirestoreStreamUtils.documentWatchBootstrap(
        FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .collection('departamentos')
            .doc(widget.departmentId!),
      ).listen((snap) {
        if (!mounted) return;
        setState(() => _departmentData = snap.data());
      });
    }
  }

  @override
  void dispose() {
    MemberProfilePhotoSyncNotifier.instance.removeListener(_photoSyncListener);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScrollPagination);
    _ctrl.removeListener(_onComposeTyping);
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    _msgSearchDebounce?.cancel();
    _msgSearchCtrl.removeListener(_onMessageSearchChanged);
    unawaited(
      ChurchChatService.clearTypingForMe(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
      ),
    );
    _messagesSub?.cancel();
    _threadSub?.cancel();
    _deptSub?.cancel();
    _peerPresencePoll?.cancel();
    _messagesPrimeFallbackTimer?.cancel();
    _voiceTicker?.cancel();
    unawaited(_chatAudio.dispose());
    _prefsSub?.cancel();
    _msgSearchCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppFinalizeBootstrap.onAppResume());
      unawaited(
        ChurchChatService.markThreadLastSeen(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
        ),
      );
      unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
    }
  }

  /// Controle Total: `.get()` com cache/retry — não culpa a rede do utilizador.
  Future<void> _primeRecentMessagesFromCacheOrServer({bool silent = false}) async {
    if (_messagesPrimeInFlight) return;
    _messagesPrimeInFlight = true;
    try {
      const rounds = 4;
      for (var round = 0; round < rounds; round++) {
        try {
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: round > 0);
          final docs = await ChurchChatService.fetchRecentMessagesPage(
            tenantId: widget.tenantId,
            threadId: widget.threadId,
          );
          if (!mounted) return;
          if (docs.isEmpty && _latestRecentDocs.isNotEmpty) return;
          setState(() => _latestRecentDocs = docs);
          return;
        } catch (_) {
          if (round < rounds - 1) {
            await Future<void>.delayed(
              Duration(milliseconds: 180 + round * 220),
            );
            continue;
          }
        }
      }
      if (!silent && mounted && _latestRecentDocs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'A carregar mensagens — puxe para atualizar ou toque em Tentar de novo.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      _messagesPrimeInFlight = false;
    }
  }

  void _onScrollPagination() {
    if (!_scroll.hasClients) return;
    if (_msgSearchCtrl.text.trim().isNotEmpty) return;
    if (_loadingMoreHistory) return;
    final p = _scroll.position;
    if (p.maxScrollExtent <= 0) return;
    if (p.pixels >= p.maxScrollExtent - 160) {
      unawaited(_loadOlderHistory());
    }
  }

  DateTime _messageCreatedAt(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final raw = d.data()['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeVisibleMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> recent,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in recent) {
      byId[d.id] = d;
    }
    for (final d in _olderMessageDocs) {
      byId.putIfAbsent(d.id, () => d);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => _messageCreatedAt(b).compareTo(_messageCreatedAt(a)));
    return merged;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestLoadedDoc() {
    final all = _mergeVisibleMessages(_latestRecentDocs);
    if (all.isEmpty) return null;
    return all.last;
  }

  Future<void> _loadOlderHistory() async {
    if (_loadingMoreHistory || !_hasMoreOlderHistory) return;
    if (_olderPagesLoaded >= ChurchChatService.maxOlderMessagePages) return;
    final oldest = _oldestLoadedDoc();
    if (oldest == null) return;
    final now = DateTime.now();
    if (_lastHistoryLoadBump != null &&
        now.difference(_lastHistoryLoadBump!).inMilliseconds < 700) {
      return;
    }
    _lastHistoryLoadBump = now;
    setState(() => _loadingMoreHistory = true);
    try {
      final page = await ChurchChatService.loadOlderMessagesPage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        startAfterDoc: oldest,
      );
      if (!mounted) return;
      setState(() {
        _loadingMoreHistory = false;
        if (page.isEmpty) {
          _hasMoreOlderHistory = false;
        } else {
          _olderPagesLoaded++;
          for (final d in page) {
            if (!_olderMessageDocs.any((x) => x.id == d.id)) {
              _olderMessageDocs.add(d);
            }
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreHistory = false);
    }
  }

  void _openForwardSheet(String messageId, Map<String, dynamic> m) {
    unawaited(
      ChurchChatForwardSheet.show(
        context,
        tenantId: widget.tenantId,
        sourceThreadId: widget.threadId,
        messageId: messageId,
        messageData: m,
      ),
    );
  }

  void _onMessagesStreamEvent(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    _messagesStreamReady = true;
    final incoming = snap.docs;
    var changed = false;
    if (incoming.isNotEmpty) {
      final prevLen = _latestRecentDocs.length;
      final prevHead = prevLen > 0 ? _latestRecentDocs.first.id : '';
      if (prevLen != incoming.length || prevHead != incoming.first.id) {
        _latestRecentDocs = incoming;
        changed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scheduleEnsureSenderProfilesForDocs(incoming);
          }
        });
      }
    } else if (_latestRecentDocs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
        }
      });
    }
    if (changed) setState(() {});
  }

  void _onThreadStreamEvent(DocumentSnapshot<Map<String, dynamic>> thrSnap) {
    if (!mounted) return;
    if (!widget.isDepartment &&
        widget.peerUid != null &&
        widget.peerUid!.isNotEmpty) {
      final mm = thrSnap.data()?['lastSeenAtByUid'];
      if (mm is Map) {
        final v = mm[widget.peerUid!];
        if (v is Timestamp) {
          _threadPeerSeenAt = v;
          _syncPeerReadStatus(v);
        }
      }
    }
    final threadMap = thrSnap.data();
    if (threadMap == null) return;
    final tm = threadMap['titlesByUid'];
    if (tm is! Map) return;
    final titles = <String, String>{};
    for (final e in tm.entries) {
      titles[e.key.toString()] = e.value.toString();
    }
    if (titles.length == _titlesByUid.length &&
        titles.entries.every(
          (e) => _titlesByUid[e.key] == e.value,
        )) {
      return;
    }
    setState(() => _titlesByUid = titles);
  }

  void _onMessageSearchChanged() {
    if (!_searchingMessages) return;
    _msgSearchDebounce?.cancel();
    _msgSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final q = _msgSearchCtrl.text.trim().toLowerCase();
      if (q == _messageSearchQuery) return;
      setState(() => _messageSearchQuery = q);
    });
  }

  void _onComposeTyping() {
    if (_voiceRecording) return;
    final t = _ctrl.text;
    if (t.isEmpty) {
      _typingDebounce?.cancel();
      _typingIdleTimer?.cancel();
      unawaited(
        ChurchChatService.clearTypingForMe(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
        ),
      );
      return;
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      final label = ChurchChatService.senderDisplayNameForNewMessage();
      unawaited(
        ChurchChatService.setTypingActive(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
          active: true,
          displayLabel: label,
        ),
      );
      _typingIdleTimer?.cancel();
      _typingIdleTimer = Timer(const Duration(seconds: 4), () {
        unawaited(
          ChurchChatService.clearTypingForMe(
            tenantId: widget.tenantId,
            threadId: widget.threadId,
          ),
        );
      });
    });
  }

  Widget _buildTypingStrip(String myUid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChurchChatService.typingCol(widget.tenantId, widget.threadId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final now = DateTime.now();
        final names = <String>[];
        var unnamed = 0;
        var recording = 0;
        for (final d in snap.data!.docs) {
          if (d.id == myUid) continue;
          final data = d.data();
          final ts = data['updatedAt'];
          if (ts is! Timestamp) continue;
          if (now.difference(ts.toDate()).inSeconds > 5) continue;
          final lb = (data['label'] ?? '').toString().trim();
          if (lb == ChurchChatService.typingLabelRecording) {
            recording++;
          } else if (lb.isNotEmpty) {
            names.add(lb);
          } else {
            unnamed++;
          }
        }
        if (names.isEmpty && unnamed == 0 && recording == 0) {
          return const SizedBox.shrink();
        }
        final text = () {
          if (recording > 0 && names.isEmpty && unnamed == 0) {
            return recording == 1
                ? 'A gravar áudio…'
                : '$recording pessoas a gravar áudio…';
          }
          if (names.isEmpty) {
            return unnamed == 1
                ? 'A digitar…'
                : '$unnamed pessoas a digitar…';
          }
          if (unnamed == 0) {
            return names.length == 1
                ? '${names.first} está a digitar…'
                : '${names.join(', ')} estão a digitar…';
          }
          return '${names.join(', ')} e mais $unnamed a digitar…';
        }();
        return Material(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: ThemeCleanPremium.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyDraftBar() {
    final d = _replyDraft;
    if (d == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Responder',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
                Text(
                  d.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyDraft = null),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancelar resposta',
          ),
        ],
      ),
    );
  }

  static String _fmtMsgTime(Timestamp ts) {
    final d = ts.toDate();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _messageHaystack(Map<String, dynamic> m) {
    final sb = StringBuffer();
    final sn = (m['senderDisplayName'] ?? '').toString().trim();
    if (sn.isNotEmpty) sb.write('${sn.toLowerCase()} ');
    final prefix = sb.toString();
    final type = (m['type'] ?? 'text').toString();
    if (type == 'text') {
      return '$prefix${(m['text'] ?? '').toString().toLowerCase()}';
    }
    if (type == 'image') return '$prefix' 'imagem foto imagem';
    if (type == 'video') return '$prefix' 'vídeo video';
    if (type == 'audio') return '$prefix' 'áudio audio';
    if (type == 'document') {
      final fn = (m['fileName'] ?? '').toString().toLowerCase();
      return '$prefix' 'documento pdf word excel ficheiro arquivo $fn';
    }
    if (type == 'sticker') return '$prefix' 'figurinha sticker emoji';
    return '$prefix${type.toLowerCase()}';
  }

  String _senderDisplayForMessage(
    String senderUid,
    Map<String, String> titlesByUid,
    Map<String, dynamic> m,
  ) {
    final fromMsg = (m['senderDisplayName'] ?? '').toString().trim();
    if (fromMsg.isNotEmpty) return fromMsg;
    final fromThread = titlesByUid[senderUid]?.trim();
    if (fromThread != null && fromThread.isNotEmpty) return fromThread;
    if (senderUid.length >= 4) {
      return 'Membro ···${senderUid.substring(senderUid.length - 4)}';
    }
    return 'Membro';
  }

  Widget _buildReactionsStrip(
    Map<String, dynamic> m,
    String myUid,
    bool mine,
  ) {
    final r = m['reactionsByUid'];
    if (r is! Map || r.isEmpty) return const SizedBox.shrink();
    final chips = <Widget>[];
    r.forEach((k, v) {
      final uid = k.toString();
      final em = v.toString();
      if (em.isEmpty) return;
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6, top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: uid == myUid
                    ? ThemeCleanPremium.primary.withValues(alpha: 0.4)
                    : ThemeCleanPremium.primary.withValues(alpha: 0.06),
              ),
            ),
            child: Text(em, style: const TextStyle(fontSize: 14)),
          ),
        ),
      );
    });
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        alignment: mine ? WrapAlignment.end : WrapAlignment.start,
        children: chips,
      ),
    );
  }

  Future<void> _sendText() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    ));
    final replyPayload = _replyDraft?.toReplyPayload();
    final mentions = _mentionedUidsPending.isEmpty
        ? null
        : _mentionedUidsPending.toList();
    _ctrl.clear();
    if (mounted) {
      setState(() {
        _replyDraft = null;
        _mentionedUidsPending.clear();
      });
    }
    final localId = 't_${DateTime.now().millisecondsSinceEpoch}';
    final pending = ChurchChatOutboundPending(
      localId: localId,
      kind: 'text',
      fileName: '',
      mime: 'text/plain',
      textBody: t,
      replyPreview: replyPayload?['preview']?.toString(),
      replyToData: replyPayload,
      mentionedUids: mentions,
    );
    _enqueuePending(pending);
    _setPendingProgress(localId, 0.12);
    ChurchChatInstantSendService.enqueueText(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      text: t,
      replyTo: replyPayload,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      mentionedUids: mentions,
      onComplete: (ok) {
        if (!mounted) return;
        if (ok) {
          _removePending(localId);
        } else {
          final i =
              _pendingOutbound.indexWhere((p) => p.localId == localId);
          if (i >= 0) {
            _pendingOutbound[i].failed = true;
            _pendingOutbound[i].errorMessage =
                'Não foi possível enviar. Toque para tentar de novo.';
            setState(() {});
          }
        }
      },
      onError: (msg) {
        if (!mounted) return;
        final i = _pendingOutbound.indexWhere((p) => p.localId == localId);
        if (i >= 0) {
          _pendingOutbound[i].failed = true;
          _pendingOutbound[i].errorMessage = msg;
          setState(() {});
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: ThemeCleanPremium.error),
        );
      },
    );
  }

  void _retryPendingText(ChurchChatOutboundPending p) {
    final t = (p.textBody ?? '').trim();
    if (t.isEmpty) return;
    p.failed = false;
    p.errorMessage = null;
    _setPendingProgress(p.localId, 0.12);
    if (mounted) setState(() {});
    ChurchChatInstantSendService.enqueueText(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      text: t,
      replyTo: p.replyToData,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      mentionedUids: p.mentionedUids,
      onComplete: (ok) {
        if (!mounted) return;
        if (ok) {
          _removePending(p.localId);
        } else if (mounted) {
          p.failed = true;
          p.errorMessage = 'Não foi possível enviar.';
          setState(() {});
        }
      },
      onError: (msg) {
        if (!mounted) return;
        p.failed = true;
        p.errorMessage = msg;
        setState(() {});
      },
    );
  }

  Future<void> _openExpressionSheet() async {
    if (_voiceRecording) return;
    await showChurchChatExpressionSheet(
      context: context,
      tenantId: widget.tenantId,
      textEditingController: _ctrl,
      initialTabIndex: 0,
      onStickerChosen: (pick) async {
        await _sendStickerPick(pick);
      },
    );
  }

  Future<void> _sendStickerPick(ChurchStickerPick pick) async {
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    ));
    final replyPayload = _replyDraft?.toReplyPayload();
    final sp = pick.storagePath?.trim();
    if (mounted) setState(() => _replyDraft = null);
    ChurchChatInstantSendService.enqueueSticker(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      downloadUrl: pick.mediaUrl,
      storagePath: (sp != null && sp.isNotEmpty) ? sp : null,
      stickerSource: pick.stickerSource,
      replyTo: replyPayload,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      onComplete: (ok) {
        if (!ok || !mounted) return;
        unawaited(
          ChurchChatExpressionPrefs.rememberStickerSent(
            tenantId: widget.tenantId,
            mediaUrl: pick.mediaUrl,
            storagePath: pick.storagePath,
            stickerSource: pick.stickerSource,
          ),
        );
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: ThemeCleanPremium.error),
        );
      },
    );
  }

  void _showEmojiReactionPicker(String messageId, Map<String, dynamic> m) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];
    final myUid = firebaseDefaultAuth.currentUser?.uid ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Escolha uma reação',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in emojis)
                    Material(
                      color: ThemeCleanPremium.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final rx = m['reactionsByUid'];
                          String? next = e;
                          if (rx is Map && rx[myUid]?.toString() == e) {
                            next = null;
                          }
                          final ok =
                              await ChurchChatService.setMyReactionOnMessage(
                            tenantId: widget.tenantId,
                            threadId: widget.threadId,
                            messageId: messageId,
                            emoji: next,
                          );
                          if (!mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Não foi possível guardar a reação.',
                                ),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDeptMentionPicker() async {
    final deptId = widget.departmentId?.trim() ?? '';
    if (!widget.isDepartment || deptId.isEmpty) return;
    final docs = await ChurchChatService.fetchActiveDepartmentMembers(
      tenantId: widget.tenantId,
      departmentId: deptId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeCleanPremium.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.alternate_email_rounded,
                          color: ThemeCleanPremium.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Mencionar membro',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data();
                      final name = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                          .toString()
                          .trim();
                      final pickName = name.isEmpty ? 'Membro' : name;
                      final authUid =
                          (d['authUid'] ?? '').toString().trim();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ThemeCleanPremium.primary
                              .withValues(alpha: 0.15),
                          child: Text(
                            pickName.isNotEmpty
                                ? pickName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.primary,
                            ),
                          ),
                        ),
                        title: Text(pickName),
                        subtitle: authUid.isEmpty
                            ? null
                            : Text(
                                authUid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (authUid.isNotEmpty) {
                            setState(() {
                              _mentionedUidsPending.add(authUid);
                            });
                          }
                          final insert = '@$pickName ';
                          final t = _ctrl.text;
                          final s = _ctrl.selection;
                          final start =
                              s.start >= 0 ? s.start : t.length;
                          final end = s.end >= 0 ? s.end : t.length;
                          final newText =
                              t.replaceRange(start, end, insert);
                          _ctrl.value = TextEditingValue(
                            text: newText,
                            selection: TextSelection.collapsed(
                              offset: start + insert.length,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMessageActions(
    String messageId,
    Map<String, dynamic> m,
    String senderUid,
  ) {
    final myUid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (ChurchChatService.messageHiddenForMe(m, myUid)) return;
    final mine = senderUid == myUid && myUid.isNotEmpty;

    final canEveryone = ChurchChatModeration.canDeleteMessageForEveryone(
      senderUid: senderUid,
      isDepartmentThread: widget.isDepartment,
      memberRole: widget.memberRole,
      memberCpfDigits: widget.memberCpfDigits,
      departmentData: _departmentData,
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply_rounded,
                  color: ThemeCleanPremium.primary),
              title: const Text('Responder'),
              subtitle: const Text('Citar esta mensagem na resposta.'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyDraft = _ReplyDraft.fromMessageDoc(messageId, m);
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.forward_rounded,
                  color: ThemeCleanPremium.primary),
              title: const Text('Reencaminhar'),
              subtitle: const Text('Enviar cópia para outra conversa.'),
              onTap: () {
                Navigator.pop(ctx);
                _openForwardSheet(messageId, m);
              },
            ),
            if ((m['type'] ?? 'text').toString() == 'text')
              ListTile(
                leading: Icon(Icons.copy_rounded,
                    color: ThemeCleanPremium.primary),
                title: const Text('Copiar texto'),
                onTap: () async {
                  final tx = (m['text'] ?? '').toString();
                  Navigator.pop(ctx);
                  if (tx.isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: tx));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copiado para a área de transferência.'),
                    ),
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.emoji_emotions_outlined,
                  color: ThemeCleanPremium.primary),
              title: const Text('Reagir'),
              subtitle: const Text('Emoji nesta mensagem.'),
              onTap: () {
                Navigator.pop(ctx);
                _showEmojiReactionPicker(messageId, m);
              },
            ),
            ListTile(
              leading: Icon(
                _prefs.isMessageStarred(widget.threadId, messageId)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: const Color(0xFFF59E0B),
              ),
              title: Text(
                _prefs.isMessageStarred(widget.threadId, messageId)
                    ? 'Remover dos favoritos'
                    : 'Favoritar mensagem',
              ),
              subtitle: const Text(
                'Marcar como importante (só para si, nesta conversa).',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final starred =
                    _prefs.isMessageStarred(widget.threadId, messageId);
                final ok = await ChurchChatMemberPrefs.setMessageStarred(
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  messageId: messageId,
                  value: !starred,
                );
                if (!mounted) return;
                if (!ok && !starred) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Limite de ${ChurchChatMemberPrefs.maxStarredMessagesPerThread} '
                        'favoritas nesta conversa (máx. '
                        '${ChurchChatMemberPrefs.maxStarredMessagesTotal} no total).',
                      ),
                    ),
                  );
                  return;
                }
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      starred
                          ? 'Removida dos favoritos.'
                          : 'Mensagem favorita.',
                    ),
                  ),
                );
              },
            ),
            if (mine)
              ListTile(
                leading: Icon(Icons.help_outline_rounded,
                    color: ThemeCleanPremium.primary),
                title: const Text('Remover ou ocultar…'),
                subtitle: const Text(
                  'Cancelar, apagar só para si ou para todos nesta conversa.',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_showSenderRemovalChoice(
                    messageId: messageId,
                    canDeleteForEveryone: canEveryone,
                  ));
                },
              )
            else ...[
              ListTile(
                leading: Icon(Icons.visibility_off_outlined,
                    color: ThemeCleanPremium.primary),
                title: const Text('Apagar para mim'),
                subtitle: const Text(
                  'Some só na sua vista — os outros não são afetados.',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_confirmHideMessageForMe(messageId));
                },
              ),
              if (canEveryone)
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded,
                      color: ThemeCleanPremium.error),
                  title: const Text('Apagar para todos'),
                  subtitle: Text(
                    widget.isDepartment
                        ? (senderUid == myUid
                            ? 'Remove para todos neste grupo.'
                            : 'Remoção global (moderador: pastor, gestor, ADM ou líder do departamento).')
                        : 'Remove para ambos na conversa direta.',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_confirmDeleteForEveryone(messageId));
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmHideMessageForMe(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar para mim'),
        content: const Text(
          'Esta mensagem deixa de aparecer para si. Os outros participantes continuam a vê-la.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar para mim'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await ChurchChatService.hideMessageForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      messageId: messageId,
    );
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar a mensagem.'),
        ),
      );
    }
  }

  Future<void> _confirmDeleteForEveryone(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar para todos'),
        content: const Text(
          'Esta mensagem será removida para todos nesta conversa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar para todos'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await ChurchChatService.deleteMessage(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      messageId: messageId,
    );
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível apagar. Em grupos: pode apagar para todos só as suas mensagens, '
            'ou use conta de moderador (pastor/gestor/ADM/líder do departamento) para as dos outros.',
          ),
        ),
      );
    }
  }

  /// Mensagem própria: um diálogo com Cancelar / para mim / para todos (alinhado ao pedido de UX).
  Future<void> _showSenderRemovalChoice({
    required String messageId,
    required bool canDeleteForEveryone,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover mensagem'),
        content: const Text(
          'Escolha o que deseja fazer com a sua mensagem nesta conversa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: const Text('Apagar para mim'),
          ),
          if (canDeleteForEveryone)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              style: TextButton.styleFrom(foregroundColor: ThemeCleanPremium.error),
              child: const Text('Apagar para todos'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'me') {
      final done = await ChurchChatService.hideMessageForMe(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        messageId: messageId,
      );
      if (!mounted) return;
      if (!done) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar a mensagem.'),
          ),
        );
      }
      return;
    }
    if (choice == 'all') {
      final done = await ChurchChatService.deleteMessage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        messageId: messageId,
      );
      if (!mounted) return;
      if (!done) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível apagar. Em grupos: pode apagar para todos só as suas mensagens, '
              'ou use conta de moderador (pastor/gestor/ADM/líder do departamento) para as dos outros.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showAttachmentSheet() async {
    unawaited(FeedPostMediaUpload.warmAuthToken().catchError((_) {}));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: churchChatWhatsPremiumLinearGradient,
                  boxShadow: [
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.42),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Text(
                        'Vários ficheiros de cada vez',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.98),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(20),
                elevation: 8,
                shadowColor: Colors.black26,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (!kIsWeb)
                          _WhatsStyleAttachTile(
                            icon: Icons.perm_media_rounded,
                            label: 'Galeria',
                            subtitle: 'fotos e vídeos',
                            color: const Color(0xFF169D5B),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_pickMixedMediaFromGallery());
                            },
                          ),
                        if (kIsWeb) ...[
                          _WhatsStyleAttachTile(
                            icon: Icons.collections_rounded,
                            label: 'Fotos',
                            subtitle: 'várias',
                            color: const Color(0xFF169D5B),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_pickImagesFromGallery());
                            },
                          ),
                          _WhatsStyleAttachTile(
                            icon: Icons.video_library_rounded,
                            label: 'Vídeos',
                            subtitle: 'vários',
                            color: const Color(0xFF7C3AED),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_pickVideosFromGallery());
                            },
                          ),
                        ],
                        _WhatsStyleAttachTile(
                          icon: Icons.photo_camera_rounded,
                          label: 'Câmara',
                          color: const Color(0xFF0EA5E9),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickImage(ImageSource.camera));
                          },
                        ),
                        if (!kIsWeb)
                          _WhatsStyleAttachTile(
                            icon: Icons.video_library_rounded,
                            label: 'Vídeos',
                            subtitle: 'vários',
                            color: const Color(0xFF7C3AED),
                            onTap: () {
                              Navigator.pop(ctx);
                              unawaited(_pickVideosFromGallery());
                            },
                          ),
                        _WhatsStyleAttachTile(
                          icon: Icons.videocam_rounded,
                          label: 'Gravar',
                          color: const Color(0xFFDB2777),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickVideo(ImageSource.camera));
                          },
                        ),
                        _WhatsStyleAttachTile(
                          icon: Icons.description_rounded,
                          label: 'Doc.',
                          subtitle: 'PDF Word ZIP',
                          color: const Color(0xFFEA580C),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickDocument());
                          },
                        ),
                        _WhatsStyleAttachTile(
                          icon: Icons.audio_file_rounded,
                          label: 'Áudio',
                          subtitle: 'vários',
                          color: const Color(0xFF4F46E5),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickAudioFile());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _warmChatFirebaseForPicker() {
    unawaited(ensureFirebaseReadyForChatSend().catchError((_) {}));
    unawaited(
      FastMediaPublishBootstrap.warmForChatSend()
          .timeout(const Duration(seconds: 3))
          .catchError((_) {}),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    _warmChatFirebaseForPicker();
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: source,
      imageQuality: mediaChatImageQuality,
      maxWidth: mediaChatImageMaxWidth.toDouble(),
      maxHeight: mediaChatImageMaxHeight.toDouble(),
    );
    if (x == null) return;
    if (mounted) {
      ImmediateMediaAttachFeedback.showArquivoAnexado(
        context,
        x.name.isNotEmpty ? x.name : 'foto.jpg',
      );
    }
    unawaited(_sendPickedImageFile(
      x,
      previewBeforeSend: kIsWeb || source == ImageSource.camera,
    ));
  }

  /// Android/iOS: uma seleção com fotos e vídeos (como galeria de avisos/eventos).
  Future<void> _pickMixedMediaFromGallery() async {
    _warmChatFirebaseForPicker();
    final r = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    var imgCount = 0;
    var vidCount = 0;
    final toSend = <PlatformFile>[];
    for (final f in r.files) {
      final name = f.name.isNotEmpty ? f.name : 'ficheiro';
      final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
      final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
        fileName: name,
        mime: mime,
      );
      if (kind == 'image') {
        if (imgCount >= kChatMaxImagesPerPick) continue;
        imgCount++;
        toSend.add(f);
      } else if (kind == 'video') {
        if (vidCount >= kChatMaxVideosPerPick) continue;
        vidCount++;
        toSend.add(f);
      }
    }
    if (toSend.isEmpty) {
      if (mounted) {
        _showChatAttachmentError(
          'Nenhuma foto ou vídeo válido na seleção.',
        );
      }
      return;
    }
    if (r.files.length > toSend.length && mounted) {
      _showChatAttachmentError(
        'Limite: até $kChatMaxImagesPerPick fotos e $kChatMaxVideosPerPick vídeos por envio.',
      );
    }
    if (!mounted) return;
    final albumId = _newAlbumGroupIdIfBatch(toSend.length);
    if (toSend.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A enviar ${toSend.length} ficheiro(s)…'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    for (var i = 0; i < toSend.length; i++) {
      if (!mounted) return;
      unawaited(_sendPickedPlatformFile(
        toSend[i],
        albumGroupId: albumId,
        albumIndex: i,
        albumCount: toSend.length,
      ));
    }
  }

  Future<void> _pickImagesFromGallery() async {
    _warmChatFirebaseForPicker();
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(
      imageQuality: mediaChatImageQuality,
      maxWidth: mediaChatImageMaxWidth.toDouble(),
      maxHeight: mediaChatImageMaxHeight.toDouble(),
      limit: kChatMaxImagesPerPick,
    );
    if (list.isEmpty) return;
    if (!mounted) return;
    final albumId = _newAlbumGroupIdIfBatch(list.length);
    if (list.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A enviar ${list.length} foto(s)…'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    for (var i = 0; i < list.length; i++) {
      if (!mounted) return;
      unawaited(_sendPickedImageFile(
        list[i],
        previewBeforeSend: false,
        albumGroupId: albumId,
        albumIndex: i,
        albumCount: list.length,
      ));
    }
  }

  Future<void> _sendPickedImageFile(
    XFile x, {
    bool previewBeforeSend = false,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    if (!mounted) return;
    final name = x.name.isNotEmpty ? x.name : 'foto.jpg';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    if (previewBeforeSend && (x.path ?? '').isNotEmpty) {
      final ok = await showChurchChatMediaPreviewSheet(
        context,
        localPath: !kIsWeb ? x.path : null,
        previewBytes: kIsWeb
            ? Uint8List.fromList(await x.readAsBytes())
            : null,
        title: 'Enviar foto',
        isVideo: false,
      );
      if (!ok || !mounted) return;
    }
    if (!kIsWeb && (x.path ?? '').isNotEmpty) {
      unawaited(_uploadAndSendFromPath(
        x.path!,
        name,
        mime,
        kind,
        albumGroupId: albumGroupId,
        albumIndex: albumIndex,
        albumCount: albumCount,
      ));
      return;
    }
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    if (previewBeforeSend && kIsWeb) {
      final ok = await showChurchChatMediaPreviewSheet(
        context,
        previewBytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        title: 'Enviar foto',
        isVideo: false,
      );
      if (!ok || !mounted) return;
    }
    unawaited(_uploadAndSend(
      bytes,
      name,
      mime,
      kind,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
    ));
  }

  Future<void> _pickVideosFromGallery() async {
    _warmChatFirebaseForPicker();
    final r = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final files = r.files.take(kChatMaxVideosPerPick).toList();
    if (r.files.length > files.length && mounted) {
      _showChatAttachmentError(
        'Só os primeiros $kChatMaxVideosPerPick vídeos serão enviados.',
      );
    }
    final albumId = _newAlbumGroupIdIfBatch(files.length);
    if (files.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A enviar ${files.length} vídeo(s)…'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      unawaited(_sendPickedPlatformFile(
        files[i],
        defaultVideoName: 'video_$i.mp4',
        albumGroupId: albumId,
        albumIndex: i,
        albumCount: files.length,
      ));
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    _warmChatFirebaseForPicker();
    final picker = ImagePicker();
    final x = await picker.pickVideo(
      source: source,
      maxDuration: mediaVideoMaxDurationEffective,
    );
    if (x == null) return;
    if (!mounted) return;
    unawaited(_sendPickedVideoXFile(
      x,
      previewBeforeSend: kIsWeb || source == ImageSource.camera,
    ));
  }

  Future<void> _sendPickedVideoXFile(
    XFile x, {
    required bool previewBeforeSend,
  }) async {
    var name = x.name.isNotEmpty ? x.name : 'video.mp4';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    if (previewBeforeSend && !kIsWeb && x.path != null && x.path!.isNotEmpty) {
      final ok = await showChurchChatMediaPreviewSheet(
        context,
        localPath: x.path,
        title: 'Enviar vídeo',
        isVideo: true,
      );
      if (!ok || !mounted) return;
    }
    if (!kIsWeb && x.path != null && x.path!.isNotEmpty) {
      unawaited(_uploadAndSendFromPath(x.path!, name, mime, kind));
      return;
    }
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    if (bytes.length > mediaChatVideoHardMaxBytesEffective) {
      _showChatAttachmentError(
        'Vídeo demasiado grande. Escolha um ficheiro até '
        '${(mediaChatVideoHardMaxBytesEffective / (1024 * 1024)).round()} MB.',
      );
      return;
    }
    if (previewBeforeSend && kIsWeb) {
      final previewBytes = bytes.length <= 6 * 1024 * 1024
          ? (bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
          : null;
      final ok = await showChurchChatMediaPreviewSheet(
        context,
        previewBytes: previewBytes,
        localPath: previewBytes == null && (x.path ?? '').isNotEmpty
            ? x.path
            : null,
        title: 'Enviar vídeo',
        isVideo: true,
      );
      if (!ok || !mounted) return;
    }
    unawaited(_uploadAndSend(bytes, name, mime, kind));
  }

  Future<void> _sendPickedPlatformFile(
    PlatformFile f, {
    String? defaultVideoName,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    final name = f.name.isNotEmpty
        ? f.name
        : (defaultVideoName ?? 'ficheiro');
    final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(name);
    if (blocked != null) {
      _showChatAttachmentError(blocked);
      return;
    }
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    final maxB = _maxBytesForChatKind(kind);
    if (f.bytes != null && maxB != null && f.bytes!.length > maxB) {
      _showChatAttachmentError(
        '«$name» é demasiado grande (máx. ${maxB ~/ (1024 * 1024)} MB).',
      );
      return;
    }
    if (!kIsWeb && (f.path ?? '').isNotEmpty) {
      unawaited(_uploadAndSendFromPath(
        f.path!,
        name,
        mime,
        kind,
        albumGroupId: albumGroupId,
        albumIndex: albumIndex,
        albumCount: albumCount,
      ));
      return;
    }
    if (f.bytes == null || f.bytes!.isEmpty) {
      _showChatAttachmentError(
        'Não foi possível ler «$name». Tente outro ficheiro.',
      );
      return;
    }
    if (kind == 'video' && f.bytes!.length > mediaChatVideoHardMaxBytesEffective) {
      _showChatAttachmentError(
        '«$name» é demasiado grande (máx. '
        '${(mediaChatVideoHardMaxBytesEffective / (1024 * 1024)).round()} MB).',
      );
      return;
    }
    unawaited(_uploadAndSend(
      f.bytes!,
      name,
      mime,
      kind,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
    ));
  }

  void _onMemberProfilePhotoSynced() {
    final uid =
        MemberProfilePhotoSyncNotifier.instance.lastAuthUid?.trim() ?? '';
    if (uid.isEmpty) return;
    final peer = widget.peerUid?.trim() ?? '';
    final me = firebaseDefaultAuth.currentUser?.uid?.trim() ?? '';
    if (uid != peer && uid != me) return;
    unawaited(_refreshSenderProfilesForAuthUids({uid}));
  }

  Future<void> _refreshSenderProfilesForAuthUids(Set<String> authUids) async {
    if (authUids.isEmpty) return;
    final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
      tenantId: widget.tenantId,
      authUids: authUids,
      refetchAuthUids: authUids,
    );
    if (!mounted || loaded.isEmpty) return;
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(widget.tenantId, loaded.values);
    setState(() => _senderMemberByUid = {..._senderMemberByUid, ...loaded});
  }

  Future<void> _loadInitialSenderProfiles() async {
    final uids = <String>{};
    final peer = widget.peerUid?.trim() ?? '';
    if (peer.isNotEmpty) uids.add(peer);
    final me = firebaseDefaultAuth.currentUser?.uid;
    if (me != null && me.isNotEmpty) uids.add(me);
    if (uids.isEmpty) return;
    final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
      tenantId: widget.tenantId,
      authUids: uids,
    );
    if (!mounted || loaded.isEmpty) return;
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(widget.tenantId, loaded.values);
    setState(() => _senderMemberByUid = {..._senderMemberByUid, ...loaded});
  }

  void _ensureSenderProfiles(Iterable<String> senderUids) {
    final missing = senderUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !_senderMemberByUid.containsKey(e))
        .toSet();
    if (missing.isEmpty) return;
    unawaited(_loadSenderProfilesForUids(missing));
  }

  Future<void> _loadSenderProfilesForUids(Set<String> missing) async {
    if (missing.isEmpty) return;
    try {
      final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
        tenantId: widget.tenantId,
        authUids: missing,
      );
      if (!mounted || loaded.isEmpty) return;
      ChurchGalleryPhotoWarmup.warmBytesForChatRefs(
        widget.tenantId,
        loaded.values,
      );
      setState(() => _senderMemberByUid = {..._senderMemberByUid, ...loaded});
    } catch (_) {}
  }

  void _scheduleEnsureSenderProfilesForDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return;
    final uids = docs
        .map((d) => (d.data()['senderUid'] ?? '').toString())
        .where((e) => e.isNotEmpty);
    _ensureSenderProfiles(uids);
  }

  void _startPeerPresencePoll() {
    _peerPresencePoll?.cancel();
    final peer = widget.peerUid?.trim() ?? '';
    if (peer.isEmpty || widget.isDepartment) return;
    Future<void> poll() async {
      final map = await ChurchChatService.fetchPresenceOnlineMap(
        tenantId: widget.tenantId,
        authUids: [peer],
      );
      if (!mounted) return;
      setState(() => _peerOnline = map[peer] ?? false);
    }

    unawaited(poll());
    _peerPresencePoll = Timer.periodic(
      const Duration(seconds: 22),
      (_) => unawaited(poll()),
    );
  }

  String? _newAlbumGroupIdIfBatch(int count) {
    if (count < 2) return null;
    return 'alb_${DateTime.now().millisecondsSinceEpoch}_${count}';
  }

  int? _pendingAlbumAnchorListIndex(String? albumGroupId) {
    if ((albumGroupId ?? '').isEmpty) return null;
    var anchor = -1;
    for (var i = 0; i < _pendingOutbound.length; i++) {
      final p = _pendingOutbound[i];
      if (p.albumGroupId == albumGroupId) {
        if (anchor < 0 || i > anchor) anchor = i;
      }
    }
    return anchor < 0 ? null : anchor;
  }

  void _enqueuePending(ChurchChatOutboundPending pending) {
    if (!mounted) return;
    setState(() => _pendingOutbound.insert(0, pending));
    _warmPendingImagePreview(pending);
  }

  void _warmPendingImagePreview(ChurchChatOutboundPending pending) {
    if (pending.kind != 'image' || kIsWeb) return;
    final path = pending.localPath?.trim() ?? '';
    if (path.isEmpty) return;
    unawaited(() async {
      try {
        final f = File(path);
        if (!await f.exists()) return;
        if (await f.length() > 380 * 1024) return;
        final b = await f.readAsBytes();
        if (!mounted) return;
        final i =
            _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
        if (i < 0) return;
        _pendingOutbound[i].previewBytes = Uint8List.fromList(b);
        if (mounted) setState(() {});
      } catch (_) {}
    }());
  }

  void _syncPeerReadStatus(Timestamp? peerSeenAt) {
    if (peerSeenAt == null ||
        widget.isDepartment ||
        widget.peerUid == null ||
        widget.peerUid!.isEmpty) {
      return;
    }
    final ms = peerSeenAt.millisecondsSinceEpoch;
    if (ms <= (_lastPeerReadSyncMs ?? 0)) return;
    _lastPeerReadSyncMs = ms;
    unawaited(
      ChurchChatService.markOutboundMessagesReadUpTo(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        peerSeenAt: peerSeenAt.toDate(),
      ),
    );
  }

  void _removePending(String localId) {
    if (!mounted) return;
    final removed =
        _pendingOutbound.where((p) => p.localId == localId).toList();
    setState(() => _pendingOutbound.removeWhere((p) => p.localId == localId));
    for (final p in removed) {
      p.dispose();
    }
  }

  void _setPendingProgress(String localId, double progress) {
    final i = _pendingOutbound.indexWhere((p) => p.localId == localId);
    if (i < 0) return;
    final p = _pendingOutbound[i];
    final clamped = progress.clamp(0.0, 1.0);
    p.progress = clamped;
    if ((p.progressListenable.value - clamped).abs() > 0.01 ||
        clamped >= 1 ||
        clamped <= 0.01) {
      p.progressListenable.value = clamped;
    }
  }

  /// Stub Firestore imediato (padrão Controle Total: BD primeiro, ficheiro depois).
  Future<void> _startPendingFirestoreStub(ChurchChatOutboundPending pending) async {
    if ((pending.firestoreMessageId ?? '').trim().isNotEmpty) return;
    await ensureFirebaseReadyForChatSend();
    final begun = await ChurchChatService.beginMediaUploadMessage(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      kind: pending.kind,
      fileName: pending.kind == 'document' ? pending.fileName : null,
      replyTo: pending.albumIndex == 0 ? _replyDraft?.toReplyPayload() : null,
      senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      albumGroupId: pending.albumGroupId,
      albumIndex: pending.albumIndex,
      albumCount: pending.albumCount,
    ).timeout(const Duration(seconds: 20));
    pending.firestoreMessageId = begun.messageId;
    pending.storagePath = begun.storagePath;
    _setPendingProgress(pending.localId, 0);
    unawaited(
      ChurchChatService.patchMediaUploadProgress(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        messageId: begun.messageId,
        progress: 0,
        force: true,
      ),
    );
    unawaited(ChurchChatMediaOutboxService.updateStub(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      localId: pending.localId,
      firestoreMessageId: begun.messageId,
      storagePath: begun.storagePath,
    ));
    if (mounted) setState(() => _replyDraft = null);
  }

  Future<void> _flushPendingUpload({
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
  }) async {
    await OptimisticChatMediaUpload.flush(
      pending: pending,
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      bytes: bytes,
      localPath: localPath,
      replyTo: null,
      onProgress: (p) => _setPendingProgress(pending.localId, p),
      onSuccess: () {
        unawaited(ChurchChatMediaOutboxService.clearJob(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
          localId: pending.localId,
        ));
        _removePending(pending.localId);
      },
      onFailed: (msg) {
        final i =
            _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
        if (i >= 0) {
          _pendingOutbound[i].failed = true;
          _pendingOutbound[i].errorMessage = msg;
          if (mounted) setState(() {});
        }
      },
      onWaitingForNetwork: () {
        final i =
            _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
        if (i >= 0) {
          _pendingOutbound[i].failed = false;
          _pendingOutbound[i].errorMessage = 'Aguardando conexão…';
          if (mounted) setState(() {});
        }
      },
    );
  }

  Future<List<int>?> _bytesForPendingUpload({
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    }
    final path = localPath?.trim() ?? pending.localPath?.trim() ?? '';
    if (!kIsWeb && path.isNotEmpty) {
      pending.localPath ??= path;
      // Mobile: Storage por [putFile] — não ler vídeo/PDF inteiro na RAM.
      if (pending.kind == 'image') {
        try {
          pending.previewBytes = await SafeImageBytes.fromPath(
            path,
            maxEdge: 480,
            quality: 68,
          );
        } catch (_) {}
      }
      return null;
    }
    if (path.isEmpty || kIsWeb) return null;
    final raw = await churchChatReadFileBytes(path);
    if (raw == null || raw.isEmpty) return null;
    final u8 = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (pending.kind == 'image') {
      pending.previewBytes = u8;
    }
    if (u8.length <= 48 * 1024 * 1024) {
      unawaited(
        ChurchChatPendingMediaCache.put(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
          localId: pending.localId,
          bytes: u8,
        ),
      );
    }
    return u8;
  }

  int? _maxBytesForChatKind(String kind) {
    switch (kind) {
      case 'video':
        return mediaChatVideoHardMaxBytesEffective;
      case 'document':
        return kChatMaxDocumentBytes;
      case 'audio':
        return 32 * 1024 * 1024;
      default:
        return null;
    }
  }

  Future<void> _enqueueAndUploadPending({
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
  }) async {
    _enqueuePending(pending);
    _setPendingProgress(pending.localId, 0.02);
    unawaited(
      runChatMediaUploadTask(() async {
        final bytesFuture = _bytesForPendingUpload(
          pending: pending,
          bytes: bytes,
          localPath: localPath,
        );
        try {
          await _startPendingFirestoreStub(pending);
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
        }
        final uploadBytes = await bytesFuture;
        await _flushPendingUpload(
          pending: pending,
          bytes: uploadBytes,
          localPath: localPath,
        );
      }, debugLabel: 'chat_media_enqueue').catchError((Object e, StackTrace st) {
        YahwehFlowLog.error('CHAT', e, st);
        final i =
            _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
        if (i >= 0) {
          _pendingOutbound[i].failed = true;
          _pendingOutbound[i].errorMessage =
              ChurchChatService.formatInstantSendError(e);
          if (mounted) setState(() {});
        }
      }),
    );
  }

  void _showChatAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ThemeCleanPremium.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _uploadAndSendFromPath(
    String localPath,
    String name,
    String mime,
    String kind, {
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(name);
    if (blocked != null) {
      _showChatAttachmentError(blocked);
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    ));
    // Enfileira imediatamente (estilo WhatsApp): evita bloquear envio lendo bytes antes.
    Uint8List? previewBytes;
    final pending = ChurchChatOutboundPending(
      localId: 'p_${DateTime.now().millisecondsSinceEpoch}_${albumIndex}',
      kind: kind,
      fileName: name,
      mime: mime,
      localPath: localPath,
      previewBytes: previewBytes,
      replyPreview: albumIndex == 0 ? _replyDraft?.preview : null,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
    );
    unawaited(_enqueueAndUploadPending(
      pending: pending,
      bytes: null,
      localPath: localPath,
    ));
  }

  Future<void> _pickDocument() async {
    _warmChatFirebaseForPicker();
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ChurchChatAttachmentUtils.documentPickerExtensions,
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final files = r.files.take(kChatMaxDocumentsPerPick).toList();
    if (r.files.length > files.length && mounted) {
      _showChatAttachmentError(
        'Só os primeiros $kChatMaxDocumentsPerPick documentos serão enviados.',
      );
    }
    if (files.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A enviar ${files.length} ficheiro(s)…'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      final f = files[i];
      final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(
        f.name.isNotEmpty ? f.name : 'ficheiro',
      );
      if (blocked != null) {
        _showChatAttachmentError(blocked);
        continue;
      }
      await _sendPickedPlatformFile(f);
      if (i < files.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  Future<void> _pickAudioFile() async {
    _warmChatFirebaseForPicker();
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: const [
        'm4a',
        'aac',
        'mp3',
        'wav',
        'ogg',
        'opus',
        'flac',
      ],
      withData: kIsWeb,
    );
    if (r == null || r.files.isEmpty) return;
    final files = r.files.take(kChatMaxAudioFilesPerPick).toList();
    if (r.files.length > files.length && mounted) {
      _showChatAttachmentError(
        'Só os primeiros $kChatMaxAudioFilesPerPick áudios serão enviados.',
      );
    }
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      unawaited(
          _sendPickedPlatformFile(files[i], defaultVideoName: 'audio_$i.m4a'));
    }
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String name,
    String mime,
    String kind, {
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(name);
    if (blocked != null) {
      _showChatAttachmentError(blocked);
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    ));
    final preview = kind == 'image'
        ? (bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
        : null;
    final pending = ChurchChatOutboundPending(
      localId: 'p_${DateTime.now().millisecondsSinceEpoch}_${albumIndex}',
      kind: kind,
      fileName: name,
      mime: mime,
      previewBytes: preview,
      replyPreview: albumIndex == 0 ? _replyDraft?.preview : null,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
    );
    unawaited(_enqueueAndUploadPending(
      pending: pending,
      bytes: bytes,
      localPath: null,
    ));
  }

  Widget _buildPendingOutboundBubble(
    ChurchChatOutboundPending p,
    String myUid,
  ) {
    final maxBubbleW = MediaQuery.sizeOf(context).width * 0.78;
    Widget body;
    if (p.kind == 'text') {
      final t = (p.textBody ?? '').trim();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((p.replyPreview ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                p.replyPreview!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: ThemeCleanPremium.onSurface.withValues(alpha: 0.55),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          Text(
            t,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ],
      );
    } else if (p.kind == 'image' && p.previewBytes != null) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.memory(
              p.previewBytes!,
              width: 200,
              fit: BoxFit.cover,
            ),
            if (!p.failed)
              ValueListenableBuilder<double>(
                valueListenable: p.progressListenable,
                builder: (context, progress, _) {
                  if (progress >= 1) return const SizedBox.shrink();
                  return Container(
                    width: 200,
                    height: 200,
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    } else if (!kIsWeb &&
        p.localPath != null &&
        p.localPath!.isNotEmpty &&
        (p.kind == 'image' || p.kind == 'video')) {
      final f = File(p.localPath!);
      body = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(
              f,
              width: 200,
              height: p.kind == 'video' ? 140 : 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 200,
                height: 120,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
            if (p.kind == 'video')
              Icon(
                Icons.play_circle_fill_rounded,
                size: 48,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            if (!p.failed && (p.kind == 'image' || p.kind == 'video'))
              ValueListenableBuilder<double>(
                valueListenable: p.progressListenable,
                builder: (context, progress, _) {
                  if (progress >= 1) return const SizedBox.shrink();
                  return Container(
                    width: 200,
                    height: p.kind == 'video' ? 140 : 200,
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    } else if (p.kind == 'audio') {
      body = ValueListenableBuilder<double>(
        valueListenable: p.progressListenable,
        builder: (context, progress, _) {
          return ChurchChatUploadProgressIndicator(
            progress: p.failed ? null : progress,
            label: p.failed
                ? (p.errorMessage ?? 'Falha no envio')
                : 'A enviar áudio',
            icon: p.failed ? Icons.error_outline_rounded : Icons.mic_rounded,
            compact: true,
          );
        },
      );
    } else {
      body = ValueListenableBuilder<double>(
        valueListenable: p.progressListenable,
        builder: (context, progress, _) {
          return ChurchChatUploadProgressIndicator(
            progress: p.failed ? null : progress,
            label: p.failed
                ? (p.errorMessage ?? 'Falha no envio')
                : 'A enviar ${p.fileName}',
            icon: p.failed
                ? Icons.error_outline_rounded
                : Icons.insert_drive_file_outlined,
            compact: true,
          );
        },
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxBubbleW),
        margin: const EdgeInsets.only(bottom: 4, left: 56, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ChurchChatSenderPalette.outgoingBubbleBackground
              .withValues(alpha: p.failed ? 0.55 : 0.92),
          borderRadius: ChurchChatSenderPalette.bubbleBorderRadius(mine: true),
          border: Border.all(
            color: p.failed
                ? ThemeCleanPremium.error.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            const SizedBox(height: 6),
            if (!p.failed && p.kind != 'text')
              ValueListenableBuilder<double>(
                valueListenable: p.progressListenable,
                builder: (context, progress, _) => LinearProgressIndicator(
                  value: progress > 0 && progress < 1 ? progress : null,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else if (p.failed)
              TextButton(
                onPressed: () {
                  if (p.kind == 'text') {
                    _retryPendingText(p);
                    return;
                  }
                  p.failed = false;
                  p.errorMessage = null;
                  p.firestoreMessageId = null;
                  p.storagePath = null;
                  if (mounted) setState(() {});
                  unawaited(() async {
                    try {
                      await _startPendingFirestoreStub(p);
                    } catch (_) {
                      return;
                    }
                    await _flushPendingUpload(
                      pending: p,
                      bytes: p.previewBytes != null
                          ? p.previewBytes!.toList()
                          : null,
                      localPath: p.localPath,
                    );
                  }());
                },
                child: const Text('Tentar de novo'),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtMsgTime(Timestamp.fromDate(p.createdAt)),
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeCleanPremium.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  p.failed
                      ? Icons.error_outline_rounded
                      : (p.progress >= 1
                          ? Icons.done_all_rounded
                          : Icons.schedule_rounded),
                  size: 14,
                  color: p.failed
                      ? ThemeCleanPremium.error
                      : ThemeCleanPremium.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingAlbumBubble(
    List<ChurchChatOutboundPending> group,
    String myUid,
  ) {
    final maxBubbleW = MediaQuery.sizeOf(context).width * 0.78;
    final cells = <ChurchChatAlbumCell>[
      for (final p in group)
        ChurchChatAlbumCell(
          previewBytes: p.previewBytes,
          localPath: p.localPath,
          type: p.kind == 'video' ? 'video' : 'image',
        ),
    ];
    final failed = group.any((p) => p.failed);
    final avgProgress = group.isEmpty
        ? 0.0
        : group.map((p) => p.progress).reduce((a, b) => a + b) / group.length;
    final lead = group.first;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxBubbleW),
        margin: const EdgeInsets.only(bottom: 4, left: 56, right: 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ChurchChatSenderPalette.outgoingBubbleBackground
              .withValues(alpha: failed ? 0.55 : 0.92),
          borderRadius: ChurchChatSenderPalette.bubbleBorderRadius(mine: true),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ChurchChatAlbumGrid(
                  items: cells,
                  maxWidth: maxBubbleW - 8,
                ),
                if (!failed && avgProgress < 1)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            value: avgProgress > 0.02 ? avgProgress : null,
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmtMsgTime(Timestamp.fromDate(lead.createdAt)),
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeCleanPremium.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : (avgProgress >= 1
                          ? Icons.done_all_rounded
                          : Icons.schedule_rounded),
                  size: 14,
                  color: failed
                      ? ThemeCleanPremium.error
                      : ThemeCleanPremium.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatVoiceDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }

  Future<void> _toggleVoiceRecordSend() async {
    if (_voiceRecording) {
      await _finishVoiceRecording(send: true);
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    _warmChatFirebaseForPicker();
    try {
      final startedPath = await _chatAudio.startRecording();
      if (startedPath == null && !kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Permissão de microfone necessária para gravar.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gravar: $e')),
        );
      }
      return;
    }

    setState(() {
      _voiceRecording = true;
      _voiceElapsed = Duration.zero;
    });
    unawaited(
      ChurchChatService.setTypingActive(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        active: true,
        displayLabel: ChurchChatService.typingLabelRecording,
      ),
    );

    _voiceTicker?.cancel();
    _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _voiceElapsed += const Duration(seconds: 1);
        if (_voiceElapsed.inSeconds >= _maxVoiceSeconds) {
          _voiceTicker?.cancel();
          unawaited(_finishVoiceRecording(send: true));
        }
      });
    });
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    _voiceTicker?.cancel();
    _voiceTicker = null;
    unawaited(
      ChurchChatService.clearTypingForMe(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
      ),
    );

    setState(() {
      _voiceRecording = false;
      _voiceElapsed = Duration.zero;
    });

    if (!send) {
      await _chatAudio.stopRecording(send: false);
      return;
    }

    final voicePath = await _chatAudio.stopRecording(send: true);
    if (kIsWeb) {
      final bytes = _chatAudio.takeWebRecordingBytes();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível obter o áudio gravado. Tente de novo ou use Anexos → áudio.',
              ),
            ),
          );
        }
        return;
      }
      final name =
          'voice_${DateTime.now().millisecondsSinceEpoch}.${bytes.length > 4 && bytes[0] == 0x4F && bytes[1] == 0x67 ? 'ogg' : 'm4a'}';
      final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
      unawaited(_uploadAndSend(bytes, name, mime, 'audio'));
      return;
    }
    if (voicePath == null || voicePath.isEmpty) return;

    final path = voicePath;
    final lower = path.toLowerCase();
    final ext = lower.endsWith('.wav') ? 'wav' : 'm4a';
    final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    unawaited(_uploadAndSendFromPath(path, name, mime, 'audio'));
  }

  Future<void> _openAttachmentExternally(String rawUrl) async {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      _showChatAttachmentError('Ficheiro indisponível.');
      return;
    }
    try {
      String resolved = raw;
      if (StorageMediaService.isFirebaseStorageMediaUrl(raw) ||
          raw.contains('firebasestorage') ||
          raw.startsWith('gs://') ||
          raw.startsWith('igrejas/')) {
        resolved = await StorageMediaService.freshPlayableMediaUrl(raw);
      } else {
        final alt = await StorageMediaService.downloadUrlFromPathOrUrl(raw);
        if (alt != null && alt.isNotEmpty) {
          resolved = alt;
        }
      }
      final uri = Uri.tryParse(resolved);
      if (uri == null) {
        _showChatAttachmentError('Link do ficheiro inválido.');
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showChatAttachmentError('Não foi possível abrir o ficheiro.');
      }
    } catch (e) {
      _showChatAttachmentError(
        'Erro ao abrir ficheiro: ${formatUploadErrorForUser(e)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    final blockedDm = !widget.isDepartment &&
        widget.peerUid != null &&
        widget.peerUid!.isNotEmpty &&
        _prefs.isBlockedPeer(widget.peerUid!);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: 48,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: churchChatWhatsPremiumLinearGradient,
          ),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: _searchingMessages
                ? 'Fechar pesquisa nas mensagens'
                : 'Pesquisar nas mensagens',
            icon: Icon(
              _searchingMessages ? Icons.close_rounded : Icons.search_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _searchingMessages = !_searchingMessages;
                if (!_searchingMessages) {
                  _msgSearchCtrl.clear();
                  _messageSearchQuery = '';
                }
              });
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Opções',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: ThemeCleanPremium.surface,
            onSelected: (v) async {
              if (v == 'clear_stuck') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Limpar envios presos?'),
                    content: const Text(
                      'Remove do Firestore mensagens suas ainda em envio/upload '
                      'e filas antigas. Mensagens já entregues (✓) não são apagadas.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Limpar'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final r = await ChurchChatStuckCleanupService.purgeAllForTenant(
                  widget.tenantId,
                );
                if (!context.mounted) return;
                final n = r.messages + r.queueDocs;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      n > 0
                          ? 'Removido(s) $n item(ns) do banco (${r.messages} mensagem(ns)).'
                          : 'Nenhum envio preso encontrado no banco.',
                    ),
                  ),
                );
              } else if (v == 'fav') {
                final ok = await ChurchChatMemberPrefs.setFavorite(
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  value: !_prefs.isFavorite(widget.threadId),
                );
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Máximo de ${ChurchChatMemberPrefs.maxFavoriteThreads} favoritos. '
                        'Remova um para adicionar outro.',
                      ),
                    ),
                  );
                }
              } else if (v == 'starred_msgs') {
                final ids =
                    _prefs.starredMessagesInThread(widget.threadId);
                if (!context.mounted) return;
                await ChurchChatStarredMessagesSheet.show(
                  context,
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  messageIds: ids,
                  onOpenMessage: (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Deslize no histórico para encontrar a mensagem favorita.',
                        ),
                      ),
                    );
                  },
                );
              } else if (v == 'mute') {
                await ChurchChatMemberPrefs.setMutedThread(
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  value: !_prefs.isMutedThread(widget.threadId),
                );
              } else if (v == 'hide_dm') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Excluir conversa?'),
                    content: const Text(
                      'Remove esta conversa da sua lista. A outra pessoa '
                      'mantém o histórico — só desaparece para si.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.error,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Excluir'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final ok = await ChurchChatMemberPrefs.setHiddenDmThread(
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  hide: true,
                );
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Limite de conversas ocultas '
                        '(${ChurchChatMemberPrefs.maxHiddenDmThreads}).',
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Conversa removida da sua lista.'),
                    ),
                  );
                  Navigator.of(context).pop();
                }
              } else if (v == 'my_photo') {
                await showChurchChatProfilePhotoSheet(
                  context,
                  tenantId: widget.tenantId,
                  cpfDigits: widget.memberCpfDigits,
                );
                final me = uid;
                if (me.isNotEmpty && mounted) {
                  unawaited(_refreshSenderProfilesForAuthUids({me}));
                }
              } else if (v == 'dept_members' &&
                  widget.isDepartment &&
                  (widget.departmentId ?? '').isNotEmpty) {
                if (!context.mounted) return;
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => ChurchDepartmentChatMembersSheet(
                    navigatorContext: context,
                    tenantId: widget.tenantId,
                    currentUid: uid,
                    departmentId: widget.departmentId!,
                    departmentName: widget.title,
                    departmentDocData: _departmentData,
                    role: widget.memberRole,
                    cpfDigits: widget.memberCpfDigits,
                  ),
                );
              } else if (v == 'block' &&
                  widget.peerUid != null &&
                  widget.peerUid!.isNotEmpty) {
                await ChurchChatMemberPrefs.setBlockedPeer(
                  tenantId: widget.tenantId,
                  peerUid: widget.peerUid!,
                  value: !_prefs.isBlockedPeer(widget.peerUid!),
                );
              } else if (v == 'notif') {
                final cur =
                    await ChurchChatNotificationPrefs.isChatPushEnabled();
                final next = !cur;
                await ChurchChatNotificationPrefs.setChatPushEnabled(
                  enabled: next,
                  tenantId: widget.tenantId,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      next
                          ? 'Notificações do chat ativadas neste aparelho.'
                          : 'Chat silenciado — não receberá avisos de novas mensagens.',
                    ),
                  ),
                );
              } else if (v == 'alert_thread') {
                await showChurchChatThreadForegroundNotifSheet(
                  context: context,
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  title: widget.title,
                );
              } else if (v == 'alert_sound' ||
                  v == 'alert_vibrate' ||
                  v == 'alert_silent') {
                final mode = v == 'alert_sound'
                    ? ChurchChatNotificationPrefs.alertModeSound
                    : v == 'alert_vibrate'
                        ? ChurchChatNotificationPrefs.alertModeVibrate
                        : ChurchChatNotificationPrefs.alertModeSilent;
                await ChurchChatNotificationPrefs.setChatAlertMode(mode: mode);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      mode == ChurchChatNotificationPrefs.alertModeSound
                          ? 'Alerta de conversa: Som + vibrar'
                          : mode == ChurchChatNotificationPrefs.alertModeVibrate
                              ? 'Alerta de conversa: Só vibrar'
                              : 'Alerta de conversa: Silencioso',
                    ),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'my_photo',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.account_circle_outlined,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: const Text('Minha foto de perfil'),
                  subtitle: const Text(
                    'Actualiza no chat e no cadastro de membro',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'clear_stuck',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cleaning_services_rounded,
                    color: Colors.orange.shade800,
                  ),
                  title: const Text('Limpar envios presos'),
                  subtitle: const Text(
                    'Apaga do banco mensagens antigas em upload/fila '
                    '(mantém as já enviadas).',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'fav',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _prefs.isFavorite(widget.threadId)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  title: Text(
                    _prefs.isFavorite(widget.threadId)
                        ? 'Remover dos favoritos'
                        : 'Favoritar conversa',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'starred_msgs',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_purple500_rounded,
                      color: Color(0xFFF59E0B)),
                  title: const Text('Mensagens favoritas'),
                  subtitle: Text(
                    _prefs.starredMessagesInThread(widget.threadId).isEmpty
                        ? 'Nenhuma nesta conversa'
                        : '${_prefs.starredMessagesInThread(widget.threadId).length} '
                            'mensagem(ns)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'mute',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_off_rounded,
                      color: ThemeCleanPremium.primary),
                  title: Text(
                    _prefs.isMutedThread(widget.threadId)
                        ? 'Ativar alertas desta conversa'
                        : 'Silenciar esta conversa',
                  ),
                  subtitle: Text(
                    'Só esta conversa — sem push até reativar.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              if (!widget.isDepartment)
                PopupMenuItem(
                  value: 'hide_dm',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: const Text('Apagar conversa (só para mim)'),
                    subtitle: const Text(
                      'Some da lista de conversas.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              if (widget.isDepartment &&
                  (widget.departmentId ?? '').isNotEmpty)
                PopupMenuItem(
                  value: 'dept_members',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.groups_rounded,
                      color: ThemeCleanPremium.primary,
                    ),
                    title: const Text('Membros do grupo'),
                    subtitle: const Text(
                      'Online/offline e mensagem direta',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              if (!widget.isDepartment &&
                  widget.peerUid != null &&
                  widget.peerUid!.isNotEmpty)
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.block_rounded,
                        color: ThemeCleanPremium.error),
                    title: Text(
                      _prefs.isBlockedPeer(widget.peerUid!)
                          ? 'Desbloquear contacto'
                          : 'Bloquear contacto',
                    ),
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'alert_thread',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.graphic_eq_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: const Text('Alerta desta conversa'),
                  subtitle: Text(
                    _prefs.threadNotifOverride(widget.threadId) == null
                        ? 'Segue DM, grupo ou modo global'
                        : 'Override ativo (som / vibrar / silêncio)',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'alert_sound',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_active_rounded),
                  title: Text('Som + vibrar (conversas)'),
                ),
              ),
              PopupMenuItem(
                value: 'alert_vibrate',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.vibration_rounded),
                  title: Text('Só vibrar (conversas)'),
                ),
              ),
              PopupMenuItem(
                value: 'alert_silent',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_off_rounded),
                  title: Text('Silencioso (conversas)'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'notif',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notifications_active_rounded),
                  title: Text('Silenciar / ativar notificações do chat'),
                  subtitle: Text(
                    'Preferência global — igual às Configurações',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
        title: Row(
          children: [
            if (widget.isDepartment)
              ChurchChatDepartmentAvatar(
                deptData: _departmentData,
                fallbackName: widget.title,
                radius: 19,
              )
            else if (widget.peerUid != null &&
                widget.peerUid!.isNotEmpty)
              ChurchChatPeerAvatar(
                tenantId: widget.tenantId,
                peerAuthUid: widget.peerUid!,
                memberRef: _senderMemberByUid[widget.peerUid!],
                radius: 19,
              )
            else
              CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  widget.title.isNotEmpty
                      ? widget.title[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                    ),
                  ),
                  if (widget.isDepartment)
                    Text(
                      'Grupo · ⋮ Membros para ver quem está online',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    )
                  else if (widget.peerUid != null &&
                      widget.peerUid!.isNotEmpty)
                    Text(
                      _peerOnline ? 'online' : 'offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChurchChatPendingStatusBanner(
            tenantId: widget.tenantId,
            compact: true,
            alwaysOfferClear: true,
            role: widget.memberRole,
          ),
          Expanded(
            child: ColoredBox(
        color: const Color(0xFFF4F6F8),
        child: Column(
          children: [
            if (_searchingMessages)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.cardBackground,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                    ),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: TextField(
                    controller: _msgSearchCtrl,
                    autofocus: true,
                    style: TextStyle(color: ThemeCleanPremium.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar nas mensagens…',
                      hintStyle: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: ThemeCleanPremium.primary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
            if (blockedDm)
              Material(
                color: ThemeCleanPremium.error.withValues(alpha: 0.12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded, color: ThemeCleanPremium.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bloqueou este contacto. Abra o menu ⋮ para desbloquear e voltar a enviar.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            RepaintBoundary(child: _buildTypingStrip(uid)),
            Expanded(
              child: RepaintBoundary(
                child: Builder(
                  builder: (context) {
                    if (!_messagesStreamReady && _latestRecentDocs.isEmpty) {
                      return YahwehSkeletonLoading.chatMessages();
                    }
                    final titlesByUid = _titlesByUid;
                    final docsRaw =
                        _mergeVisibleMessages(_latestRecentDocs);
                    final visibleDocs = docsRaw
                        .where((d) => !ChurchChatService.messageHiddenForMe(
                              d.data(),
                              uid,
                            ))
                        .toList();
                    final hideFirestoreMsgIds = _pendingOutbound
                        .map((p) => p.firestoreMessageId?.trim() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toSet();
                    final pendingOutgoingTexts = <String>{
                      for (final p in _pendingOutbound)
                        if (p.kind == 'text' && !p.failed && !p.cancelled)
                          (p.textBody ?? '').trim(),
                    }..removeWhere((s) => s.isEmpty);
                    final hasActivePending = _pendingOutbound.any(
                      (p) => !p.failed && !p.cancelled,
                    );
                    var streamDocs = visibleDocs.where((d) {
                      if (hideFirestoreMsgIds.contains(d.id)) return false;
                      final m = d.data();
                      if (pendingOutgoingTexts.isNotEmpty) {
                        final sender = (m['senderUid'] ?? '').toString();
                        if (sender == uid &&
                            (m['type'] ?? 'text').toString() == 'text') {
                          final txt = (m['text'] ?? '').toString().trim();
                          if (pendingOutgoingTexts.contains(txt)) {
                            return false;
                          }
                        }
                      }
                      final delivery =
                          (m['deliveryStatus'] ?? '').toString();
                      if (delivery == 'uploading') {
                        final created = m['createdAt'];
                        if (created is Timestamp) {
                          final age = DateTime.now()
                              .difference(created.toDate());
                          if (age > const Duration(minutes: 12)) {
                            unawaited(
                              ChurchChatService.abandonMediaUploadMessage(
                                tenantId: widget.tenantId,
                                threadId: widget.threadId,
                                messageId: d.id,
                              ),
                            );
                            return false;
                          }
                        }
                        if (hasActivePending &&
                            (m['senderUid'] ?? '').toString() == uid) {
                          return false;
                        }
                      }
                      return true;
                    }).toList();
                    final q = _messageSearchQuery;
                    final docs = q.isEmpty
                        ? streamDocs
                        : streamDocs
                            .where((d) =>
                                _messageHaystack(d.data()).contains(q))
                            .toList();
                    if (docs.isEmpty && _pendingOutbound.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            q.isEmpty
                                ? 'Sem mensagens ainda.'
                                : 'Nenhuma mensagem correspondente.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }
                    final pendingCount = _pendingOutbound.length;
                    final historyTail = (_loadingMoreHistory ||
                            (_hasMoreOlderHistory && docs.isNotEmpty))
                        ? 1
                        : 0;
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      itemCount: docs.length + pendingCount + historyTail,
                      itemBuilder: (_, i) {
                        if (i >= docs.length + pendingCount) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loadingMoreHistory
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          );
                        }
                        if (i < pendingCount) {
                          final p = _pendingOutbound[pendingCount - 1 - i];
                          final anchorIdx =
                              _pendingAlbumAnchorListIndex(p.albumGroupId);
                          if (anchorIdx != null &&
                              _pendingOutbound[anchorIdx] != p) {
                            return const SizedBox.shrink();
                          }
                          if (anchorIdx != null &&
                              (p.albumGroupId ?? '').isNotEmpty) {
                            final group = _pendingOutbound
                                .where((x) => x.albumGroupId == p.albumGroupId)
                                .toList()
                              ..sort((a, b) =>
                                  a.albumIndex.compareTo(b.albumIndex));
                            return _buildPendingAlbumBubble(group, uid);
                          }
                          return _buildPendingOutboundBubble(p, uid);
                        }
                        final docIndex = i - pendingCount;
                        final anchor =
                            ChurchChatAlbumUtils.anchorDocIndexOrNull(
                                docs, docIndex);
                        if (anchor == null) {
                          return const SizedBox.shrink();
                        }
                        final m = docs[docIndex].data();
                        final albumDocs =
                            ChurchChatAlbumUtils.albumGroupIdFrom(m) != null
                                ? ChurchChatAlbumUtils.collectAlbumDocs(
                                    docs, docIndex)
                                : null;
                        final isAlbumBubble =
                            albumDocs != null && albumDocs.length > 1;
                        final mine = (m['senderUid'] ?? '').toString() == uid;
                        final type = (m['type'] ?? 'text').toString();
                        final createdRaw = m['createdAt'];
                        Timestamp? ct;
                        if (createdRaw is Timestamp) ct = createdRaw;
                        final ps = _threadPeerSeenAt;
                        final dsRaw =
                            (m['deliveryStatus'] ?? '').toString();
                        final peerRead = dsRaw ==
                                ChurchChatService.deliveryRead ||
                            (ps != null &&
                                ct != null &&
                                ps.millisecondsSinceEpoch >=
                                    ct.millisecondsSinceEpoch);
                        final messageId = docs[docIndex].id;
                        DateTime? msgWhen;
                        if (ct != null) msgWhen = ct.toDate();
                        DateTime? olderWhen;
                        if (docIndex + 1 < docs.length) {
                          final olderRaw = docs[docIndex + 1].data()['createdAt'];
                          if (olderRaw is Timestamp) {
                            olderWhen = olderRaw.toDate();
                          }
                        }
                        final showDate = msgWhen != null &&
                            churchChatNeedsDateSeparator(
                              olderMessage: olderWhen,
                              currentMessage: msgWhen,
                            );
                        final senderUid =
                            (m['senderUid'] ?? '').toString();
                        final senderLabel = _senderDisplayForMessage(
                          senderUid,
                          titlesByUid,
                          m,
                        );
                        final groupIncoming =
                            widget.isDepartment && !mine;
                        final quoteAccent = (!mine &&
                                widget.isDepartment)
                            ? ChurchChatSenderPalette
                                .nameColorForUid(senderUid)
                            : null;
                        final maxBubbleW =
                            MediaQuery.sizeOf(context).width * 0.78;
                        final bubbleDecoration = mine
                            ? BoxDecoration(
                                color: ChurchChatSenderPalette
                                    .outgoingBubbleBackground,
                                borderRadius:
                                    ChurchChatSenderPalette.bubbleBorderRadius(
                                  mine: true,
                                ),
                                boxShadow: ChurchChatSenderPalette.bubbleShadow,
                              )
                            : BoxDecoration(
                                color: groupIncoming
                                    ? ChurchChatSenderPalette
                                        .bubbleBackgroundForUid(senderUid)
                                    : ChurchChatSenderPalette
                                        .incomingDmBubbleBackground,
                                borderRadius:
                                    ChurchChatSenderPalette.bubbleBorderRadius(
                                  mine: false,
                                ),
                                border: Border.all(
                                  color: groupIncoming
                                      ? ChurchChatSenderPalette
                                          .bubbleBorderForUid(senderUid)
                                      : const Color(0xFFE2E8F0),
                                  width: 0.6,
                                ),
                                boxShadow: ChurchChatSenderPalette.bubbleShadow,
                              );
                        final bubbleCard = Container(
                            constraints: BoxConstraints(maxWidth: maxBubbleW),
                            margin: EdgeInsets.only(
                              bottom: 4,
                              left: mine ? 56 : (groupIncoming ? 0 : 4),
                              right: mine ? 4 : 56,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isAlbumBubble ? 4 : 12,
                              vertical: isAlbumBubble ? 4 : 8,
                            ),
                            decoration: bubbleDecoration,
                            child: Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isDepartment &&
                                    !mine &&
                                    senderLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      senderLabel,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: ChurchChatSenderPalette
                                            .nameColorForUid(senderUid),
                                      ),
                                    ),
                                  ),
                                _MessageBody(
                                  messageId: messageId,
                                  type: type,
                                  data: m,
                                  mine: mine,
                                  replyQuoteAccent: quoteAccent,
                                  onOpenAttachment: _openAttachmentExternally,
                                  albumDocs: albumDocs,
                                ),
                                _buildReactionsStrip(m, uid, mine),
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_prefs.isMessageStarred(
                                          widget.threadId, messageId))
                                        const Padding(
                                          padding: EdgeInsets.only(right: 4),
                                          child: Icon(
                                            Icons.star_rounded,
                                            size: 14,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ),
                                      if (ct != null)
                                        Text(
                                          _fmtMsgTime(ct),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: mine
                                                ? ThemeCleanPremium.onSurface
                                                    .withValues(alpha: 0.55)
                                                : ThemeCleanPremium
                                                    .onSurfaceVariant,
                                          ),
                                        ),
                                      if (mine) ...[
                                        const SizedBox(width: 5),
                                        ChurchChatDeliveryStatusIcon(
                                          deliveryStatus: peerRead
                                              ? ChurchChatService.deliveryRead
                                              : dsRaw,
                                          mine: true,
                                          peerRead: !widget.isDepartment &&
                                              widget.peerUid != null &&
                                              widget.peerUid!.isNotEmpty &&
                                              peerRead,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        return GestureDetector(
                          onLongPress: () {
                            if (ChurchChatService.messageHiddenForMe(m, uid)) {
                              return;
                            }
                            _showMessageActions(messageId, m, senderUid);
                          },
                          onDoubleTap: () {
                            if (ChurchChatService.messageHiddenForMe(m, uid)) {
                              return;
                            }
                            unawaited(
                              ChurchChatService.setMyReactionOnMessage(
                                tenantId: widget.tenantId,
                                threadId: widget.threadId,
                                messageId: messageId,
                                emoji: '❤️',
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.stretch,
                            children: [
                              if (showDate && msgWhen != null)
                                ChurchChatDateSeparatorChip(
                                  label: churchChatDateSeparatorLabel(msgWhen),
                                ),
                              Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: groupIncoming
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          ChurchChatPeerAvatar(
                                            tenantId: widget.tenantId,
                                            peerAuthUid: senderUid,
                                            memberRef:
                                                _senderMemberByUid[senderUid],
                                            radius: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(child: bubbleCard),
                                        ],
                                      )
                                    : bubbleCard,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          RepaintBoundary(
          child: AbsorbPointer(
            absorbing: blockedDm,
            child: SafeArea(
            top: false,
            child: Material(
              elevation: 8,
              shadowColor: Colors.black26,
              color: ThemeCleanPremium.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReplyDraftBar(),
                  if (_voiceRecording)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.error.withValues(alpha: 0.08),
                        border: Border(
                          bottom: BorderSide(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => _finishVoiceRecording(send: false),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ThemeCleanPremium.error,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fiber_manual_record_rounded,
                                    size: 14,
                                    color: ThemeCleanPremium.error),
                                const SizedBox(width: 8),
                                Text(
                                  _formatVoiceDuration(_voiceElapsed),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Text(
                              kIsWeb
                                  ? 'Toque em parar para enviar'
                                  : 'Solte para enviar · deslize para cancelar',
                              maxLines: 2,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 10,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _voiceRecording ? null : _showAttachmentSheet,
                    icon: Icon(Icons.attach_file_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    tooltip: 'Foto, vídeo, documento…',
                  ),
                  if (widget.isDepartment &&
                      (widget.departmentId?.trim().isNotEmpty ?? false))
                    IconButton(
                      onPressed: _voiceRecording
                          ? null
                          : () => unawaited(_openDeptMentionPicker()),
                      icon: Icon(
                        Icons.alternate_email_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                      tooltip: 'Mencionar membro (@)',
                    ),
                  GestureDetector(
                    onLongPressStart: kIsWeb
                        ? null
                        : (_) => unawaited(_startVoiceRecording()),
                    onLongPressEnd: kIsWeb
                        ? null
                        : (_) => unawaited(_finishVoiceRecording(send: true)),
                    onLongPressCancel: kIsWeb
                        ? null
                        : () => unawaited(_finishVoiceRecording(send: false)),
                    child: IconButton(
                      onPressed: _toggleVoiceRecordSend,
                      icon: Icon(
                        _voiceRecording
                            ? Icons.stop_circle_rounded
                            : Icons.mic_rounded,
                        color: _voiceRecording
                            ? ThemeCleanPremium.error
                            : ThemeCleanPremium.onSurfaceVariant,
                      ),
                      tooltip: _voiceRecording
                          ? (kIsWeb ? 'Toque para enviar' : 'Soltar para enviar')
                          : (kIsWeb
                              ? 'Toque para gravar voz'
                              : 'Segure para gravar · toque para modo alternativo'),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_voiceRecording,
                      autocorrect: true,
                      enableSuggestions: true,
                      smartDashesType: SmartDashesType.enabled,
                      smartQuotesType: SmartQuotesType.enabled,
                      /// Sem isto, [inferAndroidSpellCheckConfiguration] mantém spellcheck desligado.
                      spellCheckConfiguration: const SpellCheckConfiguration(),
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        color: ThemeCleanPremium.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: _voiceRecording
                            ? 'A gravar…'
                            : 'Mensagem',
                        hintStyle: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                        prefixIcon: _voiceRecording
                            ? null
                            : IconButton(
                                tooltip: 'Emojis e figurinhas',
                                onPressed: _voiceRecording
                                    ? null
                                    : _openExpressionSheet,
                                icon: Icon(
                                  Icons.emoji_emotions_rounded,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        filled: true,
                        fillColor: ThemeCleanPremium.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          borderSide: BorderSide(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          borderSide: BorderSide(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          borderSide: BorderSide(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 10),
                      ),
                      onSubmitted: _voiceRecording
                          ? null
                          : (_) {
                              _sendText();
                            },
                    ),
                  ),
                  IconButton(
                    onPressed: _voiceRecording ? null : _sendText,
                    icon: Icon(Icons.send_rounded,
                        color: ThemeCleanPremium.primary),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    ),
          ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  final String messageId;
  final String type;
  final Map<String, dynamic> data;
  final bool mine;
  final Color? replyQuoteAccent;
  final Future<void> Function(String rawUrl)? onOpenAttachment;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? albumDocs;

  const _MessageBody({
    required this.messageId,
    required this.type,
    required this.data,
    required this.mine,
    this.replyQuoteAccent,
    this.onOpenAttachment,
    this.albumDocs,
  });

  Widget _replyQuote(BuildContext context) {
    final rt = data['replyTo'];
    if (rt is! Map) return const SizedBox.shrink();
    final preview = (rt['preview'] ?? '').toString();
    if (preview.isEmpty) return const SizedBox.shrink();
    final accent = replyQuoteAccent ?? ThemeCleanPremium.primary;
    return _inlineQuoteBox(
      context,
      label: 'Resposta',
      preview: preview,
      accent: accent,
    );
  }

  Widget _forwardedQuote(BuildContext context) {
    final fwd = data['forwardedFrom'];
    if (fwd is! Map) return const SizedBox.shrink();
    final preview = (fwd['preview'] ?? '').toString();
    if (preview.isEmpty) return const SizedBox.shrink();
    return _inlineQuoteBox(
      context,
      label: 'Reencaminhada',
      preview: preview,
      accent: ThemeCleanPremium.primary.withValues(alpha: 0.75),
    );
  }

  Widget _inlineQuoteBox(
    BuildContext context, {
    required String label,
    required String preview,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: mine
              ? Colors.black.withValues(alpha: 0.06)
              : ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: accent.withValues(alpha: 0.85),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                color: ThemeCleanPremium.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _quotePrefix(BuildContext context) => [
        _forwardedQuote(context),
        _replyQuote(context),
      ];

  Widget _buildAlbumGrid(BuildContext context) {
    final docs = albumDocs!;
    final cells = <ChurchChatAlbumCell>[];
    for (final d in docs) {
      final dm = d.data();
      final t = (dm['type'] ?? 'image').toString();
      final url = (dm['mediaUrl'] ?? '').toString().trim();
      final delivery = (dm['deliveryStatus'] ?? '').toString();
      if (url.isEmpty &&
          (delivery == ChurchChatService.deliveryUploading ||
              delivery == ChurchChatService.deliverySending)) {
        cells.add(ChurchChatAlbumCell(type: t));
        continue;
      }
      cells.add(ChurchChatAlbumCell(
        url: url.isEmpty ? null : url,
        type: t == 'video' ? 'video' : 'image',
        onTap: url.isEmpty
            ? null
            : () => churchChatOpenImageZoom(context, url),
      ));
    }
    final maxW = MediaQuery.sizeOf(context).width * 0.72;
    return ChurchChatAlbumGrid(items: cells, maxWidth: maxW);
  }

  @override
  Widget build(BuildContext context) {
    if (albumDocs != null && albumDocs!.length > 1) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          _buildAlbumGrid(context),
        ],
      );
    }
    if (type == 'text') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          Text(
            (data['text'] ?? '').toString(),
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
        ],
      );
    }
    if (type == 'sticker') {
      final surl = (data['mediaUrl'] ?? '').toString();
      if (surl.isEmpty) {
        return Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._quotePrefix(context),
            const Text('[figurinha indisponível]'),
          ],
        );
      }
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          Container(
            constraints:
                const BoxConstraints(maxWidth: 176, maxHeight: 176),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeNetworkImage(
              imageUrl: surl,
              fit: BoxFit.contain,
              height: 168,
              skipFreshDisplayUrl: true,
            ),
          ),
        ],
      );
    }
    final url = (data['mediaUrl'] ?? '').toString();
    final delivery = (data['deliveryStatus'] ?? '').toString();
    if (url.isEmpty) {
      if (delivery == ChurchChatService.deliveryUploading ||
          delivery == ChurchChatService.deliverySending ||
          delivery == ChurchChatService.deliveryQueued) {
        final progress = (data['uploadProgress'] is num)
            ? (data['uploadProgress'] as num).toDouble().clamp(0.0, 1.0)
            : null;
        final uploadIcon = type == 'video'
            ? Icons.videocam_rounded
            : type == 'audio'
                ? Icons.mic_rounded
                : type == 'image'
                    ? Icons.image_rounded
                    : Icons.cloud_upload_rounded;
        final uploadLabel = type == 'video'
            ? 'A enviar vídeo'
            : type == 'audio'
                ? 'A enviar áudio'
                : 'A enviar ficheiro';
        return Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._quotePrefix(context),
            ChurchChatUploadProgressIndicator(
              progress: progress,
              label: uploadLabel,
              icon: uploadIcon,
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          const Text('[mídia indisponível]'),
        ],
      );
    }
    if (type == 'image') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          LayoutBuilder(
            builder: (context, c) {
              final maxW = c.maxWidth.isFinite ? c.maxWidth : 280.0;
              final w = maxW.clamp(140.0, 280.0);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox(
                  width: w,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        GestureDetector(
                          onTap: () => churchChatOpenImageZoom(context, url),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: SafeNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              width: w,
                              skipFreshDisplayUrl: true,
                              memCacheWidth: (MediaQuery.devicePixelRatioOf(
                                          context) *
                                      w)
                                  .round()
                                  .clamp(96, 320),
                              memCacheHeight: (MediaQuery.devicePixelRatioOf(
                                          context) *
                                      w *
                                      0.75)
                                  .round()
                                  .clamp(72, 240),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.72),
                                ],
                              ),
                            ),
                            child: SafeArea(
                              top: false,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () =>
                                        churchChatOpenImageZoom(context, url),
                                    icon: const Icon(Icons.zoom_in_rounded,
                                        size: 22),
                                    label: const Text(
                                      'Ampliar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () =>
                                        churchChatSaveImageUrl(context, url),
                                    icon: const Icon(Icons.download_rounded,
                                        size: 22),
                                    label: const Text(
                                      'Guardar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }
    if (type == 'video') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ChurchHostedVideoSurface(
                    videoUrl: url,
                    autoPlay: false,
                    layoutAspectRatio: 16 / 9,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF0F172A).withValues(alpha: 0.92),
                        const Color(0xFF1E293B).withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                'Toque no vídeo para reproduzir',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              showChurchHostedVideoTheater(
                                context,
                                videoUrl: url,
                                title: 'Vídeo',
                              );
                            },
                            icon: const Icon(Icons.fullscreen_rounded, size: 22),
                            label: const Text(
                              'Ampliar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => churchChatShareDownloadVideo(
                              context,
                              url,
                              fileName:
                                  (data['fileName'] ?? '').toString(),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 22),
                            label: const Text(
                              'Baixar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (type == 'document') {
      final name = (data['fileName'] ?? 'Documento').toString().trim();
      IconData ic = Icons.insert_drive_file_rounded;
      final lower = name.toLowerCase();
      if (lower.endsWith('.pdf')) {
        ic = Icons.picture_as_pdf_rounded;
      } else if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
        ic = Icons.description_rounded;
      } else if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
        ic = Icons.table_chart_rounded;
      }
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          InkWell(
            onTap: () async {
              await onOpenAttachment?.call(url);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ic, color: const Color(0xFF128C7E)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    name.isEmpty ? 'Documento' : name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (type == 'audio') {
      final sp = (data['storagePath'] ?? '').toString().trim();
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          ChurchChatInlineAudioPlayer(
            mediaUrl: url,
            storagePath: sp.isEmpty ? null : sp,
            messageId: messageId,
            mine: mine,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._quotePrefix(context),
        InkWell(
          onTap: () async {
            await onOpenAttachment?.call(url);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audiotrack_rounded, color: Color(0xFF128C7E)),
              const SizedBox(width: 8),
              Text(
                kIsWeb ? 'Abrir ficheiro' : 'Abrir ficheiro',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Botão circular colorido na folha de anexos (referência visual WhatsApp / Super Premium).
class _WhatsStyleAttachTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _WhatsStyleAttachTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color,
                        Color.lerp(color, Colors.black, 0.12)!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle == null ? label : '$label\n$subtitle',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: ThemeCleanPremium.onSurface.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
