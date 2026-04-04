import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show SafeCircleAvatarImage;

/// Comentários de um post em `igrejas/{tenant}/noticias/{id}/comentarios`.
void showNoticiaCommentsBottomSheet(
  BuildContext context, {
  required CollectionReference<Map<String, dynamic>> commentsRef,
  required String tenantId,
  bool canDelete = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => NoticiaCommentsSheet(
      commentsRef: commentsRef,
      tenantId: tenantId,
      canDelete: canDelete,
    ),
  );
}

class NoticiaCommentsSheet extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> commentsRef;
  final String tenantId;
  final bool canDelete;

  const NoticiaCommentsSheet({
    super.key,
    required this.commentsRef,
    required this.tenantId,
    this.canDelete = false,
  });

  @override
  State<NoticiaCommentsSheet> createState() => _NoticiaCommentsSheetState();
}

class _NoticiaCommentsSheetState extends State<NoticiaCommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String authorName = user?.displayName ?? '';
      String authorPhoto = user?.photoURL ?? '';
      if (authorName.isEmpty && user != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          authorName =
              (uDoc.data()?['nome'] ?? uDoc.data()?['name'] ?? 'Membro')
                  .toString();
          authorPhoto =
              (uDoc.data()?['fotoUrl'] ?? uDoc.data()?['photoUrl'] ?? '')
                  .toString();
        } catch (_) {
          authorName = 'Membro';
        }
      }
      await widget.commentsRef.add({
        'text': texto,
        'texto': texto,
        'authorUid': user?.uid ?? '',
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      });
      try {
        final postRef = widget.commentsRef.parent;
        if (postRef != null) {
          await postRef.set(
            {'commentsCount': FieldValue.increment(1)},
            SetOptions(merge: true),
          );
        }
      } catch (_) {}
      _ctrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Comentário enviado!'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Comentários',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.commentsRef.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
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
                            'Erro ao carregar comentários.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${snap.error}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                final sorted =
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                        docs);
                sorted.sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  if (ta is Timestamp && tb is Timestamp) {
                    return tb.compareTo(ta);
                  }
                  return 0;
                });
                if (sorted.isEmpty) {
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final doc = sorted[i];
                    final c = doc.data();
                    final name = (c['authorName'] ?? 'Membro').toString();
                    final photo = (c['authorPhoto'] ?? '').toString();
                    final text = (c['text'] ?? c['texto'] ?? '').toString();
                    final ts = c['createdAt'];
                    String timeAgo = '';
                    if (ts is Timestamp) {
                      final diff = DateTime.now().difference(ts.toDate());
                      if (diff.inDays > 0) {
                        timeAgo = '${diff.inDays}d';
                      } else if (diff.inHours > 0) {
                        timeAgo = '${diff.inHours}h';
                      } else if (diff.inMinutes > 0) {
                        timeAgo = '${diff.inMinutes}min';
                      } else {
                        timeAgo = 'agora';
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SafeCircleAvatarImage(
                            imageUrl: photo.isNotEmpty &&
                                    (photo.startsWith('http://') ||
                                        photo.startsWith('https://'))
                                ? photo
                                : null,
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
                                        text: name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      TextSpan(text: '  $text'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  timeAgo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.canDelete)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.red,
                              ),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Excluir comentário'),
                                    content: const Text(
                                        'Deseja excluir este comentário?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              ThemeCleanPremium.error,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Excluir'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await doc.reference.delete();
                                  try {
                                    final postRef = widget.commentsRef.parent;
                                    if (postRef != null) {
                                      await postRef.set(
                                        {
                                          'commentsCount':
                                              FieldValue.increment(-1),
                                        },
                                        SetOptions(merge: true),
                                      );
                                    }
                                  } catch (_) {}
                                }
                              },
                              tooltip: 'Excluir comentário',
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
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
}
