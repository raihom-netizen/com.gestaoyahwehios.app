import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Comentários do mural — cache-first, envio otimista, sem spinner infinito na web.
class MuralCommentsSheet extends StatefulWidget {
  const MuralCommentsSheet({
    super.key,
    required this.postRef,
    required this.authorUid,
    required this.authorName,
    this.authorPhoto = '',
  });

  final DocumentReference<Map<String, dynamic>> postRef;
  final String authorUid;
  final String authorName;
  final String authorPhoto;

  static Future<void> show(
    BuildContext context, {
    required DocumentReference<Map<String, dynamic>> postRef,
    required String authorUid,
    required String authorName,
    String authorPhoto = '',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MuralCommentsSheet(
        postRef: postRef,
        authorUid: authorUid,
        authorName: authorName,
        authorPhoto: authorPhoto,
      ),
    );
  }

  @override
  State<MuralCommentsSheet> createState() => _MuralCommentsSheetState();
}

class _MuralCommentsSheetState extends State<MuralCommentsSheet> {
  final _ctrl = TextEditingController();
  List<MuralCommentItem> _items = const [];
  bool _loading = true;
  bool _sending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = _items.isEmpty;
      _loadError = null;
    });
    try {
      final list = await NoticiaSocialService.fetchComments(widget.postRef);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Não foi possível carregar comentários.';
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final optimistic = MuralCommentItem(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      authorName: widget.authorName,
      text: text,
      createdAt: Timestamp.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _items = [optimistic, ..._items];
    });
    _ctrl.clear();
    try {
      if (!await YahwehModuleMediaGate.ensureReadyForPublish(
        context: context,
        module: YahwehMediaModule.avisos,
      )) {
        if (mounted) {
          setState(() {
            _items = _items.where((e) => e.id != optimistic.id).toList();
          });
        }
        return;
      }
      await NoticiaSocialService.addComment(
        postRef: widget.postRef,
        uid: widget.authorUid,
        authorName: widget.authorName,
        text: text,
        authorPhoto: widget.authorPhoto,
      );
      if (!mounted) return;
      await _reload();
    } catch (e) {
      await YahwehModuleMediaGate.recoverNoAppAfterPublishError(e);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != optimistic.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Não foi possível comentar agora.'),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.mode_comment_outlined,
                      size: 20, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Comentários',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _loading ? null : _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 260,
                child: _buildList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Escreva um comentário...',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.1),
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
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

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: ThemeCleanPremium.primary,
          ),
        ),
      );
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            TextButton(onPressed: _reload, child: const Text('Tentar de novo')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Seja o primeiro a comentar.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 12, color: Colors.grey.shade200),
      itemBuilder: (context, i) {
        final c = _items[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
              child: Icon(Icons.person,
                  size: 14, color: ThemeCleanPremium.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.text,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  if (c.pending)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'A enviar…',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
