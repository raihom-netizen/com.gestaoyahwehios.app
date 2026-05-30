import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Lista de mensagens favoritas da conversa actual.
class ChurchChatStarredMessagesSheet extends StatefulWidget {
  const ChurchChatStarredMessagesSheet({
    super.key,
    required this.tenantId,
    required this.threadId,
    required this.messageIds,
    required this.onOpenMessage,
  });

  final String tenantId;
  final String threadId;
  final List<String> messageIds;
  final void Function(String messageId) onOpenMessage;

  static Future<void> show(
    BuildContext context, {
    required String tenantId,
    required String threadId,
    required List<String> messageIds,
    required void Function(String messageId) onOpenMessage,
  }) {
    final h = MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: h * 0.58,
        child: ChurchChatStarredMessagesSheet(
          tenantId: tenantId,
          threadId: threadId,
          messageIds: messageIds,
          onOpenMessage: (id) {
            Navigator.pop(ctx);
            onOpenMessage(id);
          },
        ),
      ),
    );
  }

  @override
  State<ChurchChatStarredMessagesSheet> createState() =>
      _ChurchChatStarredMessagesSheetState();
}

class _ChurchChatStarredMessagesSheetState
    extends State<ChurchChatStarredMessagesSheet> {
  late List<String> _ids;

  @override
  void initState() {
    super.initState();
    _ids = List<String>.from(widget.messageIds);
  }

  @override
  Widget build(BuildContext context) {
    if (_ids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline_rounded, size: 40),
            const SizedBox(height: 12),
            Text(
              'Sem mensagens favoritas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Toque numa mensagem → Favoritar mensagem.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mensagens favoritas (${_ids.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _ids.length,
            itemBuilder: (context, i) {
              final id = _ids[i];
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: ChurchChatService.messagesCol(
                  widget.tenantId,
                  widget.threadId,
                ).doc(id).get(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final preview = _preview(data);
                  final when = data?['createdAt'];
                  String whenLabel = '';
                  if (when is Timestamp) {
                    final d = when.toDate();
                    whenLabel =
                        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
                        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                  }
                  return ListTile(
                    leading: const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B)),
                    title: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: whenLabel.isEmpty ? null : Text(whenLabel),
                    onTap: () => widget.onOpenMessage(id),
                    trailing: IconButton(
                      tooltip: 'Remover dos favoritos',
                      icon: const Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B)),
                      onPressed: () async {
                        await ChurchChatMemberPrefs.setMessageStarred(
                          tenantId: widget.tenantId,
                          threadId: widget.threadId,
                          messageId: id,
                          value: false,
                        );
                        if (!mounted) return;
                        setState(() => _ids.remove(id));
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _preview(Map<String, dynamic>? data) {
    if (data == null) return 'Mensagem removida ou indisponível';
    final type = (data['type'] ?? 'text').toString();
    if (type == 'text') {
      final t = (data['text'] ?? '').toString().trim();
      return t.isEmpty ? 'Texto' : t;
    }
    if (type == 'image') return '📷 Foto';
    if (type == 'video') return '🎬 Vídeo';
    if (type == 'audio') return '🎤 Áudio';
    if (type == 'sticker') return 'Figurinha';
    return 'Mensagem';
  }
}
