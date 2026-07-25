import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/chat_engine/tdlib_chat_adapter.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:image_picker/image_picker.dart';

/// Página de thread do chat — motor TDLib (Telegram).
///
/// Mensagens em tempo real, envio de texto/foto/vídeo/documento/áudio,
/// reply, forward, apagar — tudo via Telegram com UI YAHWEH.
class TdlibChatThreadPage extends StatefulWidget {
  const TdlibChatThreadPage({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<TdlibChatThreadPage> createState() => _TdlibChatThreadPageState();
}

class _TdlibChatThreadPageState extends State<TdlibChatThreadPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  List<TdlibMessageItem> _messages = const [];
  bool _loading = true;
  StreamSubscription<List<TdlibMessageItem>>? _sub;
  int? _replyToId;
  String? _replyToPreview;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _sub = TdLibService.instance.messagesStream.listen((list) {
      if (!mounted) return;
      setState(() {
        _messages = list.where((m) => m.chatId == widget.chatId).toList();
        _loading = false;
      });
    });
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
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
        // Mark as read
        if (items.isNotEmpty) {
          unawaited(TdLibService.instance.markAsRead(
            widget.chatId,
            items.map((m) => m.id).toList(),
          ));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    final replyId = _replyToId;
    _clearReply();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e')),
        );
      }
    }
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
      await TdLibService.instance.sendLocalFile(
        widget.chatId,
        file.path,
        kind: kind,
        replyToMessageId: _replyToId,
      );
      _clearReply();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar mídia: $e')),
        );
      }
    }
  }

  void _setReply(TdlibMessageItem msg) {
    setState(() {
      _replyToId = msg.id;
      _replyToPreview = msg.text.isNotEmpty
          ? msg.text
          : msg.preview;
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
      await TdLibService.instance.deleteMessages(
        widget.chatId,
        [msg.id],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao apagar: $e')),
        );
      }
    }
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _messages.isEmpty && !_loading
                ? Center(
                    child: Text(
                      'Nenhuma mensagem ainda.\nEnvie a primeira!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      // reversed list
                      final msg = _messages[_messages.length - 1 - i];
                      return _MessageBubble(
                        message: msg,
                        onReply: () => _setReply(msg),
                        onDelete: () => _deleteMessage(msg),
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
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 4,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file_rounded),
            onPressed: _showAttachmentSheet,
          ),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Mensagem…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
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
              onChanged: (v) {
                // Typing indicator
                unawaited(TdLibService.instance.sendChatAction(widget.chatId));
              },
            ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
              onPressed: _sendText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bolha de mensagem — estilo WhatsApp/YAHWEH.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onReply,
    required this.onDelete,
  });

  final TdlibMessageItem message;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.primary.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.mediaKind != null)
                _buildMediaPreview(theme),
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.dateEpoch != null)
                    Text(
                      _formatTime(message.dateEpoch!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isRead
                          ? Icons.done_all_rounded
                          : Icons.done_rounded,
                      size: 14,
                      color: message.isRead
                          ? Colors.blue
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview(ThemeData theme) {
    final kind = message.mediaKind ?? '';
    IconData icon;
    String label;
    switch (kind) {
      case 'photo':
        icon = Icons.image_rounded;
        label = 'Foto';
        break;
      case 'video':
        icon = Icons.play_circle_fill_rounded;
        label = 'Vídeo';
        break;
      case 'voice':
        icon = Icons.mic_rounded;
        label = 'Áudio';
        break;
      case 'document':
        icon = Icons.description_rounded;
        label = message.fileName ?? 'Documento';
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        label = 'Arquivo';
    }

    // Show local image if available (mobile only — TDLib not on Web)
    if (kind == 'photo' &&
        message.mediaLocalPath != null &&
        message.mediaLocalPath!.isNotEmpty &&
        !kIsWeb) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            'file://${message.mediaLocalPath}',
            width: 200,
            height: 150,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildMediaIcon(icon, label, theme),
          ),
        ),
      );
    }

    return _buildMediaIcon(icon, label, theme);
  }

  Widget _buildMediaIcon(IconData icon, String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
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
                onReply();
              },
            ),
            if (message.isOutgoing)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: Colors.red),
                title: const Text('Apagar para todos'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
          ],
        ),
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
