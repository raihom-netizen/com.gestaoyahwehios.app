import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_notification_settings_page.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_chat_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, imageUrlFromMap;
import 'package:gestao_yahweh/ui/widgets/church_chat_peer_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_profile_photo_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_list_preview.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

enum _HubConversasFilter { all, unread, favorites, archived }

String? _chatHubActiveTypingPreview(Map<String, dynamic> data, String myUid) {
  final typingUid = (data['typingUid'] ?? '').toString();
  if (typingUid.isEmpty || typingUid == myUid) return null;
  final ts = data['typingUpdatedAt'];
  if (ts is! Timestamp) return null;
  if (DateTime.now().difference(ts.toDate()).inSeconds > 8) return null;
  final p = (data['typingPreview'] ?? '').toString().trim();
  return p.isNotEmpty ? p : 'A digitar…';
}

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
  /// Permissões granulares do painel (ex.: módulo `departamentos`), alinhadas a [AppPermissions.canEditDepartments].
  final List<String>? permissions;

  const ChurchChatHubPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    this.embeddedInShell = false,
    this.permissions,
  });

  @override
  State<ChurchChatHubPage> createState() => _ChurchChatHubPageState();
}

class _ChurchChatHubPageState extends State<ChurchChatHubPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _resolvedTenantId;
  List<_DeptEntry> _departments = [];
  /// Stream único de `chat_threads` (reconexão automática em [ChurchChatService]).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _chatThreadsStream;
  /// Evita lista de conversas «a piscar»: mantém o último snapshot válido se o stream falhar de momento.
  QuerySnapshot<Map<String, dynamic>>? _lastGoodChatThreadsSnap;
  bool _chatPushEnabled = true;
  _HubConversasFilter _conversasFilter = _HubConversasFilter.all;
  final _searchCtrl = TextEditingController();
  final _membersFilterCtrl = TextEditingController();
  final _deptFilterCtrl = TextEditingController();
  late TabController _hubTabController;
  Timer? _gruposResyncDebounce;
  Timer? _conversasResyncDebounce;
  /// Avatares no hub — `chat_peer_profiles` (sem stream de 600 `membros`).
  Map<String, ChurchChatMemberRef> _peerMemberByUid = {};
  Map<String, bool> _peerOnlineByUid = {};
  Timer? _presencePollTimer;
  String? _presencePollKey;
  late final VoidCallback _photoSyncListener;
  bool _dmSelectMode = false;
  final Set<String> _selectedDmThreadIds = <String>{};

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('chat');
    _photoSyncListener = _onMemberProfilePhotoSynced;
    MemberProfilePhotoSyncNotifier.instance.addListener(_photoSyncListener);
    WidgetsBinding.instance.addObserver(this);
    _hubTabController = TabController(length: 3, vsync: this);
    _hubTabController.addListener(_hubTabListener);
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
    MemberProfilePhotoSyncNotifier.instance.removeListener(_photoSyncListener);
    WidgetsBinding.instance.removeObserver(this);
    _gruposResyncDebounce?.cancel();
    _conversasResyncDebounce?.cancel();
    _presencePollTimer?.cancel();
    ChurchPanelNavigationBridge.instance
        .unregisterChatOpenListener(_onChatPendingFromBridge);
    _hubTabController.removeListener(_hubTabListener);
    _hubTabController.dispose();
    _searchCtrl.dispose();
    _membersFilterCtrl.dispose();
    _deptFilterCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final t = _resolvedTenantId;
      if (t != null) unawaited(_syncMemberDepartments(t));
      unawaited(_pullRefreshConversas());
    }
  }

  void _hubTabListener() {
    if (_hubTabController.indexIsChanging) return;
    if (_hubTabController.index != 0 && _dmSelectMode) {
      setState(_clearDmSelectUi);
    }
    if (_hubTabController.index == 0) {
      _requestConversasResync();
    } else if (_hubTabController.index == 1) {
      _requestGruposResync();
    }
  }

  void _requestGruposResync() {
    _gruposResyncDebounce?.cancel();
    _gruposResyncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final t = _resolvedTenantId;
      if (t != null) unawaited(_syncMemberDepartments(t));
    });
  }

  /// Reanexa o stream de `chat_threads` (token + nova subscrição), p.ex. após
  /// voltar do fundo ou pull-to-refresh — sem depender de botão na UI.
  Future<void> _pullRefreshConversas() async {
    final tid = _resolvedTenantId;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (tid == null || uid.isEmpty) return;
    if (_chatThreadsStream == null) {
      await _bootstrap();
      return;
    }
    await _repairChatThreadsIndex(tid);
  }

  void _requestConversasResync() {
    _conversasResyncDebounce?.cancel();
    _conversasResyncDebounce = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      unawaited(_pullRefreshConversas());
    });
  }

  static bool _docIsDepartmentThread(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final t = (doc.data()['type'] ?? '').toString();
    if (t == 'department') return true;
    return doc.id.startsWith('dept_');
  }

  static Set<String> _peerUidsFromDmThreads(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String myUid,
  ) {
    final out = <String>{};
    for (final d in docs) {
      if (_docIsDepartmentThread(d)) continue;
      final peers = (d.data()['participantUids'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty) ??
          [];
      for (final p in peers) {
        if (p != myUid) out.add(p);
      }
      final legacyPeer = ChurchChatService.otherUidInDmThread(d.id, myUid);
      if (legacyPeer != null && legacyPeer.isNotEmpty) out.add(legacyPeer);
    }
    return out;
  }

  static Set<String> _lastSenderUidsFromThreads(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String myUid,
  ) {
    final out = <String>{};
    for (final d in docs) {
      final sender = (d.data()['lastSenderUid'] ?? '').toString().trim();
      if (sender.isNotEmpty && sender != myUid) out.add(sender);
    }
    return out;
  }

  void _onMemberProfilePhotoSynced() {
    final tid = _resolvedTenantId;
    final uid =
        MemberProfilePhotoSyncNotifier.instance.lastAuthUid?.trim() ?? '';
    if (tid == null || uid.isEmpty) return;
    unawaited(_refreshPeerProfilesForAuthUids(tid, {uid}));
  }

  Future<void> _refreshPeerProfilesForAuthUids(
    String tenantId,
    Set<String> authUids,
  ) async {
    if (authUids.isEmpty) return;
    final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
      tenantId: tenantId,
      authUids: authUids,
      refetchAuthUids: authUids,
    );
    if (!mounted || _resolvedTenantId != tenantId) return;
    if (loaded.isEmpty) return;
    setState(() => _peerMemberByUid = {..._peerMemberByUid, ...loaded});
  }

  void _schedulePeerProfilesLoad(String tenantId, Set<String> peerUids) {
    if (peerUids.isEmpty) return;
    final missing =
        peerUids.where((u) => !_peerMemberByUid.containsKey(u)).toSet();
    if (missing.isEmpty) return;
    unawaited(() async {
      final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
        tenantId: tenantId,
        authUids: missing,
      );
      if (!mounted || _resolvedTenantId != tenantId) return;
      if (loaded.isEmpty) return;
      setState(() => _peerMemberByUid = {..._peerMemberByUid, ...loaded});
    }());
  }

  void _schedulePresencePolling(String tenantId, Set<String> peerUids) {
    final key = peerUids.toList()..sort();
    final keyStr = '$tenantId|${key.join(",")}';
    if (_presencePollKey == keyStr && _presencePollTimer != null) return;
    _presencePollKey = keyStr;
    _presencePollTimer?.cancel();
    if (peerUids.isEmpty) {
      _peerOnlineByUid = {};
      return;
    }
    Future<void> poll() async {
      final online = await ChurchChatService.fetchPresenceOnlineMap(
        tenantId: tenantId,
        authUids: peerUids,
      );
      if (!mounted || _resolvedTenantId != tenantId) return;
      setState(() => _peerOnlineByUid = online);
    }

    unawaited(poll());
    _presencePollTimer = Timer.periodic(
      const Duration(seconds: 22),
      (_) => unawaited(poll()),
    );
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

  bool _syncingChatThreads = false;

  /// Repara índice DM (cliente + Cloud Function) antes de mostrar lista vazia.
  Future<void> _repairChatThreadsIndex(String tenantId) async {
    if (_syncingChatThreads) return;
    _syncingChatThreads = true;
    try {
      await ChurchChatService.syncDmThreadsIndex(tenantId);
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        final fallback = await ChurchChatService.loadDmThreadsSnapshotFallback(
          tenantId: tenantId,
          uid: uid,
        );
        if (mounted && fallback.docs.isNotEmpty) {
          _lastGoodChatThreadsSnap = fallback;
        }
      }
      if (mounted) {
        setState(() {
          if (uid.isNotEmpty) {
            _chatThreadsStream =
                ChurchChatService.chatThreadsSnapshotsForUser(tenantId, uid);
          }
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('syncDmThreadsIndex: $e\n$st');
      }
    } finally {
      _syncingChatThreads = false;
    }
  }

  Future<void> _bootstrap() async {
    final tid = await TenantResolverService
        .resolveEffectiveTenantIdPreferringUserBinding(
      widget.tenantId,
      userUid: FirebaseAuth.instance.currentUser?.uid,
    );
    if (!mounted) return;
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
    await _repairChatThreadsIndex(tid);
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
    var peer = peers.firstWhere((p) => p != myUid, orElse: () => '');
    if (peer.isEmpty) {
      peer = ChurchChatService.otherUidInDmThread(doc.id, myUid) ?? '';
    }
    final titles = data['titlesByUid'];
    var title = peer;
    if (titles is Map && titles[peer] != null) {
      title = titles[peer].toString();
    }
    final t = title.trim();
    return t.isNotEmpty ? t : peer;
  }

  String _deptDisplayTitle(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final t = (data['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;
    var deptId = (data['departmentId'] ?? '').toString().trim();
    if (deptId.isEmpty && doc.id.startsWith('dept_')) {
      deptId = doc.id.substring(5);
    }
    for (final d in _departments) {
      if (d.id == deptId) return d.name;
    }
    return 'Grupo';
  }

  String? _departmentIdFromThreadDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    var deptId = (doc.data()['departmentId'] ?? '').toString().trim();
    if (deptId.isEmpty && doc.id.startsWith('dept_')) {
      deptId = doc.id.substring(5);
    }
    return deptId.isEmpty ? null : deptId;
  }

  String _threadListSortTitle(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    if (_docIsDepartmentThread(doc)) {
      return _deptDisplayTitle(doc);
    }
    return _dmDisplayTitle(doc, myUid);
  }

  _DeptEntry? _deptEntryById(String? departmentId) {
    if (departmentId == null || departmentId.isEmpty) return null;
    for (final d in _departments) {
      if (d.id == departmentId) return d;
    }
    return null;
  }

  String _memberDisplayName(ChurchChatMemberRef ref) {
    final data = ref.data;
    final nome = (data['nome'] ?? data['name'] ?? '').toString().trim();
    if (nome.isNotEmpty) return nome;
    return ref.authUid;
  }

  /// Primeiro nome na lista (estilo WhatsApp).
  static String _firstNameForChatRow(String displayName) {
    final t = displayName.trim();
    if (t.isEmpty) return displayName;
    final parts = t.split(RegExp(r'\s+'));
    return parts.first;
  }

  void _clearDmSelectUi() {
    _dmSelectMode = false;
    _selectedDmThreadIds.clear();
  }

  void _toggleDmSelectMode() {
    setState(() {
      if (_dmSelectMode) {
        _clearDmSelectUi();
      } else {
        _dmSelectMode = true;
      }
    });
  }

  void _toggleDmThreadSelected(String threadId) {
    setState(() {
      if (_selectedDmThreadIds.contains(threadId)) {
        _selectedDmThreadIds.remove(threadId);
      } else {
        _selectedDmThreadIds.add(threadId);
      }
    });
  }

  void _selectAllDmThreads(Iterable<String> threadIds) {
    setState(() {
      _selectedDmThreadIds
        ..clear()
        ..addAll(threadIds);
    });
  }

  Future<bool> _confirmHideConversations(int count) async {
    final n = count.clamp(1, 999);
    final label = n == 1 ? 'esta conversa' : 'estas $n conversas';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'Excluir conversa?' : 'Excluir conversas?'),
        content: Text(
          'Remove $label da sua lista. As mensagens mantêm-se no histórico '
          'da outra pessoa — só desaparecem para si.',
        ),
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
            child: Text(n == 1 ? 'Excluir' : 'Excluir ($n)'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _hideDmThreadWithConfirm({
    required String tenantId,
    required String threadId,
  }) async {
    if (!await _confirmHideConversations(1)) return;
    final ok = await ChurchChatMemberPrefs.setHiddenDmThread(
      tenantId: tenantId,
      threadId: threadId,
      hide: true,
    );
    if (!mounted) return;
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
      const SnackBar(content: Text('Conversa removida da sua lista.')),
    );
  }

  Future<void> _commitBulkHideSelectedDmThreads(String tenantId) async {
    final ids = _selectedDmThreadIds.toList();
    if (ids.isEmpty) return;
    if (!await _confirmHideConversations(ids.length)) return;
    final result = await ChurchChatMemberPrefs.hideDmThreadsBatch(
      tenantId: tenantId,
      threadIds: ids,
    );
    if (!mounted) return;
    if (result.hidden <= 0 && result.hitLimit) {
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
    setState(_clearDmSelectUi);
    final msg = result.hitLimit
        ? '${result.hidden} conversa(s) removida(s). Limite de ocultas atingido.'
        : '${result.hidden} conversa(s) removida(s) da sua lista.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Widget _buildDmBulkSelectBar(
    String tenantId,
    List<String> displayedThreadIds,
  ) {
    final n = _selectedDmThreadIds.length;
    final allSelected = displayedThreadIds.isNotEmpty &&
        displayedThreadIds.every(_selectedDmThreadIds.contains);
    return Material(
      elevation: 12,
      color: ThemeCleanPremium.cardBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancelar seleção',
                onPressed: () => setState(_clearDmSelectUi),
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      n == 0
                          ? 'Toque nas conversas para selecionar'
                          : '$n selecionada${n == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Conversas diretas',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (displayedThreadIds.isNotEmpty)
                TextButton(
                  onPressed: () {
                    if (allSelected) {
                      setState(_selectedDmThreadIds.clear);
                    } else {
                      _selectAllDmThreads(displayedThreadIds);
                    }
                  },
                  child: Text(
                    allSelected ? 'Limpar' : 'Todas',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () => unawaited(_commitBulkHideSelectedDmThreads(tenantId)),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text(
                  'Excluir',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDmSelectionToolbar(int visibleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dmSelectMode
                  ? 'Modo seleção — toque para marcar'
                  : 'Mantenha premido ou use o menu para opções',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: visibleCount == 0 ? null : _toggleDmSelectMode,
            icon: Icon(
              _dmSelectMode ? Icons.close_rounded : Icons.checklist_rounded,
              size: 18,
            ),
            label: Text(_dmSelectMode ? 'Cancelar' : 'Selecionar'),
            style: TextButton.styleFrom(
              foregroundColor: ThemeCleanPremium.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
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
                    prefs.isPinned(threadId)
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: ThemeCleanPremium.primary,
                  ),
                  title: Text(
                    prefs.isPinned(threadId)
                        ? 'Desafixar conversa'
                        : 'Fixar conversa',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ChurchChatMemberPrefs.setPinnedThread(
                      tenantId: tenantId,
                      threadId: threadId,
                      value: !prefs.isPinned(threadId),
                    );
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Máximo de ${ChurchChatMemberPrefs.maxPinnedThreads} conversas fixadas.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    prefs.isArchived(threadId)
                        ? Icons.unarchive_rounded
                        : Icons.inventory_2_outlined,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                  title: Text(
                    prefs.isArchived(threadId)
                        ? 'Desarquivar conversa'
                        : 'Arquivar conversa',
                  ),
                  subtitle: const Text(
                    'Some da lista principal; mensagens mantêm-se no histórico.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await ChurchChatMemberPrefs.setArchivedThread(
                      tenantId: tenantId,
                      threadId: threadId,
                      value: !prefs.isArchived(threadId),
                    );
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Limite de conversas arquivadas '
                            '(${ChurchChatMemberPrefs.maxArchivedThreads}).',
                          ),
                        ),
                      );
                    }
                  },
                ),
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
                      await _hideDmThreadWithConfirm(
                        tenantId: tenantId,
                        threadId: threadId,
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
      return ColoredBox(
        color: Colors.white,
        child: YahwehSkeletonLoading.chatThreads(),
      );
    }

    return ColoredBox(
      color: Colors.white,
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
            onProfilePhotoTap: () async {
              final uidMe = uid;
              await showChurchChatProfilePhotoSheet(
                context,
                tenantId: tid,
                cpfDigits: widget.cpf,
              );
              if (!mounted || uidMe.isEmpty) return;
              unawaited(_refreshPeerProfilesForAuthUids(tid, {uidMe}));
            },
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
                  controller: _deptFilterCtrl,
                  hintText: 'Pesquisar grupos…',
                  icon: Icons.groups_rounded,
                );
              }
              return _HubScopedSearchBar(
                controller: _membersFilterCtrl,
                hintText: 'Pesquisar membros…',
                icon: Icons.person_search_rounded,
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _hubTabController,
              children: [
                _KeepAliveHubTab(
                  child: _buildConversasTab(context, tid, uid),
                ),
                _KeepAliveHubTab(
                  child: _buildGruposTab(context, tid, uid),
                ),
                _KeepAliveHubTab(
                  child: _buildContatosTab(context, tid, uid),
                ),
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
      return RefreshIndicator(
        onRefresh: _pullRefreshConversas,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: YahwehSkeletonLoading.chatThreads(),
            ),
          ],
        ),
      );
    }
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
            final peerIds = {
              ..._peerUidsFromDmThreads(dmDocs, uid),
              ..._lastSenderUidsFromThreads(dmDocs, uid),
            };
            _schedulePeerProfilesLoad(tid, peerIds);
            _schedulePresencePolling(tid, peerIds);
            final memberByPeer = _peerMemberByUid;
            final photoByPeer = <String, String>{
              for (final e in memberByPeer.entries)
                if (e.value.photoUrl != null && e.value.photoUrl!.isNotEmpty)
                  e.key: e.value.photoUrl!,
            };
                if (streamError != null && snapForList == null) {
                  return RefreshIndicator(
                    onRefresh: _pullRefreshConversas,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
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
                  ),
                );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    snapForList == null) {
                  return RefreshIndicator(
                    onRefresh: _pullRefreshConversas,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: YahwehSkeletonLoading.chatThreads(),
                        ),
                      ],
                    ),
                  );
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
                        ButtonSegment(
                          value: _HubConversasFilter.archived,
                          label: Text('Arquivadas'),
                          icon: Icon(Icons.inventory_2_outlined, size: 18),
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

                final conversasFiltered =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in dmDocs) {
                  final isDept = _docIsDepartmentThread(doc);
                  final data = doc.data();
                  if (!isDept &&
                      !ChurchChatService.threadHasListableConversation(
                        data,
                        threadId: doc.id,
                      )) {
                    continue;
                  }
                  if (!isDept && prefs.isHiddenDmThread(doc.id)) continue;
                  final archived = prefs.isArchived(doc.id);
                  if (_conversasFilter == _HubConversasFilter.archived) {
                    if (!archived) continue;
                  } else if (archived) {
                    continue;
                  }
                  if (!ChurchChatService.userParticipatesInThread(
                    threadId: doc.id,
                    data: data,
                    uid: uid,
                  )) {
                    continue;
                  }
                  final peers = (data['participantUids'] as List?)
                          ?.map((e) => e.toString())
                          .where((e) => e.isNotEmpty)
                          .toList() ??
                      [];
                  late final String disp;
                  late final String preview;
                  if (isDept) {
                    disp = _deptDisplayTitle(doc);
                    preview = (data['lastMessagePreview'] ?? '').toString();
                  } else {
                    final others = peers.where((p) => p != uid).toList();
                    if (others.isEmpty) continue;
                    final peer = others.first;
                    if (prefs.isBlockedPeer(peer)) continue;
                    disp = _dmDisplayTitle(doc, uid);
                    preview = (data['lastMessagePreview'] ?? '').toString();
                  }
                  if (q.isNotEmpty) {
                    if (!disp.toLowerCase().contains(ql) &&
                        !preview.toLowerCase().contains(ql)) {
                      continue;
                    }
                  }
                  conversasFiltered.add(doc);
                }
                conversasFiltered.sort((a, b) {
                  final ap = prefs.isPinned(a.id);
                  final bp = prefs.isPinned(b.id);
                  if (ap != bp) return ap ? -1 : 1;
                  final ta = _threadLastActivityMs(a.data());
                  final tb = _threadLastActivityMs(b.data());
                  final c = tb.compareTo(ta);
                  if (c != 0) return c;
                  return _threadListSortTitle(a, uid)
                      .toLowerCase()
                      .compareTo(_threadListSortTitle(b, uid).toLowerCase());
                });

                Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> sel =
                    conversasFiltered;
                switch (_conversasFilter) {
                  case _HubConversasFilter.favorites:
                    sel = conversasFiltered.where((d) => prefs.isFavorite(d.id));
                    break;
                  case _HubConversasFilter.unread:
                    sel = conversasFiltered.where(
                      (d) => _chatHubThreadIsUnreadForUser(d.data(), uid),
                    );
                    break;
                  case _HubConversasFilter.archived:
                    break;
                  case _HubConversasFilter.all:
                    break;
                }
                final displayed = sel.toList();
                final displayedDmThreadIds = displayed
                    .where((d) => !_docIsDepartmentThread(d))
                    .map((d) => d.id)
                    .toList();

                threads.add(_buildDmSelectionToolbar(displayed.length));

                if (displayed.isEmpty) {
                  threads.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 24),
                      child: Text(
                        q.isNotEmpty
                            ? 'Nenhuma conversa corresponde à pesquisa.'
                            : _conversasFilter == _HubConversasFilter.favorites
                                ? 'Sem favoritas. Toque numa conversa e use Favoritar.'
                                : _conversasFilter == _HubConversasFilter.archived
                                    ? 'Sem conversas arquivadas.'
                                    : _conversasFilter == _HubConversasFilter.unread
                                    ? 'Sem mensagens não lidas.'
                                    : _syncingChatThreads
                                        ? 'A sincronizar conversas…'
                                        : 'Sem conversas ainda. Use + para nova mensagem ou Contatos para abrir um grupo de departamento.',
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
                  threads.add(_sectionHeader('Conversas'));
                  threads.add(_unifiedConversationListRows(
                    context,
                    tid,
                    uid,
                    displayed,
                    prefs,
                    photoByPeer,
                    memberByPeer,
                  ));
                }

                final listView = RefreshIndicator(
                  onRefresh: _pullRefreshConversas,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                    children: threads,
                  ),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: listView),
                    if (_dmSelectMode)
                      _buildDmBulkSelectBar(tid, displayedDmThreadIds),
                  ],
                );
              },
            );
          },
        );
  }

  Widget _buildContatosTab(BuildContext context, String tid, String uid) {
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

  /// Sem preferência gravada ou com pesquisa ativa → A–Z; caso contrário aplica [orderIds].
  List<_DeptEntry> _orderedDepartmentGroupsForTab(
    List<_DeptEntry> filtered,
    List<String> orderIds, {
    required bool useSavedOrder,
  }) {
    final byId = {for (final e in filtered) e.id: e};
    if (!useSavedOrder || orderIds.isEmpty) {
      final list = byId.values.toList();
      list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return list;
    }
    final ordered = <_DeptEntry>[];
    for (final id in orderIds) {
      final e = byId.remove(id);
      if (e != null) ordered.add(e);
    }
    final rest = byId.values.toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return [...ordered, ...rest];
  }

  void _onDepartmentGroupReorder(
    String tid,
    List<_DeptEntry> orderedSnapshot,
    int oldIndex,
    int newIndex,
  ) {
    var ni = newIndex;
    if (ni > oldIndex) {
      ni -= 1;
    }
    final next = List<_DeptEntry>.from(orderedSnapshot);
    final item = next.removeAt(oldIndex);
    next.insert(ni, item);
    unawaited(
      ChurchChatMemberPrefs.setDepartmentGroupOrder(
        tenantId: tid,
        departmentIdsInOrder: next.map((e) => e.id).toList(),
      ),
    );
  }

  Widget _buildGruposTab(BuildContext context, String tid, String uid) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchChatMemberPrefs.watch(tid),
      builder: (context, prefSnap) {
        final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
        final ql = _deptFilterCtrl.text.trim().toLowerCase();
        final filtered = _departments.where((d) {
          if (ql.isEmpty) {
            return true;
          }
          return d.name.toLowerCase().contains(ql);
        }).toList();

        if (filtered.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => _syncMemberDepartments(tid),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                Padding(
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
              ],
            ),
          );
        }

        final useSavedOrder = ql.isEmpty;
        final ordered = _orderedDepartmentGroupsForTab(
          filtered,
          prefs.departmentGroupOrderIds,
          useSavedOrder: useSavedOrder,
        );
        final canReorder = useSavedOrder && ordered.length > 1;
        final hasCustomOrder = prefs.departmentGroupOrderIds.isNotEmpty;

        String helpPrimary;
        if (!useSavedOrder) {
          helpPrimary =
              'Pesquisa ativa — grupos em ordem alfabética. Limpe o campo para voltar à sua ordem.';
        } else if (ordered.length > 1) {
          helpPrimary =
              'Grupos em faixas. Arraste para definir a ordem neste aparelho. Toque na faixa para abrir o chat ou use Ver membros à direita.';
        } else {
          helpPrimary =
              'Grupos em faixas. Toque na linha para abrir o chat ou Ver membros à direita.';
        }

        Widget stripTile(_DeptEntry d, {int? reorderIndex}) {
          final threadId = ChurchChatService.deptThreadId(d.id);
          return _DeptGroupPremiumStripCard(
            tenantId: tid,
            myUid: uid,
            entry: d,
            threadId: threadId,
            reorderIndex: reorderIndex,
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
                    memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
                  ),
                ),
              );
            },
            onOpenMembers: () =>
                _showDepartmentMembersSheet(context, tid, uid, d),
          );
        }

        return RefreshIndicator(
          onRefresh: () => _syncMemberDepartments(tid),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          ThemeCleanPremium.primaryLight.withValues(alpha: 0.06),
                        ],
                      ),
                      border: Border.all(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.view_stream_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                helpPrimary,
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
                        if (useSavedOrder && hasCustomOrder) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                unawaited(
                                  ChurchChatMemberPrefs.clearDepartmentGroupOrder(
                                    tid,
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.sort_by_alpha_rounded,
                                size: 18,
                                color: ThemeCleanPremium.primary,
                              ),
                              label: Text(
                                'Ordem alfabética (A-Z)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (canReorder)
                SliverReorderableList(
                  itemCount: ordered.length,
                  onReorder: (oldIndex, newIndex) {
                    _onDepartmentGroupReorder(
                      tid,
                      ordered,
                      oldIndex,
                      newIndex,
                    );
                  },
                  itemBuilder: (ctx, index) {
                    final d = ordered[index];
                    return KeyedSubtree(
                      key: ValueKey<String>('deptgrp_${d.id}'),
                      child: stripTile(d, reorderIndex: index),
                    );
                  },
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      return stripTile(ordered[i], reorderIndex: null);
                    },
                    childCount: ordered.length,
                  ),
                ),
            ],
          ),
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
      builder: (ctx) => ChurchDepartmentChatMembersSheet(
        navigatorContext: context,
        tenantId: tid,
        currentUid: uid,
        departmentId: dept.id,
        departmentName: dept.name,
        departmentDocData: dept.deptData,
        role: widget.role,
        cpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
        permissions: widget.permissions,
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

  /// Lista unificada estilo WhatsApp — DM + grupos de departamento.
  Widget _unifiedConversationListRows(
    BuildContext context,
    String tid,
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < docs.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.shade200,
              indent: 72,
            ),
          if (_docIsDepartmentThread(docs[i]))
            _deptChatRow(
              context,
              tid,
              uid,
              docs[i],
              prefs,
              memberByPeerUid,
            )
          else
            _dmChatRow(
              context,
              tid,
              uid,
              docs[i],
              prefs,
              photoByPeerUid,
              memberByPeerUid,
              selectionMode: _dmSelectMode,
              selected: _selectedDmThreadIds.contains(docs[i].id),
              onToggleSelected: () => _toggleDmThreadSelected(docs[i].id),
            ),
        ],
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
    Map<String, ChurchChatMemberRef> memberByPeerUid, {
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onToggleSelected,
  }) {
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
    final rawPreview =
        (data['lastMessagePreview'] ?? 'Toque para conversar').toString();
    final typingPreview = _chatHubActiveTypingPreview(data, uid);
    final isTyping = typingPreview != null;
    final preview = churchChatHubRowSubtitle(
      rawPreview: rawPreview,
      isTyping: isTyping,
      typingPreview: typingPreview,
    );
    final ts = data['lastMessageAt'];
    final memberRef = memberByPeerUid[peer];
    final isUnread = _chatHubThreadIsUnreadForUser(data, uid);

    final online = _peerOnlineByUid[peer] ?? false;
    return _chatTile(
      title: rowTitle,
      subtitle: preview,
      subtitleIsTyping: isTyping,
      subtitleMaxLines: 2,
      timeLabel: _fmtTime(ts),
      photo: ChurchChatPeerAvatar(
        tenantId: tid,
        peerAuthUid: peer,
        memberRef: memberRef,
        radius: 24,
      ),
      showPresence: !selectionMode,
      online: online,
      isUnread: isUnread,
      isFavorite: prefs.isFavorite(doc.id),
      isPinned: prefs.isPinned(doc.id),
      isMuted: prefs.isMutedThread(doc.id),
      selectionMode: selectionMode,
      selected: selected,
      onTap: () {
        if (selectionMode) {
          onToggleSelected?.call();
          return;
        }
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
      onLongPress: selectionMode
          ? onToggleSelected
          : () => _showThreadActionsSheet(
              context: context,
              tenantId: tid,
              threadId: doc.id,
              title: fullTitle,
              isDepartment: false,
              peerUid: peer,
              prefs: prefs,
            ),
      onMoreTap: selectionMode
          ? null
          : () => _showThreadActionsSheet(
              context: context,
              tenantId: tid,
              threadId: doc.id,
              title: fullTitle,
              isDepartment: false,
              peerUid: peer,
              prefs: prefs,
            ),
    );
  }

  Widget _deptChatRow(
    BuildContext context,
    String tid,
    String uid,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    ChurchChatMemberPrefsModel prefs,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    final data = doc.data();
    final fullTitle = _deptDisplayTitle(doc);
    final deptId = _departmentIdFromThreadDoc(doc);
    final deptEntry = _deptEntryById(deptId);
    final rawPreview =
        (data['lastMessagePreview'] ?? 'Toque para conversar').toString();
    final typingPreview = _chatHubActiveTypingPreview(data, uid);
    final isTyping = typingPreview != null;
    var preview = churchChatHubRowSubtitle(
      rawPreview: rawPreview,
      isTyping: isTyping,
      typingPreview: typingPreview,
    );
    if (!isTyping) {
      final lastSender = (data['lastSenderUid'] ?? '').toString();
      final senderRef = memberByPeerUid[lastSender];
      final senderName = senderRef != null
          ? _firstNameForChatRow(_memberDisplayName(senderRef))
          : '';
      preview = churchChatHubGroupPreviewLine(
        preview: preview,
        myUid: uid,
        lastSenderUid: lastSender,
        senderFirstName: senderName,
      );
    }
    final ts = data['lastMessageAt'];
    final isUnread = _chatHubThreadIsUnreadForUser(data, uid);

    return _chatTile(
      title: fullTitle,
      subtitle: preview,
      subtitleIsTyping: isTyping,
      subtitleMaxLines: 2,
      timeLabel: _fmtTime(ts),
      photo: ChurchChatDepartmentAvatar(
        deptData: deptEntry?.deptData,
        fallbackName: fullTitle,
        radius: 24,
      ),
      showPresence: false,
      isUnread: isUnread,
      isFavorite: prefs.isFavorite(doc.id),
      isPinned: prefs.isPinned(doc.id),
      isMuted: prefs.isMutedThread(doc.id),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ChurchChatThreadPage(
              tenantId: tid,
              threadId: doc.id,
              title: fullTitle,
              isDepartment: true,
              departmentId: deptId,
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
        isDepartment: true,
        peerUid: null,
        prefs: prefs,
      ),
      onMoreTap: () => _showThreadActionsSheet(
        context: context,
        tenantId: tid,
        threadId: doc.id,
        title: fullTitle,
        isDepartment: true,
        peerUid: null,
        prefs: prefs,
      ),
    );
  }

  Widget _chatTile({
    required String title,
    required String subtitle,
    required String timeLabel,
    required Widget photo,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    VoidCallback? onMoreTap,
    bool showPresence = false,
    bool online = false,
    bool isUnread = false,
    bool isFavorite = false,
    bool isPinned = false,
    bool isMuted = false,
    bool selectionMode = false,
    bool selected = false,
    bool subtitleIsTyping = false,
    int subtitleMaxLines = 1,
    Widget? trailing,
  }) {
    final accent = isPinned
        ? ThemeCleanPremium.primary
        : isFavorite
            ? const Color(0xFFF59E0B)
            : isUnread
                ? ThemeCleanPremium.primary
                : Colors.transparent;
  final rowBg = isUnread
        ? ThemeCleanPremium.primary.withValues(alpha: 0.06)
        : isPinned
            ? ThemeCleanPremium.primary.withValues(alpha: 0.04)
            : isFavorite
            ? const Color(0xFFFFFBEB)
            : Colors.white;

    return Material(
      color: rowBg,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onTap(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                )
              else if (accent != Colors.transparent)
                Container(
                  width: 3,
                  height: 52,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
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
                            fontWeight:
                                isUnread ? FontWeight.w800 : FontWeight.w700,
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
                            color: subtitleIsTyping
                                ? ThemeCleanPremium.primary
                                : isUnread
                                    ? ThemeCleanPremium.onSurface
                                    : ThemeCleanPremium.onSurfaceVariant,
                            fontSize: 13,
                            fontStyle: subtitleIsTyping
                                ? FontStyle.italic
                                : FontStyle.normal,
                            fontWeight: subtitleIsTyping || isUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
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
                      if (!selectionMode && onMoreTap != null)
                        IconButton(
                          tooltip: 'Opções da conversa',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                          onPressed: onMoreTap,
                        ),
                      if (trailing != null) trailing,
                    ],
                  ),
                ],
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
      backgroundColor: Colors.transparent,
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
                hintText: 'Pesquisar conversas e grupos',
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

  const _PremiumHubTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 380;
    final labelSize = narrow ? 10.5 : 11.5;
    final iconSize = narrow ? 16.0 : 17.0;
    final tabH = narrow ? 42.0 : 46.0;

    Widget tabContent(IconData icon, String label) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize),
            SizedBox(width: narrow ? 4 : 5),
            Text(label),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17.5),
        gradient: churchChatWhatsPremiumLinearGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
          tabAlignment: TabAlignment.fill,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: churchChatWhatsPremiumLinearGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.42),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          labelColor: Colors.white,
          unselectedLabelColor: ThemeCleanPremium.onSurfaceVariant,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: labelSize,
            letterSpacing: 0.15,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: labelSize,
          ),
          tabs: [
            Tab(
              height: tabH,
              child: tabContent(Icons.chat_bubble_rounded, 'Conversas'),
            ),
            Tab(
              height: tabH,
              child: tabContent(Icons.groups_rounded, 'Grupos'),
            ),
            Tab(
              height: tabH,
              child: tabContent(Icons.contacts_rounded, 'Contatos'),
            ),
          ],
        ),
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
      return YahwehSkeletonLoading.chatThreads(count: 8);
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
                    return Material(
                      color: on
                          ? ThemeCleanPremium.primary.withValues(alpha: 0.05)
                          : Colors.white,
                      child: InkWell(
                        onTap: () => widget.onOpenDm(auth, label),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
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
                                    size: 22,
                                  ),
                                ],
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

/// Cartão em **faixa** (lista vertical) — evita `Column` + `Expanded` + `Spacer`
/// dentro de altura não limitada (causava layout inválido / área cinza na web).
class _DeptGroupPremiumStripCard extends StatelessWidget {
  final String tenantId;
  final String myUid;
  final String threadId;
  final _DeptEntry entry;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMembers;
  /// Índice na [SliverReorderableList]; `null` = sem arrastar.
  final int? reorderIndex;

  const _DeptGroupPremiumStripCard({
    required this.tenantId,
    required this.myUid,
    required this.threadId,
    required this.entry,
    required this.onOpenChat,
    required this.onOpenMembers,
    this.reorderIndex,
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
        final participants = data?['participantUids'];
        final nChatMembers = participants is List ? participants.length : 0;

        const stripRadius = 26.0;
        final stripBody = Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(stripRadius),
              child: InkWell(
                onTap: onOpenChat,
                borderRadius: BorderRadius.circular(stripRadius),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(stripRadius),
                    color: unreadFlag
                        ? ThemeCleanPremium.primary.withValues(alpha: 0.07)
                        : Colors.white,
                    border: Border.all(
                      color: unreadFlag
                          ? ThemeCleanPremium.primary.withValues(alpha: 0.25)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 10, top: 4),
                          child: Container(
                            width: 4,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: unreadFlag
                                  ? ThemeCleanPremium.primary
                                  : ThemeCleanPremium.primary
                                      .withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ChurchChatDepartmentAvatar(
                            deptData: entry.deptData,
                            fallbackName: entry.name,
                            radius: 22,
                          ),
                          if (unreadFlag)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 13,
                                height: 13,
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      height: 1.2,
                                      color: ThemeCleanPremium.onSurface,
                                      letterSpacing: -0.25,
                                    ),
                                  ),
                                ),
                                if (timeLabel.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    timeLabel,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
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
                            const SizedBox(height: 6),
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
                            if (unreadFlag) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: const Color(0xFFFFF7ED),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.mark_chat_unread_rounded,
                                      size: 16,
                                      color: const Color(0xFFB45309),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Novas mensagens',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ver membros',
                        onPressed: onOpenMembers,
                        icon: Icon(
                          Icons.groups_rounded,
                          color: ThemeCleanPremium.primary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reorderIndex != null)
                ReorderableDragStartListener(
                  index: reorderIndex!,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding:
                          const EdgeInsets.only(left: 4, top: 12, right: 2),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 26,
                        color: ThemeCleanPremium.onSurfaceVariant
                            .withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              Expanded(child: stripBody),
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
  final VoidCallback onProfilePhotoTap;

  const _PremiumChatHeader({
    required this.chatPushEnabled,
    required this.onMuteTap,
    required this.onNewDm,
    required this.onAlertModeTap,
    required this.onProfilePhotoTap,
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
                          'Mensagens, fotos, vídeos e grupos por departamento',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Minha foto de perfil (chat e cadastro)',
                    onPressed: onProfilePhotoTap,
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      color: Colors.white,
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

  String? _cpfDigitsForMember(Map<String, dynamic> d, String docId) {
    final fromField =
        (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (fromField.length >= 11) return fromField;
    final fromId = docId.replaceAll(RegExp(r'\D'), '');
    if (fromId.length >= 11) return fromId;
    return fromField.isEmpty ? null : fromField;
  }

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
    final radius = BorderRadius.vertical(
      top: Radius.circular(ThemeCleanPremium.radiusLg + 4),
    );
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  gradient: churchChatWhatsPremiumLinearGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nova conversa direta',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Toque num membro para abrir a DM — fotos do cadastro',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _filter,
                style: TextStyle(
                  color: ThemeCleanPremium.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Filtrar por nome…',
                  hintStyle: TextStyle(
                    color: ThemeCleanPremium.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: ThemeCleanPremium.primary,
                  ),
                  filled: true,
                  fillColor: ThemeCleanPremium.cardBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color:
                          ThemeCleanPremium.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color:
                          ThemeCleanPremium.primary.withValues(alpha: 0.28),
                      width: 1.15,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: ThemeCleanPremium.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Material(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _eligible.isEmpty
                                  ? 'Nenhum membro disponível para conversa.'
                                  : 'Nenhum resultado para "${_filter.text.trim()}".',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ThemeCleanPremium.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final doc = filtered[i];
                        final d = doc.data();
                        final auth =
                            (d['authUid'] ?? d['firebaseUid'] ?? '').toString();
                        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                            .toString()
                            .trim();
                        final letter = nome.isNotEmpty
                            ? nome[0].toUpperCase()
                            : '?';
                        final cpfOpt = _cpfDigitsForMember(d, doc.id);
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
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.pop(
                                    context,
                                    _PickResult(uid: auth, name: nome),
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.cardBackground,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.22),
                                        width: 1.1,
                                      ),
                                      boxShadow:
                                          ThemeCleanPremium.softUiCardShadow,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 54,
                                            height: 54,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.center,
                                              children: [
                                                ClipOval(
                                                  child: FotoMembroWidget(
                                                    size: 50,
                                                    tenantId: widget.tid,
                                                    memberId: doc.id,
                                                    memberData: d,
                                                    authUid: auth.isNotEmpty
                                                        ? auth
                                                        : null,
                                                    cpfDigits: cpfOpt,
                                                    memCacheWidth: 160,
                                                    memCacheHeight: 160,
                                                    fallbackChild:
                                                        CircleAvatar(
                                                      radius: 25,
                                                      backgroundColor:
                                                          ThemeCleanPremium
                                                              .primary
                                                              .withValues(
                                                                  alpha: 0.14),
                                                      foregroundColor:
                                                          ThemeCleanPremium
                                                              .primary,
                                                      child: Text(
                                                        letter,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 20,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: BoxDecoration(
                                                      color: on
                                                          ? ThemeCleanPremium
                                                              .success
                                                          : const Color(
                                                              0xFF9CA3AF),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: ThemeCleanPremium
                                                            .cardBackground,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  nome.isEmpty ? auth : nome,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                    height: 1.25,
                                                    color: ThemeCleanPremium
                                                        .onSurface,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      on
                                                          ? Icons
                                                              .circle_rounded
                                                          : Icons
                                                              .trip_origin_rounded,
                                                      size: 12,
                                                      color: on
                                                          ? ThemeCleanPremium
                                                              .success
                                                          : ThemeCleanPremium
                                                              .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      on
                                                          ? 'Online'
                                                          : 'Offline',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: on
                                                            ? ThemeCleanPremium
                                                                .success
                                                            : ThemeCleanPremium
                                                                .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chat_rounded,
                                            color: ThemeCleanPremium.primary
                                                .withValues(alpha: 0.65),
                                            size: 22,
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Mantém o estado das abas ao deslizar entre elas (evita reconstruções «a branco»).
class _KeepAliveHubTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveHubTab({required this.child});

  @override
  State<_KeepAliveHubTab> createState() => _KeepAliveHubTabState();
}

class _KeepAliveHubTabState extends State<_KeepAliveHubTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            const Color(0xFFECFEFF).withValues(alpha: 0.42),
            const Color(0xFFEDE9FE).withValues(alpha: 0.35),
            ThemeCleanPremium.surface.withValues(alpha: 0.25),
          ],
        ),
      ),
      child: widget.child,
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
