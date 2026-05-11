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
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
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

class _ChurchChatHubPageState extends State<ChurchChatHubPage>
    with SingleTickerProviderStateMixin {
  String? _resolvedTenantId;
  List<_DeptEntry> _departments = [];
  Timer? _presenceTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dmSub;
  bool _chatPushEnabled = true;
  final _searchCtrl = TextEditingController();
  final _membersFilterCtrl = TextEditingController();
  final _deptFilterCtrl = TextEditingController();
  late TabController _hubTabController;

  @override
  void initState() {
    super.initState();
    _hubTabController = TabController(length: 3, vsync: this);
    _membersFilterCtrl.addListener(() => setState(() {}));
    _deptFilterCtrl.addListener(() => setState(() {}));
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
        entries.add(_DeptEntry(
          id: id,
          name: name,
          deptData: doc.exists ? doc.data() : null,
        ));
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
    _hubTabController.dispose();
    _searchCtrl.dispose();
    _membersFilterCtrl.dispose();
    _deptFilterCtrl.dispose();
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
                if (!isDepartment)
                  ListTile(
                    leading: Icon(Icons.visibility_off_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    title: const Text('Ocultar conversa da lista'),
                    subtitle: Text(
                      'Só nas suas conversas diretas — some da lista neste aparelho; pode voltar por «nova conversa».',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _PremiumHubTabBar(controller: _hubTabController),
          ),
          AnimatedBuilder(
            animation: _hubTabController,
            builder: (context, _) {
              final i = _hubTabController.index;
              if (i == 0) {
                return _ChatSearchBar(
                  controller: _searchCtrl,
                  onChanged: () => setState(() {}),
                );
              }
              if (i == 1) {
                return _HubScopedSearchBar(
                  controller: _membersFilterCtrl,
                  hintText: 'Pesquisar membros…',
                  icon: Icons.person_search_rounded,
                );
              }
              return _HubScopedSearchBar(
                controller: _deptFilterCtrl,
                hintText: 'Pesquisar grupos por departamento…',
                icon: Icons.filter_alt_rounded,
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _hubTabController,
              children: [
                _buildConversasTab(context, tid, uid),
                _buildMembrosTab(context, tid, uid),
                _buildGruposTab(context, tid, uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversasTab(BuildContext context, String tid, String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              if (q.isNotEmpty && !d.name.toLowerCase().contains(ql)) {
                continue;
              }
              deptCandidates.add(d);
            }
            deptCandidates.sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            final dmFiltered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in dmDocs) {
              final data = doc.data();
              if ((data['type'] ?? '') == 'department') continue;
              if (_hidden(data, uid)) continue;
              final peers = (data['participantUids'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final peer =
                  peers.firstWhere((p) => p != uid, orElse: () => '');
              if (prefs.isBlockedPeer(peer)) continue;
              final disp = _dmDisplayTitle(doc, uid);
              final preview = (data['lastMessagePreview'] ?? '').toString();
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
                .compareTo(_dmDisplayTitle(b, uid).toLowerCase()));

            final favDepts = deptCandidates
                .where((d) =>
                    prefs.isFavorite(ChurchChatService.deptThreadId(d.id)))
                .toList();
            final restDepts = deptCandidates
                .where((d) =>
                    !prefs.isFavorite(ChurchChatService.deptThreadId(d.id)))
                .toList();

            final favDms =
                dmFiltered.where((d) => prefs.isFavorite(d.id)).toList();
            final restDms =
                dmFiltered.where((d) => !prefs.isFavorite(d.id)).toList();

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
    );
  }

  Widget _buildMembrosTab(BuildContext context, String tid, String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchChatMemberPrefs.watch(tid),
      builder: (context, prefSnap) {
        final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
        return _AllMembersDirectoryView(
          tenantId: tid,
          myUid: uid,
          prefs: prefs,
          filterCtrl: _membersFilterCtrl,
          role: widget.role,
          cpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
          onOpenDm: (peerUid, displayName) =>
              _startDmWithPeer(context, tid, uid, peerUid, displayName),
        );
      },
    );
  }

  Widget _buildGruposTab(BuildContext context, String tid, String uid) {
    final ql = _deptFilterCtrl.text.trim().toLowerCase();
    final filtered = _departments.where((d) {
      if (ql.isEmpty) return true;
      return d.name.toLowerCase().contains(ql);
    }).toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _departments.isEmpty
                ? 'Sem grupos — faça parte de um departamento na sua ficha de membro.'
                : 'Nenhum grupo corresponde à pesquisa.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeCleanPremium.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final d = filtered[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PremiumDeptGroupCard(
            entry: d,
            onOpenDetail: () =>
                _showDepartmentMembersSheet(context, tid, uid, d),
          ),
        );
      },
    );
  }

  Future<void> _startDmWithPeer(
    BuildContext context,
    String tid,
    String myUid,
    String peerUid,
    String displayName,
  ) async {
    final nav = Navigator.of(context);
    await ChurchChatService.ensureDmThread(
      tenantId: tid,
      uidA: myUid,
      uidB: peerUid,
      titleA: FirebaseAuth.instance.currentUser?.displayName ?? 'Eu',
      titleB: displayName,
    );
    final threadId = ChurchChatService.dmThreadId(myUid, peerUid);
    if (!mounted) return;
    await nav.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tid,
          threadId: threadId,
          title: displayName,
          isDepartment: false,
          peerUid: peerUid,
          memberRole: widget.role,
          memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
        ),
      ),
    );
  }

  Future<void> _showDepartmentMembersSheet(
    BuildContext context,
    String tid,
    String uid,
    _DeptEntry dept,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DepartmentMembersSheet(
        navigatorContext: context,
        tenantId: tid,
        currentUid: uid,
        entry: dept,
        role: widget.role,
        cpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
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
          photo: ChurchChatDepartmentAvatar(
            deptData: d.deptData,
            fallbackName: d.name,
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
                  departmentId: d.id,
                  memberRole: widget.role,
                  memberCpfDigits:
                      widget.cpf.replaceAll(RegExp(r'\D'), ''),
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
              showPresence: true,
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
                      memberRole: widget.role,
                      memberCpfDigits:
                          widget.cpf.replaceAll(RegExp(r'\D'), ''),
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
    bool showPresence = false,
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
                      if (showPresence)
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: online
                                  ? ThemeCleanPremium.success
                                  : const Color(0xFF9CA3AF),
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
          'A conversa direta some da lista neste aparelho. Pode voltar a abrir por «nova conversa» com a mesma pessoa.',
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
    docs.sort((a, b) {
      final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    });
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
            return _NovaConversaDiretaSheet(
              scrollController: scroll,
              docs: docs,
              tid: tid,
              myUid: uid,
              prefs: prefs,
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
          memberRole: widget.role,
          memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
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

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _churchChatFetchDeptMembers(String tenantId, String deptId) async {
  bool isActive(Map<String, dynamic> d) {
    final st = (d['STATUS'] ?? d['status'] ?? '').toString().toLowerCase();
    return st == 'ativo';
  }

  int nameCmp(QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b) {
    final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
        .toString()
        .toLowerCase();
    final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
        .toString()
        .toLowerCase();
    return na.compareTo(nb);
  }

  try {
    final q = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros')
        .where('departamentosIds', arrayContains: deptId)
        .limit(400)
        .get();
    final out =
        q.docs.where((doc) => isActive(doc.data())).toList();
    out.sort(nameCmp);
    return out;
  } catch (_) {
    final all = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros')
        .limit(600)
        .get();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in all.docs) {
      final data = doc.data();
      if (!isActive(data)) continue;
      final ids = data['departamentosIds'];
      if (ids is! List) continue;
      var hit = false;
      for (final x in ids) {
        if (x.toString() == deptId) {
          hit = true;
          break;
        }
      }
      if (!hit) continue;
      out.add(doc);
    }
    out.sort(nameCmp);
    return out;
  }
}

class _PremiumHubTabBar extends StatelessWidget {
  final TabController controller;

  const _PremiumHubTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              ThemeCleanPremium.primary,
              ThemeCleanPremium.primaryLight,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: ThemeCleanPremium.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        tabs: const [
          Tab(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_rounded, size: 18),
                SizedBox(width: 6),
                Text('Conversas'),
              ],
            ),
          ),
          Tab(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_rounded, size: 18),
                SizedBox(width: 6),
                Text('Membros'),
              ],
            ),
          ),
          Tab(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.groups_rounded, size: 18),
                SizedBox(width: 6),
                Text('Grupos'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HubScopedSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;

  const _HubScopedSearchBar({
    required this.controller,
    required this.hintText,
    required this.icon,
  });

  @override
  State<_HubScopedSearchBar> createState() => _HubScopedSearchBarState();
}

class _HubScopedSearchBarState extends State<_HubScopedSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_r);
  }

  void _r() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_r);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
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
          style: TextStyle(
            color: ThemeCleanPremium.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
            prefixIcon: Icon(widget.icon, color: ThemeCleanPremium.primary),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Limpar',
                    icon: Icon(Icons.clear_rounded,
                        color: ThemeCleanPremium.onSurfaceVariant),
                    onPressed: () {
                      widget.controller.clear();
                      setState(() {});
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

class _AllMembersDirectoryView extends StatefulWidget {
  final String tenantId;
  final String myUid;
  final ChurchChatMemberPrefsModel prefs;
  final TextEditingController filterCtrl;
  final String role;
  final String cpfDigits;
  final void Function(String peerUid, String displayName) onOpenDm;

  const _AllMembersDirectoryView({
    required this.tenantId,
    required this.myUid,
    required this.prefs,
    required this.filterCtrl,
    required this.role,
    required this.cpfDigits,
    required this.onOpenDm,
  });

  @override
  State<_AllMembersDirectoryView> createState() =>
      _AllMembersDirectoryViewState();
}

class _AllMembersDirectoryViewState extends State<_AllMembersDirectoryView> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _docs;
  bool _loading = true;

  void _onFilterChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.filterCtrl.addListener(_onFilterChanged);
    _load();
  }

  @override
  void dispose() {
    widget.filterCtrl.removeListener(_onFilterChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros')
          .limit(600)
          .get();
      if (!mounted) return;
      setState(() {
        _docs = q.docs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _docs = [];
        _loading = false;
      });
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible {
    final docs = _docs ?? [];
    final q = widget.filterCtrl.text.trim().toLowerCase();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final d = doc.data();
      final st = (d['STATUS'] ?? d['status'] ?? '').toString().toLowerCase();
      if (st != 'ativo') continue;
      final auth = (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
      if (auth.isEmpty || auth == widget.myUid) continue;
      if (widget.prefs.isBlockedPeer(auth)) continue;
      final nome =
          (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      final label = nome.isEmpty ? auth : nome;
      if (q.isNotEmpty) {
        if (!label.toLowerCase().contains(q) &&
            !auth.toLowerCase().contains(q)) {
          continue;
        }
      }
      out.add(doc);
    }
    out.sort((a, b) {
      final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(28),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.15,
                ),
                Text(
                  (_docs ?? []).isEmpty
                      ? 'Não foi possível listar membros.'
                      : 'Nenhum membro corresponde ao filtro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ThemeCleanPremium.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final doc = rows[i];
                final d = doc.data();
                final auth =
                    (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
                final nome =
                    (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
                final label = nome.isEmpty ? auth : nome;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('igrejas')
                      .doc(widget.tenantId)
                      .collection('chat_presence')
                      .doc(auth)
                      .snapshots(),
                  builder: (context, presSnap) {
                    final on = ChurchChatService.isOnlineFromSnapshot(
                        presSnap.data);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: ThemeCleanPremium.cardBackground,
                        elevation: 0,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        child: InkWell(
                          onTap: () => widget.onOpenDm(auth, label),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              border: Border.all(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.08),
                              ),
                              boxShadow: ThemeCleanPremium.softUiCardShadow,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: ThemeCleanPremium
                                            .primary
                                            .withValues(alpha: 0.88),
                                        child: Text(
                                          label.isNotEmpty
                                              ? label[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: -1,
                                        bottom: -1,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: on
                                                ? ThemeCleanPremium.success
                                                : const Color(0xFF9CA3AF),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white,
                                                width: 2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color:
                                                ThemeCleanPremium.onSurface,
                                          ),
                                        ),
                                        Text(
                                          on ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: on
                                                ? const Color(0xFF16A34A)
                                                : ThemeCleanPremium
                                                    .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _PremiumDeptGroupCard extends StatelessWidget {
  final _DeptEntry entry;
  final VoidCallback onOpenDetail;

  const _PremiumDeptGroupCard({
    required this.entry,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpenDetail,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ThemeCleanPremium.primary.withValues(alpha: 0.13),
                ThemeCleanPremium.primaryLight.withValues(alpha: 0.07),
              ],
            ),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ChurchChatDepartmentAvatar(
                  deptData: entry.deptData,
                  fallbackName: entry.name,
                  radius: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: ThemeCleanPremium.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Grupo do departamento · ver membros',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DepartmentMembersSheet extends StatelessWidget {
  final BuildContext navigatorContext;
  final String tenantId;
  final String currentUid;
  final _DeptEntry entry;
  final String role;
  final String cpfDigits;

  const _DepartmentMembersSheet({
    required this.navigatorContext,
    required this.tenantId,
    required this.currentUid,
    required this.entry,
    required this.role,
    required this.cpfDigits,
  });

  Future<void> _openGroupChat(BuildContext sheetCtx) async {
    Navigator.of(sheetCtx).pop();
    if (!navigatorContext.mounted) return;
    await Navigator.of(navigatorContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tenantId,
          threadId: ChurchChatService.deptThreadId(entry.id),
          title: entry.name,
          isDepartment: true,
          departmentId: entry.id,
          memberRole: role,
          memberCpfDigits: cpfDigits,
        ),
      ),
    );
  }

  Future<void> _openDm(
      BuildContext sheetCtx, String peerUid, String name) async {
    Navigator.of(sheetCtx).pop();
    await ChurchChatService.ensureDmThread(
      tenantId: tenantId,
      uidA: currentUid,
      uidB: peerUid,
      titleA: FirebaseAuth.instance.currentUser?.displayName ?? 'Eu',
      titleB: name,
    );
    final threadId = ChurchChatService.dmThreadId(currentUid, peerUid);
    if (!navigatorContext.mounted) return;
    await Navigator.of(navigatorContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tenantId,
          threadId: threadId,
          title: name,
          isDepartment: false,
          peerUid: peerUid,
          memberRole: role,
          memberCpfDigits: cpfDigits,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.onSurfaceVariant
                        .withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChurchChatDepartmentAvatar(
                      deptData: entry.deptData,
                      fallbackName: entry.name,
                      radius: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Membros com este departamento na ficha',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: _churchChatFetchDeptMembers(tenantId, entry.id),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum membro ativo encontrado neste grupo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final auth =
                            (d['authUid'] ?? d['firebaseUid'] ?? '')
                                .toString();
                        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                            .toString()
                            .trim();
                        final label =
                            nome.isEmpty ? (auth.isNotEmpty ? auth : 'Membro') : nome;
                        final canDm = auth.isNotEmpty &&
                            auth != currentUid;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: CircleAvatar(
                            backgroundColor: ThemeCleanPremium.primary
                                .withValues(alpha: 0.15),
                            foregroundColor: ThemeCleanPremium.primary,
                            child: Text(
                              label.isNotEmpty
                                  ? label[0].toUpperCase()
                                  : '?',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: canDm
                              ? Text(
                                  'Mensagem direta',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                          trailing: canDm
                              ? IconButton(
                                  tooltip: 'Mensagem direta',
                                  icon: Icon(
                                    Icons.chat_rounded,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                  onPressed: () => _openDm(ctx, auth, label),
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: ThemeCleanPremium.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openGroupChat(ctx),
                    icon: const Icon(Icons.forum_rounded),
                    label: const Text(
                      'Abrir chat do grupo',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                          'Chat da igreja',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Abas: conversas · todos os membros · grupos por departamento',
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

/// Lista de membros para nova DM — filtro por nome ou UID.
class _NovaConversaDiretaSheet extends StatefulWidget {
  final ScrollController scrollController;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String tid;
  final String myUid;
  final ChurchChatMemberPrefsModel prefs;

  const _NovaConversaDiretaSheet({
    required this.scrollController,
    required this.docs,
    required this.tid,
    required this.myUid,
    required this.prefs,
  });

  @override
  State<_NovaConversaDiretaSheet> createState() =>
      _NovaConversaDiretaSheetState();
}

class _NovaConversaDiretaSheetState extends State<_NovaConversaDiretaSheet> {
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _eligible {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in widget.docs) {
      final d = doc.data();
      final auth = (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
      if (auth.isEmpty || auth == widget.myUid) continue;
      if (widget.prefs.isBlockedPeer(auth)) continue;
      out.add(doc);
    }
    return out;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered {
    final q = _filter.text.trim().toLowerCase();
    final base = _eligible;
    if (q.isEmpty) return base;
    return base.where((doc) {
      final d = doc.data();
      final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final auth =
          (d['authUid'] ?? d['firebaseUid'] ?? '').toString().toLowerCase();
      return nome.contains(q) || auth.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color:
                ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Icon(Icons.person_search_rounded,
                  color: ThemeCleanPremium.primary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nova conversa direta',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: TextField(
            controller: _filter,
            style: TextStyle(
              color: ThemeCleanPremium.onSurface,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Filtrar por nome…',
              hintStyle:
                  TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
              prefixIcon: Icon(Icons.filter_alt_rounded,
                  color: ThemeCleanPremium.primary),
              filled: true,
              fillColor: ThemeCleanPremium.cardBackground,
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
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _eligible.isEmpty
                          ? 'Nenhum membro disponível para conversa.'
                          : 'Nenhum resultado para «${_filter.text.trim()}».',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ThemeCleanPremium.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final doc = filtered[i];
                    final d = doc.data();
                    final auth =
                        (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
                    final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                        .toString()
                        .trim();
                    return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('igrejas')
                          .doc(widget.tid)
                          .collection('chat_presence')
                          .doc(auth)
                          .snapshots(),
                      builder: (context, presSnap) {
                        final on = ChurchChatService.isOnlineFromSnapshot(
                            presSnap.data);
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          elevation: 0,
                          color: ThemeCleanPremium.cardBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            side: BorderSide(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.08),
                            ),
                          ),
                          child: ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  backgroundColor: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                  foregroundColor: ThemeCleanPremium.primary,
                                  child: Text(
                                    nome.isNotEmpty
                                        ? nome[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: on
                                          ? ThemeCleanPremium.success
                                          : const Color(0xFF9CA3AF),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              nome.isEmpty ? auth : nome,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              on ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: on
                                    ? const Color(0xFF16A34A)
                                    : ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                            onTap: () => Navigator.pop(
                              context,
                              _PickResult(uid: auth, name: nome),
                            ),
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
}

class _DeptEntry {
  final String id;
  final String name;
  final Map<String, dynamic>? deptData;
  _DeptEntry({required this.id, required this.name, this.deptData});
}

class _PickResult {
  final String uid;
  final String name;
  _PickResult({required this.uid, required this.name});
}
