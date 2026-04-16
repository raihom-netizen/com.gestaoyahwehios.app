import 'dart:async' show StreamSubscription;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';

List<String> _pastoralStrList(dynamic v) {
  if (v is! List) return [];
  return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
}

/// Mensagem pastoral visível para o membro no painel (filtro por segmento).
bool pastoralMessageVisibleToMember({
  required Map<String, dynamic> data,
  required String myMemberDocId,
  required List<String> myDepartmentIds,
  required String myCargoSlug,
}) {
  if (data['archived'] == true) return false;
  final exp = data['expiresAt'];
  if (exp is Timestamp) {
    if (DateTime.now().isAfter(exp.toDate())) return false;
  }
  final seg = (data['segment'] ?? 'broadcast').toString().toLowerCase();
  if (seg == 'broadcast') return true;
  if (seg == 'member') {
    final ids = _pastoralStrList(data['memberDocIds']);
    if (ids.isNotEmpty) return ids.contains(myMemberDocId);
    return (data['memberDocId'] ?? '').toString() == myMemberDocId;
  }
  if (seg == 'department') {
    final ids = _pastoralStrList(data['departmentIds']);
    if (ids.isNotEmpty) {
      return ids.any((id) => myDepartmentIds.contains(id));
    }
    final did = (data['departmentId'] ?? '').toString();
    return did.isNotEmpty && myDepartmentIds.contains(did);
  }
  if (seg == 'cargo') {
    final labels = _pastoralStrList(data['cargoLabels']);
    if (labels.isNotEmpty) {
      for (final lab in labels) {
        if (FcmService.slugTopicPart(lab) == myCargoSlug) return true;
      }
      return false;
    }
    final cl = (data['cargoLabel'] ?? '').toString();
    if (cl.isEmpty) return false;
    return FcmService.slugTopicPart(cl) == myCargoSlug;
  }
  return false;
}

List<String> _deptIdsFromMemberData(Map<String, dynamic>? data) {
  if (data == null) return [];
  final raw = data['DEPARTAMENTOS'] ?? data['departamentos'];
  if (raw is! List) return [];
  return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
}

String _cargoSlugFromMemberData(Map<String, dynamic>? data) {
  if (data == null) return '';
  final v = (data['CARGO'] ??
          data['cargo'] ??
          data['FUNCAO'] ??
          data['funcao'] ??
          '')
      .toString()
      .trim();
  return FcmService.slugTopicPart(v);
}

/// Card no painel inicial: mensagens da pastoral + confirmação de leitura.
class PastoralInboxHomeCard extends StatelessWidget {
  final String tenantId;
  final String cpfDigits;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs;

  const PastoralInboxHomeCard({
    super.key,
    required this.tenantId,
    required this.cpfDigits,
    required this.memberDocs,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    QueryDocumentSnapshot<Map<String, dynamic>>? myDoc;
    for (final d in memberDocs) {
      final data = d.data();
      final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (cpfDigits.length == 11 && cpf == cpfDigits) {
        myDoc = d;
        break;
      }
      final au = (data['authUid'] ?? '').toString().trim();
      if (au.isNotEmpty && au == uid) {
        myDoc = d;
        break;
      }
    }
    if (myDoc == null) return const SizedBox.shrink();

    final myData = myDoc.data();
    final myId = myDoc.id;
    final depts = _deptIdsFromMemberData(myData);
    final cargoSlug = _cargoSlugFromMemberData(myData);

    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('pastoral_mensagens')
        .orderBy('createdAt', descending: true)
        .limit(20);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final visible = snap.data!.docs.where((doc) {
          return pastoralMessageVisibleToMember(
            data: doc.data(),
            myMemberDocId: myId,
            myDepartmentIds: depts,
            myCargoSlug: cargoSlug,
          );
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        return _PastoralInboxMergedContent(
          key: ValueKey<String>(
            '$tenantId|$uid|${visible.map((d) => d.id).join(',')}',
          ),
          tenantId: tenantId,
          uid: uid,
          visible: visible,
        );
      },
    );
  }
}

class _PastoralInboxMergedContent extends StatefulWidget {
  final String tenantId;
  final String uid;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> visible;

  const _PastoralInboxMergedContent({
    super.key,
    required this.tenantId,
    required this.uid,
    required this.visible,
  });

  @override
  State<_PastoralInboxMergedContent> createState() =>
      _PastoralInboxMergedContentState();
}

class _PastoralInboxMergedContentState extends State<_PastoralInboxMergedContent> {
  final Map<String, bool> _read = {};
  final List<StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subs = [];

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _subscribe() {
    // Inscreve em **todas** as mensagens visíveis (query limit 20). Antes só os 5
    // primeiros por data eram ouvidos, mas a lista mostrada são os 5 primeiros *não
    // lidos* — fora desse conjunto o cartão nunca sumia após confirmar.
    for (final doc in widget.visible) {
      final sub = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('pastoral_mensagens')
          .doc(doc.id)
          .collection('leituras')
          .doc(widget.uid)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() => _read[doc.id] = snap.exists);
      });
      _subs.add(sub);
    }
  }

  bool _sameVisibleOrderAndIds(_PastoralInboxMergedContent old) {
    if (old.visible.length != widget.visible.length) return false;
    for (var i = 0; i < widget.visible.length; i++) {
      if (old.visible[i].id != widget.visible[i].id) return false;
    }
    return true;
  }

  void _markReadLocal(String messageId) {
    if (!mounted) return;
    setState(() => _read[messageId] = true);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _PastoralInboxMergedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameVisibleOrderAndIds(oldWidget)) {
      _cancelSubs();
      _read.clear();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _cancelSubs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.visible
        .where((d) => _read[d.id] != true)
        .take(5)
        .toList();
    if (unread.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl + 2),
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.45),
            ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.6),
      child: Container(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary.withValues(alpha: 0.14),
                        ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.22),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: [
                      BoxShadow(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.mark_email_unread_rounded,
                    color: ThemeCleanPremium.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Mensagens da pastoral',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: ThemeCleanPremium.onSurface,
                                letterSpacing: -0.35,
                                height: 1.2,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              unread.length == 1
                                  ? '1 nova'
                                  : '${unread.length} novas',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Toque em «Responder agora» para escrever ao pastor, ou confirme só a leitura. Ao enviar, o aviso some deste painel.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.4,
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
          ...unread.map((doc) => _PastoralInboxTile(
                tenantId: widget.tenantId,
                messageId: doc.id,
                uid: widget.uid,
                title: (doc.data()['title'] ?? '').toString(),
                body: (doc.data()['body'] ?? '').toString(),
                segment: (doc.data()['segment'] ?? '').toString(),
                onAcknowledged: () => _markReadLocal(doc.id),
              )),
          if (widget.visible.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: ThemeCleanPremium.spaceXs),
              child: Text(
                '+ ${widget.visible.length - 5} mensagem(ns) no histórico recente — confira também as notificações.',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  height: 1.35,
                  color: ThemeCleanPremium.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastoralInboxTile extends StatefulWidget {
  final String tenantId;
  final String messageId;
  final String uid;
  final String title;
  final String body;
  final String segment;
  final VoidCallback onAcknowledged;

  const _PastoralInboxTile({
    required this.tenantId,
    required this.messageId,
    required this.uid,
    required this.title,
    required this.body,
    required this.segment,
    required this.onAcknowledged,
  });

  @override
  State<_PastoralInboxTile> createState() => _PastoralInboxTileState();
}

class _PastoralInboxTileState extends State<_PastoralInboxTile>
    with SingleTickerProviderStateMixin {
  final _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  late AnimationController _exitCtrl;
  late Animation<double> _opacityOut;
  late Animation<Offset> _slide;
  bool _saving = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curved =
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic);
    _opacityOut = Tween<double>(begin: 1, end: 0).animate(curved);
    _slide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.14),
    ).animate(curved);
    _replyCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _exitCtrl.dispose();
    _replyFocus.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _playExitThenAck() async {
    if (!mounted) return;
    setState(() => _exiting = true);
    await _exitCtrl.forward();
    if (!mounted) return;
    widget.onAcknowledged();
  }

  Future<void> _submit({required bool includeReply}) async {
    if (_saving || _exiting) return;
    final r = _replyCtrl.text.trim();
    if (includeReply && r.isEmpty) return;

    final leituraRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('pastoral_mensagens')
        .doc(widget.messageId)
        .collection('leituras')
        .doc(widget.uid);

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payload = <String, dynamic>{
        'readAt': FieldValue.serverTimestamp(),
      };
      if (includeReply && r.isNotEmpty) payload['reply'] = r;
      await leituraRef.set(payload);
      if (!mounted) return;
      messenger.showSnackBar(
        ThemeCleanPremium.successSnackBar(
          includeReply && r.isNotEmpty
              ? 'Resposta enviada ao pastor. Obrigado!'
              : 'Leitura confirmada. Obrigado!',
        ),
      );
      await _playExitThenAck();
    } catch (e, st) {
      assert(() {
        debugPrint('pastoral leitura: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível registrar agora. Tente de novo. (${e is FirebaseException ? e.code : 'erro'})',
          ),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _focusReply() {
    FocusScope.of(context).requestFocus(_replyFocus);
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = _replyCtrl.text.trim().isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: Material(
        color: ThemeCleanPremium.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.16),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title.isEmpty ? 'Mensagem' : widget.title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.body,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.45,
                    color: ThemeCleanPremium.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_saving || _exiting) ? null : _focusReply,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    label: Text(
                      'Responder agora',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      ),
                      elevation: 2,
                      shadowColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                TextField(
                  controller: _replyCtrl,
                  focusNode: _replyFocus,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_exiting,
                  style: GoogleFonts.inter(
                    color: ThemeCleanPremium.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Escreva aqui a sua resposta ao pastor (opcional)',
                    hintStyle: GoogleFonts.inter(
                      color: ThemeCleanPremium.onSurfaceVariant
                          .withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
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
                  ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: (_saving || _exiting)
                            ? null
                            : () => _submit(includeReply: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeCleanPremium.onSurfaceVariant,
                          side: BorderSide(
                            color: ThemeCleanPremium.onSurfaceVariant
                                .withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          _saving ? 'Enviando…' : 'Só confirmar leitura',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: (_saving || _exiting || !hasReply)
                            ? null
                            : () => _submit(includeReply: true),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          'Enviar resposta',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: _opacityOut,
      child: SlideTransition(
        position: _slide,
        child: tile,
      ),
    );
  }
}
