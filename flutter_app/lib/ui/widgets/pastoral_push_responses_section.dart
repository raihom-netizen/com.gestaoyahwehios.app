import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Painel na aba Push: mensagens recentes e subcoleção `leituras` (confirmação + texto de resposta).
class PastoralPushResponsesSection extends StatefulWidget {
  final String tenantId;

  const PastoralPushResponsesSection({super.key, required this.tenantId});

  @override
  State<PastoralPushResponsesSection> createState() =>
      _PastoralPushResponsesSectionState();
}

class _PastoralPushResponsesSectionState
    extends State<PastoralPushResponsesSection> {
  final Set<String> _expanded = {};
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _msgTitle(Map<String, dynamic> d) {
    final t = (d['title'] ?? '').toString().trim();
    return t.isEmpty ? 'Mensagem' : t;
  }

  static String _formatTs(dynamic v) {
    if (v is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(v.toDate());
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return const SizedBox.shrink();

    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('pastoral_mensagens')
        .orderBy('createdAt', descending: true)
        .limit(35);

    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.cardBackground,
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: [
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.forum_rounded,
                  color: ThemeCleanPremium.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leituras e respostas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                        color: ThemeCleanPremium.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confirmações na caixa de entrada do membro e textos opcionais enviados de volta.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ThemeCleanPremium.onSurface,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar por título da mensagem…',
              hintStyle: GoogleFonts.inter(
                fontSize: 13.5,
                color: ThemeCleanPremium.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: ThemeCleanPremium.primary.withValues(alpha: 0.75),
                size: 22,
              ),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Limpar',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        size: 20,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: ThemeCleanPremium.surface,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd + 2),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd + 2),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd + 2),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
                  width: 1.4,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Não foi possível carregar o histórico.',
                    style: TextStyle(
                      color: ThemeCleanPremium.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final q = _searchCtrl.text.trim().toLowerCase();
              final docs = snap.data!.docs
                  .where((d) => d.data()['archived'] != true)
                  .where((d) {
                    if (q.isEmpty) return true;
                    return _msgTitle(d.data()).toLowerCase().contains(q);
                  })
                  .toList();

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    q.isNotEmpty
                        ? 'Nenhuma mensagem corresponde à busca.'
                        : 'Ainda não há mensagens pastorais nesta igreja.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: ThemeCleanPremium.onSurfaceVariant,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data();
                  final expanded = _expanded.contains(doc.id);
                  return Material(
                    color: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg + 2),
                    clipBehavior: Clip.antiAlias,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusLg + 2),
                        border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: ThemeCleanPremium.primary
                              .withValues(alpha: 0.06),
                        ),
                        child: ExpansionTile(
                          key: ValueKey<String>('pastoral_expand_${doc.id}'),
                          tilePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusLg + 2,
                            ),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusLg + 2,
                            ),
                          ),
                          backgroundColor: Colors.transparent,
                          collapsedBackgroundColor: Colors.transparent,
                          iconColor: ThemeCleanPremium.primary,
                          collapsedIconColor: ThemeCleanPremium.primary,
                          onExpansionChanged: (v) {
                            setState(() {
                              if (v) {
                                _expanded.add(doc.id);
                              } else {
                                _expanded.remove(doc.id);
                              }
                            });
                          },
                          leading: _PastoralMessageLeadingBadge(),
                          title: Text(
                            _msgTitle(data),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: -0.2,
                              color: ThemeCleanPremium.onSurface,
                              height: 1.25,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTs(data['createdAt']),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          children: [
                            if (expanded)
                              _PastoralLeiturasPanel(
                                tenantId: tid,
                                messageId: doc.id,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PastoralLeiturasPanel extends StatelessWidget {
  final String tenantId;
  final String messageId;

  const _PastoralLeiturasPanel({
    required this.tenantId,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('pastoral_mensagens')
        .doc(messageId)
        .collection('leituras');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final rows = snap.data!.docs.toList();
        rows.sort((a, b) {
          final ta = a.data()['readAt'];
          final tb = b.data()['readAt'];
          final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
          final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
          return db.compareTo(da);
        });
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              'Nenhuma confirmação de leitura ainda.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: ThemeCleanPremium.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2),
              child: Text(
                'Respostas dos membros',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ),
            ...rows.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PastoralLeituraRow(
                  tenantId: tenantId,
                  uid: d.id,
                  data: d.data(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PastoralLeituraRow extends StatefulWidget {
  final String tenantId;
  final String uid;
  final Map<String, dynamic> data;

  const _PastoralLeituraRow({
    required this.tenantId,
    required this.uid,
    required this.data,
  });

  @override
  State<_PastoralLeituraRow> createState() => _PastoralLeituraRowState();
}

class _PastoralLeituraRowState extends State<_PastoralLeituraRow> {
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _resolveLabel();
  }

  Future<void> _resolveLabel() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      if (!mounted) return;
      if (snap.exists) {
        final d = snap.data() ?? {};
        final dn = (d['displayName'] ?? '').toString().trim();
        final em = (d['email'] ?? '').toString().trim();
        final label =
            dn.isNotEmpty ? dn : (em.isNotEmpty ? em : '');
        if (label.isNotEmpty) {
          setState(() => _displayName = label);
          return;
        }
      }
    } catch (_) {
      // Regras podem bloquear leitura de outros users — tenta ficha do membro.
    }
    try {
      final q = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId.trim())
          .collection('membros')
          .where('authUid', isEqualTo: widget.uid)
          .limit(1)
          .get();
      if (!mounted) return;
      if (q.docs.isNotEmpty) {
        final d = q.docs.first.data();
        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
            .toString()
            .trim();
        if (nome.isNotEmpty) {
          setState(() => _displayName = nome);
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _displayName = null);
  }

  String _uidShort(String u) {
    if (u.length <= 10) return u;
    return '${u.substring(0, 10)}…';
  }

  String get _label =>
      (_displayName != null && _displayName!.isNotEmpty)
          ? _displayName!
          : 'Membro (${_uidShort(widget.uid)})';

  String _formatRead(dynamic v) {
    if (v is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(v.toDate());
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final readAt = widget.data['readAt'];
    final reply = (widget.data['reply'] ?? '').toString().trim();
    final hasReply = reply.isNotEmpty;
    final maxBubble = MediaQuery.sizeOf(context).width * 0.92;

    const bubbleGrey = Color(0xFFF1F5F9);
    const bubbleBorder = Color(0xFFE2E8F0);
    const statusGreen = Color(0xFF059669);
    const statusMuted = Color(0xFF64748B);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubble.clamp(280, 560)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: bubbleGrey,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: bubbleBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: ThemeCleanPremium.primary
                            .withValues(alpha: 0.14),
                        child: Text(
                          _label.isNotEmpty
                              ? _label.substring(0, 1).toUpperCase()
                              : '?',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: ThemeCleanPremium.primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: ThemeCleanPremium.onSurface,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  hasReply
                                      ? Icons.done_all_rounded
                                      : Icons.remove_red_eye_outlined,
                                  size: 15,
                                  color: hasReply ? statusGreen : statusMuted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    hasReply
                                        ? 'Respondeu · ${_formatRead(readAt)}'
                                        : 'Leitura · ${_formatRead(readAt)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (hasReply) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              ThemeCleanPremium.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        reply,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _PastoralStatusChip(
                    label: hasReply ? 'Respondido' : 'Sem texto de resposta',
                    icon: hasReply ? Icons.check_circle_rounded : Icons.circle_outlined,
                    foreground: hasReply ? statusGreen : statusMuted,
                    background: hasReply
                        ? statusGreen.withValues(alpha: 0.1)
                        : statusMuted.withValues(alpha: 0.1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastoralMessageLeadingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary,
            ThemeCleanPremium.primary.withValues(alpha: 0.82),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.forum_rounded, color: Colors.white, size: 22),
    );
  }
}

class _PastoralStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  const _PastoralStatusChip({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
