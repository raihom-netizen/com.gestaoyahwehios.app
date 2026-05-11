import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Lista estilo WhatsApp — DM + grupos por departamento (só vínculos do membro).
class ChurchChatHubPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool embeddedInShell;

  const ChurchChatHubPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<ChurchChatHubPage> createState() => _ChurchChatHubPageState();
}

class _ChurchChatHubPageState extends State<ChurchChatHubPage> {
  String? _resolvedTenantId;
  List<_DeptEntry> _departments = [];
  Timer? _presenceTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dmSub;
  bool _chatPushEnabled = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final tid =
        await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    if (!mounted) return;
    setState(() => _resolvedTenantId = tid);
    unawaited(_loadChatNotifPrefs());
    await _syncMemberDepartments(tid);
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 25), (_) {
      ChurchChatService.touchPresence(tid);
    });
    ChurchChatService.touchPresence(tid);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _dmSub = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('chat_threads')
          .where('participantUids', arrayContains: uid)
          .snapshots()
          .listen((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadChatNotifPrefs() async {
    final v = await ChurchChatNotificationPrefs.isChatPushEnabled();
    if (!mounted) return;
    setState(() => _chatPushEnabled = v);
  }

  Future<void> _openChatAlertModeSheet() async {
    final current = await ChurchChatNotificationPrefs.getChatAlertMode();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeCleanPremium.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      builder: (ctx) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required String mode,
        }) {
          final selected = current == mode;
          return ListTile(
            leading: Icon(
              icon,
              color: selected
                  ? ThemeCleanPremium.primary
                  : ThemeCleanPremium.onSurfaceVariant,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(subtitle),
            trailing: selected
                ? Icon(Icons.check_circle_rounded, color: ThemeCleanPremium.primary)
                : null,
            onTap: () async {
              Navigator.pop(ctx);
              await ChurchChatNotificationPrefs.setChatAlertMode(mode: mode);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Alerta do chat: $title')),
              );
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                icon: Icons.notifications_active_rounded,
                title: 'Som + vibrar',
                subtitle: 'Estilo conversa padrão.',
                mode: ChurchChatNotificationPrefs.alertModeSound,
              ),
              option(
                icon: Icons.vibration_rounded,
                title: 'Só vibrar',
                subtitle: 'Sem som, apenas vibração.',
                mode: ChurchChatNotificationPrefs.alertModeVibrate,
              ),
              option(
                icon: Icons.notifications_off_rounded,
                title: 'Silencioso',
                subtitle: 'Sem som e sem vibração.',
                mode: ChurchChatNotificationPrefs.alertModeSilent,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _syncMemberDepartments(String tid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final digits = widget.cpf.replaceAll(RegExp(r'\D'), '');
    final base =
        FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');

    DocumentSnapshot<Map<String, dynamic>>? membro;
    try {
      if (digits.length == 11) {
        final byCpf = await base.doc(digits).get();
        if (byCpf.exists) membro = byCpf;
      }
      membro ??= await base.doc(uid).get();
      if (!membro.exists) {
        final q =
            await base.where('authUid', isEqualTo: uid).limit(1).get();
        if (q.docs.isNotEmpty) membro = q.docs.first;
      }
    } catch (_) {}

    final deptIds = <String>[];
    if (membro != null && membro.exists) {
      final d = membro.data() ?? {};
      final raw = d['departamentosIds'];
      if (raw is List) {
        deptIds.addAll(raw.map((e) => e.toString()).where((s) => s.isNotEmpty));
      }
      final depNames = d['DEPARTAMENTOS'];
      if (depNames is List) {
        final col = FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tid)
            .collection('departamentos');
        for (final name in depNames) {
          final key = normalizeChurchDepartmentNameKey(name.toString());
          if (key.isEmpty) continue;
          try {
            final hit = await col.where('nome', isEqualTo: name.toString()).limit(1).get();
            if (hit.docs.isNotEmpty) {
              deptIds.add(hit.docs.first.id);
            }
          } catch (_) {}
        }
      }
    }

    await ChurchChatService.syncUserChatProfile(
      tenantId: tid,
      departmentIds: deptIds.toSet().toList(),
      memberDocId: membro?.id,
    );

    final deptCol =
        FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('departamentos');
    final entries = <_DeptEntry>[];
    for (final id in deptIds.toSet()) {
      try {
        final doc = await deptCol.doc(id).get();
        final name = doc.exists
            ? churchDepartmentNameFromData(doc.data() ?? {}, docId: doc.id)
            : id;
        entries.add(_DeptEntry(id: id, name: name));
        await ChurchChatService.ensureDepartmentThread(
          tenantId: tid,
          departmentId: id,
          departmentName: name,
          participantUids: [uid],
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _departments = entries);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _presenceTimer?.cancel();
    _dmSub?.cancel();
    super.dispose();
  }

  bool _hidden(dynamic data, String uid) {
    final h = data['hiddenForUids'];
    if (h is List && h.map((e) => e.toString()).contains(uid)) return true;
    return false;
  }

  String _dmDisplayTitle(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    final data = doc.data();
    final peers = (data['participantUids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final peer =
        peers.firstWhere((p) => p != myUid, orElse: () => '');
    final titles = data['titlesByUid'];
    var title = peer;
    if (titles is Map && titles[peer] != null) {
      title = titles[peer].toString();
    }
    final t = title.trim();
    return t.isNotEmpty ? t : peer;
  }

  Future<void> _showThreadActionsSheet({
    required BuildContext context,
    required String tenantId,
    required String threadId,
    required String title,
    required bool isDepartment,
    required String? peerUid,
    required ChurchChatMemberPrefsModel prefs,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeCleanPremium.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.onSurfaceVariant
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    prefs.isFavorite(threadId)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  title: Text(
                    prefs.isFavorite(threadId)
                        ? 'Remover dos favoritos'
                        : 'Favoritar conversa',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ChurchChatMemberPrefs.setFavorite(
                      tenantId: tenantId,
                      threadId: threadId,
                      value: !prefs.isFavorite(threadId),
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
                  },
                ),
                ListTile(
                  leading: Icon(
                    prefs.isMutedThread(threadId)
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: Text(
                    prefs.isMutedThread(threadId)
                        ? 'Ativar alertas desta conversa'
                        : 'Silenciar esta conversa',
                  ),
                  subtitle: Text(
                    prefs.isMutedThread(threadId)
                        ? 'Voltará a receber notificações push deste chat.'
                        : 'Sem push desta conversa (global do chat continua nas Configurações).',
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ChurchChatMemberPrefs.setMutedThread(
                      tenantId: tenantId,
                      threadId: threadId,
                      value: !prefs.isMutedThread(threadId),
                    );
                  },
                ),
                if (!isDepartment &&
                    peerUid != null &&
                    peerUid.isNotEmpty) ...[
                  ListTile(
                    leading: Icon(
                      prefs.isBlockedPeer(peerUid)
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: Text(
                      prefs.isBlockedPeer(peerUid)
                          ? 'Desbloquear contacto'
                          : 'Bloquear contacto',
                    ),
                    subtitle: Text(
                      prefs.isBlockedPeer(peerUid)
                          ? 'Poderá voltar a conversar e receber mensagens.'
                          : 'Deixa de ver esta conversa e não recebe mensagens desta pessoa.',
                      style: TextStyle(
                        fontSize: 11,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ChurchChatMemberPrefs.setBlockedPeer(
                        tenantId: tenantId,
                        peerUid: peerUid,
                        value: !prefs.isBlockedPeer(peerUid),
                      );
                    },
                  ),
                ],
                ListTile(
                  leading: Icon(Icons.visibility_off_rounded,
                      color: ThemeCleanPremium.onSurfaceVariant),
                  title: const Text('Ocultar conversa da lista'),
                  subtitle: Text(
                    'Igual a manter no arquivo — pode reabrir pelo grupo ou novo contacto.',
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _confirmHide(context, tenantId, threadId);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tid = _resolvedTenantId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (tid == null || uid == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ThemeCleanPremium.churchPanelBodyGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PremiumChatHeader(
            chatPushEnabled: _chatPushEnabled,
            onMuteTap: () async {
              final next = !_chatPushEnabled;
              await ChurchChatNotificationPrefs.setChatPushEnabled(
                enabled: next,
                tenantId: tid,
              );
              if (mounted) setState(() => _chatPushEnabled = next);
            },
            onNewDm: () => _openPickPeer(context, tid, uid),
            onAlertModeTap: _openChatAlertModeSheet,
          ),
          _ChatSearchBar(
            controller: _searchCtrl,
            onChanged: () => setState(() {}),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ChurchChatMemberPrefs.watch(tid),
              builder: (context, prefSnap) {
                final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('igrejas')
                      .doc(tid)
                      .collection('chat_threads')
                      .where('participantUids', arrayContains: uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final dmDocs = snap.data?.docs ?? [];
                    final threads = <Widget>[];
                    final q = _searchCtrl.text.trim();
                    final ql = q.toLowerCase();

                    final deptCandidates = <_DeptEntry>[];
                    for (final d in _departments) {
                      if (q.isNotEmpty &&
                          !d.name.toLowerCase().contains(ql)) {
                        continue;
                      }
                      deptCandidates.add(d);
                    }
                    deptCandidates.sort((a, b) => a.name
                        .toLowerCase()
                        .compareTo(b.name.toLowerCase()));

                    final dmFiltered =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    for (final doc in dmDocs) {
                      final data = doc.data();
                      if ((data['type'] ?? '') == 'department') continue;
                      if (_hidden(data, uid)) continue;
                      final peers = (data['participantUids'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          [];
                      final peer = peers.firstWhere((p) => p != uid,
                          orElse: () => '');
                      if (prefs.isBlockedPeer(peer)) continue;
                      final disp = _dmDisplayTitle(doc, uid);
                      final preview =
                          (data['lastMessagePreview'] ?? '').toString();
                      if (q.isNotEmpty) {
                        if (!disp.toLowerCase().contains(ql) &&
                            !preview.toLowerCase().contains(ql)) {
                          continue;
                        }
                      }
                      dmFiltered.add(doc);
                    }
                    dmFiltered.sort((a, b) => _dmDisplayTitle(a, uid)
                        .toLowerCase()
                        .compareTo(
                            _dmDisplayTitle(b, uid).toLowerCase()));

                    final favDepts = deptCandidates
                        .where((d) => prefs.isFavorite(
                            ChurchChatService.deptThreadId(d.id)))
                        .toList();
                    final restDepts = deptCandidates
                        .where((d) => !prefs.isFavorite(
                            ChurchChatService.deptThreadId(d.id)))
                        .toList();

                    final favDms = dmFiltered
                        .where((d) => prefs.isFavorite(d.id))
                        .toList();
                    final restDms = dmFiltered
                        .where((d) => !prefs.isFavorite(d.id))
                        .toList();

                    final favMerged = <MapEntry<String, Widget>>[];
                    for (final d in favDepts) {
                      favMerged.add(MapEntry(
                        d.name.toLowerCase(),
                        _deptTile(context, tid, uid, d, prefs),
                      ));
                    }
                    for (final doc in favDms) {
                      favMerged.add(MapEntry(
                        _dmDisplayTitle(doc, uid).toLowerCase(),
                        _dmTile(context, tid, uid, doc, prefs),
                      ));
                    }
                    favMerged.sort((a, b) => a.key.compareTo(b.key));

                    if (favMerged.isNotEmpty) {
                      threads.add(_sectionHeader(
                          'Favoritos (até ${ChurchChatMemberPrefs.maxFavoriteThreads})'));
                      for (final e in favMerged) {
                        threads.add(e.value);
                      }
                    }

                    if (restDepts.isNotEmpty) {
                      threads.add(_sectionHeader('Grupos (departamentos)'));
                      for (final d in restDepts) {
                        threads.add(_deptTile(context, tid, uid, d, prefs));
                      }
                    }

                    threads.add(_sectionHeader('Mensagens diretas'));
                    if (restDms.isEmpty) {
                      if (dmFiltered.isEmpty) {
                        threads.add(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            child: Text(
                              q.isNotEmpty
                                  ? 'Nenhuma conversa corresponde à pesquisa.'
                                  : 'Sem conversas diretas ainda. Use o botão + para escolher um membro.',
                              style: TextStyle(
                                color: ThemeCleanPremium.onSurfaceVariant,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                    } else {
                      for (final doc in restDms) {
                        threads.add(_dmTile(context, tid, uid, doc, prefs));
                      }
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                      children: threads,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: ThemeCleanPremium.onSurfaceVariant,
          letterSpacing: 0.85,
        ),
      ),
    );
  }

  Widget _deptTile(
    BuildContext context,
    String tid,
    String uid,
    _DeptEntry d,
    ChurchChatMemberPrefsModel prefs,
  ) {
    final threadId = ChurchChatService.deptThreadId(d.id);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchChatService.threadRef(tid, threadId).snapshots(),
      builder: (context, thr) {
        final data = thr.data?.data();
        final preview = (data?['lastMessagePreview'] ?? 'Grupo do departamento')
            .toString();
        final ts = data?['lastMessageAt'];
        return _chatTile(
          title: d.name,
          subtitle: preview,
          timeLabel: _fmtTime(ts),
          isFavorite: prefs.isFavorite(threadId),
          isMuted: prefs.isMutedThread(threadId),
          photo: CircleAvatar(
            backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.9),
            child: Text(
              d.name.isNotEmpty ? d.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => ChurchChatThreadPage(
                  tenantId: tid,
                  threadId: threadId,
                  title: d.name,
                  isDepartment: true,
                ),
              ),
            );
          },
          onLongPress: () => _showThreadActionsSheet(
            context: context,
            tenantId: tid,
            threadId: threadId,
            title: d.name,
            isDepartment: true,
            peerUid: null,
            prefs: prefs,
          ),
        );
      },
    );
  }

  Widget _dmTile(
    BuildContext context,
    String tid,
    String uid,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ChurchChatMemberPrefsModel prefs,
  ) {
    final data = doc.data();
    final peers = (data['participantUids'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final peer = peers.firstWhere((p) => p != uid, orElse: () => '');
    final titles = data['titlesByUid'];
    String title = peer;
    if (titles is Map && titles[peer] != null) {
      title = titles[peer].toString();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('chat_presence')
          .doc(peer)
          .snapshots(),
      builder: (context, pres) {
        final online =
            ChurchChatService.isOnlineFromSnapshot(pres.data);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ChurchChatService.threadRef(tid, doc.id).snapshots(),
          builder: (context, thr) {
            final tdata = thr.data?.data();
            final preview =
                (tdata?['lastMessagePreview'] ?? 'Toque para conversar')
                    .toString();
            final ts = tdata?['lastMessageAt'];
            return _chatTile(
              title: title,
              subtitle: preview,
              timeLabel: _fmtTime(ts),
              isFavorite: prefs.isFavorite(doc.id),
              isMuted: prefs.isMutedThread(doc.id),
              online: online,
              photo: CircleAvatar(
                backgroundColor:
                    ThemeCleanPremium.primary.withValues(alpha: 0.88),
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => ChurchChatThreadPage(
                      tenantId: tid,
                      threadId: doc.id,
                      title: title,
                      isDepartment: false,
                      peerUid: peer.isEmpty ? null : peer,
                    ),
                  ),
                );
              },
              onLongPress: () => _showThreadActionsSheet(
                context: context,
                tenantId: tid,
                threadId: doc.id,
                title: title,
                isDepartment: false,
                peerUid: peer.isEmpty ? null : peer,
                prefs: prefs,
              ),
            );
          },
        );
      },
    );
  }

  Widget _chatTile({
    required String title,
    required String subtitle,
    required String timeLabel,
    required Widget photo,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool online = false,
    bool isFavorite = false,
    bool isMuted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ThemeCleanPremium.cardBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
              ),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      photo,
                      if (online)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFavorite)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      if (isMuted)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.notifications_off_rounded,
                            size: 17,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fmtTime(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}';
  }

  Future<void> _confirmHide(
      BuildContext context, String tid, String threadId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ocultar conversa'),
        content: const Text(
          'A conversa some da lista neste aparelho. Pode voltar a abrir pelo departamento ou novo contacto.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ocultar')),
        ],
      ),
    );
    if (ok == true) {
      await ChurchChatService.hideThreadForMe(
          tenantId: tid, threadId: threadId);
    }
  }

  Future<void> _openPickPeer(
      BuildContext context, String tid, String uid) async {
    final prefs = await ChurchChatMemberPrefs.load(tid);
    QuerySnapshot<Map<String, dynamic>>? q;
    try {
      q = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .limit(120)
          .get();
    } catch (_) {
      q = null;
    }
    if (!context.mounted) return;
    final docs = q?.docs
            .where((d) {
              final s =
                  (d.data()['STATUS'] ?? d.data()['status'] ?? '').toString();
              return s.toLowerCase() == 'ativo';
            })
            .toList() ??
        [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível carregar membros para nova conversa.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<_PickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.person_search_rounded,
                          color: ThemeCleanPremium.primary, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'Nova conversa direta',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final doc = docs[i];
                      final d = doc.data();
                      final auth =
                          (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
                      final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                          .toString()
                          .trim();
                      if (auth.isEmpty || auth == uid) {
                        return const SizedBox.shrink();
                      }
                      if (prefs.isBlockedPeer(auth)) {
                        return const SizedBox.shrink();
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        elevation: 0,
                        color: ThemeCleanPremium.cardBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          side: BorderSide(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                ThemeCleanPremium.primary.withValues(alpha: 0.12),
                            foregroundColor: ThemeCleanPremium.primary,
                            child: Text(
                              nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(
                            nome.isEmpty ? auth : nome,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.pop(
                            ctx,
                            _PickResult(uid: auth, name: nome),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (picked == null || !context.mounted) return;
    await ChurchChatService.ensureDmThread(
      tenantId: tid,
      uidA: uid,
      uidB: picked.uid,
      titleA: FirebaseAuth.instance.currentUser?.displayName ?? 'Eu',
      titleB: picked.name,
    );
    final threadId = ChurchChatService.dmThreadId(uid, picked.uid);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tid,
          threadId: threadId,
          title: picked.name,
          isDepartment: false,
          peerUid: picked.uid,
        ),
      ),
    );
  }
}

class _ChatSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _ChatSearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<_ChatSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_l);
  }

  void _l() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_l);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          border: Border.all(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
          ),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: TextField(
          controller: widget.controller,
          onChanged: (_) => widget.onChanged(),
          style: TextStyle(
            color: ThemeCleanPremium.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Pesquisar conversas',
            hintStyle: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
            prefixIcon:
                Icon(Icons.search_rounded, color: ThemeCleanPremium.primary),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Limpar',
                    icon: Icon(Icons.clear_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onChanged();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
        ),
      ),
    );
  }
}

class _PremiumChatHeader extends StatelessWidget {
  final bool chatPushEnabled;
  final VoidCallback onMuteTap;
  final VoidCallback onNewDm;
  final VoidCallback onAlertModeTap;

  const _PremiumChatHeader({
    required this.chatPushEnabled,
    required this.onMuteTap,
    required this.onNewDm,
    required this.onAlertModeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Conversas',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Grupos = departamentos • Mensagens diretas entre membros',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Modo de alerta (som/vibrar/silencioso)',
                    onPressed: onAlertModeTap,
                    icon: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: chatPushEnabled
                        ? 'Silenciar notificações do chat'
                        : 'Ativar notificações do chat',
                    onPressed: onMuteTap,
                    icon: Icon(
                      chatPushEnabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Nova conversa',
                    onPressed: onNewDm,
                    icon: const Icon(
                      Icons.add_comment_rounded,
                      color: Colors.white,
                      size: 26,
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
}

class _DeptEntry {
  final String id;
  final String name;
  _DeptEntry({required this.id, required this.name});
}

class _PickResult {
  final String uid;
  final String name;
  _PickResult({required this.uid, required this.name});
}
