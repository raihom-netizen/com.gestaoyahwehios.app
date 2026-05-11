import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Conversa fullscreen estilo WhatsApp.
class ChurchChatThreadPage extends StatefulWidget {
  final String tenantId;
  final String threadId;
  final String title;
  final bool isDepartment;
  final String? peerUid;

  const ChurchChatThreadPage({
    super.key,
    required this.tenantId,
    required this.threadId,
    required this.title,
    required this.isDepartment,
    this.peerUid,
  });

  @override
  State<ChurchChatThreadPage> createState() => _ChurchChatThreadPageState();
}

class _ChurchChatThreadPageState extends State<ChurchChatThreadPage> {
  final _ctrl = TextEditingController();
  final _msgSearchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _searchingMessages = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  ChurchChatMemberPrefsModel _prefs = const ChurchChatMemberPrefsModel();

  @override
  void initState() {
    super.initState();
    _prefsSub =
        ChurchChatMemberPrefs.watch(widget.tenantId).listen((snap) {
      if (!mounted) return;
      setState(() => _prefs = ChurchChatMemberPrefs.parse(snap));
    });
    _msgSearchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _prefsSub?.cancel();
    _msgSearchCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _messageHaystack(Map<String, dynamic> m) {
    final type = (m['type'] ?? 'text').toString();
    if (type == 'text') {
      return (m['text'] ?? '').toString().toLowerCase();
    }
    if (type == 'image') return 'imagem foto imagem';
    if (type == 'video') return 'vídeo video';
    if (type == 'audio') return 'áudio audio';
    return type.toLowerCase();
  }

  Future<void> _sendText() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final ok = await ChurchChatService.sendTextMessage(
        tenantId: widget.tenantId,
        threadId: widget.threadId,
        text: t,
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
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _uploadAndSend(bytes, x.name, 'image/jpeg', 'image');
  }

  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    final x = await picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _uploadAndSend(bytes, x.name, 'video/mp4', 'video');
  }

  Future<void> _pickAndSendAudio() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['m4a', 'aac', 'mp3', 'wav', 'ogg'],
      withData: true,
    );
    final f = r?.files.single;
    if (f?.bytes == null) return;
    final name = f!.name;
    await _uploadAndSend(f.bytes!, name, 'audio/mpeg', 'audio');
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
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Envio bloqueado para este contacto.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ThemeCleanPremium.primary,
                ThemeCleanPremium.primary.withValues(alpha: 0.92),
                ThemeCleanPremium.primaryLight,
              ],
            ),
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
            Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChurchChatService.messagesCol(widget.tenantId, widget.threadId)
                  .orderBy('createdAt', descending: true)
                  .limit(120)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docsRaw = snap.data!.docs;
                final q = _msgSearchCtrl.text.trim().toLowerCase();
                final docs = q.isEmpty
                    ? docsRaw
                    : docsRaw
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final mine = (m['senderUid'] ?? '').toString() == uid;
                    final type = (m['type'] ?? 'text').toString();
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: mine
                              ? ThemeCleanPremium.primary.withValues(alpha: 0.16)
                              : ThemeCleanPremium.cardBackground,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(10),
                            topRight: const Radius.circular(10),
                            bottomLeft: Radius.circular(mine ? 10 : 2),
                            bottomRight: Radius.circular(mine ? 2 : 10),
                          ),
                          border: Border.all(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                          ),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: _MessageBody(type: type, data: m),
                      ),
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
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _sending ? null : _pickAndSendAudio,
                    icon: Icon(Icons.mic_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    tooltip: 'Áudio',
                  ),
                  IconButton(
                    onPressed: _sending ? null : _pickAndSendImage,
                    icon: Icon(Icons.photo_camera_back_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    tooltip: 'Foto',
                  ),
                  IconButton(
                    onPressed: _sending ? null : _pickAndSendVideo,
                    icon: Icon(Icons.videocam_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    tooltip: 'Vídeo',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      style: TextStyle(
                        color: ThemeCleanPremium.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Mensagem',
                        hintStyle: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
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
                            horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _sendText,
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
  final String type;
  final Map<String, dynamic> data;

  const _MessageBody({required this.type, required this.data});

  @override
  Widget build(BuildContext context) {
    if (type == 'text') {
      return Text(
        (data['text'] ?? '').toString(),
        style: const TextStyle(fontSize: 15, height: 1.35),
      );
    }
    final url = (data['mediaUrl'] ?? '').toString();
    if (url.isEmpty) {
      return const Text('[mídia indisponível]');
    }
    if (type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SafeNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          height: 220,
        ),
      );
    }
    if (type == 'video') {
      return InkWell(
        onTap: () async {
          final u = Uri.parse(url);
          if (await canLaunchUrl(u)) {
            await launchUrl(u, mode: LaunchMode.externalApplication);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill_rounded,
                color: Color(0xFF128C7E), size: 36),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                kIsWeb ? 'Abrir vídeo' : 'Toque para abrir o vídeo',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Color(0xFF075E54)),
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
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
            kIsWeb ? 'Abrir áudio' : 'Ouvir áudio',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
