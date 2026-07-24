import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_whatsapp_one_tap_button.dart';

/// Barra moderna: Participar · Comentar · Compartilhar (WhatsApp 1 toque).
/// Contadores em tempo real via stream do documento.
class YahwehSocialPostBar extends StatefulWidget {
  final String tenantId;
  final String postId;
  final bool isEvento;
  /// Slug da igreja (link no texto da agenda / WhatsApp).
  final String churchSlug;
  /// Nome da igreja para mensagem WhatsApp.
  final String churchName;
  /// `eventos` ou `avisos`.
  final String postsParentCollection;
  /// Se true, permite abrir comentários só para leitura sem login.
  final bool allowGuestCommentView;

  const YahwehSocialPostBar({
    super.key,
    required this.tenantId,
    required this.postId,
    required this.isEvento,
    this.churchSlug = '',
    this.churchName = '',
    this.postsParentCollection = ChurchTenantPostsCollections.eventos,
    this.allowGuestCommentView = true,
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
  String get _tenantId => ChurchRepository.churchId(widget.tenantId.trim());

  DocumentReference<Map<String, dynamic>> get _postRef =>
      ChurchUiCollections.churchDoc(_tenantId)
      .collection(widget.postsParentCollection)
      .doc(widget.postId);

  Future<({String name, String photo})> _memberDisplay() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
            debugPrint('SocialPostBar _memberDisplay ensurePanelReadReady: $e\n$st');
          });
        }
        Future<DocumentSnapshot<Map<String, dynamic>>> readUser() =>
            firebaseDefaultFirestore.collection('users').doc(user.uid).get();
        final uDoc = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                readUser,
                maxAttempts: 4,
              ).timeout(ChurchPanelReadTimeouts.queryCap)
            : await readUser().timeout(ChurchPanelReadTimeouts.queryCap);
        final d = uDoc.data() ?? {};
        name = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        photo = (d['fotoUrl'] ?? d['photoUrl'] ?? photo).toString();
      } catch (e, st) {
        debugPrint('SocialPostBar _memberDisplay load user: $e\n$st');
        name = 'Membro';
      }
    }
    return (name: name.isEmpty ? 'Membro' : name, photo: photo);
  }

  String _socialErrMsg(Object e, String fallback) {
    final s = e.toString();
    if (s.contains('Entre na área') || s.contains('Entre no app')) {
      return s.replaceFirst(RegExp(r'^Bad state:\s*'), '');
    }
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'Sem permissão para esta ação. Entre como membro desta igreja e tente de novo.';
    }
    if (s.contains('unavailable') || s.contains('network')) {
      return 'Sem conexão. Verifique a internet e tente de novo.';
    }
    return fallback;
  }

  Future<void> _toggleLike(Map<String, dynamic> data, bool currentlyLiked) async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre na área do membro para curtir, comentar ou participar.',
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
      await NoticiaSocialService.toggleCurtidaOnPost(
        postRef: _postRef,
        uid: uid,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyLiked: currentlyLiked,
      );
    } catch (e, st) {
      debugPrint('SocialPostBar _toggleLike: $e\n$st');
      if (mounted) {
        setState(() => _optLiked = null);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            _socialErrMsg(e, 'Não foi possível atualizar a curtida.'),
          ),
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
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre na área do membro para confirmar presença.',
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
        tenantId: _tenantId,
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
        } catch (e, st) {
          debugPrint('SocialPostBar _toggleRsvp startAt parse: $e\n$st');
        }
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
    } catch (e, st) {
      debugPrint('SocialPostBar _toggleRsvp: $e\n$st');
      if (mounted) {
        setState(() => _optRsvp = null);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            _socialErrMsg(e, 'Não foi possível confirmar presença.'),
          ),
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
    final user = firebaseDefaultAuth.currentUser;
    if (user == null && !widget.allowGuestCommentView) {
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
              final u = firebaseDefaultAuth.currentUser;
              if (u == null || u.isAnonymous) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    ThemeCleanPremium.feedbackSnackBar(
                      'Entre na área do membro para comentar.',
                    ),
                  );
                }
                return;
              }
              setLocal(() => sending = true);
              try {
                final m = await _memberDisplay();
                await NoticiaSocialService.addComment(
                  postRef: _postRef,
                  uid: u.uid,
                  authorName: m.name,
                  text: t,
                  authorPhoto: m.photo,
                );
                ctrl.clear();
              } catch (e, st) {
                debugPrint('SocialPostBar _openComments send: $e\n$st');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    ThemeCleanPremium.feedbackSnackBar(
                      _socialErrMsg(e, 'Erro ao enviar comentário.'),
                    ),
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
                            .watchSafe(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Não foi possível carregar comentários.\n'
                                  'Entre como membro e tente de novo.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                            );
                          }
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
      stream: _postRef.watchSafe(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
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
        final churchName = widget.churchName.trim().isNotEmpty
            ? widget.churchName.trim()
            : 'Nossa igreja';

        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha única: Participar · Comentar · Compartilhar · ♥ (WISDOM colorido).
              Row(
                children: [
                  Expanded(
                    child: _ModernEngageChip(
                      icon: rsvp
                          ? Icons.check_circle_rounded
                          : Icons.event_available_rounded,
                      label: 'Participar',
                      selected: rsvp,
                      accent: const Color(0xFF10B981),
                      onTap: _rsvpBusy
                          ? null
                          : () => _toggleRsvp(data, serverRsvp),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _ModernEngageChip(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Comentar',
                      accent: const Color(0xFF6366F1),
                      onTap: _openComments,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: YahwehNoticiaWhatsAppOneTapButton(
                      churchName: churchName,
                      churchSlug: widget.churchSlug,
                      tenantId: _tenantId,
                      noticiaId: widget.postId,
                      postData: data.isNotEmpty
                          ? data
                          : <String, dynamic>{
                              'title': '',
                              'text': '',
                            },
                      noticiaKindOverride:
                          widget.isEvento ? 'evento' : 'aviso',
                      compact: true,
                      label: 'Compartilhar',
                    ),
                  ),
                  const SizedBox(width: 2),
                  Material(
                    color: liked
                        ? const Color(0xFFE11D48).withValues(alpha: 0.14)
                        : const Color(0xFFFCE7F3),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _likeBusy
                          ? null
                          : () => _toggleLike(data, serverLiked),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: const Color(0xFFE11D48),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (likeCount > 0 || rsvpCount > 0 || commentsCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4, right: 4),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (likeCount > 0)
                        Text(
                          '$likeCount ${likeCount == 1 ? 'curtida' : 'curtidas'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      if (rsvpCount > 0)
                        Text(
                          '$rsvpCount ${rsvpCount == 1 ? 'confirmou' : 'confirmaram'} presença',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF059669),
                          ),
                        ),
                      if (commentsCount > 0)
                        GestureDetector(
                          onTap: _openComments,
                          child: Text(
                            'Ver $commentsCount comentário${commentsCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
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

class _ModernEngageChip extends StatelessWidget {
  const _ModernEngageChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? accent
        : Color.lerp(accent, Colors.white, 0.88)!;
    final fg = selected ? Colors.white : accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 36,
          decoration: BoxDecoration(
            gradient: selected
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      bg,
                      Color.lerp(accent, Colors.white, 0.78)!,
                    ],
                  ),
            color: selected ? accent : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 1 : 0.45),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: fg),
                    const SizedBox(width: 3),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
