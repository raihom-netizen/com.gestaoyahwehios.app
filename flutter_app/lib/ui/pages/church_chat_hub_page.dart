import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_peer_profile_service.dart';
import 'package:gestao_yahweh/services/church_chat_display_name.dart';
import 'package:gestao_yahweh/services/member_profile_photo_sync_notifier.dart';
import 'package:gestao_yahweh/services/church_chat_local_conversations.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/church_chat_moderation.dart';
import 'package:gestao_yahweh/services/church_chat_threads_list_cache.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/services/church_firestore_collection_migration_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/services/pending_uploads_migration.dart';
import 'package:gestao_yahweh/core/yahweh_chat_engine_service.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_notification_settings_page.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_thread_foreground_notif_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_chat_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, imageUrlFromMap;
import 'package:gestao_yahweh/ui/widgets/church_chat_peer_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_profile_photo_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_broadcast_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_whatsapp_theme.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_list_preview.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/services/church_chat_hub_departments_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_auto_recovery_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_pending_status_banner.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';
import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

enum _HubConversasFilter { all, unread, favorites, groups, archived }

/// Conversa activa no split Web (lista + thread lado a lado).
class _SplitThreadSelection {
  const _SplitThreadSelection({
    required this.threadId,
    required this.title,
    required this.isDepartment,
    this.peerUid,
    this.departmentId,
    this.initialDraftText,
  });

  final String threadId;
  final String title;
  final bool isDepartment;
  final String? peerUid;
  final String? departmentId;
  final String? initialDraftText;
}

/// Cache RAM — grupos/departamentos instantâneos ao reabrir o Chat (aba Grupos).
abstract final class _ChatHubDepartmentsRamCache {
  _ChatHubDepartmentsRamCache._();

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _byTenant = {};

  static const Duration _ttl = Duration(minutes: 20);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peek(
    String tenantId,
  ) {
    final key = tenantId.trim();
    if (key.isEmpty) return null;
    final hit = _byTenant[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byTenant.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void put(
    String tenantId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = tenantId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _byTenant[key] = (docs: List.from(docs), at: DateTime.now());
  }
}

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
  final lastSender = (data['lastSenderUid'] ?? '').toString();
  if (lastSender.isNotEmpty && lastSender == myUid) return false;
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

/// Gestor, pastoral, secretário, tesoureiro — vê todos os grupos (não líder de departamento).
bool _chatHubSeesAllDepartmentGroups(String role, List<String>? permissions) =>
    AppPermissions.chatHubSeesAllDepartmentGroups(role, permissions: permissions);

/// Lista estilo WhatsApp — DM + grupos por departamento (membro: só os seus; liderança: todos).
/// DM na aba «Conversas»: dados do documento em `chat_threads` (sem segundo stream por linha),
/// foto de perfil a partir de `membros`, primeiro nome + prévia; presença só em `chat_presence`.
class ChurchChatHubPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool embeddedInShell;
  final VoidCallback? onShellBack;
  /// Permissões granulares do painel (ex.: módulo `departamentos`), alinhadas a [AppPermissions.canEditDepartments].
  final List<String>? permissions;

  const ChurchChatHubPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    this.embeddedInShell = false,
    this.onShellBack,
    this.permissions,
  });

  @override
  State<ChurchChatHubPage> createState() => _ChurchChatHubPageState();
}

class _ChurchChatHubPageState extends State<ChurchChatHubPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _resolvedTenantId;
  List<_DeptEntry> _departments = [];
  bool _departmentsLoading = false;
  String? _departmentsSoftError;
  int _deptSyncGeneration = 0;
  /// Stream único de `chat_threads` (reconexão automática em [ChatHubThreads]).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _chatThreadsStream;
  /// Evita lista de conversas «a piscar»: mantém o último snapshot válido se o stream falhar de momento.
  QuerySnapshot<Map<String, dynamic>>? _lastGoodChatThreadsSnap;
  bool _chatPushEnabled = true;
  _HubConversasFilter _conversasFilter = _HubConversasFilter.all;
  _SplitThreadSelection? _splitSelected;
  final _searchCtrl = TextEditingController();
  final _membersFilterCtrl = TextEditingController();
  final _deptFilterCtrl = TextEditingController();
  /// Pesquisa com debounce — evita reconstruir lista de conversas a cada tecla.
  final ValueNotifier<String> _debouncedConversasSearch = ValueNotifier('');
  final ValueNotifier<String> _debouncedDeptSearch = ValueNotifier('');
  Timer? _conversasSearchDebounce;
  Timer? _deptSearchDebounce;
  late TabController _hubTabController;
  Timer? _gruposResyncDebounce;
  Timer? _conversasResyncDebounce;
  DateTime? _lastSilentConversasSync;
  static const Duration _conversasSilentSyncMinInterval = Duration(minutes: 2);
  /// Avatares no hub — `chat_peer_profiles` (sem stream de 600 `membros`).
  Map<String, ChurchChatMemberRef> _peerMemberByUid = {};
  Map<String, bool> _peerOnlineByUid = {};
  Timer? _presencePollTimer;
  String? _presencePollKey;
  late final VoidCallback _photoSyncListener;
  bool _dmSelectMode = false;
  final Set<String> _selectedDmThreadIds = <String>{};
  List<ChurchChatLocalConversationEntry> _localConversations = [];
  late final VoidCallback _localConvListener;
  bool _resumeChatThreadAttempted = false;
  bool _conversasSkeletonTimedOut = false;
  bool _conversasListPrimed = false;
  Timer? _conversasSkeletonTimer;
  Timer? _lazyMemberWarmupTimer;
  final Map<String, int> _unreadCountByThreadId = {};
  String? _unreadCountsLoadKey;

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('chat');
    unawaited(ensureFirebaseReadyForChatSend().catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PendingUploadsMigration.migrateAwayFromFirestoreQueueIfNeeded());
    });
    // Streams/grupos só após _bootstrap() resolver o doc canónico (evita legado vazio).
    _conversasSkeletonTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _conversasSkeletonTimedOut = true);
    });
    _localConvListener = () {
      if (mounted) unawaited(_reloadLocalConversations());
    };
    ChurchChatLocalConversations.revision.addListener(_localConvListener);
    _photoSyncListener = _onMemberProfilePhotoSynced;
    MemberProfilePhotoSyncNotifier.instance.addListener(_photoSyncListener);
    WidgetsBinding.instance.addObserver(this);
    _hubTabController = TabController(length: 3, vsync: this);
    _hubTabController.addListener(_hubTabListener);
    _searchCtrl.addListener(_onConversasSearchInput);
    _deptFilterCtrl.addListener(_onDeptSearchInput);
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
      ChatHubThreads.invalidateStreamCache();
      unawaited(_bootstrap());
    }
  }

  @override
  void dispose() {
    _lazyMemberWarmupTimer?.cancel();
    ChurchChatLocalConversations.revision.removeListener(_localConvListener);
    MemberProfilePhotoSyncNotifier.instance.removeListener(_photoSyncListener);
    WidgetsBinding.instance.removeObserver(this);
    _gruposResyncDebounce?.cancel();
    _conversasResyncDebounce?.cancel();
    _conversasSkeletonTimer?.cancel();
    _conversasSearchDebounce?.cancel();
    _deptSearchDebounce?.cancel();
    _searchCtrl.removeListener(_onConversasSearchInput);
    _deptFilterCtrl.removeListener(_onDeptSearchInput);
    _debouncedConversasSearch.dispose();
    _debouncedDeptSearch.dispose();
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

  void _onConversasSearchInput() {
    _conversasSearchDebounce?.cancel();
    _conversasSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      final q = _searchCtrl.text.trim();
      if (_debouncedConversasSearch.value == q) return;
      _debouncedConversasSearch.value = q;
    });
  }

  void _onDeptSearchInput() {
    _deptSearchDebounce?.cancel();
    _deptSearchDebounce = Timer(const Duration(milliseconds: 500), () {
      final q = _deptFilterCtrl.text.trim().toLowerCase();
      if (_debouncedDeptSearch.value == q) return;
      _debouncedDeptSearch.value = q;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!kIsWeb) unawaited(AppFinalizeBootstrap.onAppResume());
      unawaited(ensureFirebaseReadyForChatSend().catchError((_) {}));
      ChurchChatMediaOutboxService.resumePendingOnAppStart();
      final t = _resolvedTenantId;
      if (t != null) {
        unawaited(_syncMemberDepartments(t, showLoadingIndicator: false));
      }
      _requestSilentConversasSyncIfStale();
    }
  }

  void _hubTabListener() {
    if (_hubTabController.indexIsChanging) return;
    if (_hubTabController.index != 0 && _dmSelectMode) {
      setState(_clearDmSelectUi);
    }
    // Lista «Conversas» mantém-se visível ao mudar de aba (sem reparo/sync visível).
    if (_hubTabController.index == 1) {
      _requestGruposResync();
    }
  }

  void _requestGruposResync() {
    _gruposResyncDebounce?.cancel();
    _gruposResyncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final t = _resolvedTenantId;
      if (t != null) {
        unawaited(_syncMemberDepartments(t, showLoadingIndicator: false));
      }
    });
  }

  void _scheduleLazyMemberWarmup(String tenantId) {
    unawaited(_warmMemberDirectoryForChat(tenantId));
    _lazyMemberWarmupTimer?.cancel();
    _lazyMemberWarmupTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      unawaited(_warmMemberDirectoryForChat(tenantId));
    });
  }

  Future<void> _pullRefreshConversas() async {
    final tid = _resolvedTenantId;
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (tid == null || uid.isEmpty) return;
    if (_chatThreadsStream == null) {
      await _bootstrap();
      return;
    }
    await _silentSyncConversasIndex(tid, force: true);
    await _warmMemberDirectoryForChat(tid);
  }

  void _requestSilentConversasSyncIfStale() {
    _conversasResyncDebounce?.cancel();
    _conversasResyncDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final tid = _resolvedTenantId;
      if (tid == null) return;
      unawaited(_silentSyncConversasIndex(tid));
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
      final legacyPeer = ChatHubOperations.otherUidInDmThread(d.id, myUid);
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
    final n = MemberProfilePhotoSyncNotifier.instance;
    final uid = n.lastAuthUid?.trim() ?? '';
    if (tid == null || uid.isEmpty) return;
    unawaited(_refreshPeerProfilesForAuthUids(tid, {uid}));
  }

  /// Diretório `_panel_cache/members_directory` — nomes na web sem N queries em `membros`.
  Future<void> _warmMemberDirectoryForChat(String tenantId) async {
    try {
      var snap = await MembersDirectorySnapshotService.readOnce(tenantId);
      if (snap.hasEntries && mounted && _resolvedTenantId == tenantId) {
        _mergeDirectoryIntoPeerProfiles(tenantId, snap);
      }
      unawaited(() async {
        if (!snap.hasEntries) {
          snap = await MembersDirectorySnapshotService.warmFromCallableIfStale(
            tenantId,
          ).timeout(const Duration(seconds: 20), onTimeout: () => snap);
        }
        if (!mounted || _resolvedTenantId != tenantId || !snap.hasEntries) {
          return;
        }
        _mergeDirectoryIntoPeerProfiles(tenantId, snap);
      }());
    } catch (_) {}
  }

  void _mergeDirectoryIntoPeerProfiles(
    String tenantId,
    MembersDirectorySnapshot snap,
  ) {
    final merged = <String, ChurchChatMemberRef>{};
    for (final e in snap.entries) {
      final au = (e.authUid ?? '').trim();
      if (au.isEmpty) continue;
      final nome = e.displayName.trim();
      if (nome.isEmpty || nome == 'Membro') continue;
      merged[au] = ChurchChatMemberRef(
        memberId: e.memberDocId,
        authUid: au,
        data: e.toMemberDataMap(),
        photoUrl: e.photoUrl,
      );
    }
    if (merged.isEmpty) return;
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(tenantId, merged.values);
    if (mounted) {
      setState(() => _peerMemberByUid = {..._peerMemberByUid, ...merged});
    }
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
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(tenantId, loaded.values);
    setState(() => _peerMemberByUid = {..._peerMemberByUid, ...loaded});
  }

  void _schedulePeerProfilesLoad(String tenantId, Set<String> peerUids) {
    if (peerUids.isEmpty) return;
    final missing = peerUids.where((u) {
      if (!_peerMemberByUid.containsKey(u)) return true;
      return _memberDisplayName(_peerMemberByUid[u]!).isEmpty;
    }).toSet();
    if (missing.isEmpty) return;
    unawaited(() async {
      await ensureFirebaseReadyForPanelRead().catchError((_) {});
      final loaded = await ChurchChatPeerProfileService.loadMemberRefsForAuthUids(
        tenantId: tenantId,
        authUids: missing,
      );
      if (!mounted || _resolvedTenantId != tenantId) return;
      if (loaded.isEmpty) return;
      ChurchGalleryPhotoWarmup.warmBytesForChatRefs(tenantId, loaded.values);
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
      final online = await ChatMessagingEngine.fetchPresenceOnlineMap(
        churchId: tenantId,
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
    // Mesmo frame do toque — abre a DM sem esperar o próximo frame.
    if (mounted) unawaited(_tryConsumePendingChatThread());
  }

  Future<void> _tryConsumePendingChatThread({int attempt = 0}) async {
    if (!mounted || !widget.embeddedInShell) return;
    const maxAttempts = 24;
    final peek =
        ChurchPanelNavigationBridge.instance.peekPendingChatThreadOpen();
    if (peek == null) return;

    // Tenant imediato (hint do shell) — não esperar bootstrap completo.
    final tidHint = ChurchRepository.churchId(widget.tenantId.trim());
    final tid = (_resolvedTenantId ?? '').trim().isNotEmpty
        ? _resolvedTenantId!.trim()
        : (tidHint.isNotEmpty ? tidHint : widget.tenantId.trim());
    if (tid.isEmpty) {
      if (attempt < maxAttempts) {
        await Future<void>.delayed(
          Duration(milliseconds: 50 + attempt * 40),
        );
        if (mounted) {
          return _tryConsumePendingChatThread(attempt: attempt + 1);
        }
      }
      return;
    }

    if (peek.tenantId != null && peek.tenantId!.isNotEmpty) {
      final peekResolved = ChurchPanelTenant.forFirestore(peek.tenantId!);
      final tidResolved = ChurchPanelTenant.forFirestore(tid);
      if (peekResolved.isNotEmpty &&
          tidResolved.isNotEmpty &&
          peekResolved != tidResolved) {
        if (_resolvedTenantId == null && attempt < maxAttempts) {
          await Future<void>.delayed(
            Duration(milliseconds: 50 + attempt * 40),
          );
          if (mounted) {
            return _tryConsumePendingChatThread(attempt: attempt + 1);
          }
        }
        return;
      }
    }

    final threadId = peek.threadId.trim();
    if (threadId.isEmpty) return;

    final myUid = firebaseDefaultAuth.currentUser?.uid.trim();
    if (myUid == null || myUid.isEmpty) return;

    final isDmPending = threadId.startsWith('dm_');
    final pendingPeer = peek.peerUid?.trim() ?? '';
    final pendingTitle = (peek.displayName ?? '').trim();

    // DM com peer conhecido → abre a conversa na hora (estilo WhatsApp).
    if (isDmPending && pendingPeer.isNotEmpty) {
      final pending =
          ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
      if (pending == null || pending.threadId != threadId) return;
      if (!mounted) return;

      final dmTitle = pendingTitle.isEmpty ? 'Membro' : pendingTitle;
      _openChatThreadPage(
        tid: tid,
        threadId: pending.threadId,
        title: dmTitle,
        isDepartment: false,
        peerUid: pendingPeer,
        initialDraftText: pending.initialDraftText,
      );

      unawaited(
        ChatHubOperations.ensureDmThreadResilient(
          tenantId: tid,
          uidA: myUid,
          uidB: pendingPeer,
          titleA: firebaseDefaultAuth.currentUser?.displayName ?? 'Eu',
          titleB: dmTitle,
        ),
      );
      if (mounted) {
        unawaited(_primeConversasListFromFallback(tid));
        unawaited(_reloadLocalConversations());
      }
      return;
    }

    // Sem peer / grupo: precisa do doc (com timeout curto).
    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await ChatHubOperations.threadRef(tid, threadId)
          .get()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snap = null;
    }

    if (isDmPending) {
      if ((snap == null || !snap.exists) && pendingPeer.isEmpty) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(
            Duration(milliseconds: 80 + attempt * 60),
          );
          if (mounted) {
            return _tryConsumePendingChatThread(attempt: attempt + 1);
          }
        }
        return;
      }
      final pending =
          ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
      if (pending == null || pending.threadId != threadId) return;
      if (!mounted) return;

      final data = snap?.data() ?? <String, dynamic>{};
      var peer = pendingPeer;
      if (peer.isEmpty) {
        final peerList = (data['participantUids'] as List?)
                ?.map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            <String>[];
        for (final p in peerList) {
          if (p != myUid) {
            peer = p;
            break;
          }
        }
      }
      if (peer.isEmpty) return;

      var dmTitle = pendingTitle;
      if (dmTitle.isEmpty) {
        dmTitle = _resolvePeerDisplayName(peer, threadData: data);
      }
      if (dmTitle.isEmpty) {
        dmTitle = _looksLikeFirebaseUid(peer) ? 'Membro' : peer;
      }

      _openChatThreadPage(
        tid: tid,
        threadId: pending.threadId,
        title: dmTitle,
        isDepartment: false,
        peerUid: peer,
        initialDraftText: pending.initialDraftText,
      );
      if (mounted) {
        unawaited(_primeConversasListFromFallback(tid));
        unawaited(_reloadLocalConversations());
      }
      return;
    }

    if (snap == null || !snap.exists) return;
    final pending =
        ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
    if (pending == null || pending.threadId != threadId) return;
    final data = snap.data() ?? {};
    final type = (data['type'] ?? '').toString();
    if (type == 'department') {
      final deptId = (data['departmentId'] ?? '').toString();
      final rawTitle = (data['title'] ?? 'Grupo').toString().trim();
      final title = rawTitle.isEmpty ? 'Grupo' : rawTitle;
      _openChatThreadPage(
        tid: tid,
        threadId: pending.threadId,
        title: title,
        isDepartment: true,
        departmentId: deptId.isEmpty ? null : deptId,
      );
      return;
    }
    if (type == 'dm') {
      final peerList = (data['participantUids'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          <String>[];
      String? peer;
      for (final p in peerList) {
        if (p != myUid) {
          peer = p;
          break;
        }
      }
      if (peer == null || peer.isEmpty) return;
      var dmTitle = _resolvePeerDisplayName(peer, threadData: data);
      if (dmTitle.isEmpty) {
        dmTitle = _looksLikeFirebaseUid(peer) ? 'Membro' : peer;
      }
      _openChatThreadPage(
        tid: tid,
        threadId: pending.threadId,
        title: dmTitle,
        isDepartment: false,
        peerUid: peer,
        initialDraftText: pending.initialDraftText,
      );
    }
  }

  bool _silentConversasSyncInFlight = false;

  /// Sincroniza índice DM em background — não recria stream nem mostra «a carregar».
  Future<void> _silentSyncConversasIndex(
    String tenantId, {
    bool force = false,
  }) async {
    if (_silentConversasSyncInFlight) return;
    final now = DateTime.now();
    if (!force &&
        _lastSilentConversasSync != null &&
        now.difference(_lastSilentConversasSync!) <
            _conversasSilentSyncMinInterval) {
      return;
    }
    _silentConversasSyncInFlight = true;
    _lastSilentConversasSync = now;
    try {
      await _primeConversasListFromFallback(tenantId);
      await ChatHubOperations.syncDmThreadsIndex(tenantId).timeout(
        const Duration(seconds: 20),
        onTimeout: () => 0,
      );
      await _primeConversasListFromFallback(tenantId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('silentSyncConversasIndex: $e\n$st');
      }
      await _primeConversasListFromFallback(tenantId);
    } finally {
      _silentConversasSyncInFlight = false;
    }
  }

  /// Lista imediata a partir de `chat_peer_profiles` + ids `dm_*` (não espera reparo CF).
  Future<void> _reloadLocalConversations() async {
    final tid = _resolvedTenantId;
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (tid == null || uid.isEmpty) return;
    final list = await ChurchChatLocalConversations.listForUser(
      tenantId: tid,
      uid: uid,
    );
    if (!mounted) return;
    setState(() => _localConversations = list);
  }

  Future<void> _pruneStaleChatUploads(String tenantId) async {
    if (tenantId.isEmpty) return;
    try {
      await PendingUploadsFirestoreService.purgeAllLegacyOpenForTenant(
        tenantId,
      );
      await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
    } catch (_) {}
  }

  Future<void> _primeConversasListFromFallback(String tenantId) async {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final fallback = await ChatHubOperations.loadDmThreadsSnapshotFallback(
        tenantId: tenantId,
        uid: uid,
      );
      if (!mounted) return;
      if (fallback.docs.isNotEmpty) {
        setState(() => _lastGoodChatThreadsSnap = fallback);
        unawaited(
          ChurchChatThreadsListCache.saveFromSnapshot(tenantId, fallback),
        );
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _conversasListPrimed = true);
    }
  }

  void _scheduleUnreadCountsLoad(
    String tenantId,
    String uid,
    List<String> threadIds,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (threadIds.isEmpty) return;
    final key = threadIds.join(',');
    if (_unreadCountsLoadKey == key) return;
    _unreadCountsLoadKey = key;
    unawaited(() async {
      final map = <String, int>{};
      for (var i = 0; i < docs.length && i < 30; i++) {
        final doc = docs[i];
        final data = doc.data();
        if (!_chatHubThreadIsUnreadForUser(data, uid)) continue;
        final n = await ChatHubOperations.threadUnreadInboundCount(
          tenantId: tenantId,
          threadId: doc.id,
          myUid: uid,
          myLastSeenInThread: _chatHubThreadMyLastSeen(data, uid),
        );
        if (n > 0) map[doc.id] = n;
      }
      if (!mounted) return;
      final changed = map.length != _unreadCountByThreadId.length ||
          map.entries.any(
            (e) => _unreadCountByThreadId[e.key] != e.value,
          );
      if (!changed) return;
      setState(() {
        for (final id in threadIds) {
          _unreadCountByThreadId.remove(id);
        }
        _unreadCountByThreadId.addAll(map);
      });
    }());
  }

  Widget _whatsappUnreadBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF25D366).withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Future<void> _bootstrap() async {
    final hint = widget.tenantId.trim();
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';

    // Path canónico imediato — UI não espera ensurePanelReadReady (evita skeleton eterno).
    final tid = ChurchRepository.churchId(hint.isNotEmpty ? hint : null);
    final effective = tid.isNotEmpty ? tid : hint;
    if (effective.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _resolvedTenantId = effective;
      if (uid.isNotEmpty) {
        _chatThreadsStream =
            ChatHubThreads.watchForUser(churchId: effective, uid: uid);
      }
    });

    // Consome atalho YahwehChat já no 1.º frame (antes do warmup).
    unawaited(_tryConsumePendingChatThread());
    unawaited(_bootstrapAfterTenantBound(effective, uid));
  }

  Future<void> _bootstrapAfterTenantBound(String tid, String uid) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady()
          .timeout(const Duration(seconds: 3), onTimeout: () {})
          .catchError((_) {});
    }

    QuerySnapshot<Map<String, dynamic>>? cachedList;
    if (uid.isNotEmpty) {
      try {
        cachedList = await ChurchChatThreadsListCache.loadSnapshot(tid, uid: uid)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (!mounted) return;
    if (cachedList != null && cachedList.docs.isNotEmpty) {
      setState(() => _lastGoodChatThreadsSnap = cachedList);
    }

    unawaited(_openGruposFast(tid));
    unawaited(_primeDepartmentsFromHive(tid));

    unawaited(ChurchFirestoreCollectionMigrationService.ensureTenantMigrated(tid));
    unawaited(_loadChatNotifPrefs());
    unawaited(_pruneStaleChatUploads(tid));
    unawaited(ChurchChatAutoRecoveryService.recoverOnSessionStart());
    unawaited(
      ChurchChatMediaOutboxService.resumeRecoverableNow().catchError((_) {}),
    );
    _scheduleLazyMemberWarmup(tid);
    unawaited(_primeConversasListFromFallback(tid));
    unawaited(_reloadLocalConversations());
    unawaited(
      ChurchChatHubDepartmentsService.loadDocs(seedTenantId: tid)
          .catchError((_) => const <QueryDocumentSnapshot<Map<String, dynamic>>>[]),
    );
    unawaited(_syncMemberDepartments(tid));
    unawaited(_silentSyncConversasIndex(tid, force: true));
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_tryResumeLastChatThread(tid));
          unawaited(_tryConsumePendingChatThread());
        }
      });
    }
  }

  /// Reabre a última conversa só se [AppResumeStateService.restoreLastScreenOnStartup].
  Future<void> _tryResumeLastChatThread(String tid) async {
    if (!AppResumeStateService.restoreLastScreenOnStartup) return;
    if (_resumeChatThreadAttempted || !widget.embeddedInShell || !mounted) {
      return;
    }
    _resumeChatThreadAttempted = true;
    if (ChurchPanelNavigationBridge.instance.peekPendingChatThreadOpen() !=
        null) {
      return;
    }
    final resume = await AppResumeStateService.readChatThread();
    if (resume == null || resume.tenantId != tid) return;
    ChurchPanelNavigationBridge.instance.requestNavigateToChatThread(
      threadId: resume.threadId,
      tenantId: tid,
    );
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

  Future<void> _ensureDeptThreadsBackground(
    String tid,
    String uid,
    List<_DeptEntry> entries,
  ) async {
    // Só garante threads dos primeiros grupos — o resto ao abrir (evita N×12s na lista).
    final slice = entries.length > 8 ? entries.take(8).toList() : entries;
    for (final e in slice) {
      try {
        await ChatHubOperations.ensureDepartmentThread(
          tenantId: tid,
          departmentId: e.id,
          departmentName: e.name,
          participantUids: [uid],
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
  }

  List<_DeptEntry> _entriesFromDeptDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final entries = docs
        .map(
          (doc) => _DeptEntry(
            id: doc.id,
            name: churchDepartmentNameFromData(doc.data(), docId: doc.id),
            deptData: doc.data(),
          ),
        )
        .toList();
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Future<List<_DeptEntry>> _loadDepartmentsFromFirestoreCache(String tid) async {
    try {
      final docs = await ChurchChatHubDepartmentsService.loadDocs(
        seedTenantId: tid,
      );
      if (docs.isEmpty) return [];
      _ChatHubDepartmentsRamCache.put(tid, docs);
      return _entriesFromDeptDocs(docs);
    } catch (_) {
      return [];
    }
  }

  Future<List<_DeptEntry>> _fetchDeptEntriesParallel(
    String tid,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    final churchId = ChurchRepository.churchId(tid);
    final deptCol = ChurchUiCollections.departamentos(churchId);
    final futures = ids.map((id) async {
      try {
        var doc = await deptCol
            .doc(id)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        if (!doc.exists) {
          doc = await deptCol.doc(id).get().timeout(const Duration(seconds: 7));
        }
        if (!doc.exists) return null;
        return _DeptEntry(
          id: doc.id,
          name: churchDepartmentNameFromData(doc.data() ?? {}, docId: doc.id),
          deptData: doc.data(),
        );
      } catch (_) {
        return null;
      }
    });
    final results = await Future.wait(futures);
    final entries = results.whereType<_DeptEntry>().toList();
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  Future<void> _primeDepartmentsFromHive(String tid) async {
    try {
      final churchId = ChurchRepository.churchId(tid);
      final rows = await TenantModuleHiveCache.readDocs(
        churchId,
        TenantModuleKeys.departamentos,
      );
      if (rows.isEmpty || !mounted) return;
      final docs = TenantModuleHiveCache.toQueryDocuments(rows);
      _ChatHubDepartmentsRamCache.put(churchId, docs);
      setState(() => _departments = _entriesFromDeptDocs(docs));
    } catch (_) {}
  }

  /// 1.º frame: RAM/Hive + carga canónica; sync de threads em background.
  Future<void> _openGruposFast([String? tenantOverride]) async {
    final seed = (tenantOverride ?? _resolvedTenantId ?? widget.tenantId).trim();
    if (seed.isEmpty) return;

    final seesAll =
        _chatHubSeesAllDepartmentGroups(widget.role, widget.permissions);

    if (!seesAll) {
      try {
        final prefIds =
            await YahwehChatEngineService.loadMemberDepartmentGroupIds(seed);
        if (prefIds.isNotEmpty) {
          final fromPrefs = await _fetchDeptEntriesParallel(seed, prefIds);
          if (fromPrefs.isNotEmpty && mounted) {
            setState(() {
              _departments = fromPrefs;
              _departmentsLoading = false;
              _departmentsSoftError = null;
            });
            final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
            if (uid.isNotEmpty) {
              unawaited(_ensureDeptThreadsBackground(seed, uid, _departments));
            }
            return;
          }
        }
      } catch (_) {}
    }

    final instant = ChurchChatHubDepartmentsService.peekInstant(seed);
    if (seesAll && instant != null && instant.isNotEmpty && mounted) {
      setState(() {
        _departments = _entriesFromDeptDocs(instant);
        _departmentsLoading = false;
        _departmentsSoftError = null;
      });
    }

    try {
      final result = await ChurchChatHubDepartmentsService.load(
        seedTenantId: seed,
      );
      if (!mounted) return;
      if (result.docs.isNotEmpty) {
        if (seesAll) {
          _ChatHubDepartmentsRamCache.put(
            ChurchPanelTenant.resolve(seed),
            result.docs,
          );
        }
        setState(() {
          _departments = _entriesFromDeptDocs(result.docs);
          _departmentsLoading = false;
          _departmentsSoftError = null;
        });
        final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
        if (uid.isNotEmpty) {
          unawaited(_ensureDeptThreadsBackground(seed, uid, _departments));
        }
        return;
      }
      if (result.softError != null && result.softError!.trim().isNotEmpty) {
        setState(() => _departmentsSoftError = result.softError);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _departmentsSoftError = e.toString());
      }
    }

    if (mounted && _departments.isEmpty) {
      final fromThreads = await _loadDepartmentsFromDeptChatThreads(seed);
      if (fromThreads.isNotEmpty && mounted) {
        setState(() {
          _departments = fromThreads;
          _departmentsSoftError = null;
        });
        final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
        if (uid.isNotEmpty) {
          unawaited(_ensureDeptThreadsBackground(seed, uid, _departments));
        }
      }
    }
    if (mounted) {
      setState(() => _departmentsLoading = false);
    }
  }

  Future<void> _syncAllDepartmentsForLeadership(String tid, String uid) async {
    await _primeDepartmentsFromHive(tid);
    final cached = await _loadDepartmentsFromFirestoreCache(tid);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _departments = cached;
        _departmentsSoftError = null;
      });
    }
    try {
      final result = await ChurchChatHubDepartmentsService.load(
        seedTenantId: tid,
        forceServer: cached.isEmpty,
      );
      var entries = _entriesFromDeptDocs(result.docs);
      if (entries.isEmpty) {
        final prefIds =
            await YahwehChatEngineService.loadMemberDepartmentGroupIds(tid);
        if (prefIds.isNotEmpty) {
          entries = await _fetchDeptEntriesParallel(tid, prefIds);
        }
      }
      if (entries.isEmpty) {
        entries = await _loadDepartmentsFromDeptChatThreads(tid);
      }
      if (!mounted) return;
      if (entries.isNotEmpty) {
        if (result.docs.isNotEmpty) {
          _ChatHubDepartmentsRamCache.put(
            ChurchPanelTenant.resolve(tid),
            result.docs,
          );
        }
        setState(() {
          _departments = entries;
          _departmentsSoftError = null;
        });
      } else if (result.softError != null &&
          result.softError!.trim().isNotEmpty) {
        setState(() => _departmentsSoftError = result.softError);
      }
      unawaited(
        ChatHubOperations.syncUserChatProfile(
          tenantId: tid,
          departmentIds: entries.map((e) => e.id).toList(),
        ).timeout(const Duration(seconds: 10)).catchError((_) {}),
      );
      unawaited(_ensureDeptThreadsBackground(tid, uid, entries));
    } catch (e) {
      if (kDebugMode) debugPrint('chat grupos (liderança): $e');
      if (!mounted) return;
      if (_departments.isEmpty) {
        final fromThreads = await _loadDepartmentsFromDeptChatThreads(tid);
        if (fromThreads.isNotEmpty && mounted) {
          setState(() {
            _departments = fromThreads;
            _departmentsSoftError = null;
          });
        } else if (cached.isEmpty && mounted && _departments.isEmpty) {
          setState(() {
            _departments = const [];
            _departmentsSoftError = e.toString();
          });
        }
      }
    }
  }

  /// Fallback: grupos já existentes em `chats` tipo department.
  Future<List<_DeptEntry>> _loadDepartmentsFromDeptChatThreads(
    String tid,
  ) async {
    try {
      final op = ChurchContextService.panelChurchId(tid);
      Future<QuerySnapshot<Map<String, dynamic>>> read({Source? source}) =>
          FirestoreWebGuard.runWithWebRecovery(
            () => ChurchUiCollections.chats(op)
                .where('type', isEqualTo: 'department')
                .limit(80)
                .get(GetOptions(source: source ?? Source.server)),
          );
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await read(source: Source.cache)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        snap = await read().timeout(const Duration(seconds: 14));
      }
      if (snap.docs.isEmpty) {
        snap = await read().timeout(const Duration(seconds: 14));
      }
      final out = <_DeptEntry>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final deptId = (data['departmentId'] ?? '').toString().trim();
        if (deptId.isEmpty) continue;
        final name = (data['title'] ?? data['departmentName'] ?? deptId)
            .toString()
            .trim();
        out.add(
          _DeptEntry(
            id: deptId,
            name: name.isEmpty ? deptId : name,
            deptData: data,
          ),
        );
      }
      if (out.isEmpty) return [];
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _appendLeaderDepartmentIds(
    String tid,
    String uid,
    String cpfDigits,
    Set<String> deptIds,
  ) async {
    if (!ChurchRolePermissions.isDepartmentLeaderRoleKey(
      ChurchRolePermissions.normalize(widget.role),
    )) {
      return;
    }
    try {
      final op = ChurchContextService.panelChurchId(tid);
      final snap = await           ChurchUiCollections.departamentos(op)
          .limit(120)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      for (final doc in snap.docs) {
        final data = doc.data();
        if (ChurchDepartmentLeaders.memberIsLeaderOfDepartment(data, cpfDigits) ||
            ChurchDepartmentLeaders.leaderUidsFromDepartmentData(data)
                .contains(uid)) {
          deptIds.add(doc.id);
        }
      }
      if (deptIds.isEmpty) {
        final snapNet = await ChurchTenantResilientReads.departamentos(tid, limit: 120)
            .timeout(const Duration(seconds: 12));
        for (final doc in snapNet.docs) {
          final data = doc.data();
          if (ChurchDepartmentLeaders.memberIsLeaderOfDepartment(data, cpfDigits) ||
              ChurchDepartmentLeaders.leaderUidsFromDepartmentData(data)
                  .contains(uid)) {
            deptIds.add(doc.id);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _syncMemberDepartments(
    String tid, {
    bool showLoadingIndicator = true,
    bool forceServer = false,
  }) async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _departmentsLoading = false);
      return;
    }
    final syncGen = ++_deptSyncGeneration;

    unawaited(_primeDepartmentsFromHive(tid));

    final cached = await _loadDepartmentsFromFirestoreCache(tid);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _departments = cached;
        _departmentsLoading = false;
      });
    } else if (mounted &&
        _departments.isEmpty &&
        showLoadingIndicator) {
      setState(() => _departmentsLoading = true);
    }

    Timer? cap;
    cap = Timer(
      kIsWeb ? const Duration(seconds: 22) : const Duration(seconds: 90),
      () {
      if (mounted && syncGen == _deptSyncGeneration && _departmentsLoading) {
        setState(() => _departmentsLoading = false);
      }
    },
    );

    try {
      if (_chatHubSeesAllDepartmentGroups(widget.role, widget.permissions)) {
        if (forceServer) {
          final result = await ChurchChatHubDepartmentsService.load(
            seedTenantId: tid,
            forceServer: true,
          );
          if (result.docs.isNotEmpty && mounted) {
            setState(() {
              _departments = _entriesFromDeptDocs(result.docs);
              _departmentsSoftError = null;
            });
          } else if (mounted &&
              result.softError != null &&
              result.softError!.trim().isNotEmpty) {
            setState(() => _departmentsSoftError = result.softError);
          }
        }
        await _syncAllDepartmentsForLeadership(tid, uid);
      } else {
        await _syncMemberDepartmentsForMember(tid, uid, syncGen);
      }
    } finally {
      cap.cancel();
      if (mounted && syncGen == _deptSyncGeneration) {
        setState(() => _departmentsLoading = false);
      }
    }
  }

  Future<void> _syncMemberDepartmentsForMember(
    String tid,
    String uid,
    int syncGen,
  ) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final prefs = await YahwehChatEngineService.loadMemberPrefs(tid);
      final prefsGroupIds = prefs.departmentGroupOrderIds;

      final digits = widget.cpf.replaceAll(RegExp(r'\D'), '');
      final churchId = ChurchRepository.churchId(tid);
      final base = ChurchUiCollections.membros(churchId);

      DocumentSnapshot<Map<String, dynamic>>? membro;
      try {
        if (digits.length == 11) {
          final byCpf = await base
              .doc(digits)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (byCpf.exists) membro = byCpf;
        }
        membro ??= await base
            .doc(uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
        if (membro != null && !membro.exists) {
          if (digits.length == 11) {
            final byCpfNet = await base.doc(digits).get().timeout(
                  const Duration(seconds: 8),
                );
            if (byCpfNet.exists) membro = byCpfNet;
          }
          membro ??= await base.doc(uid).get().timeout(
                const Duration(seconds: 8),
              );
          if (!membro.exists) {
            final q = await base
                .where('authUid', isEqualTo: uid)
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 10));
            if (q.docs.isNotEmpty) membro = q.docs.first;
          }
        }
      } catch (_) {}

      final deptIds = <String>[];
      if (prefsGroupIds.isNotEmpty) {
        deptIds.addAll(prefsGroupIds);
      }
      if (membro != null && membro.exists) {
        final d = membro.data() ?? {};
        final raw = d['departamentosIds'];
        if (raw is List) {
          deptIds.addAll(raw.map((e) => e.toString()).where((s) => s.isNotEmpty));
        }
        final depNames = d['DEPARTAMENTOS'];
        if (depNames is List) {
          final col = ChurchUiCollections.departamentos(churchId);
          final nameFutures = depNames.map((name) async {
            try {
              final hit = await col
                  .where('nome', isEqualTo: name.toString())
                  .limit(1)
                  .get(const GetOptions(source: Source.cache))
                  .timeout(const Duration(seconds: 3));
              if (hit.docs.isNotEmpty) return hit.docs.first.id;
              final hitNet = await col
                  .where('nome', isEqualTo: name.toString())
                  .limit(1)
                  .get()
                  .timeout(const Duration(seconds: 6));
              if (hitNet.docs.isNotEmpty) return hitNet.docs.first.id;
            } catch (_) {}
            return null;
          });
          final resolved = await Future.wait(nameFutures);
          deptIds.addAll(resolved.whereType<String>());
        }
      }

      final deptIdSet = deptIds.toSet();
      await _appendLeaderDepartmentIds(tid, uid, digits, deptIdSet);

      final uniqueIds = prefsGroupIds.isNotEmpty
          ? [
              ...prefsGroupIds,
              ...deptIdSet.where((id) => !prefsGroupIds.contains(id)),
            ]
          : deptIdSet.toList();
      if (uniqueIds.isNotEmpty) {
        final cachedEntries = await _fetchDeptEntriesParallel(tid, uniqueIds);
        if (cachedEntries.isNotEmpty && mounted) {
          setState(() => _departments = cachedEntries);
        }
      } else if (mounted && _departments.isEmpty) {
        setState(() => _departments = const []);
      }

      unawaited(
        ChatHubOperations.syncUserChatProfile(
          tenantId: tid,
          departmentIds: uniqueIds,
          memberDocId: membro?.id,
        ).timeout(const Duration(seconds: 10)).catchError((_) {}),
      );

      final entries = await _fetchDeptEntriesParallel(tid, uniqueIds);
      if (!mounted) return;
      setState(() => _departments = entries);
      unawaited(_ensureDeptThreadsBackground(tid, uid, entries));
    } catch (e) {
      if (kDebugMode) debugPrint('chat grupos (membro): $e');
      if (!mounted) return;
      if (_departments.isEmpty) {
        setState(() => _departments = const []);
      }
    } finally {
      if (mounted && syncGen == _deptSyncGeneration) {
        setState(() => _departmentsLoading = false);
      }
    }
  }

  /// Ordenação «última atividade primeiro» (alinhado ao comportamento dos grupos na lista).
  static int _threadLastActivityMs(Map<String, dynamic> data) {
    for (final key in ['lastMessageAt', 'updatedAt', 'createdAt']) {
      final v = data[key];
      if (v is Timestamp) return v.millisecondsSinceEpoch;
    }
    return 0;
  }

  /// Evita mostrar UID Firebase como «nome» na lista (comum na web sem cache).
  static bool _looksLikeFirebaseUid(String raw) =>
      ChurchChatDisplayName.looksLikeFirebaseUid(raw);

  String? _titleFromThreadForPeer(Map<String, dynamic> data, String peer) {
    final titles = data['titlesByUid'];
    if (titles is! Map) return null;
    final t = titles[peer]?.toString().trim() ?? '';
    if (t.isEmpty || t == peer || _looksLikeFirebaseUid(t)) return null;
    return t;
  }

  String? _displayNameFromLocalCache(String peerUid) {
    for (final loc in _localConversations) {
      if (loc.peerUid != peerUid) continue;
      final n = loc.displayName.trim();
      if (n.isNotEmpty && !_looksLikeFirebaseUid(n)) return n;
    }
    return null;
  }

  String _resolvePeerDisplayName(
    String peer, {
    Map<String, dynamic>? threadData,
  }) {
    if (peer.isEmpty) return '';
    final memberRef = _peerMemberByUid[peer];
    if (memberRef != null) {
      final fromMember = _memberDisplayName(memberRef);
      if (fromMember.isNotEmpty) return fromMember;
    }
    if (threadData != null) {
      final fromThread = _titleFromThreadForPeer(threadData, peer);
      if (fromThread != null) return fromThread;
    }
    final fromLocal = _displayNameFromLocalCache(peer);
    if (fromLocal != null) return fromLocal;
    return '';
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
      peer = ChatHubOperations.otherUidInDmThread(doc.id, myUid) ?? '';
    }
    final resolved = _resolvePeerDisplayName(peer, threadData: data);
    if (resolved.isNotEmpty) return resolved;
    if (peer.isNotEmpty && _looksLikeFirebaseUid(peer)) {
      final tid = _resolvedTenantId;
      if (tid != null) {
        unawaited(_refreshPeerProfilesForAuthUids(tid, {peer}));
      }
      return ChurchChatDisplayName.fallbackMember;
    }
    return ChurchChatDisplayName.fallbackMember;
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
    final auth = (ref.data['authUid'] ?? ref.data['firebaseUid'] ?? '')
        .toString()
        .trim();
    return ChurchChatDisplayName.fromMemberData(
      ref.data,
      authUid: auth.isNotEmpty ? auth : ref.authUid,
      memberDocId: ref.memberId,
    );
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
        title: Text(n == 1 ? 'Limpar conversa?' : 'Limpar conversas?'),
        content: Text(
          'Apaga $label por completo no Firebase e no armazenamento '
          '(mensagens, fotos e vídeos) para TODOS os participantes. '
          'Esta ação não pode ser desfeita.',
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
            child: Text(n == 1 ? 'Limpar tudo' : 'Limpar ($n)'),
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
    final purged = await ChatHubOperations.purgeThreadMessagesCompletely(
      tenantId: tenantId,
      threadId: threadId,
    );
    await ChurchChatLocalConversations.remove(
      tenantId: tenantId,
      threadId: threadId,
    );
    // Também some da lista pessoal (além do purge global).
    await ChurchChatMemberPrefs.setHiddenDmThread(
      tenantId: tenantId,
      threadId: threadId,
      hide: true,
    );
    if (!mounted) return;
    if (!purged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível limpar a conversa. Verifique a rede e tente de novo.',
          ),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conversa limpa no Firebase e no armazenamento.'),
      ),
    );
  }

  Future<void> _deleteGroupThreadWithConfirm({
    required String tenantId,
    required String threadId,
    required String title,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir grupo?'),
        content: Text(
          'Apaga o histórico de «$title» para todos os membros. '
          'Esta ação não pode ser desfeita.',
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
            child: const Text('Excluir grupo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await ChatHubOperations.deleteGroupThread(
      tenantId: tenantId,
      threadId: threadId,
    );
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível excluir o grupo. Verifique a sua permissão ou tente de novo.',
          ),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grupo excluído.')),
    );
  }

  Future<void> _commitBulkHideSelectedDmThreads(String tenantId) async {
    final ids = _selectedDmThreadIds.toList();
    if (ids.isEmpty) return;
    if (!await _confirmHideConversations(ids.length)) return;
    var purged = 0;
    for (final id in ids) {
      final ok = await ChatHubOperations.purgeThreadMessagesCompletely(
        tenantId: tenantId,
        threadId: id,
      );
      if (ok) purged++;
      await ChurchChatLocalConversations.remove(
        tenantId: tenantId,
        threadId: id,
      );
      await ChurchChatMemberPrefs.setHiddenDmThread(
        tenantId: tenantId,
        threadId: id,
        hide: true,
      );
    }
    if (!mounted) return;
    setState(_clearDmSelectUi);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          purged == ids.length
              ? '$purged conversa(s) limpa(s) no Firebase e no armazenamento.'
              : '$purged de ${ids.length} conversa(s) limpa(s). Verifique a rede.',
        ),
      ),
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
    if (!_dmSelectMode) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Toque para marcar conversas',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: visibleCount == 0 ? null : _toggleDmSelectMode,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: ThemeCleanPremium.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: const Text('Cancelar'),
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
    required String memberRole,
    Map<String, dynamic>? departmentDocData,
  }) async {
    final cpf = widget.cpf.replaceAll(RegExp(r'\D'), '');
    final canDeleteGroup = isDepartment &&
        ChurchChatModeration.canDeleteGroupConversation(
          memberRole,
          departmentData: departmentDocData,
          memberCpfDigits: cpf,
        );
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
                if (!isDepartment) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: const Text('Limpar conversa'),
                    subtitle: const Text(
                      'Apaga mensagens, fotos e vídeos no Firebase para todos.',
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
                ] else if (canDeleteGroup) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_rounded,
                      color: ThemeCleanPremium.error,
                    ),
                    title: const Text('Excluir grupo'),
                    subtitle: const Text(
                      'Apaga o histórico para todos os membros (pastor, administrador ou secretário).',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _deleteGroupThreadWithConfirm(
                        tenantId: tenantId,
                        threadId: threadId,
                        title: title,
                      );
                    },
                  ),
                ],
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
              ],
            ),
          ),
        );
      },
    );
  }

  String? _chatHubModuleBarSubtitle() {
    return 'Grupos e privadas · tudo dentro do app';
  }

  Future<void> _onChatHubProfilePhotoTap(String tid, String uidMe) async {
    await showChurchChatProfilePhotoSheet(
      context,
      tenantId: tid,
      cpfDigits: widget.cpf,
    );
    if (!mounted || uidMe.isEmpty) return;
    unawaited(_refreshPeerProfilesForAuthUids(tid, {uidMe}));
  }

  Future<void> _onChatHubMuteTap(String tid) async {
    final next = !_chatPushEnabled;
    await ChurchChatNotificationPrefs.setChatPushEnabled(
      enabled: next,
      tenantId: tid,
    );
    if (mounted) setState(() => _chatPushEnabled = next);
  }

  bool get _canSendBroadcast =>
      AppPermissions.canSendChurchBroadcast(
        widget.role,
        permissions: widget.permissions,
      );

  Future<void> _openBroadcastSheet(String tid) async {
    await showChurchChatBroadcastSheet(
      context,
      tenantId: tid,
      role: widget.role,
      permissions: widget.permissions,
      departmentOptions: _departments
          .map((d) => (id: d.id, name: d.name))
          .toList(),
    );
  }

  bool _useWhatsAppSplitLayout(BuildContext context) =>
      kIsWeb &&
      widget.embeddedInShell &&
      MediaQuery.sizeOf(context).width >= 900;

  void _openChatThreadPage({
    required String tid,
    required String threadId,
    required String title,
    required bool isDepartment,
    String? peerUid,
    String? departmentId,
    String? initialDraftText,
  }) {
    if (_useWhatsAppSplitLayout(context)) {
      setState(() {
        _splitSelected = _SplitThreadSelection(
          threadId: threadId,
          title: title,
          isDepartment: isDepartment,
          peerUid: peerUid,
          departmentId: departmentId,
          initialDraftText: initialDraftText,
        );
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tid,
          threadId: threadId,
          title: title,
          isDepartment: isDepartment,
          peerUid: peerUid,
          departmentId: departmentId,
          memberRole: widget.role,
          memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
          initialDraftText: initialDraftText,
        ),
      ),
    );
  }

  Widget _buildWhatsAppWebSplit(String tid, Widget listPanel) {
    final sel = _splitSelected;
    return Material(
      color: ChurchChatWhatsAppTheme.hubBackground,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 400,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: listPanel,
            ),
          ),
          Expanded(
            child: sel == null
                ? const ChurchChatWhatsAppSplitEmptyPane()
                : ChurchChatThreadPage(
                    key: ValueKey(sel.threadId),
                    tenantId: tid,
                    threadId: sel.threadId,
                    title: sel.title,
                    isDepartment: sel.isDepartment,
                    peerUid: sel.peerUid,
                    departmentId: sel.departmentId,
                    memberRole: widget.role,
                    memberCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
                    initialDraftText: sel.initialDraftText,
                    embeddedInSplitPanel: true,
                    onSplitPanelClose: () =>
                        setState(() => _splitSelected = null),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tid = _resolvedTenantId;
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (tid == null || uid == null) {
      return ColoredBox(
        color: Colors.white,
        child: YahwehSkeletonLoading.chatThreads(),
      );
    }

    final shellFullscreen = widget.onShellBack != null;
    /// Painel web embutido: ocupa toda a área útil (não simula telefone 440px).
    final webPanelEmbedded = kIsWeb && widget.embeddedInShell;
    final webPhoneFrame = kIsWeb &&
        !widget.embeddedInShell &&
        MediaQuery.sizeOf(context).width >= 720;

    Widget hubCore = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shellFullscreen)
          ChurchEmbeddedModuleBar(
            title: YahwehContactButtonLabels.yahwehChat,
            icon: kChurchShellNavEntries[ChurchShellIndices.chatIgreja].icon,
            accent: kChurchShellNavEntries[ChurchShellIndices.chatIgreja].accent,
            onBack: widget.onShellBack!,
            subtitle: _chatHubModuleBarSubtitle(),
            actions: [
              if (_canSendBroadcast)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Transmissão',
                  onPressed: () => _openBroadcastSheet(tid),
                  icon: const Icon(Icons.campaign_rounded,
                      color: Colors.white, size: 22),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Nova conversa',
                onPressed: () => _openPickPeer(context, tid, uid),
                icon: const Icon(Icons.add_comment_rounded,
                    color: Colors.white, size: 22),
              ),
              _ChatHubOverflowMenu(
                chatPushEnabled: _chatPushEnabled,
                onMuteTap: () => _onChatHubMuteTap(tid),
                onAlertModeTap: _openChatAlertModeSheet,
                onProfilePhotoTap: () =>
                    _onChatHubProfilePhotoTap(tid, uid),
                onBroadcastTap:
                    _canSendBroadcast ? () => _openBroadcastSheet(tid) : null,
                iconColor: Colors.white,
              ),
            ],
          )
        else
          _WhatsAppStyleChatHubHeader(
            chatPushEnabled: _chatPushEnabled,
            onMuteTap: () => _onChatHubMuteTap(tid),
            onNewDm: () => _openPickPeer(context, tid, uid),
            onAlertModeTap: _openChatAlertModeSheet,
            onProfilePhotoTap: () => _onChatHubProfilePhotoTap(tid, uid),
            onBroadcastTap:
                _canSendBroadcast ? () => _openBroadcastSheet(tid) : null,
          ),
        ChurchChatPendingStatusBanner(
          tenantId: tid,
          compact: true,
          alwaysOfferClear: false,
          role: widget.role,
          permissions: widget.permissions,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
          child: _PremiumHubTabBar(
            controller: _hubTabController,
            dense: true,
          ),
        ),
        AnimatedBuilder(
          animation: _hubTabController,
          builder: (context, _) {
            final i = _hubTabController.index;
            if (i == 0) {
              return _ChatSearchBar(controller: _searchCtrl);
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
    );

    if (webPanelEmbedded || webPhoneFrame) {
      hubCore = Material(
        color: const Color(0xFFF0F2F5),
        child: hubCore,
      );
    }

    if (webPanelEmbedded) {
      if (_useWhatsAppSplitLayout(context)) {
        return SizedBox.expand(
          child: _buildWhatsAppWebSplit(tid, hubCore),
        );
      }
      return SizedBox.expand(child: hubCore);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: churchChatHubBackgroundGradient,
      ),
      child: webPhoneFrame
          ? Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).width * 0.92)
                      .clamp(480.0, 720.0),
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.92)
                      .clamp(640.0, 960.0),
                ),
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: hubCore,
                ),
              ),
            )
          : hubCore,
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
            if (snap.hasData && snap.data!.docs.isNotEmpty) {
              _lastGoodChatThreadsSnap = snap.data;
              unawaited(
                ChurchChatThreadsListCache.saveFromSnapshot(tid, snap.data!),
              );
            } else if (snap.hasError &&
                _lastGoodChatThreadsSnap != null &&
                _lastGoodChatThreadsSnap!.docs.isNotEmpty) {
              unawaited(_primeConversasListFromFallback(tid));
            }
            final snapForList = snap.hasData && snap.data!.docs.isNotEmpty
                ? snap.data!
                : (_lastGoodChatThreadsSnap ?? snap.data);
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
                        ChurchPanelResilientLoadBanner(
                          hasLocalData: false,
                          isSyncing: false,
                          errorTitle:
                              'Não foi possível carregar a lista de conversas',
                          error: streamError,
                          onRetry: _pullRefreshConversas,
                        ),
                      ],
                    ),
                  );
                }
                final hasInstantList = snapForList != null &&
                    snapForList.docs.isNotEmpty;
                final hasLocalFallback = _localConversations.isNotEmpty;
                if (snap.connectionState == ConnectionState.waiting &&
                    !hasInstantList &&
                    !hasLocalFallback &&
                    !_conversasListPrimed &&
                    !_conversasSkeletonTimedOut) {
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

                return ValueListenableBuilder<String>(
                  valueListenable: _debouncedConversasSearch,
                  builder: (context, q, _) {
                final threads = <Widget>[];
                final ql = q.toLowerCase();

                if (streamError != null && snapForList != null) {
                  threads.add(
                    ChurchPanelResilientLoadBanner(
                      hasLocalData: true,
                      isSyncing: false,
                      showStaleCache: true,
                      errorTitle:
                          'Não foi possível sincronizar a lista de conversas',
                      onRetry: _pullRefreshConversas,
                      staleMessage:
                          'Modo offline — última lista de conversas guardada. Puxe para atualizar.',
                    ),
                  );
                  threads.add(const SizedBox(height: 10));
                }

                threads.add(
                  ChurchChatWhatsAppFilterChips<_HubConversasFilter>(
                    selected: _conversasFilter,
                    onSelected: (f) => setState(() => _conversasFilter = f),
                    items: const [
                      _HubConversasFilter.all,
                      _HubConversasFilter.unread,
                      _HubConversasFilter.favorites,
                      _HubConversasFilter.groups,
                    ],
                    labelFor: (f) => switch (f) {
                      _HubConversasFilter.all => 'Tudo',
                      _HubConversasFilter.unread => 'Não lidas',
                      _HubConversasFilter.favorites => 'Favoritas',
                      _HubConversasFilter.groups => 'Grupos',
                      _HubConversasFilter.archived => 'Arquivadas',
                    },
                  ),
                );

                final conversasFiltered =
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in dmDocs) {
                  final isDept = _docIsDepartmentThread(doc);
                  final data = doc.data();
                  if (!isDept &&
                      !ChatHubOperations.threadHasListableConversation(
                        data,
                        threadId: doc.id,
                      )) {
                    continue;
                  }
                  if (!isDept && prefs.isHiddenDmThread(doc.id)) continue;
                  if (_conversasFilter == _HubConversasFilter.archived) {
                    if (!prefs.isArchived(doc.id)) continue;
                  }
                  if (!ChatHubOperations.userParticipatesInThread(
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
                    var peer = peers.where((p) => p != uid).firstOrNull;
                    peer ??= ChatHubOperations.otherUidInDmThread(doc.id, uid);
                    if (peer == null || peer.isEmpty) continue;
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
                  final au = _chatHubThreadIsUnreadForUser(a.data(), uid);
                  final bu = _chatHubThreadIsUnreadForUser(b.data(), uid);
                  if (au != bu) return au ? -1 : 1;
                  final ta = _threadLastActivityMs(a.data());
                  final tb = _threadLastActivityMs(b.data());
                  final c = tb.compareTo(ta);
                  if (c != 0) return c;
                  return _threadListSortTitle(a, uid)
                      .toLowerCase()
                      .compareTo(_threadListSortTitle(b, uid).toLowerCase());
                });
                _scheduleUnreadCountsLoad(
                  tid,
                  uid,
                  conversasFiltered.map((d) => d.id).toList(),
                  conversasFiltered,
                );

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
                  case _HubConversasFilter.groups:
                    sel = conversasFiltered.where(_docIsDepartmentThread);
                    break;
                  case _HubConversasFilter.archived:
                    break;
                  case _HubConversasFilter.all:
                    break;
                }
                final displayed = sel.toList();
                final displayedIds = displayed.map((d) => d.id).toSet();
                final localOnly = <ChurchChatLocalConversationEntry>[];
                final mergeLocalCache =
                    q.isEmpty && _conversasFilter == _HubConversasFilter.all;
                if (mergeLocalCache) {
                  for (final loc in _localConversations) {
                    if (displayedIds.contains(loc.threadId)) continue;
                    if (prefs.isHiddenDmThread(loc.threadId)) continue;
                    if (loc.peerUid.isNotEmpty &&
                        prefs.isBlockedPeer(loc.peerUid)) {
                      continue;
                    }
                    localOnly.add(loc);
                  }
                }
                final displayedDmThreadIds = displayed
                    .where((d) => !_docIsDepartmentThread(d))
                    .map((d) => d.id)
                    .toList();

                final deptOnlyEntries = <_DeptEntry>[];
                if (mergeLocalCache) {
                  for (final d in _departments) {
                    final threadId = ChatHubOperations.deptThreadId(d.id);
                    if (displayedIds.contains(threadId)) continue;
                    deptOnlyEntries.add(d);
                  }
                }

                threads.add(_buildDmSelectionToolbar(
                  displayed.length + localOnly.length + deptOnlyEntries.length,
                ));

                if (displayed.isEmpty &&
                    localOnly.isEmpty &&
                    deptOnlyEntries.isEmpty) {
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
                                    : _conversasFilter == _HubConversasFilter.groups
                                        ? 'Sem grupos de departamento.'
                                    : _conversasFilter == _HubConversasFilter.unread
                                    ? 'Sem mensagens não lidas.'
                                    : streamError != null &&
                                            (snapForList?.docs.isEmpty ?? true) &&
                                            !hasLocalFallback
                                        ? 'Não foi possível carregar. Puxe para baixo para atualizar.'
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
                  final unreadDocs = displayed
                      .where(
                        (d) => _chatHubThreadIsUnreadForUser(d.data(), uid),
                      )
                      .toList();
                  final readDocs = displayed
                      .where(
                        (d) => !_chatHubThreadIsUnreadForUser(d.data(), uid),
                      )
                      .toList();
                  if (unreadDocs.isNotEmpty) {
                    threads.add(_sectionHeader('Não lidas'));
                    _appendFirestoreConversationRows(
                      threads,
                      context,
                      tid,
                      uid,
                      unreadDocs,
                      prefs,
                      photoByPeer,
                      memberByPeer,
                    );
                  }
                  if (readDocs.isNotEmpty) {
                    threads.add(_sectionHeader(
                      unreadDocs.isNotEmpty ? 'Recentes' : 'Conversas',
                    ));
                    _appendFirestoreConversationRows(
                      threads,
                      context,
                      tid,
                      uid,
                      readDocs,
                      prefs,
                      photoByPeer,
                      memberByPeer,
                    );
                  }
                  if (localOnly.isNotEmpty) {
                    _appendLocalConversationRows(
                      threads,
                      context,
                      tid,
                      uid,
                      localOnly,
                      prefs,
                      photoByPeer,
                      memberByPeer,
                    );
                  }
                  if (deptOnlyEntries.isNotEmpty) {
                    threads.add(_sectionHeader('Grupos de departamento'));
                    for (final d in deptOnlyEntries) {
                      threads.add(
                        _deptEntryOnlyChatRow(
                          context,
                          tid,
                          uid,
                          d,
                          prefs,
                        ),
                      );
                    }
                  }
                }

                final listView = RefreshIndicator(
                  onRefresh: _pullRefreshConversas,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                    itemCount: threads.length,
                    itemBuilder: (context, i) => threads[i],
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
          },
        );
  }

  Widget _buildContatosTab(BuildContext context, String tid, String uid) {
    return _AllMembersDirectoryView(
      key: const ValueKey('chat_hub_contatos_dir'),
      tenantId: tid,
      myUid: uid,
      filterCtrl: _membersFilterCtrl,
      role: widget.role,
      cpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
      onOpenDm: (peerUid, displayName) =>
          _startDmWithPeer(context, tid, uid, peerUid, displayName),
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

  Map<String, Map<String, dynamic>> _deptThreadDataById(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    final out = <String, Map<String, dynamic>>{};
    if (snap == null) return out;
    for (final d in snap.docs) {
      if (!d.id.startsWith('dept_')) continue;
      out[d.id] = d.data();
    }
    return out;
  }

  Widget _buildGruposTab(BuildContext context, String tid, String uid) {
    Widget buildPrefsAndList(Map<String, Map<String, dynamic>> deptThreadById) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchChatMemberPrefs.watch(tid),
      builder: (context, prefSnap) {
        final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
        return ValueListenableBuilder<String>(
          valueListenable: _debouncedDeptSearch,
          builder: (context, ql, _) {
        final filtered = _departments.where((d) {
          if (ql.isEmpty) {
            return true;
          }
          return d.name.toLowerCase().contains(ql);
        }).toList();

        if (filtered.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => _syncMemberDepartments(tid, forceServer: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
                if (_departmentsLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        size: 56,
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _departmentsLoading
                            ? 'A carregar grupos…'
                            : _departments.isEmpty
                                ? (_departmentsSoftError != null &&
                                        _departmentsSoftError!
                                            .trim()
                                            .isNotEmpty
                                    ? 'Não foi possível carregar os grupos. Verifique a rede e toque em Carregar grupos.'
                                    : (_chatHubSeesAllDepartmentGroups(
                                            widget.role, widget.permissions)
                                        ? 'Nenhum departamento cadastrado ainda. Crie departamentos no módulo Departamentos para aparecerem aqui como grupos.'
                                        : 'Sem grupos — faça parte de um departamento na sua ficha de membro.'))
                                : 'Nenhum grupo corresponde à pesquisa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_departmentsLoading &&
                          _departments.isEmpty &&
                          _departmentsSoftError != null &&
                          _departmentsSoftError!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _departmentsSoftError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (!_departmentsLoading && _departments.isEmpty) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => _syncMemberDepartments(
                            tid,
                            forceServer: true,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Carregar grupos'),
                        ),
                      ],
                    ],
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
          final threadId = ChatHubOperations.deptThreadId(d.id);
          return _DeptGroupPremiumStripCard(
            tenantId: tid,
            myUid: uid,
            entry: d,
            threadId: threadId,
            threadData: deptThreadById[threadId],
            reorderIndex: reorderIndex,
            onOpenChat: () {
              _openChatThreadPage(
                tid: tid,
                threadId: threadId,
                title: d.name,
                isDepartment: true,
                departmentId: d.id,
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
      },
    );
    }

    final threadStream = _chatThreadsStream;
    if (threadStream == null) {
      return buildPrefsAndList(_deptThreadDataById(_lastGoodChatThreadsSnap));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: threadStream,
      initialData: _lastGoodChatThreadsSnap,
      builder: (context, ts) => buildPrefsAndList(
        _deptThreadDataById(ts.data ?? _lastGoodChatThreadsSnap),
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
    if (peerUid.trim().isEmpty) return;
    final threadId = ChatHubOperations.dmThreadId(myUid, peerUid);
    var title = displayName.trim();
    if (title.isEmpty) title = 'Membro';

    unawaited(
      ChatHubOperations.ensureDmThreadResilient(
        tenantId: tid,
        uidA: myUid,
        uidB: peerUid,
        titleA: firebaseDefaultAuth.currentUser?.displayName ?? 'Eu',
        titleB: title,
      ).timeout(const Duration(seconds: 12)).catchError((_) => false),
    );

    if (!context.mounted) return;
    _openChatThreadPage(
      tid: tid,
      threadId: threadId,
      title: title,
      isDepartment: false,
      peerUid: peerUid,
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

  static const _hubRowDivider = Divider(
    height: 1,
    thickness: 1,
    color: Color(0xFFE5E7EB),
    indent: 72,
  );

  void _appendFirestoreConversationRows(
    List<Widget> out,
    BuildContext context,
    String tid,
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    for (var i = 0; i < docs.length; i++) {
      if (i > 0) out.add(_hubRowDivider);
      final doc = docs[i];
      out.add(
        _docIsDepartmentThread(doc)
            ? _deptChatRow(
                context,
                tid,
                uid,
                doc,
                prefs,
                memberByPeerUid,
              )
            : _dmChatRow(
                context,
                tid,
                uid,
                doc,
                prefs,
                photoByPeerUid,
                memberByPeerUid,
                selectionMode: _dmSelectMode,
                selected: _selectedDmThreadIds.contains(doc.id),
                onToggleSelected: () => _toggleDmThreadSelected(doc.id),
              ),
      );
    }
  }

  void _appendLocalConversationRows(
    List<Widget> out,
    BuildContext context,
    String tid,
    String uid,
    List<ChurchChatLocalConversationEntry> entries,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) out.add(_hubRowDivider);
      out.add(
        _dmChatRowFromLocal(
          context,
          tid,
          uid,
          entries[i],
          prefs,
          photoByPeerUid,
          memberByPeerUid,
        ),
      );
    }
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

  Widget _localConversationListRows(
    BuildContext context,
    String tid,
    String uid,
    List<ChurchChatLocalConversationEntry> entries,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.shade200,
              indent: 72,
            ),
          _dmChatRowFromLocal(
            context,
            tid,
            uid,
            entries[i],
            prefs,
            photoByPeerUid,
            memberByPeerUid,
          ),
        ],
      ],
    );
  }

  Widget _dmChatRowFromLocal(
    BuildContext context,
    String tid,
    String uid,
    ChurchChatLocalConversationEntry loc,
    ChurchChatMemberPrefsModel prefs,
    Map<String, String> photoByPeerUid,
    Map<String, ChurchChatMemberRef> memberByPeerUid,
  ) {
    final peer = loc.peerUid;
    if (peer.isEmpty) return const SizedBox.shrink();
    var fullTitle = _resolvePeerDisplayName(peer);
    if (fullTitle.isEmpty) {
      final locName = loc.displayName.trim();
      if (locName.isNotEmpty && !_looksLikeFirebaseUid(locName)) {
        fullTitle = locName;
      } else {
        fullTitle = ChurchChatDisplayName.fallbackMember;
      }
    }
    final rowTitle = _firstNameForChatRow(fullTitle);
    final preview = loc.lastMessage;
    final memberRef = memberByPeerUid[peer];
    final online = _peerOnlineByUid[peer] ?? false;
    return _chatTile(
      title: rowTitle,
      subtitle: preview,
      subtitleMaxLines: 2,
      timeLabel: _fmtTimeMs(loc.lastMessageAtMs),
      photo: ChurchChatPeerAvatar(
        tenantId: tid,
        peerAuthUid: peer,
        memberRef: memberRef,
        radius: 24,
      ),
      showPresence: true,
      online: online,
      isUnread: false,
      isFavorite: prefs.isFavorite(loc.threadId),
      isPinned: prefs.isPinned(loc.threadId),
      isMuted: prefs.isMutedThread(loc.threadId),
      onTap: () {
        _openChatThreadPage(
          tid: tid,
          threadId: loc.threadId,
          title: fullTitle,
          isDepartment: false,
          peerUid: peer,
        );
      },
    );
  }

  String _fmtTimeMs(int ms) {
    if (ms <= 0) return '';
    return _fmtTime(Timestamp.fromMillisecondsSinceEpoch(ms));
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
    var peer = peers.where((p) => p != uid).firstOrNull;
    peer ??= ChatHubOperations.otherUidInDmThread(doc.id, uid);
    if (peer == null || peer.isEmpty) return const SizedBox.shrink();
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
    final unreadCount =
        _unreadCountByThreadId[doc.id] ?? (isUnread ? 1 : 0);

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
      unreadCount: unreadCount,
      isFavorite: prefs.isFavorite(doc.id),
      isPinned: prefs.isPinned(doc.id),
      isMuted: prefs.isMutedThread(doc.id),
      isActive: _splitSelected?.threadId == doc.id,
      selectionMode: selectionMode,
      selected: selected,
      onTap: () {
        if (selectionMode) {
          onToggleSelected?.call();
          return;
        }
        _openChatThreadPage(
          tid: tid,
          threadId: doc.id,
          title: fullTitle,
          isDepartment: false,
          peerUid: peer,
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
              memberRole: widget.role,
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
              memberRole: widget.role,
            ),
    );
  }

  /// Grupo de departamento ainda sem thread indexada — aparece em «Conversas» (estilo WhatsApp).
  Widget _deptEntryOnlyChatRow(
    BuildContext context,
    String tid,
    String uid,
    _DeptEntry entry,
    ChurchChatMemberPrefsModel prefs,
  ) {
    final threadId = ChatHubOperations.deptThreadId(entry.id);
    return _chatTile(
      title: entry.name,
      subtitle: 'Toque para abrir o grupo',
      subtitleMaxLines: 1,
      timeLabel: '',
      photo: ChurchChatDepartmentAvatar(
        deptData: entry.deptData,
        fallbackName: entry.name,
        radius: 24,
      ),
      showPresence: false,
      isUnread: false,
      unreadCount: 0,
      isFavorite: prefs.isFavorite(threadId),
      isPinned: prefs.isPinned(threadId),
      isMuted: prefs.isMutedThread(threadId),
      onTap: () {
        _openChatThreadPage(
          tid: tid,
          threadId: threadId,
          title: entry.name,
          isDepartment: true,
          departmentId: entry.id,
        );
      },
      onLongPress: () => _showThreadActionsSheet(
        context: context,
        tenantId: tid,
        threadId: threadId,
        title: entry.name,
        isDepartment: true,
        peerUid: null,
        prefs: prefs,
        memberRole: widget.role,
        departmentDocData: entry.deptData,
      ),
      onMoreTap: () => _showThreadActionsSheet(
        context: context,
        tenantId: tid,
        threadId: threadId,
        title: entry.name,
        isDepartment: true,
        peerUid: null,
        prefs: prefs,
        memberRole: widget.role,
        departmentDocData: entry.deptData,
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
    final unreadCount =
        _unreadCountByThreadId[doc.id] ?? (isUnread ? 1 : 0);

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
      unreadCount: unreadCount,
      isFavorite: prefs.isFavorite(doc.id),
      isPinned: prefs.isPinned(doc.id),
      isMuted: prefs.isMutedThread(doc.id),
      isActive: _splitSelected?.threadId == doc.id,
      onTap: () {
        _openChatThreadPage(
          tid: tid,
          threadId: doc.id,
          title: fullTitle,
          isDepartment: true,
          departmentId: deptId,
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
        memberRole: widget.role,
        departmentDocData: deptEntry?.deptData ?? data,
      ),
      onMoreTap: () => _showThreadActionsSheet(
        context: context,
        tenantId: tid,
        threadId: doc.id,
        title: fullTitle,
        isDepartment: true,
        peerUid: null,
        prefs: prefs,
        memberRole: widget.role,
        departmentDocData: deptEntry?.deptData ?? data,
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
    int unreadCount = 0,
    bool isFavorite = false,
    bool isPinned = false,
    bool isMuted = false,
    bool selectionMode = false,
    bool selected = false,
    bool isActive = false,
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
  final rowBg = isActive
        ? ChurchChatWhatsAppTheme.activeRowBackground
        : isUnread
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
                      if (isUnread && unreadCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _whatsappUnreadBadge(unreadCount),
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
    final churchId = ChurchRepository.churchId(tid.trim());
    QuerySnapshot<Map<String, dynamic>>? q;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      q = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchUiCollections.membros(churchId).limit(120).get(),
        maxAttempts: 4,
      ).timeout(const Duration(seconds: 14));
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
    await ChatHubOperations.ensureDmThread(
      tenantId: tid,
      uidA: uid,
      uidB: picked.uid,
      titleA: firebaseDefaultAuth.currentUser?.displayName ?? 'Eu',
      titleB: picked.name,
    );
    final threadId = ChatHubOperations.dmThreadId(uid, picked.uid);
    if (!context.mounted) return;
    _openChatThreadPage(
      tid: tid,
      threadId: threadId,
      title: picked.name,
      isDepartment: false,
      peerUid: picked.uid,
    );
  }
}

class _ChatSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final bool compact;

  const _ChatSearchBar({
    required this.controller,
    this.compact = true,
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
    final compact = widget.compact;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, compact ? 4 : 10),
      child: TextField(
        controller: widget.controller,
        style: TextStyle(
          color: ThemeCleanPremium.onSurface,
          fontWeight: FontWeight.w500,
          fontSize: compact ? 14 : 15,
        ),
        decoration: InputDecoration(
          hintText: 'Pesquisar ou começar uma nova conversa',
          hintStyle: TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            fontSize: compact ? 14 : 15,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: compact ? 20 : 24,
            color: const Color(0xFF128C7E),
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.clear_rounded,
                    size: compact ? 20 : 22,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                  onPressed: widget.controller.clear,
                )
              : null,
          filled: true,
          fillColor: ThemeCleanPremium.cardBackground,
          isDense: compact,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 8 : 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            borderSide: const BorderSide(color: Color(0xFF128C7E), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _PremiumHubTabBar extends StatelessWidget {
  final TabController controller;
  final bool dense;

  const _PremiumHubTabBar({
    required this.controller,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 380;
    final labelSize = dense
        ? (narrow ? 10.0 : 10.5)
        : (narrow ? 10.5 : 11.5);
    final iconSize = dense
        ? (narrow ? 15.0 : 16.0)
        : (narrow ? 16.0 : 17.0);
    final tabH = dense
        ? (narrow ? 30.0 : 32.0)
        : (narrow ? 42.0 : 46.0);

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

    final outerPad = dense ? 0.0 : 1.5;
    final outerRadius = dense ? 10.0 : 17.5;
    return Container(
      padding: EdgeInsets.all(outerPad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        color: dense ? ThemeCleanPremium.cardBackground : null,
        gradient: dense ? null : churchChatWhatsPremiumLinearGradient,
        border: dense
            ? Border.all(color: Colors.grey.shade300, width: 0.8)
            : null,
        boxShadow: dense
            ? null
            : [
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
        padding: EdgeInsets.all(dense ? 2 : 4),
        decoration: BoxDecoration(
          color: dense ? Colors.transparent : ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(dense ? 10 : 16),
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          tabAlignment: TabAlignment.fill,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(dense ? 8 : 12),
            color: dense ? const Color(0xFF128C7E) : null,
            gradient: dense ? null : churchChatWhatsPremiumLinearGradient,
            boxShadow: dense
                ? null
                : [
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: TextField(
        controller: widget.controller,
        style: TextStyle(
          color: ThemeCleanPremium.onSurface,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            fontSize: 14,
          ),
          prefixIcon: Icon(widget.icon, size: 20, color: const Color(0xFF128C7E)),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.clear_rounded,
                    size: 20,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: ThemeCleanPremium.cardBackground,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF128C7E), width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Linha unificada — Firestore `membros` ou cache `_panel_cache/members_directory`.
class _ChatDirectoryMemberRow {
  const _ChatDirectoryMemberRow({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;
}

class _AllMembersDirectoryView extends StatefulWidget {
  final String tenantId;
  final String myUid;
  final TextEditingController filterCtrl;
  final String role;
  final String cpfDigits;
  final Future<void> Function(String peerUid, String displayName) onOpenDm;

  const _AllMembersDirectoryView({
    super.key,
    required this.tenantId,
    required this.myUid,
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
  List<_ChatDirectoryMemberRow> _rows = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _openingDm = false;
  Map<String, bool> _presenceOnlineByUid = {};
  Timer? _presencePollTimer;
  Timer? _filterDebounce;
  Timer? _loadCapTimer;
  ChurchChatMemberPrefsModel _prefs = const ChurchChatMemberPrefsModel();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  StreamSubscription<MembersDirectorySnapshot>? _directorySub;

  String get _churchId => ChurchRepository.churchId(widget.tenantId.trim());

  void _applyDirectoryRows(MembersDirectorySnapshot directory) {
    if (!directory.hasEntries) return;
    final rows = _rowsFromDirectory(directory);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _loadFailed = false;
    });
    _schedulePresencePoll();
    final refs = rows
        .map((r) {
          final auth = _authUidFromMemberData(r.docId, r.data);
          if (auth == null) return null;
          return churchChatMemberRefFromMemberDoc(r.docId, r.data);
        })
        .whereType<ChurchChatMemberRef>()
        .toList();
    ChurchGalleryPhotoWarmup.warmBytesForChatRefs(widget.tenantId, refs);
  }

  void _onFilterChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    widget.filterCtrl.addListener(_onFilterChanged);
    _prefsSub = ChurchChatMemberPrefs.watch(widget.tenantId).listen((snap) {
      if (!mounted) return;
      setState(() => _prefs = ChurchChatMemberPrefs.parse(snap));
    });
    final mem = MembersDirectorySnapshotService.peekMemory(_churchId);
    if (mem == null) {
      final alt = MembersDirectorySnapshotService.peekMemory(widget.tenantId);
      if (alt != null && alt.hasEntries) {
        _rows = _rowsFromDirectory(alt);
        _loading = false;
      }
    } else if (mem.hasEntries) {
      _rows = _rowsFromDirectory(mem);
      _loading = false;
    }
    final ram = ChurchMembersLoadService.peekRam(_churchId);
    if (_rows.isEmpty && ram != null && ram.isNotEmpty) {
      _rows = ram
          .map((d) => _ChatDirectoryMemberRow(docId: d.id, data: d.data()))
          .toList();
      _loading = false;
    }
    unawaited(_warmContatosFromModuleCache());
    _directorySub =
        MembersDirectorySnapshotService.watch(_churchId).listen((dir) {
      if (dir.hasEntries) _applyDirectoryRows(dir);
    });
    _loadCapTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _loadFailed = _rows.isEmpty;
      });
    });
    unawaited(_loadInstantFromCache());
    unawaited(_load());
  }

  /// RAM/prefs — lista de contatos sem esperar repair de acesso.
  Future<void> _warmContatosFromModuleCache() async {
    try {
      await YahwehModuleCaches.membros.warmUp(widget.tenantId);
      if (!mounted || _rows.isNotEmpty) return;
      final docs = YahwehModuleCaches.membros.docs;
      if (docs.isEmpty) return;
      final rows = docs
          .map((d) => _ChatDirectoryMemberRow(docId: d.id, data: d.data()))
          .toList();
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _loadFailed = false;
      });
      _schedulePresencePoll();
    } catch (_) {}
  }

  /// Nomes + fotos do `_panel_cache/members_directory` — sem esperar `membrosRecent(600)`.
  Future<void> _loadInstantFromCache() async {
    try {
      var directory =
          await MembersDirectorySnapshotService.readOnce(_churchId);
      if (!directory.hasEntries) {
        directory =
            await MembersDirectorySnapshotService.readOnce(widget.tenantId);
      }
      if (!mounted || !directory.hasEntries) return;
      _applyDirectoryRows(directory);
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.filterCtrl.removeListener(_onFilterChanged);
    _filterDebounce?.cancel();
    _loadCapTimer?.cancel();
    _prefsSub?.cancel();
    _directorySub?.cancel();
    _presencePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _onMemberTap(String auth, String label) async {
    if (_openingDm || auth.isEmpty) return;
    setState(() => _openingDm = true);
    try {
      await widget.onOpenDm(auth, label);
    } finally {
      if (mounted) setState(() => _openingDm = false);
    }
  }

  void _schedulePresencePoll() {
    _presencePollTimer?.cancel();
    final authUids = <String>{};
    for (final row in _rows) {
      final auth = _authUidFromMemberData(row.docId, row.data);
      if (auth == null || auth.isEmpty || auth == widget.myUid) continue;
      authUids.add(auth);
    }
    if (authUids.isEmpty) {
      _presenceOnlineByUid = {};
      return;
    }
    Future<void> poll() async {
      final online = await ChatMessagingEngine.fetchPresenceOnlineMap(
        churchId: _churchId,
        authUids: authUids,
      );
      if (!mounted) return;
      setState(() => _presenceOnlineByUid = online);
    }

    unawaited(poll());
    _presencePollTimer = Timer.periodic(
      const Duration(seconds: 22),
      (_) => unawaited(poll()),
    );
  }

  static String? _authUidFromMemberData(String docId, Map<String, dynamic> d) {
    var auth = (d['authUid'] ?? d['firebaseUid'] ?? '').toString().trim();
    if (auth.isEmpty &&
        docId.length >= 20 &&
        docId.length <= 128 &&
        !RegExp(r'^\d{11}$').hasMatch(docId)) {
      auth = docId;
    }
    return auth.isEmpty ? null : auth;
  }

  List<_ChatDirectoryMemberRow> _rowsFromDirectory(
    MembersDirectorySnapshot directory,
  ) {
    return directory.entries
        .where((e) => e.memberDocId.isNotEmpty)
        .map(
          (e) => _ChatDirectoryMemberRow(
            docId: e.memberDocId,
            data: e.toMemberDataMap(),
          ),
        )
        .toList();
  }

  Future<void> _load() async {
    final hadRows = _rows.isNotEmpty;
    if (!hadRows && mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    var rows = <_ChatDirectoryMemberRow>[];
    var fetchFailed = false;
    final churchId = _churchId;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      try {
        var directory =
            await MembersDirectorySnapshotService.readOnce(churchId);
        if (!directory.hasEntries) {
          directory =
              await MembersDirectorySnapshotService.readOnce(widget.tenantId);
        }
        if (directory.hasEntries) {
          rows = _rowsFromDirectory(directory);
        }
      } catch (_) {
        fetchFailed = true;
      }

      if (rows.isEmpty) {
        try {
          final warmed =
              await MembersDirectorySnapshotService.warmFromCallableIfStale(
            churchId,
          ).timeout(const Duration(seconds: 18));
          if (warmed.hasEntries) {
            rows = _rowsFromDirectory(warmed);
          }
        } catch (_) {
          fetchFailed = true;
        }
      }

      if (rows.isEmpty) {
        try {
          final result = await FirestoreWebGuard.runWithWebRecovery(
            () => ChurchMembersLoadService.load(
              seedTenantId: churchId,
              limit: 80,
            ),
            maxAttempts: 4,
          ).timeout(PanelResilientLoad.queryCap);
          if (result.docs.isNotEmpty) {
            rows = result.docs
                .map((d) => _ChatDirectoryMemberRow(docId: d.id, data: d.data()))
                .toList();
          }
        } catch (_) {
          fetchFailed = true;
        }
      }

      if (rows.isEmpty) {
        try {
          final snap = await FirestoreWebGuard.runWithWebRecovery(
            () => ChurchTenantResilientReads.membrosRecent(
              churchId,
              limit: 80,
            ),
            maxAttempts: 4,
          ).timeout(PanelResilientLoad.queryCap);
          rows = snap.docs
              .map((d) => _ChatDirectoryMemberRow(docId: d.id, data: d.data()))
              .toList();
        } catch (_) {
          fetchFailed = true;
        }
      }
    } catch (_) {
      fetchFailed = true;
    } finally {
      if (!mounted) return;
      _loadCapTimer?.cancel();
      setState(() {
        if (rows.isNotEmpty) _rows = rows;
        _loading = false;
        _loadFailed = _rows.isEmpty && fetchFailed;
      });
    }

    if (_rows.isNotEmpty) {
      _schedulePresencePoll();
      final refs = _rows
          .map((r) {
            final auth = _authUidFromMemberData(r.docId, r.data);
            if (auth == null) return null;
            return churchChatMemberRefFromMemberDoc(r.docId, r.data);
          })
          .whereType<ChurchChatMemberRef>()
          .toList();
      ChurchGalleryPhotoWarmup.warmBytesForChatRefs(
        churchId,
        refs,
      );
    }
  }

  List<_ChatDirectoryMemberRow> _filteredMemberRows() {
    final q = widget.filterCtrl.text.trim().toLowerCase();
    final out = <_ChatDirectoryMemberRow>[];
    for (final row in _rows) {
      final d = row.data;
      final st = (d['STATUS'] ?? d['status'] ?? 'ativo').toString().toLowerCase();
      if (st != 'ativo') continue;
      final auth = _authUidFromMemberData(row.docId, d);
      if (auth == null || auth == widget.myUid) continue;
      if (_prefs.isBlockedPeer(auth)) continue;
      final label = ChurchChatDisplayName.fromMemberData(
        d,
        authUid: auth,
        memberDocId: row.docId,
      );
      if (q.isNotEmpty) {
        if (!label.toLowerCase().contains(q) &&
            !auth.toLowerCase().contains(q)) {
          continue;
        }
      }
      out.add(row);
    }
    return out;
  }

  List<_ChatDirectoryMemberRow> _sortMembersOnlineFirst(
    List<_ChatDirectoryMemberRow> members,
    Map<String, bool> presenceOnlineByUid,
  ) {
    bool online(String uid) => presenceOnlineByUid[uid] ?? false;

    final copy = List<_ChatDirectoryMemberRow>.from(members);
    copy.sort((a, b) {
      final da = a.data;
      final db = b.data;
      final authA = _authUidFromMemberData(a.docId, da) ?? '';
      final authB = _authUidFromMemberData(b.docId, db) ?? '';
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
    final rows = _sortMembersOnlineFirst(
      _filteredMemberRows(),
      _presenceOnlineByUid,
    );
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
                      _loadFailed
                          ? 'Não foi possível listar membros. Puxe para atualizar.'
                          : _rows.isEmpty
                              ? 'Nenhum membro ativo com acesso ao app.'
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
                    final row = rows[i];
                    final d = row.data;
                    final auth = _authUidFromMemberData(row.docId, d) ?? '';
                    final label = ChurchChatDisplayName.fromMemberData(
                      d,
                      authUid: auth,
                      memberDocId: row.docId,
                    );
                    final on = _presenceOnlineByUid[auth] ?? false;
                    final photoUrl = imageUrlFromMap(d);
                    return Material(
                      color: on
                          ? ThemeCleanPremium.primary.withValues(alpha: 0.05)
                          : Colors.white,
                      child: InkWell(
                        onTap: _openingDm
                            ? null
                            : () => unawaited(_onMemberTap(auth, label)),
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
                                        memberId: row.docId,
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
  }
}

/// Cartão em **faixa** (lista vertical) — evita `Column` + `Expanded` + `Spacer`
/// dentro de altura não limitada (causava layout inválido / área cinza na web).
class _DeptGroupPremiumStripCard extends StatelessWidget {
  final String tenantId;
  final String myUid;
  final String threadId;
  final _DeptEntry entry;
  final Map<String, dynamic>? threadData;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMembers;
  /// Índice na [SliverReorderableList]; `null` = sem arrastar.
  final int? reorderIndex;

  const _DeptGroupPremiumStripCard({
    required this.tenantId,
    required this.myUid,
    required this.threadId,
    required this.entry,
    this.threadData,
    required this.onOpenChat,
    required this.onOpenMembers,
    this.reorderIndex,
  });

  @override
  Widget build(BuildContext context) {
    final data = threadData;
    final unreadFlag = data != null
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
                              right: -4,
                              top: -4,
                              child: _GroupStripUnreadBadge(
                                tenantId: tenantId,
                                threadId: threadId,
                                myUid: myUid,
                                threadData: data,
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
                              _GroupStripUnreadBadge(
                                tenantId: tenantId,
                                threadId: threadId,
                                myUid: myUid,
                                threadData: data,
                                showLabel: true,
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
  }
}

/// Cabeçalho fino estilo WhatsApp — título + nova conversa + menu (⋮).
class _WhatsAppStyleChatHubHeader extends StatelessWidget {
  final bool chatPushEnabled;
  final VoidCallback onMuteTap;
  final VoidCallback onNewDm;
  final VoidCallback onAlertModeTap;
  final VoidCallback onProfilePhotoTap;
  final VoidCallback? onBroadcastTap;

  const _WhatsAppStyleChatHubHeader({
    required this.chatPushEnabled,
    required this.onMuteTap,
    required this.onNewDm,
    required this.onAlertModeTap,
    required this.onProfilePhotoTap,
    this.onBroadcastTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF128C7E),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Text(
                'Conversas',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (onBroadcastTap != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Transmissão',
                  onPressed: onBroadcastTap,
                  icon: const Icon(Icons.campaign_rounded,
                      color: Colors.white, size: 24),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Nova conversa',
                onPressed: onNewDm,
                icon: const Icon(Icons.add_comment_rounded,
                    color: Colors.white, size: 24),
              ),
              _ChatHubOverflowMenu(
                chatPushEnabled: chatPushEnabled,
                onMuteTap: onMuteTap,
                onAlertModeTap: onAlertModeTap,
                onProfilePhotoTap: onProfilePhotoTap,
                onBroadcastTap: onBroadcastTap,
                iconColor: Colors.white,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHubOverflowMenu extends StatelessWidget {
  final bool chatPushEnabled;
  final VoidCallback onMuteTap;
  final VoidCallback onAlertModeTap;
  final VoidCallback onProfilePhotoTap;
  final VoidCallback? onBroadcastTap;
  final Color iconColor;

  const _ChatHubOverflowMenu({
    required this.chatPushEnabled,
    required this.onMuteTap,
    required this.onAlertModeTap,
    required this.onProfilePhotoTap,
    this.onBroadcastTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Mais opções',
      icon: Icon(Icons.more_vert_rounded, color: iconColor, size: 24),
      onSelected: (value) {
        switch (value) {
          case 'broadcast':
            onBroadcastTap?.call();
          case 'profile':
            onProfilePhotoTap();
          case 'alerts':
            onAlertModeTap();
          case 'mute':
            onMuteTap();
        }
      },
      itemBuilder: (context) => [
        if (onBroadcastTap != null)
          const PopupMenuItem(
            value: 'broadcast',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.campaign_rounded),
              title: Text('Transmissão (lista de difusão)'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'profile',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.account_circle_outlined),
            title: Text('Minha foto de perfil'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'alerts',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.tune_rounded),
            title: Text('Modo de alerta'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: ListTile(
            dense: true,
            leading: Icon(
              chatPushEnabled
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
            ),
            title: Text(
              chatPushEnabled
                  ? 'Silenciar notificações'
                  : 'Ativar notificações',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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
  Timer? _filterDebounce;
  String _filterQuery = '';
  Map<String, bool> _presenceOnlineByUid = {};
  Timer? _presencePollTimer;

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
    _filter.addListener(_onFilterChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_pollPresence());
      _presencePollTimer = Timer.periodic(
        const Duration(seconds: 22),
        (_) => unawaited(_pollPresence()),
      );
    });
  }

  Future<void> _pollPresence() async {
    final uids = _eligible
        .map((doc) =>
            (doc.data()['authUid'] ?? doc.data()['firebaseUid'] ?? '')
                .toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (uids.isEmpty) return;
    final online = await ChatMessagingEngine.fetchPresenceOnlineMap(
      churchId: widget.tid,
      authUids: uids,
    );
    if (!mounted) return;
    var changed = online.length != _presenceOnlineByUid.length;
    if (!changed) {
      for (final e in online.entries) {
        if (_presenceOnlineByUid[e.key] != e.value) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;
    setState(() => _presenceOnlineByUid = online);
  }

  void _onFilterChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final q = _filter.text.trim().toLowerCase();
      if (q == _filterQuery) return;
      setState(() => _filterQuery = q);
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _presencePollTimer?.cancel();
    _filter.removeListener(_onFilterChanged);
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
    final q = _filterQuery;
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
                        final nome = ChurchChatDisplayName.fromMemberData(
                          d,
                          authUid: auth,
                          memberDocId: doc.id,
                        );
                        final letter = nome.isNotEmpty
                            ? nome[0].toUpperCase()
                            : '?';
                        final cpfOpt = _cpfDigitsForMember(d, doc.id);
                        final on = _presenceOnlineByUid[auth] ?? false;
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
                                                  nome,
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

class _GroupStripUnreadBadge extends StatefulWidget {
  const _GroupStripUnreadBadge({
    required this.tenantId,
    required this.threadId,
    required this.myUid,
    required this.threadData,
    this.showLabel = false,
  });

  final String tenantId;
  final String threadId;
  final String myUid;
  final Map<String, dynamic>? threadData;
  final bool showLabel;

  @override
  State<_GroupStripUnreadBadge> createState() => _GroupStripUnreadBadgeState();
}

class _GroupStripUnreadBadgeState extends State<_GroupStripUnreadBadge> {
  int _count = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _GroupStripUnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadData != widget.threadData ||
        oldWidget.threadId != widget.threadId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final data = widget.threadData;
    if (data == null) return;
    final n = await ChatHubOperations.threadUnreadInboundCount(
      tenantId: widget.tenantId,
      threadId: widget.threadId,
      myUid: widget.myUid,
      myLastSeenInThread: _chatHubThreadMyLastSeen(data, widget.myUid),
    );
    if (!mounted) return;
    setState(() => _count = n > 0 ? n : 1);
  }

  @override
  Widget build(BuildContext context) {
    final label = _count > 99 ? '99+' : '$_count';
    if (widget.showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFECFDF5),
          border: Border.all(
            color: const Color(0xFF25D366).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_chat_unread_rounded,
              size: 16,
              color: Color(0xFF059669),
            ),
            const SizedBox(width: 6),
            Text(
              _count == 1 ? '1 mensagem não lida' : '$label mensagens não lidas',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: ThemeCleanPremium.onSurface,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
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
