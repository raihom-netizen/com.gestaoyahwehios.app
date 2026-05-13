import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_notification_settings_page.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_chat_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, imageUrlFromMap;
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

enum _HubConversasFilter { all, unread, favorites }

Timestamp? _chatHubThreadMyLastSeen(Map<String, dynamic> data, String myUid) {
  final seenMap = data['lastSeenAtByUid'];
  if (seenMap is! Map) return null;
  final t = seenMap[myUid];
  if (t is Timestamp) return t;
  return null;
}

bool _chatHubThreadIsUnreadForUser(Map<String, dynamic> data, String myUid) {
  final lastMsg = data['lastMessageAt'];
  if (lastMsg is! Timestamp) return false;
  final mySeen = _chatHubThreadMyLastSeen(data, myUid);
  if (mySeen == null) return true;
  return lastMsg.toDate().isAfter(mySeen.toDate());
}

int _gruposGridCrossAxisCount(double width) {
  if (width >= 1200) return 4;
  if (width >= 900) return 3;
  if (width >= 520) return 2;
  return 2;
}

String _chatHubFmtThreadTime(dynamic ts) {
  if (ts is! Timestamp) return '';
  final d = ts.toDate();
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '${d.day}/${d.month}';
}

/// Lista estilo WhatsApp — DM + grupos por departamento (só vínculos do membro).
/// DM na aba «Conversas»: dados do documento em `chat_threads` (sem segundo stream por linha),
/// foto de perfil a partir de `membros`, primeiro nome + prévia; presença só em `chat_presence`.
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
    with TickerProviderStateMixin {
  String? _resolvedTenantId;
  List<_DeptEntry> _departments = [];
  Timer? _presenceTimer;
  /// Stream único de `chat_threads` (reconexão automática em [ChurchChatService]).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _chatThreadsStream;
  /// Evita lista de conversas «a piscar»: mantém o último snapshot válido se o stream falhar de momento.
  QuerySnapshot<Map<String, dynamic>>? _lastGoodChatThreadsSnap;
  bool _chatPushEnabled = true;
  /// Grupo com mensagem mais recente do que a última leitura neste aparelho.
  bool _unreadGroupMessages = false;
  late AnimationController _gruposPulseCtrl;
  _HubConversasFilter _conversasFilter = _HubConversasFilter.all;
  final _searchCtrl = TextEditingController();
  final _membersFilterCtrl = TextEditingController();
  final _deptFilterCtrl = TextEditingController();
  late TabController _hubTabController;

  @override
  void initState() {
    super.initState();
    _hubTabController = TabController(length: 3, vsync: this);
    _gruposPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _hubTabController.addListener(_syncGruposPulse);
    _membersFilterCtrl.addListener(() => setState(() {}));
    _deptFilterCtrl.addListener(() => setState(() {}));
    ChurchPanelNavigationBridge.instance
        .registerChatOpenListener(_onChatPendingFromBridge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_tryConsumePendingChatThread());
    });
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ChurchChatHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _lastGoodChatThreadsSnap = null;
      _chatThreadsStream = null;
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    ChurchPanelNavigationBridge.instance
        .unregisterChatOpenListener(_onChatPendingFromBridge);
    _hubTabController.removeListener(_syncGruposPulse);
    _hubTabController.dispose();
    _gruposPulseCtrl.dispose();
    _searchCtrl.dispose();
    _membersFilterCtrl.dispose();
    _deptFilterCtrl.dispose();
    _presenceTimer?.cancel();
    super.dispose();
  }

  void _syncGruposPulse() {
    if (!mounted) return;
    final blink = _unreadGroupMessages && _hubTabController.index != 2;
    if (blink) {
      if (!_gruposPulseCtrl.isAnimating) {
        _gruposPulseCtrl.repeat(reverse: true);
      }
    } else {
      _gruposPulseCtrl.stop();
      _gruposPulseCtrl.value = 1.0;
    }
  }

  static bool _docIsDepartmentThread(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final t = (doc.data()['type'] ?? '').toString();
    if (t == 'department') return true;
    return doc.id.startsWith('dept_');
  }

  static bool _computeUnreadGroupThreads(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) {
    for (final d in docs) {
      if (!_docIsDepartmentThread(d)) continue;
      if (_chatHubThreadIsUnreadForUser(d.data(), uid)) return true;
    }
    return false;
  }

  void _onChatPendingFromBridge() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_tryConsumePendingChatThread());
    });
  }

  Future<void> _tryConsumePendingChatThread() async {
    if (!mounted || !widget.embeddedInShell) return;
    final tid = _resolvedTenantId;
    if (tid == null) return;
    final peek =
        ChurchPanelNavigationBridge.instance.peekPendingChatThreadOpen();
    if (peek == null) return;
    if (peek.tenantId != null &&
        peek.tenantId!.isNotEmpty &&
        peek.tenantId != tid) {
      return;
    }
    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await ChurchChatService.threadRef(tid, peek.threadId).get();
    } catch (_) {
      snap = null;
    }
    if (!mounted || snap == null || !snap.exists) return;
    final pending =
        ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
    if (pending == null || pending.threadId != peek.threadId) return;
    final data = snap.data() ?? {};
    final type = (data['type'] ?? '').toString();
    final nav = Navigator.of(context);
    if (type == 'department') {
      final deptId = (data['departmentId'] ?? '').toString();
      final rawTitle = (data['title'] ?? 'Grupo').toString().trim();
      final title = rawTitle.isEmpty ? 'Grupo' : rawTitle;
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ChurchChatThreadPage(
            tenantId: tid,
            threadId: pending.threadId,
            title: title,
            isDepartment: true,
            departmentId: deptId.isEmpty ? null : deptId,
            memberRole: widget.role,
            memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
          ),
        ),
      );
      return;
    }
    if (type == 'dm') {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final peerList = (data['participantUids'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          <String>[];
      String? peer;
      for (final p in peerList) {
        if (p != uid) {
          peer = p;
          break;
        }
      }
      if (peer == null || peer.isEmpty) return;
      final titles = data['titlesByUid'];
      var dmTitle = peer;
      if (titles is Map && titles[peer] != null) {
        dmTitle = titles[peer].toString();
      }
      await nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ChurchChatThreadPage(
            tenantId: tid,
            threadId: pending.threadId,
            title: dmTitle,
            isDepartment: false,
            peerUid: peer,
            memberRole: widget.role,
            memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
          ),
        ),
      );
    }
  }

  Future<void> _bootstrap() async {
    final tid = await TenantResolverService
        .resolveEffectiveTenantIdPreferringUserBinding(
      widget.tenantId,
      userUid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (!mounted) return;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    setState(() {
      if (_resolvedTenantId != tid) {
        _lastGoodChatThreadsSnap = null;
      }
      _resolvedTenantId = tid;
      final u = FirebaseAuth.instance.currentUser?.uid;
      _chatThreadsStream = (u != null && u.isNotEmpty)
          ? ChurchChatService.chatThreadsSnapshotsForUser(tid, u)
          : null;
    });
    unawaited(_loadChatNotifPrefs());
    await _syncMemberDepartments(tid);
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 25), (_) {
      ChurchChatService.touchPresence(tid);
    });
    ChurchChatService.touchPresence(tid);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_tryConsumePendingChatThread());
      });
    }
  }

  Future<void> _loadChatNotifPrefs() async {
    final v = await ChurchChatNotificationPrefs.isChatPushEnabled();
    if (!mounted) return;
    setState(() => _chatPushEnabled = v);
  }

  Future<void> _openChatAlertModeSheet() async {
    final tid = _resolvedTenantId;
    if (tid == null) return;
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
          child: SingleChildScrollView(
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
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: const Text(
                    'Personalização Super Premium',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'DM, grupos e alerta por conversa (com pesquisa).',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ChurchChatNotificationSettingsPage(
                          tenantId: tid,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _threadForegroundNotifSubtitle(
    ChurchChatMemberPrefsModel prefs,
    String threadId,
  ) {
    final ov = prefs.threadNotifOverride(threadId);
    if (ov == null) {
      return 'Segue DM/grupo ou o modo global da conta.';
    }
    switch (ov) {
      case ChurchChatNotificationPrefs.alertModeVibrate:
        return 'Override: só vibrar';
      case ChurchChatNotificationPrefs.alertModeSilent:
        return 'Override: silencioso';
      default:
        return 'Override: som + vibrar';
    }
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

  /// Ordenação «última atividade primeiro» (alinhado ao comportamento dos grupos na lista).
  static int _threadLastActivityMs(Map<String, dynamic> data) {
    for (final key in ['lastMessageAt', 'updatedAt', 'createdAt']) {
      final v = data[key];
      if (v is Timestamp) return v.millisecondsSinceEpoch;
    }
    return 0;
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

  /// Primeiro nome na lista (estilo WhatsApp).
  static String _firstNameForChatRow(String displayName) {
    final t = displayName.trim();
    if (t.isEmpty) return displayName;
    final parts = t.split(RegExp(r'\s+'));
    return parts.first;
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
                ListTile(
                  leading: Icon(
                    Icons.graphic_eq_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: const Text('Alerta desta conversa'),
                  subtitle: Text(
                    _threadForegroundNotifSubtitle(prefs, threadId),
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    await showChurchChatThreadForegroundNotifSheet(
                      context: context,
                      tenantId: tenantId,
                      threadId: threadId,
                      title: title,
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
                if (!isDepartment) ...[
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: const Text('Apagar conversa (só para mim)'),
                    subtitle: const Text(
                      'Some da lista de conversas. A outra pessoa mantém o histórico no aparelho dela.',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await ChurchChatMemberPrefs.setHiddenDmThread(
                        tenantId: tenantId,
                        threadId: threadId,
                        hide: true,
                      );
                      if (!context.mounted) return;
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Limite de conversas ocultas '
                              '(${ChurchChatMemberPrefs.maxHiddenDmThreads}).',
                            ),
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Conversa removida da sua lista.'),
                        ),
                      );
                    },
                  ),
                ],
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
            child: _PremiumHubTabBar(
              controller: _hubTabController,
              gruposOpacity: _gruposPulseCtrl,
            ),
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
    final threadStream = _chatThreadsStream;
    if (threadStream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .limit(600)
          .snapshots(),
      builder: (context, memSnap) {
        final photoByPeer = churchChatMemberPhotoUrlByAuthUid(memSnap.data);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ChurchChatMemberPrefs.watch(tid),
          builder: (context, prefSnap) {
            final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: threadStream,
              builder: (context, snap) {
                if (snap.hasData) {
                  _lastGoodChatThreadsSnap = snap.data;
                }
                final snapForList =
                    snap.hasData ? snap.data! : _lastGoodChatThreadsSnap;
                final streamError = snap.hasError ? snap.error : null;

                final dmDocs = snapForList?.docs ?? [];
                final unreadG = _computeUnreadGroupThreads(dmDocs, uid);
                if (unreadG != _unreadGroupMessages) {
                  Future.microtask(() {
                    if (mounted && unreadG != _unreadGroupMessages) {
                      setState(() => _unreadGroupMessages = unreadG);
                      _syncGruposPulse();
                    }
                  });
                }

                if (streamError != null && snapForList == null) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 48,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Não foi possível carregar a lista de conversas. '
                        'Verifique a ligação ou peça ao gestor para atualizar as regras do Firebase.\n'
                        '$streamError',
                        style: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    snapForList == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final threads = <Widget>[];
                final q = _searchCtrl.text.trim();
                final ql = q.toLowerCase();

                if (streamError != null && snapForList != null) {
                  threads.add(
                    Material(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Não foi possível sincronizar agora — está a ver a última lista '
                                'recebida. A ligação restabelece-se sozinha; puxe para atualizar ou '
                                'abra o chat de novo. As conversas só somem se as apagar ou, nos grupos, '
                                'se um gestor as remover.',
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.grey.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  threads.add(const SizedBox(height: 10));
                }

                threads.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                    child: Text(
                      'Só conversas diretas — grupos na aba Grupos.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
                threads.add(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: SegmentedButton<_HubConversasFilter>(
                      segments: const [
                        ButtonSegment(
                          value: _HubConversasFilter.all,
                          label: Text('Todas'),
                          icon: Icon(Icons.chat_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: _HubConversasFilter.unread,
                          label: Text('Não lidas'),
                          icon: Icon(Icons.mark_chat_unread_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: _HubConversasFilter.favorites,
                          label: Text('Favoritas'),
                          icon: Icon(Icons.star_rounded, size: 18),
                        ),
                      ],
                      selected: {_conversasFilter},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(() => _conversasFilter = s.first);
                      },
                    ),
                  ),
                );

                final dmFiltered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in dmDocs) {
                  if (_docIsDepartmentThread(doc)) {
                    continue;
                  }
                  final data = doc.data();
                  if (prefs.isHiddenDmThread(doc.id)) continue;
                  final peers = (data['participantUids'] as List?)
                          ?.map((e) => e.toString())
                          .where((e) => e.isNotEmpty)
                          .toList() ??
                      [];
                  final others = peers.where((p) => p != uid).toList();
                  if (others.isEmpty) continue;
                  final peer = others.first;
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
                dmFiltered.sort((a, b) {
                  final ta = _threadLastActivityMs(a.data());
                  final tb = _threadLastActivityMs(b.data());
                  final c = tb.compareTo(ta);
                  if (c != 0) return c;
                  return _dmDisplayTitle(a, uid)
                      .toLowerCase()
                      .compareTo(_dmDisplayTitle(b, uid).toLowerCase());
                });

                Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> sel =
                    dmFiltered;
                switch (_conversasFilter) {
                  case _HubConversasFilter.favorites:
                    sel = dmFiltered.where((d) => prefs.isFavorite(d.id));
                    break;
                  case _HubConversasFilter.unread:
                    sel = dmFiltered.where(
                      (d) => _chatHubThreadIsUnreadForUser(d.data(), uid),
                    );
                    break;
                  case _HubConversasFilter.all:
                    break;
                }
                final displayed = sel.toList();

                if (displayed.isEmpty) {
                  threads.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 24),
                      child: Text(
                        q.isNotEmpty
                            ? 'Nenhuma conversa corresponde à pesquisa.'
                            : _conversasFilter == _HubConversasFilter.favorites
                                ? 'Sem favoritas. Toque numa conversa e use «Favoritar».'
                                : _conversasFilter == _HubConversasFilter.unread
                                    ? 'Sem mensagens não lidas nas conversas diretas.'
                                    : 'Sem conversas diretas ainda. Use o botão + ou a aba Membros.',
                        style: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                } else {
                  threads.add(_sectionHeader('Mensagens diretas'));
                  threads.add(_dmConversationListRows(
                    context,
                    tid,
                    uid,
                    displayed,
                    prefs,
                    photoByPeer,
                  ));
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  children: threads,
                );
              },
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

    final mqW = MediaQuery.sizeOf(context).width;
    final crossAxis = _gruposGridCrossAxisCount(mqW);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      ThemeCleanPremium.primaryLight.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      color: ThemeCleanPremium.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Vista em grelha · toque no cartão para abrir o grupo · contagem não lidas / total de mensagens',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverLayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.crossAxisExtent;
            final spacing = 12.0;
            final tileW = (w - spacing * (crossAxis - 1)) / crossAxis;
            final aspect = tileW < 200 ? 0.68 : 0.74;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxis,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: aspect,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final d = filtered[i];
                  final threadId = ChurchChatService.deptThreadId(d.id);
                  return _DeptGroupPremiumGridCard(
                    tenantId: tid,
                    myUid: uid,
                    entry: d,
                    threadId: threadId,
                    onOpenChat: () {
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
                    onOpenMembers: () =>
                        _showDepartmentMembersSheet(context, tid, uid, d),
                  );
                },
                childCount: filtered.length,
              ),
            );
          },
        ),
      ],
      ),
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
      builder: (ctx) => ChurchDepartmentChatMembersSheet(
        navigatorContext: context,
        tenantId: tid,
        currentUid: uid,
        departmentId: dept.id,
        departmentName: dept.name,
        departmentDocData: dept.deptData,
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

  /// Lista estilo WhatsApp: foto do perfil, primeiro nome, pré-visualização estável
  /// (dados do documento em `chat_threads` — sem segundo listener no mesmo thread).
  Widget _dmConversationListRows(
    BuildContext context,
    String tid,
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
  ) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final doc in docs)
          _dmChatRow(context, tid, uid, doc, prefs, photoByPeerUid),
      ],
    );
  }

  Widget _dmChatRow(
    BuildContext context,
    String tid,
    String uid,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
  ) {
    final data = doc.data();
    final peers = (data['participantUids'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    final others = peers.where((p) => p != uid).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final peer = others.first;
    final fullTitle = _dmDisplayTitle(doc, uid);
    final rowTitle = _firstNameForChatRow(fullTitle);
    final preview =
        (data['lastMessagePreview'] ?? 'Toque para conversar').toString();
    final ts = data['lastMessageAt'];
    final photoUrl = photoByPeerUid[peer];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memCache = (52 * dpr).round().clamp(96, 240);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('chat_presence')
          .doc(peer)
          .snapshots(),
      builder: (context, pres) {
        final online = ChurchChatService.isOnlineFromSnapshot(pres.data);
        return _chatTile(
          title: rowTitle,
          subtitle: preview,
          subtitleMaxLines: 2,
          timeLabel: _fmtTime(ts),
          photo: SafeCircleAvatarImage(
            imageUrl: photoUrl,
            radius: 26,
            memCacheSize: memCache,
            fallbackIcon: Icons.person_rounded,
            fallbackColor: ThemeCleanPremium.primary,
            backgroundColor:
                ThemeCleanPremium.primary.withValues(alpha: 0.12),
          ),
          showPresence: true,
          online: online,
          isFavorite: prefs.isFavorite(doc.id),
          isMuted: prefs.isMutedThread(doc.id),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => ChurchChatThreadPage(
                  tenantId: tid,
                  threadId: doc.id,
                  title: fullTitle,
                  isDepartment: false,
                  peerUid: peer,
                  memberRole: widget.role,
                  memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
                ),
              ),
            );
          },
          onLongPress: () => _showThreadActionsSheet(
            context: context,
            tenantId: tid,
            threadId: doc.id,
            title: fullTitle,
            isDepartment: false,
            peerUid: peer,
            prefs: prefs,
          ),
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
    int subtitleMaxLines = 1,
    Widget? trailing,
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
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontSize: 13,
                            height: subtitleMaxLines > 1 ? 1.25 : null,
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
                      if (trailing != null) trailing,
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

  String _fmtTime(dynamic ts) => _chatHubFmtThreadTime(ts);

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
    final innerR = BorderRadius.circular(ThemeCleanPremium.radiusMd);
    final outerR = BorderRadius.circular(ThemeCleanPremium.radiusMd + 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.all(1.25),
        decoration: BoxDecoration(
          borderRadius: outerR,
          gradient: churchChatWhatsPremiumLinearGradient,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: innerR,
          child: ColoredBox(
            color: ThemeCleanPremium.cardBackground,
            child: TextField(
              controller: widget.controller,
              onChanged: (_) => widget.onChanged(),
              style: TextStyle(
                color: ThemeCleanPremium.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Pesquisar conversas',
                hintStyle:
                    TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF2563EB),
                ),
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpar',
                        icon: Icon(
                          Icons.clear_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
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
        ),
      ),
    );
  }
}

class _PremiumHubTabBar extends StatelessWidget {
  final TabController controller;
  final Animation<double> gruposOpacity;

  const _PremiumHubTabBar({
    required this.controller,
    required this.gruposOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, gruposOpacity]),
      builder: (context, _) {
        final gPulse = gruposOpacity.value.clamp(0.0, 1.0);
        return Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17.5),
            gradient: churchChatWhatsPremiumLinearGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: controller,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: churchChatWhatsPremiumLinearGradient,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.38),
                    blurRadius: 12,
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
              tabs: [
                const Tab(
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
                const Tab(
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
                  child: Opacity(
                    opacity: controller.index != 2
                        ? (0.58 + 0.42 * gPulse)
                        : 1.0,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.groups_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Grupos'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    final innerR = BorderRadius.circular(ThemeCleanPremium.radiusMd);
    final outerR = BorderRadius.circular(ThemeCleanPremium.radiusMd + 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        padding: const EdgeInsets.all(1.25),
        decoration: BoxDecoration(
          borderRadius: outerR,
          gradient: churchChatWhatsPremiumLinearGradient,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: innerR,
          child: ColoredBox(
            color: ThemeCleanPremium.cardBackground,
            child: TextField(
              controller: widget.controller,
              style: TextStyle(
                color: ThemeCleanPremium.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle:
                    TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
                prefixIcon:
                    Icon(widget.icon, color: const Color(0xFF2563EB)),
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpar',
                        icon: Icon(
                          Icons.clear_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredMemberDocs() {
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
    return out;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortMembersOnlineFirst(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
    Map<String, Timestamp> presenceByUid,
  ) {
    bool online(String uid) {
      final ts = presenceByUid[uid];
      if (ts == null) return false;
      return DateTime.now().difference(ts.toDate()).inSeconds < 45;
    }

    final copy =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(members);
    copy.sort((a, b) {
      final da = a.data();
      final db = b.data();
      final authA = (da['authUid'] ?? da['firebaseUid'] ?? '').toString();
      final authB = (db['authUid'] ?? db['firebaseUid'] ?? '').toString();
      final onA = online(authA);
      final onB = online(authB);
      if (onA != onB) {
        if (onA) return -1;
        if (onB) return 1;
      }
      final na = (da['NOME_COMPLETO'] ?? da['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (db['NOME_COMPLETO'] ?? db['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    });
    return copy;
  }

  String? _cpfDigitsFromMembro(Map<String, dynamic> d) {
    final raw =
        (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    return raw.length == 11 ? raw : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('chat_presence')
          .snapshots(),
      builder: (context, presSnap) {
        final presenceByUid = <String, Timestamp>{};
        for (final p in presSnap.data?.docs ?? []) {
          final ts = p.data()['lastSeenAt'];
          if (ts is Timestamp) presenceByUid[p.id] = ts;
        }
        final rows =
            _sortMembersOnlineFirst(_filteredMemberDocs(), presenceByUid);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cachePx = (40 * dpr).round().clamp(96, 240);

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
                    final ts = presenceByUid[auth];
                    final on = ts != null &&
                        DateTime.now().difference(ts.toDate()).inSeconds < 45;
                    final photoUrl = imageUrlFromMap(d);
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
                                      StableMemberAvatar(
                                        imageUrl:
                                            photoUrl.isEmpty ? null : photoUrl,
                                        tenantId: widget.tenantId,
                                        memberId: doc.id,
                                        cpfDigits: _cpfDigitsFromMembro(d),
                                        authUid:
                                            auth.isNotEmpty ? auth : null,
                                        memberData: d,
                                        size: 40,
                                        memCacheWidth: cachePx,
                                        memCacheHeight: cachePx,
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
                ),
        );
      },
    );
  }
}

class _DeptGroupPremiumGridCard extends StatelessWidget {
  final String tenantId;
  final String myUid;
  final String threadId;
  final _DeptEntry entry;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMembers;

  const _DeptGroupPremiumGridCard({
    required this.tenantId,
    required this.myUid,
    required this.threadId,
    required this.entry,
    required this.onOpenChat,
    required this.onOpenMembers,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchChatService.threadRef(tenantId, threadId).snapshots(),
      builder: (context, ts) {
        final data = ts.data?.data();
        final unreadFlag = ts.hasData && data != null
            ? _chatHubThreadIsUnreadForUser(data, myUid)
            : false;
        final preview = (data?['lastMessagePreview'] ?? 'Toque para abrir o grupo')
            .toString()
            .trim();
        final safePreview =
            preview.isEmpty ? 'Toque para abrir o grupo' : preview;
        final lastMsgAt = data?['lastMessageAt'];
        final timeLabel = _chatHubFmtThreadTime(lastMsgAt);
        final mySeen =
            data != null ? _chatHubThreadMyLastSeen(data, myUid) : null;
        final lmKey =
            lastMsgAt is Timestamp ? lastMsgAt.millisecondsSinceEpoch : 0;
        final seenKey = mySeen?.millisecondsSinceEpoch ?? -1;
        final participants = data?['participantUids'];
        final nChatMembers = participants is List ? participants.length : 0;

        return Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ThemeCleanPremium.primary.withValues(alpha: 0.14),
                  ThemeCleanPremium.primaryLight.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(
                  alpha: unreadFlag ? 0.35 : 0.2,
                ),
                width: unreadFlag ? 1.2 : 1,
              ),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    onTap: onOpenChat,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ChurchChatDepartmentAvatar(
                                    deptData: entry.deptData,
                                    fallbackName: entry.name,
                                    radius: 24,
                                  ),
                                  if (unreadFlag)
                                    Positioned(
                                      right: -3,
                                      top: -3,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 10),
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
                                        fontSize: 14.5,
                                        height: 1.2,
                                        color: ThemeCleanPremium.onSurface,
                                        letterSpacing: -0.25,
                                      ),
                                    ),
                                    if (timeLabel.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Última atividade · $timeLabel',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeCleanPremium
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (nChatMembers > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '$nChatMembers no chat',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeCleanPremium.primary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            safePreview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          FutureBuilder<({int unread, int total})>(
                            key: ValueKey<String>(
                              '$threadId|$lmKey|$seenKey',
                            ),
                            future: ChurchChatService
                                .threadMessageUnreadAndTotalCounts(
                              tenantId: tenantId,
                              threadId: threadId,
                              myLastSeenInThread: mySeen,
                            ),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                      ConnectionState.waiting &&
                                  !snap.hasData) {
                                return Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: ThemeCleanPremium.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'A contar mensagens…',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: ThemeCleanPremium
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              final u = snap.data?.unread ?? 0;
                              final t = snap.data?.total ?? 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: unreadFlag
                                      ? const Color(0xFFFFF7ED)
                                      : Colors.white.withValues(alpha: 0.55),
                                  border: Border.all(
                                    color: unreadFlag
                                        ? const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.55)
                                        : ThemeCleanPremium.onSurfaceVariant
                                            .withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.sms_outlined,
                                      size: 17,
                                      color: unreadFlag
                                          ? const Color(0xFFB45309)
                                          : ThemeCleanPremium.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$u / $t',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        letterSpacing: -0.2,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'não lidas / total',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: ThemeCleanPremium
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onOpenMembers,
                    icon: Icon(
                      Icons.groups_rounded,
                      size: 20,
                      color: ThemeCleanPremium.primary,
                    ),
                    label: Text(
                      'Ver membros',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
        gradient: churchChatWhatsPremiumLinearGradient,
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.42),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
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
                          'Super Premium · conversas, membros e grupos',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Estilo WhatsApp — mensagens, fotos e vídeos no thread',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11.5,
                            height: 1.3,
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
