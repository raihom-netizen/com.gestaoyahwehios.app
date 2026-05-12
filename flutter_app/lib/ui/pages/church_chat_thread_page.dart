import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/services/church_chat_attachment_utils.dart';
import 'package:gestao_yahweh/services/church_chat_expression_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_fs.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_moderation.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_expression_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_inline_audio_player.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_sender_palette.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_save_media.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
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
  });

  @override
  State<ChurchChatThreadPage> createState() => _ChurchChatThreadPageState();
}

class _ChurchChatThreadPageState extends State<ChurchChatThreadPage>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _msgSearchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _searchingMessages = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deptSub;
  Map<String, dynamic>? _departmentData;
  ChurchChatMemberPrefsModel _prefs = const ChurchChatMemberPrefsModel();

  static const int _maxVoiceSeconds = 600;

  AudioRecorder? _voiceRecorder;
  String? _voiceRecordPath;
  bool _voiceRecording = false;
  Timer? _voiceTicker;
  Duration _voiceElapsed = Duration.zero;

  _ReplyDraft? _replyDraft;
  int _messageLimit = ChurchChatService.defaultMessagePageSize;
  bool _loadingMoreHistory = false;
  DateTime? _lastLimitBump;
  Timer? _typingDebounce;
  Timer? _typingIdleTimer;

  /// Uids mencionados nesta composição (picker @) — enviados em [mentionedUids] no texto.
  final Set<String> _mentionedUidsPending = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScrollPagination);
    _ctrl.addListener(_onComposeTyping);
    _prefsSub =
        ChurchChatMemberPrefs.watch(widget.tenantId).listen((snap) {
      if (!mounted) return;
      setState(() => _prefs = ChurchChatMemberPrefs.parse(snap));
    });
    _msgSearchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ChurchChatService.markThreadLastSeen(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
        ),
      );
    });
    if (widget.isDepartment &&
        widget.departmentId != null &&
        widget.departmentId!.isNotEmpty) {
      _deptSub = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('departamentos')
          .doc(widget.departmentId!)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() => _departmentData = snap.data());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScrollPagination);
    _ctrl.removeListener(_onComposeTyping);
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    unawaited(
      ChurchChatService.clearTypingForMe(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
      ),
    );
    _deptSub?.cancel();
    _voiceTicker?.cancel();
    final vr = _voiceRecorder;
    if (vr != null) {
      unawaited((() async {
        try {
          await vr.cancel();
        } catch (_) {}
        await vr.dispose();
      })());
    }
    _prefsSub?.cancel();
    _msgSearchCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ChurchChatService.markThreadLastSeen(
          tenantId: widget.tenantId,
          threadId: widget.threadId,
        ),
      );
    }
  }

  void _onScrollPagination() {
    if (!_scroll.hasClients) return;
    if (_msgSearchCtrl.text.trim().isNotEmpty) return;
    if (_loadingMoreHistory) return;
    final p = _scroll.position;
    if (p.maxScrollExtent <= 0) return;
    if (p.pixels >= p.maxScrollExtent - 160) {
      _maybeIncreaseMessageLimit();
    }
  }

  void _maybeIncreaseMessageLimit() {
    const maxLimit = 2500;
    if (_messageLimit >= maxLimit) return;
    final now = DateTime.now();
    if (_lastLimitBump != null &&
        now.difference(_lastLimitBump!).inMilliseconds < 700) {
      return;
    }
    _lastLimitBump = now;
    setState(() {
      _loadingMoreHistory = true;
      _messageLimit += ChurchChatService.defaultMessagePageSize;
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _loadingMoreHistory = false);
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
    _typingDebounce = Timer(const Duration(milliseconds: 420), () {
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
        for (final d in snap.data!.docs) {
          if (d.id == myUid) continue;
          final data = d.data();
          final ts = data['updatedAt'];
          if (ts is! Timestamp) continue;
          if (now.difference(ts.toDate()).inSeconds > 5) continue;
          final lb = (data['label'] ?? '').toString().trim();
          if (lb.isNotEmpty) {
            names.add(lb);
          } else {
            unnamed++;
          }
        }
        if (names.isEmpty && unnamed == 0) return const SizedBox.shrink();
        final text = () {
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
    if (t.isEmpty || _sending) return;
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    await ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    final replyPayload = _replyDraft?.toReplyPayload();
    setState(() => _sending = true);
    try {
      final ok = await ChurchChatService.sendTextMessage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        text: t,
        replyTo: replyPayload,
        senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
        mentionedUids: _mentionedUidsPending.isEmpty
            ? null
            : _mentionedUidsPending.toList(),
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não é possível enviar — desbloqueie o contacto nas opções da conversa.',
              ),
            ),
          );
        }
        return;
      }
      _ctrl.clear();
      if (mounted) {
        setState(() {
          _replyDraft = null;
          _mentionedUidsPending.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openExpressionSheet() async {
    if (_voiceRecording || _sending) return;
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
    if (_sending) return;
    final can = await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    if (!can) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não é possível enviar — desbloqueie o contacto nas opções.',
            ),
          ),
        );
      }
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    await ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    final replyPayload = _replyDraft?.toReplyPayload();
    final sp = pick.storagePath?.trim();
    setState(() => _sending = true);
    try {
      final ok = await ChurchChatService.sendStickerMessage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        downloadUrl: pick.mediaUrl,
        storagePath: (sp != null && sp.isNotEmpty) ? sp : null,
        stickerSource: pick.stickerSource,
        replyTo: replyPayload,
        senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não é possível enviar — desbloqueie o contacto nas opções da conversa.',
              ),
            ),
          );
        }
        return;
      }
      if (mounted) setState(() => _replyDraft = null);
      unawaited(
        ChurchChatExpressionPrefs.rememberStickerSent(
          tenantId: widget.tenantId,
          mediaUrl: pick.mediaUrl,
          storagePath: pick.storagePath,
          stickerSource: pick.stickerSource,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showEmojiReactionPicker(String messageId, Map<String, dynamic> m) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'];
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
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
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (ChurchChatService.messageHiddenForMe(m, myUid)) return;

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

  Future<void> _showAttachmentSheet() async {
    if (_sending) return;
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
                        'Super Premium · Mídia (estilo WhatsApp)',
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
                          label: 'Galeria',
                          color: const Color(0xFF169D5B),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickImage(ImageSource.gallery));
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
                          icon: Icons.video_library_rounded,
                          label: 'Vídeo',
                          color: const Color(0xFF7C3AED),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickVideo(ImageSource.gallery));
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
                          color: const Color(0xFFEA580C),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_pickDocument());
                          },
                        ),
                        _WhatsStyleAttachTile(
                          icon: Icons.audio_file_rounded,
                          label: 'Áudio',
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

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final name = x.name.isNotEmpty ? x.name : 'foto.jpg';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    await _uploadAndSend(bytes, name, mime, kind);
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickVideo(source: source);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final name = x.name.isNotEmpty ? x.name : 'video.mp4';
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    await _uploadAndSend(bytes, name, mime, kind);
  }

  Future<void> _pickDocument() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'txt',
        'csv',
        'rtf',
        'odt',
        'ods',
        'zip',
      ],
      withData: true,
    );
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final name = f!.name;
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    await _uploadAndSend(f.bytes!, name, mime, kind);
  }

  Future<void> _pickAudioFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'm4a',
        'aac',
        'mp3',
        'wav',
        'ogg',
        'opus',
        'flac',
      ],
      withData: true,
    );
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final name = f!.name;
    final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
    final kind = ChurchChatAttachmentUtils.messageKindForAttachment(
      fileName: name,
      mime: mime,
    );
    await _uploadAndSend(f.bytes!, name, mime, kind);
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String name,
    String mime,
    String kind,
  ) async {
    final can = await ChurchChatMemberPrefs.canSendToDmThread(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    if (!can) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não é possível enviar — desbloqueie o contacto nas opções.',
            ),
          ),
        );
      }
      return;
    }
    _typingDebounce?.cancel();
    _typingIdleTimer?.cancel();
    await ChurchChatService.clearTypingForMe(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
    );
    final replyPayload = _replyDraft?.toReplyPayload();
    setState(() => _sending = true);
    try {
      final up = await ChurchChatService.uploadChatBytes(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        bytes: bytes,
        fileName: name,
        contentType: mime,
      );
      final ok = await ChurchChatService.sendMediaMessage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        downloadUrl: up.url,
        storagePath: up.path,
        kind: kind,
        fileName: kind == 'document' ? name : null,
        replyTo: replyPayload,
        senderDisplayName: ChurchChatService.senderDisplayNameForNewMessage(),
      );
      if (ok && mounted) {
        setState(() => _replyDraft = null);
      }
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Envio bloqueado para este contacto.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    if (_sending) return;
    if (_voiceRecording) {
      await _finishVoiceRecording(send: true);
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Na web use «Anexos» → ficheiro de áudio. Gravação de voz só na app.',
            ),
          ),
        );
      }
      return;
    }
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
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
      await recorder.dispose();
      return;
    }
    AudioEncoder enc = AudioEncoder.aacLc;
    if (!await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      enc = AudioEncoder.wav;
    }
    final dir = await getTemporaryDirectory();
    final ext = enc == AudioEncoder.wav ? 'wav' : 'm4a';
    final path =
        '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await recorder.start(
        RecordConfig(encoder: enc),
        path: path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gravar: $e')),
        );
      }
      await recorder.dispose();
      return;
    }

    setState(() {
      _voiceRecorder = recorder;
      _voiceRecordPath = path;
      _voiceRecording = true;
      _voiceElapsed = Duration.zero;
    });

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

    final recorder = _voiceRecorder;
    final expectedPath = _voiceRecordPath;

    setState(() {
      _voiceRecording = false;
      _voiceRecorder = null;
      _voiceRecordPath = null;
      _voiceElapsed = Duration.zero;
    });

    if (recorder == null) return;

    if (!send) {
      try {
        await recorder.cancel();
      } catch (_) {}
      await recorder.dispose();
      if (expectedPath != null && !kIsWeb) {
        await churchChatDeleteFileQuiet(expectedPath);
      }
      return;
    }

    String? outPath;
    try {
      outPath = await recorder.stop();
    } catch (_) {}
    await recorder.dispose();

    final path = outPath ?? expectedPath;
    if (path == null || kIsWeb) return;

    try {
      final bytes = await churchChatReadFileBytes(path);
      await churchChatDeleteFileQuiet(path);
      final lower = path.toLowerCase();
      final ext = lower.endsWith('.wav') ? 'wav' : 'm4a';
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final mime = ChurchChatAttachmentUtils.mimeFromFileName(name);
      await _uploadAndSend(bytes, name, mime, 'audio');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar áudio: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final blockedDm = !widget.isDepartment &&
        widget.peerUid != null &&
        widget.peerUid!.isNotEmpty &&
        _prefs.isBlockedPeer(widget.peerUid!);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
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
                if (!_searchingMessages) _msgSearchCtrl.clear();
              });
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Opções',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: ThemeCleanPremium.surface,
            onSelected: (v) async {
              if (v == 'fav') {
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
              } else if (v == 'mute') {
                await ChurchChatMemberPrefs.setMutedThread(
                  tenantId: widget.tenantId,
                  threadId: widget.threadId,
                  value: !_prefs.isMutedThread(widget.threadId),
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
            CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(
                widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?',
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
                      fontSize: 17,
                    ),
                  ),
                  if (widget.peerUid != null)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('igrejas')
                          .doc(widget.tenantId)
                          .collection('chat_presence')
                          .doc(widget.peerUid!)
                          .snapshots(),
                      builder: (context, snap) {
                        final on =
                            ChurchChatService.isOnlineFromSnapshot(snap.data);
                        return Text(
                          on ? 'online' : 'offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
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
            _buildTypingStrip(uid),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('igrejas')
                    .doc(widget.tenantId)
                    .collection('membros')
                    .limit(800)
                    .snapshots(),
                builder: (context, memAll) {
                  final photoByUid =
                      churchChatMemberPhotoUrlByAuthUid(memAll.data);
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: ChurchChatService.threadRef(
                            widget.tenantId, widget.threadId)
                        .snapshots(),
                    builder: (context, thrSnap) {
                Timestamp? peerSeenAt;
                if (!widget.isDepartment &&
                    widget.peerUid != null &&
                    widget.peerUid!.isNotEmpty) {
                  final mm = thrSnap.data?.data()?['lastSeenAtByUid'];
                  if (mm is Map) {
                    final v = mm[widget.peerUid!];
                    if (v is Timestamp) peerSeenAt = v;
                  }
                }
                final threadMap = thrSnap.data?.data();
                final titlesByUid = <String, String>{};
                if (threadMap != null) {
                  final tm = threadMap['titlesByUid'];
                  if (tm is Map) {
                    for (final e in tm.entries) {
                      titlesByUid[e.key.toString()] = e.value.toString();
                    }
                  }
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ChurchChatService.messagesCol(
                          widget.tenantId, widget.threadId)
                      .orderBy('createdAt', descending: true)
                      .limit(_messageLimit)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docsRaw = snap.data!.docs;
                    final visibleDocs = docsRaw
                        .where((d) => !ChurchChatService.messageHiddenForMe(
                              d.data(),
                              uid,
                            ))
                        .toList();
                    final q = _msgSearchCtrl.text.trim().toLowerCase();
                    final docs = q.isEmpty
                        ? visibleDocs
                        : visibleDocs
                            .where((d) =>
                                _messageHaystack(d.data()).contains(q))
                            .toList();
                    if (docs.isEmpty) {
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
                    return ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final m = docs[i].data();
                        final mine = (m['senderUid'] ?? '').toString() == uid;
                        final type = (m['type'] ?? 'text').toString();
                        final createdRaw = m['createdAt'];
                        Timestamp? ct;
                        if (createdRaw is Timestamp) ct = createdRaw;
                        final ps = peerSeenAt;
                        final peerRead = ps != null &&
                            ct != null &&
                            ps.millisecondsSinceEpoch >=
                                ct.millisecondsSinceEpoch;
                        final messageId = docs[i].id;
                        final senderUid =
                            (m['senderUid'] ?? '').toString();
                        final senderLabel = _senderDisplayForMessage(
                          senderUid,
                          titlesByUid,
                          m,
                        );
                        final groupIncoming =
                            widget.isDepartment && !mine;
                        final bubbleBg = mine
                            ? ThemeCleanPremium.primary
                                .withValues(alpha: 0.16)
                            : (groupIncoming
                                ? ChurchChatSenderPalette
                                    .bubbleBackgroundForUid(senderUid)
                                : ThemeCleanPremium.cardBackground);
                        final bubbleBorder = mine
                            ? ThemeCleanPremium.primary
                                .withValues(alpha: 0.06)
                            : (groupIncoming
                                ? ChurchChatSenderPalette
                                    .bubbleBorderForUid(senderUid)
                                : ThemeCleanPremium.primary
                                    .withValues(alpha: 0.06));
                        final quoteAccent = (!mine &&
                                widget.isDepartment)
                            ? ChurchChatSenderPalette
                                .nameColorForUid(senderUid)
                            : null;
                        final bubbleCard = Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.sizeOf(context).width * 0.82,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: mine
                                ? BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(0xFFB9E7D9),
                                        ThemeCleanPremium.primary
                                            .withValues(alpha: 0.24),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: const Radius.circular(14),
                                      bottomRight: const Radius.circular(4),
                                    ),
                                    border: Border.all(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.14),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.2),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  )
                                : BoxDecoration(
                                    color: bubbleBg,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: Radius.circular(mine ? 14 : 4),
                                      bottomRight:
                                          Radius.circular(mine ? 4 : 14),
                                    ),
                                    border: Border.all(
                                      color: bubbleBorder,
                                    ),
                                    boxShadow:
                                        ThemeCleanPremium.softUiCardShadow,
                                  ),
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
                                if (widget.isDepartment && mine)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'Você',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: ThemeCleanPremium.onSurface
                                            .withValues(alpha: 0.48),
                                      ),
                                    ),
                                  ),
                                _MessageBody(
                                  messageId: messageId,
                                  type: type,
                                  data: m,
                                  mine: mine,
                                  replyQuoteAccent: quoteAccent,
                                ),
                                _buildReactionsStrip(m, uid, mine),
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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
                                      if (mine &&
                                          !widget.isDepartment &&
                                          widget.peerUid != null &&
                                          widget.peerUid!.isNotEmpty) ...[
                                        const SizedBox(width: 5),
                                        Icon(
                                          Icons.done_all_rounded,
                                          size: 15,
                                          color: peerRead
                                              ? const Color(0xFF53BDEB)
                                              : ThemeCleanPremium.onSurface
                                                  .withValues(alpha: 0.45),
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
                          child: Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: groupIncoming
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      SafeCircleAvatarImage(
                                        imageUrl: photoByUid[senderUid],
                                        radius: 19,
                                        memCacheSize: (38 *
                                                MediaQuery.devicePixelRatioOf(
                                                    context))
                                            .round()
                                            .clamp(72, 220),
                                        fallbackIcon: Icons.person_rounded,
                                        fallbackColor:
                                            ChurchChatSenderPalette
                                                .nameColorForUid(senderUid),
                                        backgroundColor: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(child: bubbleCard),
                                    ],
                                  )
                                : bubbleCard,
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
                },
              ),
            ),
          AbsorbPointer(
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
                            onPressed: _sending
                                ? null
                                : () => _finishVoiceRecording(send: false),
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
                              'Toque no microfone para enviar',
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
                    onPressed: (_sending || _voiceRecording)
                        ? null
                        : _showAttachmentSheet,
                    icon: Icon(Icons.attach_file_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    tooltip: 'Foto, vídeo, documento…',
                  ),
                  if (widget.isDepartment &&
                      (widget.departmentId?.trim().isNotEmpty ?? false))
                    IconButton(
                      onPressed: (_sending || _voiceRecording)
                          ? null
                          : () => unawaited(_openDeptMentionPicker()),
                      icon: Icon(
                        Icons.alternate_email_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                      tooltip: 'Mencionar membro (@)',
                    ),
                  if (!kIsWeb)
                    IconButton(
                      onPressed: _sending ? null : _toggleVoiceRecordSend,
                      icon: Icon(
                        _voiceRecording
                            ? Icons.stop_circle_rounded
                            : Icons.mic_rounded,
                        color: _voiceRecording
                            ? ThemeCleanPremium.error
                            : ThemeCleanPremium.onSurfaceVariant,
                      ),
                      tooltip: _voiceRecording
                          ? 'Enviar gravação'
                          : 'Gravar mensagem de voz',
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
                                onPressed: (_sending || _voiceRecording)
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
                    onPressed: (_sending || _voiceRecording)
                        ? null
                        : _sendText,
                    icon: _sending
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeCleanPremium.primary,
                            ),
                          )
                        : Icon(Icons.send_rounded,
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
  final Color? replyQuoteAccent;

  const _MessageBody({
    required this.messageId,
    required this.type,
    required this.data,
    required this.mine,
    this.replyQuoteAccent,
  });

  Widget _replyQuote(BuildContext context) {
    final rt = data['replyTo'];
    if (rt is! Map) return const SizedBox.shrink();
    final preview = (rt['preview'] ?? '').toString();
    if (preview.isEmpty) return const SizedBox.shrink();
    final accent = replyQuoteAccent ?? ThemeCleanPremium.primary;
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
        child: Text(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _replyQuote(context);
    if (type == 'text') {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          quote,
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
            quote,
            const Text('[figurinha indisponível]'),
          ],
        );
      }
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          quote,
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
            ),
          ),
        ],
      );
    }
    final url = (data['mediaUrl'] ?? '').toString();
    if (url.isEmpty) {
      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          quote,
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
          quote,
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
          quote,
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
          quote,
          InkWell(
            onTap: () async {
              final u = Uri.parse(url);
              if (await canLaunchUrl(u)) {
                await launchUrl(u, mode: LaunchMode.externalApplication);
              }
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
          quote,
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
        quote,
        InkWell(
          onTap: () async {
            final u = Uri.parse(url);
            if (await canLaunchUrl(u)) {
              await launchUrl(u, mode: LaunchMode.externalApplication);
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
  final Color color;
  final VoidCallback onTap;

  const _WhatsStyleAttachTile({
    required this.icon,
    required this.label,
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
                  label,
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
