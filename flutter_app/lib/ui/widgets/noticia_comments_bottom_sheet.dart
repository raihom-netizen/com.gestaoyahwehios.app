import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Comentários de um post — cache-first, sem `watchSafe` (evita INTERNAL ASSERTION web).
Future<void> showNoticiaCommentsBottomSheet(
  BuildContext context, {
  required CollectionReference<Map<String, dynamic>> commentsRef,
  required String tenantId,
  bool canDelete = false,
}) {
  final postRef = commentsRef.parent;
  if (postRef == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => NoticiaCommentsSheet(
      postRef: postRef,
      commentsRef: commentsRef,
      tenantId: tenantId,
      canDelete: canDelete,
    ),
  );
}

class NoticiaCommentsSheet extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> postRef;
  final CollectionReference<Map<String, dynamic>> commentsRef;
  final String tenantId;
  final bool canDelete;

  const NoticiaCommentsSheet({
    super.key,
    required this.postRef,
    required this.commentsRef,
    required this.tenantId,
    this.canDelete = false,
  });

  @override
  State<NoticiaCommentsSheet> createState() => _NoticiaCommentsSheetState();
}

class _NoticiaCommentsSheetState extends State<NoticiaCommentsSheet> {
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
      final list = await NoticiaSocialService.fetchComments(
        widget.postRef,
        limit: 120,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('NoticiaCommentsSheet _reload: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Não foi possível carregar comentários.';
      });
    }
  }

  Future<({String name, String photo, String uid})> _author() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) {
      return (name: 'Membro', photo: '', uid: '');
    }
    var authorName = user.displayName?.trim() ?? '';
    var authorPhoto = user.photoURL?.trim() ?? '';
    if (authorName.isEmpty) {
      try {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
        }
        Future<DocumentSnapshot<Map<String, dynamic>>> readUser() =>
            firebaseDefaultFirestore.collection('users').doc(user.uid).get();
        final uDoc = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                readUser,
                maxAttempts: 4,
              ).timeout(const Duration(seconds: 12))
            : await readUser().timeout(const Duration(seconds: 10));
        final d = uDoc.data() ?? {};
        authorName = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        authorPhoto =
            (d['fotoUrl'] ?? d['photoUrl'] ?? authorPhoto).toString();
      } catch (_) {
        authorName = 'Membro';
      }
    }
    return (
      name: authorName.isEmpty ? 'Membro' : authorName,
      photo: authorPhoto,
      uid: user.uid,
    );
  }

  Future<void> _send() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _sending) return;
    final author = await _author();
    if (author.uid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Entre na conta para comentar.'),
        );
      }
      return;
    }
    final optimistic = MuralCommentItem(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      authorName: author.name,
      text: texto,
      createdAt: Timestamp.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _items = [optimistic, ..._items];
    });
    _ctrl.clear();
    try {
      await NoticiaSocialService.addComment(
        postRef: widget.postRef,
        uid: author.uid,
        authorName: author.name,
        text: texto,
        authorPhoto: author.photo,
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Comentário enviado!'),
      );
    } catch (e, st) {
      debugPrint('NoticiaCommentsSheet _send: $e\n$st');
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

  Future<void> _deleteComment(MuralCommentItem item) async {
    if (item.id.startsWith('local_')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir comentário'),
        content: const Text('Deseja excluir este comentário?'),
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
    if (ok != true || !mounted) return;
    try {
      Future<void> run() async {
        await widget.commentsRef.doc(item.id).delete();
        await widget.postRef.set(
          {'commentsCount': FieldValue.increment(-1)},
          SetOptions(merge: true),
        );
      }

      if (kIsWeb) {
        await FirestoreWebGuard.runChatWriteWithRecovery(run, maxAttempts: 5);
      } else {
        await run();
      }
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList();
      });
    } catch (e, st) {
      debugPrint('NoticiaCommentsSheet _deleteComment: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível excluir o comentário.',
          ),
        );
      }
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min';
    return 'agora';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Comentários',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(child: _buildList(scrollCtrl)),
          Divider(height: 1, color: Colors.grey.shade200),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                8,
                MediaQuery.of(context).viewInsets.bottom + 8,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        ThemeCleanPremium.primary.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: 'Adicionar comentário...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: ThemeCleanPremium.primaryLight,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _sending
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: _send,
                          icon: const Icon(
                            Icons.send_rounded,
                            color: ThemeCleanPremium.primary,
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(44, 44),
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

  Widget _buildList(ScrollController scrollCtrl) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              TextButton(onPressed: _reload, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhum comentário ainda.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 4),
            Text(
              'Digite abaixo e envie para ser o primeiro!',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final c = _items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SafeCircleAvatarImage(
                imageUrl: null,
                radius: 16,
                fallbackIcon: Icons.person_rounded,
                fallbackColor: Colors.grey.shade600,
                backgroundColor: Colors.grey.shade300,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: c.authorName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '  ${c.text}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.pending ? 'A enviar…' : _timeAgo(c.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle:
                            c.pending ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canDelete && !c.pending)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _deleteComment(c),
                  tooltip: 'Excluir comentário',
                ),
            ],
          ),
        );
      },
    );
  }
}
