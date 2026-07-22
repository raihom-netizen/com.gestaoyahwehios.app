import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/services/church_chat_optimized_payload_cache.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/features/chat/chat.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatUploadErrorForUser, isFirebaseNoAppError, kFeedPublishQueuedUserMessage;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_album_utils.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_album_grid.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_pending_status_banner.dart';
import 'package:gestao_yahweh/services/church_chat_expression_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_fs.dart'
    show churchChatReadFileBytes;
import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/chat_strict_publish_service.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_moderation.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_chat_local_file_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/church_chat_auto_recovery_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart'
    hide formatUploadErrorForUser;
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_date_separator.dart';
import 'package:gestao_yahweh/services/church_chat_diagnostic_service.dart';
import 'package:gestao_yahweh/services/church_chat_fast_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_instant_send_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_delivery_status.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_media_preview_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_forward_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_telegram_text.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_expression_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_chat_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_inline_audio_player.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_storage_media.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_upload_progress.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_starred_messages_sheet.dart';
import 'package:gestao_yahweh/services/church_chat_stuck_cleanup_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_pending_voice_bubble.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_voice_mic_button.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_sender_palette.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_peer_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_profile_photo_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_whatsapp_theme.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_save_media.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_messaging_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_local_cache_engine.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

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

  /// Web split — conversa embutida ao lado da lista (sem push fullscreen).
  final bool embeddedInSplitPanel;
  final VoidCallback? onSplitPanelClose;

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
    this.embeddedInSplitPanel = false,
    this.onSplitPanelClose,
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
  Future<void>? _voiceStartFuture;
  /// Evita `IconButton.onPressed` após soltar o long-press (reiniciava gravação).
  bool _micLongPressActive = false;
  bool _voiceSlideCancel = false;
  double _voiceSlideOffset = 0;
  static const double _voiceCancelSlideThreshold = 72;
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
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messagesStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _threadStream;
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
  Timer? _webMessagesPoll;
  int? _lastPeerReadSyncMs;
  late final VoidCallback _photoSyncListener;
  final List<ChurchChatOutboundPending> _pendingOutbound = [];
  String? _effectiveTenantId;

  String get _tid => ChurchRepository.churchId(
        (_effectiveTenantId ?? '').trim().isNotEmpty
            ? _effectiveTenantId!
            : widget.tenantId.trim(),
      );

  Future<String> _awaitOperationalTenantId() async {
    final cached = (_effectiveTenantId ?? '').trim();
    if (cached.isNotEmpty) return cached;
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final resolved = tid.trim();
      if (resolved.isEmpty) return widget.tenantId.trim();
      if (mounted && _effectiveTenantId != resolved) {
        setState(() => _effectiveTenantId = resolved);
        _bindChatFirestoreStreams(resolved);
      }
      return resolved;
    } catch (e, st) {
      debugPrint('_awaitOperationalTenantId fallback: $e\n$st');
      return widget.tenantId.trim();
    }
  }

  double _chatBubbleMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final effective = kIsWeb ? w.clamp(0.0, 900.0) : w;
    return effective * 0.78;
  }

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('chat_thread');
    unawaited(
      AppResumeStateService.saveChatThread(
        tenantId: _tid,
        threadId: widget.threadId,
      ),
    );
    unawaited(
      ensureFirebaseReadyForChatSend().catchError((e, st) {
        debugPrint('initState warm ensureFirebaseReadyForChatSend: $e\n$st');
      }),
    );
    unawaited(
      ChurchChatFastSendService.warmSendPipeline().catchError((e, st) {
        debugPrint('initState warm warmSendPipeline: $e\n$st');
      }),
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
    _msgSearchCtrl.addListener(_onMessageSearchChanged);
    _bindChatFirestoreStreams(_tid);
    unawaited(_hydrateMessagesFromLocalCache());
    unawaited(_primeRecentMessagesFromCacheOrServer());
    unawaited(_initChatThreadTenantAndStreams());
    unawaited(_bootstrapThreadUploads());
    Future<void>.delayed(const Duration(seconds: 18), () {
      if (!mounted) return;
      unawaited(
        ChurchChatDiagnosticService.runOnChatOpen(
          tenantIdHint: _tid,
          userUid: firebaseDefaultAuth.currentUser?.uid,
        ),
      );
    });
    _messagesPrimeFallbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (!_messagesStreamReady) {
        setState(() => _messagesStreamReady = true);
      }
      if (_latestRecentDocs.isEmpty) {
        unawaited(_primeRecentMessagesFromCacheOrServer());
      }
    });
    if (kIsWeb) {
      _webMessagesPoll = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!mounted) return;
        unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
      });
    }
    _startPeerPresencePoll();
  }

  Future<void> _initChatThreadTenantAndStreams() async {
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      if (!mounted || tid.trim().isEmpty) return;
      if (tid != _tid) {
        setState(() => _effectiveTenantId = tid);
        _bindChatFirestoreStreams(tid);
        unawaited(_primeRecentMessagesFromCacheOrServer());
      }
    } catch (e, st) {
      debugPrint('_initChatThreadTenantAndStreams: $e\n$st');
    }
    if (!mounted) return;
    if (widget.isDepartment &&
        widget.departmentId != null &&
        widget.departmentId!.isNotEmpty) {
      _deptSub?.cancel();
      _deptSub = FirestoreStreamUtils.documentWatchBootstrap(
                    ChurchUiCollections.departamentos(_tid)
            .doc(widget.departmentId!),
      ).listen((snap) {
        if (!mounted) return;
        setState(() => _departmentData = snap.data());
      });
    }
    unawaited(_loadInitialSenderProfiles());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ChatThreadOperations.markThreadLastSeen(
          tenantId: _tid,
          threadId: widget.threadId,
        ),
      );
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) unawaited(_bootstrapThreadUploads());
      });
    });
  }

  void _bindChatFirestoreStreams(String tid) {
    final tenantId = tid.trim();
    if (tenantId.isEmpty) return;
    _messagesSub?.cancel();
    _threadSub?.cancel();
    _prefsSub?.cancel();
    _messagesStream = ChatThreadOperations.recentMessagesStream(
      tenantId: tenantId,
      threadId: widget.threadId,
    );
    _threadStream = ChatThreadOperations.threadSnapshots(
      tenantId,
      widget.threadId,
    );
    _messagesSub = _messagesStream!.listen(
      _onMessagesStreamEvent,
      onError: (_, __) {
        if (mounted && _latestRecentDocs.isEmpty) {
          setState(() => _messagesStreamReady = true);
        }
      },
    );
    _threadSub = _threadStream!.listen(_onThreadStreamEvent);
    _prefsSub = ChurchChatMemberPrefs.watch(tenantId).listen((snap) {
      if (!mounted) return;
      setState(() => _prefs = ChurchChatMemberPrefs.parse(snap));
    });
  }

  Future<void> _bootstrapThreadUploads() async {
    try {
      await FirestoreWebGuard.prepareForChatWrite().catchError((e, st) {
        debugPrint('_bootstrapThreadUploads prepareForChatWrite: $e\n$st');
      });
      await ChurchChatMediaOutboxService.resumeForThread(
        tenantId: _tid,
        threadId: widget.threadId,
      );
      final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        await ChurchChatAutoRecoveryService.promoteLocalDeliveryAfterSync(
          tenantId: _tid,
          threadId: widget.threadId,
          uid: uid,
        );
        // maxAge > 0: nunca apagar mensagens com upload recente/em curso
        // (Duration.zero apagava mídia acabada de enviar ao reabrir a thread).
        await ChurchChatAutoRecoveryService.recoverStuckForThread(
          tenantId: _tid,
          threadId: widget.threadId,
          uid: uid,
          maxAge: const Duration(minutes: 10),
        );
      }
    } catch (e, st) {
      debugPrint('_bootstrapThreadUploads: $e\n$st');
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
      ChatThreadOperations.clearTypingForMe(
        tenantId: _tid,
        threadId: widget.threadId,
      ),
    );
    _messagesSub?.cancel();
    _threadSub?.cancel();
    _deptSub?.cancel();
    _peerPresencePoll?.cancel();
    _webMessagesPoll?.cancel();
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
      if (!kIsWeb) unawaited(AppFinalizeBootstrap.onAppResume());
      unawaited(
        ChatThreadOperations.markThreadLastSeen(
          tenantId: _tid,
          threadId: widget.threadId,
        ),
      );
      unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
      unawaited(_bootstrapThreadUploads());
      ChurchChatUploadsService.resumeWhenOnline();
    }
  }

  /// Cache local — conversa abre com histórico antes do 1.º snapshot Firestore (web/mobile).
  Future<void> _hydrateMessagesFromLocalCache() async {
    try {
      final cached = await ChatLocalCacheEngine.loadMessagesPage(
        churchId: _tid,
        chatId: widget.threadId,
      );
      if (!mounted || cached.isEmpty) return;
      if (_latestRecentDocs.isNotEmpty) return;
      setState(() {
        _latestRecentDocs = cached;
        _messagesStreamReady = true;
      });
    } catch (e, st) {
      debugPrint('_hydrateMessagesFromLocalCache: $e\n$st');
    }
  }

  /// Controle Total: `.get()` com cache/retry — não culpa a rede do utilizador.
  Future<void> _primeRecentMessagesFromCacheOrServer({bool silent = false}) async {
    if (_messagesPrimeInFlight) return;
    _messagesPrimeInFlight = true;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
          debugPrint(
            '_primeRecentMessagesFromCacheOrServer ensurePanelReadReady: $e\n$st',
          );
        });
      }
      const rounds = 4;
      for (var round = 0; round < rounds; round++) {
        try {
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: round > 0);
          Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> read() =>
              ChatMessagingEngine.openConversation(
                churchId: _tid,
                chatId: widget.threadId,
              );
          final docs = kIsWeb
              ? await FirestoreWebGuard.runWithWebRecovery(
                  read,
                  maxAttempts: 4,
                ).timeout(ChurchPanelReadTimeouts.queryCap)
              : await read().timeout(ChurchPanelReadTimeouts.queryCap);
          if (!mounted) return;
          if (docs.isEmpty && _latestRecentDocs.isNotEmpty) return;
          _prunePendingOutboundMatchedByStream(docs);
          setState(() {
            _latestRecentDocs = docs;
            _messagesStreamReady = true;
          });
          return;
        } catch (e, st) {
          debugPrint(
            '_primeRecentMessagesFromCacheOrServer round=$round: $e\n$st',
          );
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

  String _deliveryStatusForBubble(Map<String, dynamic> m) {
    if (ChurchChatMessageFields.uploadCompleted(m)) {
      return ChatThreadOperations.deliverySent;
    }
    final st = ChurchChatMessageFields.status(m);
    if (st == ChatThreadOperations.deliverySent ||
        st == 'delivered' ||
        st == ChatThreadOperations.deliveryRead) {
      return st;
    }
    if (ChurchChatMessageFields.storagePath(m).isNotEmpty &&
        !ChurchChatMessageFields.isUploadInProgress(m)) {
      return ChatThreadOperations.deliverySent;
    }
    if (ChurchChatMessageFields.storagePath(m).isNotEmpty &&
        ChurchChatMessageFields.storageVerified(m)) {
      return ChatThreadOperations.deliverySent;
    }
    return st;
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
    if (_olderPagesLoaded >= ChatThreadOperations.maxOlderMessagePages) return;
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
      final page = await ChatThreadOperations.loadOlderMessagesPage(
        tenantId: _tid,
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
    } catch (e, st) {
      debugPrint('_loadOlderHistory: $e\n$st');
      if (mounted) setState(() => _loadingMoreHistory = false);
    }
  }

  void _openForwardSheet(String messageId, Map<String, dynamic> m) {
    unawaited(
      ChurchChatForwardSheet.show(
        context,
        tenantId: _tid,
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
      // Aplica SEMPRE o snapshot (não só quando length/head mudam):
      // atualizações de conteúdo (finalize de upload, status) e mensagens novas
      // dentro da mesma página não podem ser ignoradas — senão a mídia «some».
      _latestRecentDocs = incoming;
      changed = true;
      _prunePendingOutboundMatchedByStream(incoming);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scheduleEnsureSenderProfilesForDocs(incoming);
          _tryRecoverStuckUploadingMessages(incoming);
        }
      });
    } else if (_latestRecentDocs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
        }
      });
    }
    if (changed) setState(() {});
  }

  void _tryRecoverStuckUploadingMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final doc in docs) {
      final m = doc.data();
      if ((m['senderUid'] ?? '').toString() != uid) continue;
      if (!ChurchChatMessageFields.isUploadInProgress(m)) continue;
      final sp = ChurchChatMessageFields.storagePath(m);
      if (sp.isEmpty) continue;
      unawaited(
        ChatStrictPublishService.tryFinalizeIfStorageReady(
          tenantId: _tid,
          threadId: widget.threadId,
          messageId: doc.id,
          data: m,
        ).then((ok) {
          if (ok && mounted) setState(() {});
        }),
      );
    }
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
        ChatThreadOperations.clearTypingForMe(
          tenantId: _tid,
          threadId: widget.threadId,
        ),
      );
      return;
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      final label = ChatThreadOperations.senderDisplayNameForNewMessage();
      unawaited(
        ChatThreadOperations.setTypingActive(
          tenantId: _tid,
          threadId: widget.threadId,
          active: true,
          displayLabel: label,
        ),
      );
      _typingIdleTimer?.cancel();
      _typingIdleTimer = Timer(const Duration(seconds: 4), () {
        unawaited(
          ChatThreadOperations.clearTypingForMe(
            tenantId: _tid,
            threadId: widget.threadId,
          ),
        );
      });
    });
  }

  Widget _buildTypingStrip(String myUid) {
    return _ChurchChatTypingPollStrip(
      tenantId: _tid,
      threadId: widget.threadId,
      myUid: myUid,
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
    if (ChurchChatMessageFields.isDocumentType(type)) {
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
    unawaited(ChatThreadOperations.clearTypingForMe(
      tenantId: _tid,
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
    unawaited(
      ChurchChatFastSendService.sendText(
        tenantId: _tid,
        threadId: widget.threadId,
        text: t,
        replyTo: replyPayload,
        senderDisplayName:
            ChatThreadOperations.senderDisplayNameForNewMessage(),
        mentionedUids: mentions,
        onComplete: (ok, {messageId}) {
          _finalizePendingTextSend(
            localId: localId,
            ok: ok,
            messageId: messageId,
          );
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
            SnackBar(
              content: Text(msg),
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        },
      ),
    );
  }

  void _retryPendingText(ChurchChatOutboundPending p) {
    final t = (p.textBody ?? '').trim();
    if (t.isEmpty) return;
    p.failed = false;
    p.errorMessage = null;
    _setPendingProgress(p.localId, 0.12);
    if (mounted) setState(() {});
    unawaited(
      ChurchChatFastSendService.sendText(
        tenantId: _tid,
        threadId: widget.threadId,
        text: t,
        replyTo: p.replyToData,
        senderDisplayName:
            ChatThreadOperations.senderDisplayNameForNewMessage(),
        mentionedUids: p.mentionedUids,
        onComplete: (ok, {messageId}) {
          _finalizePendingTextSend(
            localId: p.localId,
            ok: ok,
            messageId: messageId,
          );
        },
        onError: (msg) {
          if (!mounted) return;
          p.failed = true;
          p.errorMessage = msg;
          setState(() {});
        },
      ),
    );
  }

  Future<void> _openExpressionSheet() async {
    if (_voiceRecording) return;
    await showChurchChatExpressionSheet(
      context: context,
      tenantId: _tid,
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
    unawaited(ChatThreadOperations.clearTypingForMe(
      tenantId: _tid,
      threadId: widget.threadId,
    ));
    final replyPayload = _replyDraft?.toReplyPayload();
    final sp = (pick.storagePath ?? '').trim();
    if (sp.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Figurinha sem caminho no Storage — reenvie ou atualize o app.'),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() => _replyDraft = null);
    ChurchChatInstantSendService.enqueueSticker(
      tenantId: _tid,
      threadId: widget.threadId,
      storagePath: sp,
      stickerSource: pick.stickerSource,
      replyTo: replyPayload,
      senderDisplayName: ChatThreadOperations.senderDisplayNameForNewMessage(),
      onComplete: (ok, {messageId}) {
        if (!ok || !mounted) return;
        unawaited(
          ChurchChatExpressionPrefs.rememberStickerSent(
            tenantId: _tid,
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
                              await ChatThreadOperations.setMyReactionOnMessage(
                            tenantId: _tid,
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
    final docs = await ChatThreadOperations.fetchActiveDepartmentMembers(
      tenantId: _tid,
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
    if (ChatThreadOperations.messageHiddenForMe(m, myUid)) return;
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
                  tenantId: _tid,
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
    final done = await ChatThreadOperations.hideMessageForMe(
      tenantId: _tid,
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
    final done = await ChatThreadOperations.deleteMessage(
      tenantId: _tid,
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
      final done = await ChatThreadOperations.hideMessageForMe(
        tenantId: _tid,
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
      final done = await ChatThreadOperations.deleteMessage(
        tenantId: _tid,
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
    unawaited(
      FeedPostMediaUpload.warmAuthToken().catchError((e, st) {
        debugPrint('_showAttachmentSheet warmAuthToken: $e\n$st');
      }),
    );
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
                          icon: Icons.photo_camera_rounded,
                          label: 'Câmara',
                          color: const Color(0xFF0EA5E9),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickImage(ImageSource.camera));
                          },
                        ),
                        _WhatsStyleAttachTile(
                          icon: Icons.description_rounded,
                          label: 'Doc.',
                          subtitle: 'PDF Word Excel',
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
    unawaited(
      _ensureChatFirebaseReadyForMedia().catchError((e, st) {
        debugPrint('_warmChatFirebaseForPicker ensure media ready: $e\n$st');
        return false;
      }),
    );
    unawaited(
      FirestoreWebGuard.prepareForChatWrite().catchError((e, st) {
        debugPrint('_warmChatFirebaseForPicker prepareForChatWrite: $e\n$st');
      }),
    );
    unawaited(
      ImmediateMediaWarm.warmFeed().catchError((e, st) {
        debugPrint('_warmChatFirebaseForPicker warmFeed: $e\n$st');
      }),
    );
    unawaited(
      FastMediaPublishBootstrap.warmForChatSend()
          .timeout(const Duration(seconds: 3))
          .catchError((e, st) {
            debugPrint(
              '_warmChatFirebaseForPicker warmForChatSend timeout/warm: $e\n$st',
            );
          }),
    );
  }

  Future<bool> _ensureChatFirebaseReadyForMedia() async {
    final ok = await ChatMediaRepository.ensureReadyForPick(
      context: mounted ? context : null,
    );
    if (ok) return true;
    try {
      await ensureFirebaseReadyForChatSend().timeout(
        const Duration(seconds: 10),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    // Telegram: aquecer Firebase em BG — não bloquear a câmara/galeria.
    _warmChatFirebaseForPicker();
    final x = source == ImageSource.camera
        ? await MediaHandlerService.instance.pickAndProcessFromCamera(
            module: YahwehMediaModule.chat,
            context: context,
          )
        : await MediaHandlerService.instance.pickAndProcessFromGallery(
            module: YahwehMediaModule.chat,
            context: context,
          );
    if (x == null) return;
    // WhatsApp: sem snack «Foto adicionada» — a bolha local já confirma o envio.
    unawaited(_sendPickedImageFile(
      x,
      previewBeforeSend: false,
    ));
  }

  Future<void> _pickImagesFromGallery() async {
    _warmChatFirebaseForPicker();
    final list = await MediaHandlerService.instance.pickAndProcessMultipleImages(
      module: YahwehMediaModule.chat,
      context: context,
    );
    if (list.isEmpty) return;
    if (list.length > kChatMaxImagesPerPick) {
      if (mounted) {
        _showChatAttachmentError(
          'Só as primeiras $kChatMaxImagesPerPick fotos serão enviadas.',
        );
      }
    }
    final capped = list.take(kChatMaxImagesPerPick).toList();
    if (capped.isEmpty || !mounted) return;

    final albumId = _newAlbumGroupIdIfBatch(capped.length);
    for (var i = 0; i < capped.length; i++) {
      if (!mounted) return;
      unawaited(_sendPickedImageFile(
        capped[i],
        previewBeforeSend: false,
        albumGroupId: albumId,
        albumIndex: i,
        albumCount: capped.length,
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
      final mat = await ChurchChatLocalFileService.materializeXFile(x);
      if (mat == null || mat.isEmpty) {
        if (mounted) {
          _showChatAttachmentError(
            'Não foi possível ler a foto. Tente outra imagem.',
          );
        }
        return;
      }
      // Bytes-first (igual Web) — evita falha do path efémero no Android.
      try {
        final bytes = await File(mat).readAsBytes();
        if (bytes.isEmpty) {
          if (mounted) {
            _showChatAttachmentError(
              'Foto vazia. Tente outra imagem.',
            );
          }
          return;
        }
        unawaited(_uploadAndSend(
          bytes,
          name,
          mime,
          kind,
          fileSizeBytes: bytes.length,
          albumGroupId: albumGroupId,
          albumIndex: albumIndex,
          albumCount: albumCount,
        ));
      } catch (_) {
        if (mounted) {
          _showChatAttachmentError(
            'Não foi possível ler a foto. Tente outra imagem.',
          );
        }
      }
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

  Future<void> _sendPickedPlatformFile(
    PlatformFile f, {
    String? defaultFileName,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) async {
    final name = f.name.isNotEmpty
        ? f.name
        : (defaultFileName ?? 'ficheiro');
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
    final kindBlocked = ChurchChatAttachmentUtils.blockReasonForChatKind(kind);
    if (kindBlocked != null) {
      _showChatAttachmentError(kindBlocked);
      return;
    }
    if (kind != 'audio' && kind != 'image') {
      final docBlocked =
          ChurchChatAttachmentUtils.blockReasonForDocumentFileName(name);
      if (docBlocked != null) {
        _showChatAttachmentError(docBlocked);
        return;
      }
    }
    final maxB = _maxBytesForChatKind(kind);
    if (f.bytes != null && maxB != null && f.bytes!.length > maxB) {
      _showChatAttachmentError(
        '«$name» é demasiado grande (máx. ${maxB ~/ (1024 * 1024)} MB).',
      );
      return;
    }
    if (!kIsWeb) {
      final mat = await ChurchChatLocalFileService.materializePlatformFile(f);
      if (mat == null || mat.isEmpty) {
        if (mounted) {
          _showChatAttachmentError(
            'Não foi possível ler «$name». Tente outro ficheiro.',
          );
        }
        return;
      }
      unawaited(_uploadAndSendFromPath(
        mat,
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
      try {
        final fileBytes = await utilitariosReadPlatformFileBytes(f);
        unawaited(_uploadAndSend(
          fileBytes,
          name,
          mime,
          kind,
          albumGroupId: albumGroupId,
          albumIndex: albumIndex,
          albumCount: albumCount,
        ));
        return;
      } catch (_) {
        _showChatAttachmentError(
          'Não foi possível ler «$name». Tente outro ficheiro.',
        );
        return;
      }
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
      tenantId: _tid,
      authUids: authUids,
      refetchAuthUids: authUids,
    );
    if (!mounted || loaded.isEmpty) return;
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(_tid, loaded.values);
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
      tenantId: _tid,
      authUids: uids,
    );
    if (!mounted || loaded.isEmpty) return;
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(_tid, loaded.values);
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
        tenantId: _tid,
        authUids: missing,
      );
      if (!mounted || loaded.isEmpty) return;
      ChurchGalleryPhotoWarmup.warmBytesForChatRefs(
        _tid,
        loaded.values,
      );
      setState(() => _senderMemberByUid = {..._senderMemberByUid, ...loaded});
    } catch (e, st) {
      debugPrint('_loadSenderProfilesForUids: $e\n$st');
    }
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
      final map = await ChatThreadOperations.fetchPresenceOnlineMap(
        tenantId: _tid,
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
    if (pending.kind == 'image') {
      _startOptimisticMediaPipeline(pending);
    } else if (pending.kind == 'audio') {
      _setPendingProgress(pending.localId, 0.06);
    }
    Future<void>.delayed(const Duration(seconds: 200), () {
      if (!mounted) return;
      final i = _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
      if (i < 0 || _pendingOutbound[i].failed) return;
      if (_pendingOutbound[i].progress >= 0.99) return;
      _pendingOutbound[i].failed = true;
      _pendingOutbound[i].errorMessage =
          'Envio demorou demais. Toque em «Tentar de novo».';
      if (mounted) setState(() {});
    });
  }

  /// Preview instantâneo + compressão em background (isolate) — estilo WhatsApp.
  void _startOptimisticMediaPipeline(ChurchChatOutboundPending pending) {
    if (pending.kind != 'image') return;
    unawaited(_warmOptimisticImagePreview(pending));
    unawaited(_precompressPendingForUpload(pending));
  }

  Future<void> _warmOptimisticImagePreview(
    ChurchChatOutboundPending pending,
  ) async {
    if (pending.previewBytes != null && pending.previewBytes!.isNotEmpty) {
      return;
    }
    final path = pending.localPath?.trim() ?? '';
    if (path.isEmpty) return;
    try {
      final preview = await MediaOptimizationService.previewFromPath(path);
      if (preview == null || preview.isEmpty || !mounted) return;
      final i = _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
      if (i < 0) return;
      _pendingOutbound[i].previewBytes = preview;
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('_warmOptimisticImagePreview: $e\n$st');
    }
  }

  /// Comprime fora da UI e guarda payload pronto — upload não bloqueia rolagem.
  Future<void> _precompressPendingForUpload(
    ChurchChatOutboundPending pending,
  ) async {
    if (pending.kind != 'image') return;
    try {
      final path = pending.localPath?.trim() ?? '';
      final payload = await MediaOptimizationService.optimizeForChat(
        localPath: path.isNotEmpty ? path : null,
      );
      ChurchChatOptimizedPayloadCache.put(
        localId: pending.localId,
        fullBytes: payload.fullBytes,
        fullMime: payload.fullMime,
        fullFileName: payload.fullFileName,
        thumbBytes: payload.thumbBytes,
        previewBytes: payload.previewBytes,
      );
      if (!mounted) return;
      final i = _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
      if (i < 0) return;
      if (payload.previewBytes != null && payload.previewBytes!.isNotEmpty) {
        _pendingOutbound[i].previewBytes = payload.previewBytes;
      }
      _setPendingProgress(pending.localId, 0.08);
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('_precompressPendingForUpload: $e\n$st');
    }
  }

  void _warmPendingImagePreview(ChurchChatOutboundPending pending) {
    _startOptimisticMediaPipeline(pending);
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
      ChatThreadOperations.markOutboundMessagesReadUpTo(
        tenantId: _tid,
        threadId: widget.threadId,
        peerSeenAt: peerSeenAt.toDate(),
      ),
    );
  }

  void _prunePendingOutboundMatchedByStream(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_pendingOutbound.isEmpty) return;
    final ids = docs.map((d) => d.id).toSet();
    final toRemove = <String>[];
    for (final p in _pendingOutbound) {
      final fid = p.firestoreMessageId?.trim() ?? '';
      if (fid.isNotEmpty && ids.contains(fid)) {
        toRemove.add(p.localId);
        continue;
      }
      final sp = p.storagePath?.trim() ?? '';
      if (sp.isEmpty) continue;
      for (final d in docs) {
        if (ChurchChatMessageFields.storagePath(d.data()).trim() == sp) {
          toRemove.add(p.localId);
          break;
        }
      }
    }
    if (toRemove.isEmpty) return;
    for (final lid in toRemove) {
      _removePending(lid);
    }
  }

  void _finalizePendingTextSend({
    required String localId,
    required bool ok,
    String? messageId,
  }) {
    if (!mounted) return;
    if (!ok) {
      final i = _pendingOutbound.indexWhere((p) => p.localId == localId);
      if (i >= 0) {
        _pendingOutbound[i].failed = true;
        _pendingOutbound[i].errorMessage =
            'Não foi possível enviar. Toque para tentar de novo.';
        setState(() {});
      }
      return;
    }
    final mid = messageId?.trim() ?? '';
    if (mid.isNotEmpty) {
      final i = _pendingOutbound.indexWhere((p) => p.localId == localId);
      if (i >= 0) {
        _pendingOutbound[i].firestoreMessageId = mid;
      }
      _prunePendingOutboundMatchedByStream(_latestRecentDocs);
      if (_pendingOutbound.any((p) => p.localId == localId)) {
        // Só remove quando o doc do servidor estiver visível na lista.
        _confirmPendingReplacedByServer(localId);
      }
    } else {
      _removePending(localId);
    }
    unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
  }

  /// Remove a bolha local **somente** quando a mensagem do servidor já está
  /// visível em [_latestRecentDocs] — evita o «sumiço» da mídia após o upload.
  /// Enquanto a bolha local existe, o doc do servidor equivalente fica oculto
  /// pelo filtro anti-duplicata, então nunca há duplicação.
  void _confirmPendingReplacedByServer(String localId, {int attempt = 0}) {
    if (!mounted) return;
    final i = _pendingOutbound.indexWhere((p) => p.localId == localId);
    if (i < 0) return; // Já removida (stream fez o prune).
    final p = _pendingOutbound[i];
    final fid = p.firestoreMessageId?.trim() ?? '';
    final sp = p.storagePath?.trim() ?? '';
    final visible = _latestRecentDocs.any((d) {
      if (fid.isNotEmpty && d.id == fid) return true;
      if (sp.isNotEmpty &&
          ChurchChatMessageFields.storagePath(d.data()).trim() == sp) {
        return true;
      }
      return false;
    });
    if (visible) {
      _removePending(localId);
      return;
    }
    if (attempt >= 8) {
      // Estável (Telegram): NUNCA remover a bolha enquanto o doc do servidor
      // não estiver visível na lista — senão a mídia «some» da conversa.
      // A bolha fica em «Enviado» e o filtro anti-duplicata evita duplicação;
      // seguimos verificando devagar até o stream entregar a mensagem.
      unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
      Future<void>.delayed(
        const Duration(seconds: 3),
        () => _confirmPendingReplacedByServer(localId, attempt: attempt),
      );
      return;
    }
    unawaited(_primeRecentMessagesFromCacheOrServer(silent: true));
    Future<void>.delayed(
      Duration(milliseconds: 350 + attempt * 450),
      () => _confirmPendingReplacedByServer(localId, attempt: attempt + 1),
    );
  }

  void _removePending(String localId) {
    if (!mounted) return;
    final removed =
        _pendingOutbound.where((p) => p.localId == localId).toList();
    setState(() => _pendingOutbound.removeWhere((p) => p.localId == localId));
    for (final p in removed) {
      ChurchChatOptimizedPayloadCache.remove(p.localId);
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

  String _pendingUploadStatusLabel(
    ChurchChatOutboundPending p,
    double progress, {
    String? mediaLabel,
    String? fileName,
  }) {
    if (p.failed) return p.errorMessage ?? 'Falha no envio';
    if (p.offlineQueued) return 'Na fila — envia ao voltar online';
    final clamped = progress.clamp(0.0, 1.0);
    if (clamped >= 1) return 'Enviado';
    if (clamped >= 0.9) return 'A finalizar…';
    if (clamped >= 0.82) return 'Quase pronto…';
    final pct = (clamped * 100).round().clamp(0, 100);
    if (mediaLabel != null) {
      return 'A enviar $mediaLabel... $pct%';
    }
    final safeName =
        (fileName ?? p.fileName).trim().isNotEmpty ? (fileName ?? p.fileName) : 'ficheiro';
    return 'A enviar $safeName... $pct%';
  }

  Future<List<int>?> _bytesForPendingUpload({
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      if (pending.kind == 'image' &&
          (pending.previewBytes == null || pending.previewBytes!.isEmpty)) {
        pending.previewBytes = u8;
      }
      if (u8.length <= 48 * 1024 * 1024) {
        unawaited(
          ChurchChatPendingMediaCache.put(
            tenantId: _tid,
            threadId: widget.threadId,
            localId: pending.localId,
            bytes: u8,
          ),
        );
      }
      return u8;
    }

    final cached = await ChurchChatPendingMediaCache.get(
      tenantId: _tid,
      threadId: widget.threadId,
      localId: pending.localId,
    );
    if (cached != null && cached.isNotEmpty) {
      if (pending.kind == 'image' &&
          (pending.previewBytes == null || pending.previewBytes!.isEmpty)) {
        pending.previewBytes = cached;
      }
      return cached;
    }

    if (pending.previewBytes != null && pending.previewBytes!.isNotEmpty) {
      return pending.previewBytes;
    }

    final path = localPath?.trim() ?? pending.localPath?.trim() ?? '';
    if (path.isEmpty) return null;

    pending.localPath ??= path;
    if (pending.kind == 'image' && !kIsWeb) {
      try {
        pending.previewBytes = await SafeImageBytes.fromPath(
          path,
          maxEdge: 320,
          quality: 62,
        );
        if (mounted) setState(() {});
      } catch (e, st) {
        debugPrint('_bytesForPendingUpload preview from path: $e\n$st');
      }
    }

    if (kIsWeb && path.isNotEmpty) {
      try {
        final raw = await XFile(path).readAsBytes();
        if (raw.isNotEmpty) {
          final u8 = raw is Uint8List ? raw : Uint8List.fromList(raw);
          unawaited(
            ChurchChatPendingMediaCache.put(
              tenantId: _tid,
              threadId: widget.threadId,
              localId: pending.localId,
              bytes: u8,
            ),
          );
          return u8;
        }
      } catch (e, st) {
        debugPrint('_bytesForPendingUpload web XFile: $e\n$st');
      }
      return null;
    }

    if (kIsWeb) return null;

    // Imagem mobile: comprimir a partir do path no serviço (evita OOM com original 5–10 MB).
    if (pending.kind == 'image') return null;

    // Vídeo/documento/áudio: upload via putFile com path persistente.
    return null;
  }

  int? _maxBytesForChatKind(String kind) {
    switch (kind) {
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
    // Outbox cedo (kill-safe) — estilo Telegram: nunca perder o anexo.
    unawaited(
      ChurchChatMediaOutboxService.registerJob(
        tenantId: _tid,
        threadId: widget.threadId,
        localId: pending.localId,
        kind: pending.kind,
        fileName: pending.fileName,
        mime: pending.mime,
        localPath: localPath ?? pending.localPath,
        bytes: bytes != null
            ? (bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
            : pending.previewBytes,
      ).catchError((_) {}),
    );
    unawaited(ChurchChatFastSendService.warmSendPipeline().catchError((_) {}));
    unawaited(_runPendingMediaUpload(
      pending: pending,
      bytes: bytes,
      localPath: localPath,
    ));
  }

  Future<void> _runPendingMediaUpload({
    required ChurchChatOutboundPending pending,
    required List<int>? bytes,
    required String? localPath,
  }) async {
    await _awaitOperationalTenantId();
    final replyTo =
        pending.albumIndex == 0 ? _replyDraft?.toReplyPayload() : null;
    final uploadBytes = await _bytesForPendingUpload(
      pending: pending,
      bytes: bytes,
      localPath: localPath,
    );
    if (mounted &&
        pending.kind == 'image' &&
        pending.previewBytes != null &&
        pending.previewBytes!.isNotEmpty) {
      setState(() {});
    }
    if (kIsWeb &&
        uploadBytes != null &&
        uploadBytes.isNotEmpty &&
        (pending.previewBytes == null || pending.previewBytes!.isEmpty)) {
      final cached = uploadBytes is Uint8List
          ? uploadBytes
          : Uint8List.fromList(uploadBytes);
      pending.previewBytes = cached;
      unawaited(
        ChurchChatPendingMediaCache.put(
          tenantId: _tid,
          threadId: widget.threadId,
          localId: pending.localId,
          bytes: cached,
        ),
      );
    }
    var repaintedVideoPreview = false;
    // WhatsApp: upload em background — sem faixa «Enviando foto/áudio…».
    unawaited(
      ChurchChatFastSendService.sendMedia(
        tenantId: _tid,
        threadId: widget.threadId,
        pending: pending,
        bytes: uploadBytes,
        localPath: localPath,
        replyTo: replyTo,
        onProgress: (p) {
          _setPendingProgress(pending.localId, p);
          if (!repaintedVideoPreview &&
              pending.kind == 'video' &&
              pending.previewBytes != null &&
              pending.previewBytes!.isNotEmpty &&
              mounted) {
            repaintedVideoPreview = true;
            setState(() {});
          }
        },
        onSuccess: () {
          if (pending.offlineQueued) {
            pending.errorMessage = null;
            pending.failed = false;
            _setPendingProgress(pending.localId, 1.0);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.successSnackBar(kFeedPublishQueuedUserMessage),
              );
              setState(() {});
            }
            // Mantém bolha local até o outbox sincronizar — não remove.
            return;
          }
          if (mounted && pending.albumIndex == 0) {
            setState(() => _replyDraft = null);
          }
          // NÃO remover a bolha já: espera a mensagem do servidor aparecer
          // na lista (senão a foto/áudio/arquivo «some» até o stream chegar).
          pending.failed = false;
          pending.errorMessage = null;
          _setPendingProgress(pending.localId, 1.0);
          if (mounted) setState(() {});
          _confirmPendingReplacedByServer(pending.localId);
        },
        onError: (msg) {
          final i =
              _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
          if (i >= 0) {
            _pendingOutbound[i].failed = true;
            _pendingOutbound[i].errorMessage = msg;
            if (mounted) setState(() {});
          }
        },
      ).catchError((Object e, StackTrace st) {
        YahwehFlowLog.error('CHAT', e, st);
        final i =
            _pendingOutbound.indexWhere((p) => p.localId == pending.localId);
        if (i >= 0) {
          _pendingOutbound[i].failed = true;
          _pendingOutbound[i].errorMessage =
              formatUploadErrorForUser(e);
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
    int? fileSizeBytes,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
    int? voiceDurationMs,
  }) async {
    final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(name);
    if (blocked != null) {
      _showChatAttachmentError(blocked);
      return;
    }
    final kindBlocked = ChurchChatAttachmentUtils.blockReasonForChatKind(kind);
    if (kindBlocked != null) {
      _showChatAttachmentError(kindBlocked);
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChatThreadOperations.clearTypingForMe(
      tenantId: _tid,
      threadId: widget.threadId,
    ));
    final pending = ChurchChatOutboundPending(
      localId: 'p_${DateTime.now().millisecondsSinceEpoch}_${albumIndex}',
      kind: kind,
      fileName: name,
      mime: mime,
      localPath: localPath,
      previewBytes: null,
      byteSize: fileSizeBytes,
      replyPreview: albumIndex == 0 ? _replyDraft?.preview : null,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
      voiceDurationMs: voiceDurationMs,
    );
    unawaited(_enqueueAndUploadPending(
      pending: pending,
      bytes: null,
      localPath: localPath,
    ));
  }

  Future<void> _pickDocument() async {
    _warmChatFirebaseForPicker();
    final r = await YahwehFilePicker.pickFiles(
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
      // Sem snack — bolhas locais confirmam o envio.
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
      final docBlocked = ChurchChatAttachmentUtils.blockReasonForDocumentFileName(
        f.name.isNotEmpty ? f.name : 'ficheiro',
      );
      if (docBlocked != null) {
        _showChatAttachmentError(docBlocked);
        continue;
      }
      unawaited(_sendPickedPlatformFile(f));
    }
  }

  Future<void> _pickAudioFile() async {
    _warmChatFirebaseForPicker();
    final r = await YahwehFilePicker.pickFiles(
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
          _sendPickedPlatformFile(files[i], defaultFileName: 'audio_$i.m4a'));
    }
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String name,
    String mime,
    String kind, {
    int? fileSizeBytes,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
    int? voiceDurationMs,
  }) async {
    final blocked = ChurchChatAttachmentUtils.blockReasonForFileName(name);
    if (blocked != null) {
      _showChatAttachmentError(blocked);
      return;
    }
    final kindBlocked = ChurchChatAttachmentUtils.blockReasonForChatKind(kind);
    if (kindBlocked != null) {
      _showChatAttachmentError(kindBlocked);
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(ChatThreadOperations.clearTypingForMe(
      tenantId: _tid,
      threadId: widget.threadId,
    ));
    final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final preview = kind == 'image' ? u8 : null;
    final pending = ChurchChatOutboundPending(
      localId: 'p_${DateTime.now().millisecondsSinceEpoch}_${albumIndex}',
      kind: kind,
      fileName: name,
      mime: mime,
      previewBytes: preview,
      byteSize: fileSizeBytes ?? u8.length,
      replyPreview: albumIndex == 0 ? _replyDraft?.preview : null,
      albumGroupId: albumGroupId,
      albumIndex: albumIndex,
      albumCount: albumCount,
      voiceDurationMs: voiceDurationMs,
    );
    unawaited(_enqueueAndUploadPending(
      pending: pending,
      bytes: bytes,
      localPath: null,
    ));
  }

  /// Ampliar foto recém-enviada (bytes locais — instantâneo, sem rede).
  Future<void> _openPendingImageZoom(ChurchChatOutboundPending p) async {
    Uint8List? bytes = p.previewBytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb) {
      final path = p.localPath?.trim() ?? '';
      if (path.isNotEmpty) {
        try {
          bytes = await File(path).readAsBytes();
        } catch (_) {}
      }
    }
    if (bytes == null || bytes.isEmpty || !mounted) return;
    await showYahwehOriginalImageZoomBytes(context, bytes: bytes);
  }

  /// Doc sintético para ações (reencaminhar/remover) na bolha já enviada,
  /// enquanto o stream ainda não substituiu a bolha local.
  Map<String, dynamic> _sentDataForPending(
    ChurchChatOutboundPending p,
    String myUid,
  ) =>
      {
        'senderUid': myUid,
        'type': p.kind,
        'storagePath': p.storagePath?.trim() ?? '',
        'deliveryStatus': ChatThreadOperations.deliverySent,
        'status': ChatThreadOperations.deliverySent,
        if (p.fileName.trim().isNotEmpty) 'fileName': p.fileName.trim(),
      };

  Widget _buildPendingOutboundBubble(
    ChurchChatOutboundPending p,
    String myUid,
  ) {
    final maxBubbleW = _chatBubbleMaxWidth(context);
    final isVisualMedia = p.kind == 'image' || p.kind == 'video';
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
          ChurchChatTelegramMessageBody(
            text: t,
            mine: true,
          ),
        ],
      );
    } else if ((p.kind == 'image' || p.kind == 'video') &&
        p.previewBytes != null) {
      final previewSide = (maxBubbleW * 0.92).clamp(240.0, 320.0);
      body = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.memory(
              p.previewBytes!,
              width: previewSide,
              height: previewSide,
              fit: BoxFit.cover,
            ),
            if (p.kind == 'video')
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            if (!p.failed)
              ValueListenableBuilder<double>(
                valueListenable: p.progressListenable,
                builder: (context, progress, _) {
                  if (progress >= 1) return const SizedBox.shrink();
                  // WhatsApp: só um relógio discreto — sem ecrã «a enviar» a cobrir a foto.
                  return Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.95),
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
        p.kind == 'image') {
      final previewSide = (maxBubbleW * 0.92).clamp(240.0, 320.0);
      body = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(
              File(p.localPath!),
              width: previewSide,
              height: previewSide,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => SizedBox(
                width: previewSide,
                height: previewSide * 0.6,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (!p.failed)
              ValueListenableBuilder<double>(
                valueListenable: p.progressListenable,
                builder: (context, progress, _) {
                  if (progress >= 1) return const SizedBox.shrink();
                  return Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    } else if (p.kind == 'audio') {
      body = ChurchChatPendingVoiceBubble(
        progressListenable: p.progressListenable,
        failed: p.failed,
        offlineQueued: p.offlineQueued,
        localPath: p.localPath,
        errorMessage: p.errorMessage,
        durationMs: p.voiceDurationMs,
        fileName: p.fileName,
      );
    } else if (ChurchChatMessageFields.isDocumentType(p.kind)) {
      body = _buildPendingDocumentBubble(p);
    } else {
      body = ValueListenableBuilder<double>(
        valueListenable: p.progressListenable,
        builder: (context, progress, _) {
          final safeName = p.fileName.trim().isNotEmpty ? p.fileName : 'ficheiro';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                p.failed
                    ? Icons.error_outline_rounded
                    : (p.kind == 'video'
                        ? Icons.videocam_outlined
                        : Icons.insert_drive_file_outlined),
                size: 22,
                color: p.failed
                    ? ThemeCleanPremium.error
                    : const Color(0xFF128C7E),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  p.failed
                      ? (p.errorMessage?.trim().isNotEmpty == true
                          ? p.errorMessage!
                          : 'Falha no envio')
                      : safeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!p.failed && progress < 1) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ],
            ],
          );
        },
      );
    }
    final canZoomPendingImage = p.kind == 'image' && !p.failed;
    final sentFid = p.firestoreMessageId?.trim() ?? '';
    final canPendingActions =
        !p.failed && p.progress >= 1 && sentFid.isNotEmpty;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: canZoomPendingImage
            ? () => unawaited(_openPendingImageZoom(p))
            : null,
        onLongPress: canPendingActions
            ? () => _showMessageActions(
                  sentFid,
                  _sentDataForPending(p, myUid),
                  myUid,
                )
            : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxBubbleW),
        margin: const EdgeInsets.only(bottom: 4, left: 56, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: p.failed
              ? null
              : ChurchChatSenderPalette.outgoingBubbleGradient,
          color: p.failed
              ? ChurchChatSenderPalette.outgoingBubbleBackground
                  .withValues(alpha: 0.55)
              : null,
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
            if (isVisualMedia) ...[
              const SizedBox(height: 8),
              _buildPendingVisualMediaStatus(p),
            ],
            if (p.failed)
              TextButton(
                onPressed: () {
                  if (p.kind == 'text') {
                    _retryPendingText(p);
                    return;
                  }
                  p.failed = false;
                  p.errorMessage = null;
                  if (mounted) setState(() {});
                  unawaited(_runPendingMediaUpload(
                    pending: p,
                    bytes: null,
                    localPath: p.localPath,
                  ));
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
      ),
    );
  }

  Widget _buildPendingVisualMediaStatus(ChurchChatOutboundPending p) {
    return ValueListenableBuilder<double>(
      valueListenable: p.progressListenable,
      builder: (context, progress, _) {
        final mediaLabel = p.kind == 'video' ? 'vídeo' : 'imagem';
        final status = _pendingUploadStatusLabel(
          p,
          progress,
          mediaLabel: mediaLabel,
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            status,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: p.failed
                  ? ThemeCleanPremium.error
                  : ThemeCleanPremium.onSurface.withValues(alpha: 0.62),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingDocumentBubble(ChurchChatOutboundPending p) {
    IconData icon;
    switch (p.kind) {
      case 'pdf':
        icon = Icons.picture_as_pdf_rounded;
        break;
      case 'doc':
        icon = Icons.description_rounded;
        break;
      case 'xls':
        icon = Icons.table_chart_rounded;
        break;
      case 'zip':
        icon = Icons.folder_zip_rounded;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        break;
    }
    final ext = ChurchChatAttachmentUtils
        .extensionOf(p.fileName)
        .replaceAll('.', '')
        .trim()
        .toUpperCase();
    return ValueListenableBuilder<double>(
      valueListenable: p.progressListenable,
      builder: (context, progress, _) {
        final clamped = progress.clamp(0.0, 1.0);
        final sending = !p.failed && !p.offlineQueued && clamped < 1;
        final pct = (clamped * 100).round().clamp(0, 100);
        final sizeLabel = (p.byteSize != null && p.byteSize! > 0)
            ? ChurchChatAttachmentUtils.formatFileSize(p.byteSize!)
            : '';
        final status = p.failed
            ? (p.errorMessage ?? 'Falha no envio')
            : (p.offlineQueued
                ? 'Na fila — envia ao voltar online'
                : (sending ? 'A enviar... $pct%' : 'A processar...'));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    p.failed ? Icons.error_outline_rounded : icon,
                    size: 21,
                    color: p.failed
                        ? ThemeCleanPremium.error
                        : ThemeCleanPremium.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.fileName.isNotEmpty ? p.fileName : 'Documento',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (ext.isNotEmpty) ext,
                          if (sizeLabel.isNotEmpty) sizeLabel,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: ThemeCleanPremium.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: p.failed
                    ? null
                    : (sending ? clamped.clamp(0.02, 1.0) : 1.0),
                minHeight: 4,
                backgroundColor:
                    ThemeCleanPremium.onSurface.withValues(alpha: 0.12),
                color: p.failed
                    ? ThemeCleanPremium.error
                    : ThemeCleanPremium.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: p.failed
                    ? ThemeCleanPremium.error
                    : ThemeCleanPremium.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPendingAlbumBubble(
    List<ChurchChatOutboundPending> group,
    String myUid,
  ) {
    final maxBubbleW = _chatBubbleMaxWidth(context);
    final cells = <ChurchChatAlbumCell>[
      for (final p in group)
        ChurchChatAlbumCell(
          previewBytes: p.previewBytes,
          localPath: p.localPath,
          type: 'image',
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
    if (_voiceRecording || _voiceStartFuture != null) return;
    _warmChatFirebaseForPicker();
    final startCompleter = _startVoiceRecordingImpl();
    _voiceStartFuture = startCompleter;
    await startCompleter;
    _voiceStartFuture = null;
  }

  Future<void> _startVoiceRecordingImpl() async {
    // UI optimista imediata (Telegram) — reverte se o microfone falhar.
    if (mounted) {
      setState(() {
        _voiceRecording = true;
        _voiceElapsed = Duration.zero;
        _voiceSlideCancel = false;
        _voiceSlideOffset = 0;
      });
    }
    unawaited(
      ChatThreadOperations.setTypingActive(
        tenantId: _tid,
        threadId: widget.threadId,
        active: true,
        displayLabel: ChatThreadOperations.typingLabelRecording,
      ),
    );
    try {
      unawaited(ensureFirebaseReadyForChatSend().catchError((_) {}));
      final startedPath = await _chatAudio.startRecording();
      if (startedPath == null) {
        if (mounted) {
          setState(() {
            _voiceRecording = false;
            _voiceElapsed = Duration.zero;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                kIsWeb
                    ? 'Permissão de microfone necessária. Autorize no browser e tente de novo.'
                    : 'Permissão de microfone necessária para gravar.',
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
        unawaited(
          ChatThreadOperations.clearTypingForMe(
            tenantId: _tid,
            threadId: widget.threadId,
          ),
        );
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _voiceRecording = false;
          _voiceElapsed = Duration.zero;
        });
      }
      unawaited(
        ChatThreadOperations.clearTypingForMe(
          tenantId: _tid,
          threadId: widget.threadId,
        ),
      );
      final msg = e.toString();
      final micDenied = _isMicrophonePermissionError(msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              micDenied
                  ? (kIsWeb
                      ? 'Microfone bloqueado no navegador. Autorize e tente novamente.'
                      : 'Microfone bloqueado no iPhone. Ative em Ajustes > Privacidade e Segurança > Microfone.')
                  : 'Não foi possível gravar: ${formatUploadErrorForUser(e)}',
            ),
            behavior: SnackBarBehavior.floating,
            action: micDenied
                ? SnackBarAction(
                    label: 'Anexar áudio',
                    onPressed: () => unawaited(_pickAudioFile()),
                  )
                : null,
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
        if (_voiceElapsed.inSeconds >= _maxVoiceSeconds) {
          _voiceTicker?.cancel();
          unawaited(_finishVoiceRecording(send: true));
        }
      });
    });
  }

  bool _isMicrophonePermissionError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('permissão de microfone negada') ||
        lower.contains('permission denied') ||
        lower.contains('notallowederror') ||
        lower.contains('microphone');
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    _voiceTicker?.cancel();
    _voiceTicker = null;

    if (_voiceStartFuture != null) {
      try {
        await _voiceStartFuture!.timeout(const Duration(seconds: 8));
      } catch (e, st) {
        debugPrint('_finishVoiceRecording wait _voiceStartFuture: $e\n$st');
      }
    }

    final recordedMs = _voiceElapsed.inMilliseconds;
    unawaited(
      ChatThreadOperations.clearTypingForMe(
        tenantId: _tid,
        threadId: widget.threadId,
      ),
    );

    setState(() {
      _voiceRecording = false;
      _voiceElapsed = Duration.zero;
      _voiceSlideCancel = false;
      _voiceSlideOffset = 0;
    });

    if (!send) {
      await _chatAudio.stopRecording(send: false);
      return;
    }

    if (recordedMs < 800) {
      await _chatAudio.stopRecording(send: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gravação muito curta. Segure o microfone um pouco mais.'),
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
      unawaited(_uploadAndSend(
        bytes,
        name,
        mime,
        'audio',
        voiceDurationMs: recordedMs,
      ));
      return;
    }
    if (voicePath == null || voicePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gravação vazia ou interrompida. Segure o microfone ou toque Enviar.',
            ),
          ),
        );
      }
      return;
    }

    final mat = await ChurchChatLocalFileService.materializeLocalPath(voicePath);
    if (mat == null || mat.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível ler o áudio gravado. Tente de novo.',
            ),
          ),
        );
      }
      return;
    }
    final lower = mat.toLowerCase();
    final ext = lower.endsWith('.wav') ? 'wav' : 'm4a';
    final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    unawaited(_uploadAndSendFromPath(
      mat,
      name,
      mime,
      'audio',
      voiceDurationMs: recordedMs,
    ));
  }

  Future<void> _openAttachmentExternally(String rawUrl) async {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      _showChatAttachmentError('Ficheiro indisponível.');
      return;
    }
    try {
      await showYahwehOriginalMedia(context, urlOrPath: raw);
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
    final webPhoneFrame = kIsWeb && MediaQuery.sizeOf(context).width >= 720;
    final scaffold = Scaffold(
      backgroundColor: ChurchChatWhatsAppTheme.threadBackground,
      appBar: AppBar(
        toolbarHeight: 48,
        elevation: 0,
        backgroundColor: ChurchChatWhatsAppTheme.header,
        foregroundColor: Colors.white,
        leading: widget.embeddedInSplitPanel
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
        automaticallyImplyLeading: !widget.embeddedInSplitPanel,
        titleSpacing: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opções',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: ThemeCleanPremium.surface,
            onSelected: (v) async {
              if (v == 'search_msgs') {
                setState(() {
                  _searchingMessages = !_searchingMessages;
                  if (!_searchingMessages) {
                    _msgSearchCtrl.clear();
                    _messageSearchQuery = '';
                  }
                });
                return;
              }
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
                  _tid,
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
                  tenantId: _tid,
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
                  tenantId: _tid,
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
                  tenantId: _tid,
                  threadId: widget.threadId,
                  value: !_prefs.isMutedThread(widget.threadId),
                );
              } else if (v == 'hide_dm') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Limpar conversa?'),
                    content: const Text(
                      'Apaga esta conversa por completo no Firebase e no '
                      'armazenamento (mensagens, fotos e vídeos) para TODOS '
                      'os participantes. Esta ação não pode ser desfeita.',
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
                        child: const Text('Limpar tudo'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final purged =
                    await ChatThreadOperations.purgeThreadMessagesCompletely(
                  tenantId: _tid,
                  threadId: widget.threadId,
                );
                await ChurchChatMemberPrefs.setHiddenDmThread(
                  tenantId: _tid,
                  threadId: widget.threadId,
                  hide: true,
                );
                if (!context.mounted) return;
                if (!purged) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Não foi possível limpar a conversa. Verifique a rede.',
                      ),
                      backgroundColor: ThemeCleanPremium.error,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Conversa limpa no Firebase e no armazenamento.',
                      ),
                    ),
                  );
                  Navigator.of(context).pop();
                }
              } else if (v == 'delete_group') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Excluir grupo?'),
                    content: Text(
                      'Apaga o histórico de «${widget.title}» para todos os membros. '
                      'Esta ação não pode ser desfeita.',
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
                        child: const Text('Excluir grupo'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final deleted = await ChatThreadOperations.deleteGroupThread(
                  tenantId: _tid,
                  threadId: widget.threadId,
                );
                if (!context.mounted) return;
                if (!deleted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Não foi possível excluir o grupo. Verifique a sua permissão.',
                      ),
                      backgroundColor: ThemeCleanPremium.error,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Grupo excluído.')),
                  );
                  Navigator.of(context).pop();
                }
              } else if (v == 'my_photo') {
                await showChurchChatProfilePhotoSheet(
                  context,
                  tenantId: _tid,
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
                    tenantId: _tid,
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
                  tenantId: _tid,
                  peerUid: widget.peerUid!,
                  value: !_prefs.isBlockedPeer(widget.peerUid!),
                );
              } else if (v == 'notif') {
                final cur =
                    await ChurchChatNotificationPrefs.isChatPushEnabled();
                final next = !cur;
                await ChurchChatNotificationPrefs.setChatPushEnabled(
                  enabled: next,
                  tenantId: _tid,
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
                  tenantId: _tid,
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
                value: 'search_msgs',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _searchingMessages
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: Text(
                    _searchingMessages
                        ? 'Fechar pesquisa'
                        : 'Pesquisar nas mensagens',
                  ),
                ),
              ),
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
                    title: const Text('Limpar conversa'),
                    subtitle: const Text(
                      'Apaga mensagens, fotos e vídeos no Firebase para todos.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              if (widget.isDepartment &&
                  ChurchChatModeration.canDeleteGroupConversation(
                    widget.memberRole,
                    departmentData: _departmentData,
                    memberCpfDigits: widget.memberCpfDigits,
                  ))
                PopupMenuItem(
                  value: 'delete_group',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: const Text('Excluir grupo'),
                    subtitle: const Text(
                      'Apaga o histórico para todos (pastor, administrador ou secretário).',
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
                tenantId: _tid,
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
            tenantId: _tid,
            compact: true,
            alwaysOfferClear: false,
            role: widget.memberRole,
          ),
          Expanded(
            child: ColoredBox(
        color: ChurchChatWhatsAppTheme.threadBackground,
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
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
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
                        .where((d) => !ChatThreadOperations.messageHiddenForMe(
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
                    final pendingMessageIds = _pendingOutbound
                        .map((p) => p.firestoreMessageId?.trim() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toSet();
                    final pendingStoragePaths = _pendingOutbound
                        .map((p) => p.storagePath?.trim() ?? '')
                        .where((sp) => sp.isNotEmpty)
                        .toSet();
                    var streamDocs = visibleDocs.where((d) {
                      if (hideFirestoreMsgIds.contains(d.id)) return false;
                      final m = d.data();
                      if (pendingOutgoingTexts.isNotEmpty) {
                        final sender = (m['senderUid'] ?? '').toString();
                        if (sender == uid &&
                            ((m['type'] ?? 'text').toString() == 'text' ||
                                (m['type'] ?? '').toString() == 'link')) {
                          final txt = (m['text'] ?? '').toString().trim();
                          if (pendingOutgoingTexts.contains(txt)) {
                            return false;
                          }
                        }
                      }
                      final delivery =
                          (m['deliveryStatus'] ?? '').toString();
                      if (delivery == 'uploading' ||
                          delivery == 'queued' ||
                          delivery == 'sending') {
                        final sp =
                            ChurchChatMessageFields.storagePath(m).trim();
                        if (sp.isNotEmpty &&
                            (m['senderUid'] ?? '').toString() == uid) {
                          unawaited(
                            ChatStrictPublishService.tryFinalizeIfStorageReady(
                              tenantId: _tid,
                              threadId: widget.threadId,
                              messageId: d.id,
                              data: m,
                            ),
                          );
                        }
                        final created = m['createdAt'];
                        // Só abandona/oculta upload preso se for MENSAGEM MINHA
                        // e sem mídia resolvível — nunca esconder mídia de
                        // outro remetente nem mensagem já com storagePath.
                        if (created is Timestamp &&
                            (m['senderUid'] ?? '').toString() == uid &&
                            !ChurchChatMessageFields.hasResolvableMedia(m)) {
                          final age = DateTime.now()
                              .difference(created.toDate());
                          if (age > const Duration(minutes: 12)) {
                            unawaited(
                              ChatThreadOperations.abandonMediaUploadMessage(
                                tenantId: _tid,
                                threadId: widget.threadId,
                                messageId: d.id,
                              ),
                            );
                            return false;
                          }
                        }
                        if (hasActivePending &&
                            (m['senderUid'] ?? '').toString() == uid) {
                          final storagePath = ChurchChatMessageFields
                              .storagePath(m)
                              .trim();
                          final isSamePending =
                              pendingMessageIds.contains(d.id) ||
                                  (storagePath.isNotEmpty &&
                                      pendingStoragePaths.contains(storagePath));
                          if (!isSamePending) {
                            return true;
                          }
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
                      cacheExtent: 480,
                      addAutomaticKeepAlives: false,
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
                        final dsRaw = _deliveryStatusForBubble(m);
                        final peerRead = dsRaw ==
                                ChatThreadOperations.deliveryRead ||
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
                        final maxBubbleW = _chatBubbleMaxWidth(context);
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
                                  tenantId: _tid,
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
                                              ? ChatThreadOperations.deliveryRead
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
                            if (ChatThreadOperations.messageHiddenForMe(m, uid)) {
                              return;
                            }
                            _showMessageActions(messageId, m, senderUid);
                          },
                          onDoubleTap: () {
                            if (ChatThreadOperations.messageHiddenForMe(m, uid)) {
                              return;
                            }
                            unawaited(
                              ChatThreadOperations.setMyReactionOnMessage(
                                tenantId: _tid,
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
                                            tenantId: _tid,
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
            ),
          RepaintBoundary(
          child: AbsorbPointer(
            absorbing: blockedDm,
            child: SafeArea(
            top: false,
            child: Material(
              elevation: 0,
              color: ChurchChatWhatsAppTheme.inputBarBackground,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReplyDraftBar(),
                  if (_voiceRecording)
                    ChurchChatVoiceRecordingBar(
                      elapsedLabel: _formatVoiceDuration(_voiceElapsed),
                      slideCancelArmed: _voiceSlideCancel,
                      onCancel: () => unawaited(_finishVoiceRecording(send: false)),
                      onSend: () =>
                          unawaited(_finishVoiceRecording(send: true)),
                    ),
                  Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _voiceRecording ? null : _showAttachmentSheet,
                    icon: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF54656F),
                    ),
                    tooltip: 'Foto, documento ou áudio…',
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
                  ChurchChatVoiceMicButton(
                    recording: _voiceRecording,
                    slideCancelArmed: _voiceSlideCancel,
                    slideOffsetDx: _voiceSlideOffset,
                    onWebTap: () => unawaited(_toggleVoiceRecordSend()),
                    onLongPressStart: kIsWeb
                        ? null
                        : (_) {
                            _micLongPressActive = true;
                            _voiceSlideCancel = false;
                            _voiceSlideOffset = 0;
                            _voiceStartFuture = _startVoiceRecording();
                            unawaited(_voiceStartFuture);
                          },
                    onLongPressMoveUpdate: kIsWeb
                        ? null
                        : (details) {
                            final dx = details.offsetFromOrigin.dx;
                            setState(() {
                              _voiceSlideOffset = dx;
                              _voiceSlideCancel =
                                  dx < -_voiceCancelSlideThreshold;
                            });
                          },
                    onLongPressEnd: kIsWeb
                        ? null
                        : (_) {
                            final send = !_voiceSlideCancel;
                            unawaited(_finishVoiceRecording(send: send));
                            Future<void>.delayed(
                              const Duration(milliseconds: 250),
                              () {
                                if (mounted) {
                                  setState(() => _micLongPressActive = false);
                                } else {
                                  _micLongPressActive = false;
                                }
                              },
                            );
                          },
                    onLongPressCancel: kIsWeb
                        ? null
                        : () {
                            unawaited(_finishVoiceRecording(send: false));
                            _micLongPressActive = false;
                            setState(() {
                              _voiceSlideCancel = false;
                              _voiceSlideOffset = 0;
                            });
                          },
                    onTapWhileRecording: () {
                      if (_micLongPressActive) return;
                      unawaited(_finishVoiceRecording(send: true));
                    },
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
                            : 'Digite uma mensagem',
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
                                icon: const Icon(
                                  Icons.emoji_emotions_outlined,
                                  color: Color(0xFF54656F),
                                ),
                              ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
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
                  Material(
                    color: const Color(0xFF128C7E),
                    shape: const CircleBorder(),
                    elevation: 0,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _voiceRecording ? null : _sendText,
                      child: SizedBox(
                        width: ThemeCleanPremium.minTouchTarget,
                        height: ThemeCleanPremium.minTouchTarget,
                        child: Icon(
                          Icons.send_rounded,
                          color: _voiceRecording
                              ? Colors.white38
                              : Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
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
    if (webPhoneFrame) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF111B21)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width * 0.94)
                  .clamp(720.0, 1200.0),
              maxHeight: (MediaQuery.sizeOf(context).height * 0.94)
                  .clamp(720.0, 980.0),
            ),
            child: Material(
              elevation: 10,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: scaffold,
            ),
          ),
        ),
      );
    }
    return scaffold;
  }
}

/// «A digitar…» por polling (~2,5 s) — sem listener Firestore extra na conversa.
class _ChurchChatTypingPollStrip extends StatefulWidget {
  const _ChurchChatTypingPollStrip({
    required this.tenantId,
    required this.threadId,
    required this.myUid,
  });

  final String tenantId;
  final String threadId;
  final String myUid;

  @override
  State<_ChurchChatTypingPollStrip> createState() =>
      _ChurchChatTypingPollStripState();
}

class _ChurchChatTypingPollStripState extends State<_ChurchChatTypingPollStrip> {
  Timer? _pollTimer;
  ChurchChatTypingActivity _activity = const ChurchChatTypingActivity();
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_poll());
      _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        unawaited(_poll());
      });
    });
  }

  Future<void> _poll() async {
    if (_pollInFlight || !mounted) return;
    _pollInFlight = true;
    try {
      final next = await ChatThreadOperations.fetchActiveTyping(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        myUid: widget.myUid,
      );
      if (!mounted) return;
      if (next.isEmpty && _activity.isEmpty) return;
      if (next.names.length == _activity.names.length &&
          next.unnamed == _activity.unnamed &&
          next.recording == _activity.recording &&
          next.names.every(_activity.names.contains)) {
        return;
      }
      setState(() => _activity = next);
    } finally {
      _pollInFlight = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activity.isEmpty) return const SizedBox.shrink();
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
                _activity.label,
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
  }
}

class _MessageBody extends StatelessWidget {
  final String messageId;
  final String type;
  final Map<String, dynamic> data;
  final bool mine;
  final String tenantId;
  final Color? replyQuoteAccent;
  final Future<void> Function(String rawUrl)? onOpenAttachment;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? albumDocs;

  const _MessageBody({
    required this.messageId,
    required this.type,
    required this.data,
    required this.mine,
    required this.tenantId,
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
      final sp = ChurchChatMessageFields.storagePath(dm);
      final legacyUrl = ChurchChatMessageFields.mediaUrl(dm);
      final delivery = ChurchChatMessageFields.status(dm);
      final hasMedia = ChurchChatMessageFields.hasResolvableMedia(dm);
      if (!hasMedia &&
          (delivery == ChatThreadOperations.deliveryUploading ||
              delivery == ChatThreadOperations.deliverySending)) {
        cells.add(ChurchChatAlbumCell(type: t));
        continue;
      }
      cells.add(ChurchChatAlbumCell(
        url: legacyUrl.isEmpty ? null : legacyUrl,
        type: t == 'video' ? 'video' : 'image',
        onTap: !hasMedia
            ? null
            : () async {
                final resolved =
                    await ChurchChatMediaResolver.resolveDownloadUrl(
                  storagePath: sp,
                  tenantId: tenantId,
                );
                final zoomUrl = resolved ?? legacyUrl;
                if (zoomUrl.isNotEmpty && context.mounted) {
                  await churchChatOpenImageZoom(context, zoomUrl);
                }
              },
      ));
    }
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    return ChurchChatAlbumGrid(
      items: cells,
      maxWidth: maxW.clamp(260.0, 360.0),
      maxVisible: 6,
    );
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
    if (type == 'text' || type == 'link') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          ChurchChatTelegramMessageBody(
            text: (data['text'] ?? '').toString(),
            linkUrl: (data['linkUrl'] ?? data['url'] ?? '').toString(),
            mine: mine,
          ),
        ],
      );
    }
    if (type == 'sticker') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          Container(
            constraints: const BoxConstraints(maxWidth: 176, maxHeight: 176),
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
            child: ChurchChatStorageMediaImage(
              data: data,
              tenantId: tenantId,
              messageId: messageId,
              height: 220,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      );
    }
    final delivery = ChurchChatMessageFields.status(data);
    final hasMedia = ChurchChatMessageFields.hasResolvableMedia(data);
    if (!hasMedia) {
      if (delivery == ChatThreadOperations.deliveryUploading ||
          delivery == ChatThreadOperations.deliverySending ||
          delivery == ChatThreadOperations.deliveryQueued) {
        final uploadIcon = type == 'audio'
            ? Icons.mic_rounded
            : type == 'image'
                ? Icons.image_rounded
                : Icons.cloud_upload_rounded;
        // WhatsApp: bolha discreta (sem «A carregar…» / barra de progresso).
        return Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._quotePrefix(context),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: mine
                    ? ChurchChatSenderPalette.outgoingBubbleBackground
                    : Colors.white,
                borderRadius:
                    ChurchChatSenderPalette.bubbleBorderRadius(mine: mine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(uploadIcon, size: 22, color: const Color(0xFF128C7E)),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ],
              ),
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
      final uploadInProgress = ChurchChatMessageFields.isUploadInProgress(data);
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          LayoutBuilder(
            builder: (context, c) {
              final maxW = c.maxWidth.isFinite ? c.maxWidth : 320.0;
              final w = maxW.clamp(180.0, 320.0);
              final dpr = MediaQuery.devicePixelRatioOf(context);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox(
                  width: w,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: ChurchChatStorageMediaImage(
                            data: data,
                            tenantId: tenantId,
                            messageId: messageId,
                            width: w,
                            fit: BoxFit.cover,
                            memCacheWidth: (dpr * w).round().clamp(160, 720),
                            memCacheHeight:
                                (dpr * w * 0.75).round().clamp(120, 540),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              await churchChatOpenReceivedMediaPreview(
                                context,
                                type: 'image',
                                data: data,
                                tenantId: tenantId,
                                messageId: messageId,
                              );
                            },
                          ),
                        ),
                        if (uploadInProgress &&
                            ChurchChatMessageFields.storagePath(data).isEmpty)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.95),
                              ),
                            ),
                          ),
                        if (!uploadInProgress)
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
                                    onPressed: () async {
                                      // Mesmo fluxo do toque na miniatura:
                                      // resolve original (com fallback) e abre inteira.
                                      await churchChatOpenReceivedMediaPreview(
                                        context,
                                        type: 'image',
                                        data: data,
                                        tenantId: tenantId,
                                        messageId: messageId,
                                      );
                                    },
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
      final uploadInProgress = ChurchChatMessageFields.isUploadInProgress(data);
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          Stack(
            alignment: Alignment.center,
            children: [
              ChurchChatStorageVideoBubble(
                data: data,
                tenantId: tenantId,
                messageId: messageId,
                mine: mine,
              ),
              if (uploadInProgress &&
                  ChurchChatMessageFields.storagePath(data).isEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    if (ChurchChatMessageFields.isDocumentType(type)) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          ChurchChatDocumentBubble(
            data: data,
            type: type,
            tenantId: tenantId,
            messageId: messageId,
            onOpenExternally: onOpenAttachment,
          ),
        ],
      );
    }
    if (type == 'audio') {
      final sp = ChurchChatMessageFields.storagePath(data);
      final legacyUrl = ChurchChatMessageFields.mediaUrl(data);
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quotePrefix(context),
          ChurchChatInlineAudioPlayer(
            mediaUrl: legacyUrl,
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
            final sp = ChurchChatMessageFields.storagePath(data);
            final resolved = await ChurchChatMediaResolver.resolveDownloadUrl(
              storagePath: sp,
              tenantId: tenantId,
              messageId: messageId,
            );
            final openUrl =
                resolved ?? ChurchChatMessageFields.mediaUrl(data);
            if (openUrl.isNotEmpty) {
              await onOpenAttachment?.call(openUrl);
            }
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
