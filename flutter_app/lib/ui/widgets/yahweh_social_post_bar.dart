import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Barra estilo Instagram: curtir, comentar, confirmar presença (evento).
/// Contadores em tempo real via stream do documento da notícia.
class YahwehSocialPostBar extends StatefulWidget {
  final String tenantId;
  final String postId;
  final bool isEvento;
  /// Slug da igreja (link no texto da agenda).
  final String churchSlug;
  /// `noticias` (eventos) ou `avisos` (mural de avisos).
  final String postsParentCollection;

  const YahwehSocialPostBar({
    super.key,
    required this.tenantId,
    required this.postId,
    required this.isEvento,
    this.churchSlug = '',
    this.postsParentCollection = ChurchTenantPostsCollections.noticias,
  });

  @override
  State<YahwehSocialPostBar> createState() => _YahwehSocialPostBarState();
}

class _YahwehSocialPostBarState extends State<YahwehSocialPostBar> {
  bool _likeBusy = false;
  bool _rsvpBusy = false;
  /// Otimista até o Firestore confirmar (null = usar dados do stream).
  bool? _optLiked;
  bool? _optRsvp;

  DocumentReference<Map<String, dynamic>> get _postRef => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection(widget.postsParentCollection)
      .doc(widget.postId);

  Future<({String name, String photo})> _memberDisplay() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final d = uDoc.data() ?? {};
        name = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        photo = (d['fotoUrl'] ?? d['photoUrl'] ?? photo).toString();
      } catch (_) {
        name = 'Membro';
      }
    }
    return (name: name.isEmpty ? 'Membro' : name, photo: photo);
  }

  Future<void> _toggleLike(Map<String, dynamic> data, bool currentlyLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre no app (área do membro) para curtir e comentar.',
        ),
      );
      return;
    }
    final uid = user.uid;
    setState(() {
      _optLiked = !currentlyLiked;
      _likeBusy = true;
    });
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleCurtida(
        tenantId: widget.tenantId,
        postId: widget.postId,
        uid: uid,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyLiked: currentlyLiked,
        parentCollection: widget.postsParentCollection,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _optLiked = null);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível atualizar a curtida.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _likeBusy = false;
          _optLiked = null;
        });
      }
    }
  }

  Future<void> _toggleRsvp(Map<String, dynamic> data, bool current) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre no app para confirmar presença.',
        ),
      );
      return;
    }
    setState(() {
      _optRsvp = !current;
      _rsvpBusy = true;
    });
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleConfirmacaoPresenca(
        tenantId: widget.tenantId,
        postId: widget.postId,
        uid: user.uid,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyConfirmed: current,
        parentCollection: widget.postsParentCollection,
      );
      if (!current && widget.isEvento && mounted) {
        DateTime? start;
        try {
          final sa = data['startAt'];
          if (sa is Timestamp) start = sa.toDate();
        } catch (_) {}
        if (start != null && start.isAfter(DateTime.now())) {
          if (!mounted) return;
          final title = (data['title'] ?? 'Evento').toString();
          final loc = (data['location'] ?? '').toString();
          final body = (data['text'] ?? data['body'] ?? '').toString();
          final desc = EventoCalendarIntegration.buildDescriptionWithPublicLink(
            body: body,
            churchSlug: widget.churchSlug,
          );
          final lat = data['locationLat'];
          final lng = data['locationLng'];
          await EventoCalendarIntegration.offerAddToCalendarDialog(
            context,
            eventTitle: title,
            start: start,
            location: loc,
            description: desc,
            locationLat: lat is num ? lat.toDouble() : (lat != null ? double.tryParse(lat.toString()) : null),
            locationLng: lng is num ? lng.toDouble() : (lng != null ? double.tryParse(lng.toString()) : null),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _optRsvp = null);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível confirmar presença.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _rsvpBusy = false;
          _optRsvp = null;
        });
      }
    }
  }

  Future<void> _openComments() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre no app para comentar.',
        ),
      );
      return;
    }
    final ctrl = TextEditingController();
    var sending = false;
    final commentsRef = _postRef.collection('comentarios');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> send() async {
              final t = ctrl.text.trim();
              if (t.isEmpty || sending) return;
              setLocal(() => sending = true);
              try {
                final m = await _memberDisplay();
                await commentsRef.add({
                  'authorUid': user.uid,
                  'authorName': m.name,
                  'authorPhoto': m.photo,
                  'text': t,
                  'texto': t,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                await _postRef.set(
                  {'commentsCount': FieldValue.increment(1)},
                  SetOptions(merge: true),
                );
                ctrl.clear();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    ThemeCleanPremium.feedbackSnackBar('Erro ao enviar comentário.'),
                  );
                }
              } finally {
                if (ctx.mounted) setLocal(() => sending = false);
              }
            }

            final pad = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: pad),
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.55,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Comentários',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: commentsRef
                            .orderBy('createdAt', descending: true)
                            .limit(40)
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Center(
                              child: Text(
                                'Nenhum comentário ainda.',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => Divider(height: 16, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final c = docs[i].data();
                              final name =
                                  (c['authorName'] ?? c['name'] ?? 'Membro').toString();
                              final text =
                                  (c['text'] ?? c['texto'] ?? '').toString();
                              final ph = (c['authorPhoto'] ?? c['photoUrl'] ?? '')
                                  .toString();
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SafeCircleAvatarImage(
                                    imageUrl: ph.isNotEmpty &&
                                            (ph.startsWith('http://') ||
                                                ph.startsWith('https://'))
                                        ? ph
                                        : null,
                                    radius: 16,
                                    fallbackIcon: Icons.person_rounded,
                                    fallbackColor: Colors.grey.shade600,
                                    backgroundColor: Colors.grey.shade200,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          text,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              decoration: InputDecoration(
                                hintText: 'Escreva um comentário...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => send(),
                            ),
                          ),
                          IconButton(
                            onPressed: sending ? null : send,
                            icon: sending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
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
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _postRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final merged = NoticiaSocialService.mergedLikeUids(data);
        final serverLiked = uid.isNotEmpty && merged.contains(uid);
        final liked = _optLiked ?? serverLiked;
        var likeCount = NoticiaSocialService.likeDisplayCount(data, merged);
        if (_optLiked != null && _optLiked != serverLiked) {
          likeCount += _optLiked! ? 1 : -1;
          if (likeCount < 0) likeCount = 0;
        }
        final rsvpList = List<String>.from(
          ((data['rsvp'] as List?) ?? []).map((e) => e.toString()),
        );
        final serverRsvp = uid.isNotEmpty && rsvpList.contains(uid);
        final rsvp = _optRsvp ?? serverRsvp;
        var rsvpCount = NoticiaSocialService.rsvpDisplayCount(data, rsvpList);
        if (_optRsvp != null && _optRsvp != serverRsvp) {
          rsvpCount += _optRsvp! ? 1 : -1;
          if (rsvpCount < 0) rsvpCount = 0;
        }
        final commentsCount = (data['commentsCount'] is num)
            ? (data['commentsCount'] as num).toInt()
            : 0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: liked ? 'Remover curtida' : 'Curtir',
                    onPressed: _likeBusy ? null : () => _toggleLike(data, serverLiked),
                    icon: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? const Color(0xFFE11D48) : Colors.grey.shade800,
                      size: 26,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Comentar',
                    onPressed: _openComments,
                    icon: Icon(Icons.chat_bubble_outline_rounded,
                        size: 24, color: Colors.grey.shade800),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.isEvento)
                    FilledButton.tonalIcon(
                      onPressed: _rsvpBusy ? null : () => _toggleRsvp(data, serverRsvp),
                      icon: Icon(
                        rsvp ? Icons.event_available_rounded : Icons.event_outlined,
                        size: 20,
                      ),
                      label: Text(rsvp ? 'Confirmado' : 'Vou participar'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (likeCount > 0)
                      Text(
                        '$likeCount ${likeCount == 1 ? 'curtida' : 'curtidas'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    if (widget.isEvento && rsvpCount > 0)
                      Text(
                        '$rsvpCount ${rsvpCount == 1 ? 'pessoa confirmou' : 'pessoas confirmaram'} presença',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: ThemeCleanPremium.success,
                        ),
                      ),
                    if (commentsCount > 0)
                      Text(
                        'Ver os $commentsCount comentários',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
