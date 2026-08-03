import 'dart:async' show StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_chat_local_prefs.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_push_bridge.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_web_parity.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_temp_file.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_user_facing_error.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_chat_thread_page.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_global_search_page.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_sessions_page.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_sync_dashboard_page.dart';
import 'package:gestao_yahweh/services/church_chat_hub_departments_service.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/pages/church_telegram_in_app_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';

/// Yahweh Chat — motor **TDLib** (Telegram Database Library).
///
/// - Sessão isolada por igreja (DB local `tdlib/{churchId}`).
/// - Departamentos e membros vêm do Firestore desta igreja.
/// - Após 1º login OTP no aparelho, reabre automático (sem colar link).
/// - Web: mesma UI; conversas abrem no cliente Telegram embutido (sem paste).
class ChurchYahwehTdlibHubPage extends StatefulWidget {
  const ChurchYahwehTdlibHubPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf = '',
    this.permissions = const [],
    this.embeddedInShell = false,
    this.onShellBack,
  });

  final String tenantId;
  final String role;
  final String cpf;
  final List<String>? permissions;
  final bool embeddedInShell;
  final VoidCallback? onShellBack;

  @override
  State<ChurchYahwehTdlibHubPage> createState() =>
      _ChurchYahwehTdlibHubPageState();
}

class _ChurchYahwehTdlibHubPageState extends State<ChurchYahwehTdlibHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  StreamSubscription<TdlibAuthSnapshot>? _authSub;
  StreamSubscription<List<TdlibChatPreview>>? _chatsSub;

  TdlibAuthSnapshot _auth = TdlibAuthSnapshot.idle;
  List<TdlibChatPreview> _chats = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _depts = const [];
  bool _loadingDepts = true;
  Object? _deptError;

  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '+55');
  final _groupsSearchCtrl = TextEditingController();
  final _contactsSearchCtrl = TextEditingController();
  final _chatsSearchCtrl = TextEditingController();
  String _groupsQuery = '';
  String _contactsQuery = '';
  String _chatsQuery = '';
  bool _chatsUnreadOnly = false;
  bool _chatsShowArchived = false;
  bool _churchOnlyMode = true;
  bool _contactsWithPhoneOnly = true;
  bool _authBusy = false;
  String? _authLocalError;
  String? _myPhoneDigits;
  final Set<int> _openedChurchChatIds = <int>{};
  final Set<int> _mutedChatIds = <int>{};
  final Set<int> _archivedChatIds = <int>{};

  static const _accent = Color(0xFF0D9488);
  static const _deptPalette = <Color>[
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
  ];

  static String _phoneRegistrationMessage(String displayName) =>
      'Olá $displayName, cadastre seu telefone (mesmo do Telegram) no app Gestão YAHWEH para entrar no grupo do departamento.';

  static int _phoneDigitsLength(MemberDirectoryEntry e) =>
      (e.telefone ?? '').replaceAll(RegExp(r'\D'), '').length;

  static bool _hasValidPhone(MemberDirectoryEntry e) =>
      _phoneDigitsLength(e) >= 10;

  ({int total, int withPhone, int withoutPhone}) _deptPhoneStats(
    List<MemberDirectoryEntry> members,
  ) {
    final total = members.length;
    final withPhone =
        members.where(_hasValidPhone).length;
    return (total: total, withPhone: withPhone, withoutPhone: total - withPhone);
  }

  Future<void> _requestMemberPhoneViaWhatsApp(MemberDirectoryEntry e) async {
    await YahwehWhatsAppService.openWithMessage(
      phoneDigits: e.telefone,
      message: _phoneRegistrationMessage(e.displayName),
    );
  }

  void _showMissingPhoneBottomSheet(List<MemberDirectoryEntry> members) {
    final missing = members.where((e) => !_hasValidPhone(e)).toList();
    if (missing.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Sem telefone no cadastro (${missing.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: missing.length,
                itemBuilder: (_, i) {
                  final e = missing[i];
                  return ListTile(
                    leading: FotoMembroWidget(
                      size: 40,
                      tenantId: _churchId,
                      memberId: e.memberDocId,
                      imageUrl: e.photoThumbUrl ?? e.photoUrl,
                      memberData: e.toMemberDataMap(),
                      authUid: e.authUid,
                      cpfDigits: e.cpfDigits,
                      preferListThumbnail: true,
                      imageCacheRevision: e.fotoUrlCacheRevision,
                    ),
                    title: Text(
                      e.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('Cadastre o telefone em Membros'),
                    trailing: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_requestMemberPhoneViaWhatsApp(e));
                      },
                      icon: const Icon(Icons.sms_rounded, size: 18),
                      label: const Text('Cobrar telefone'),
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

  Widget _buildChatLeadingAvatar({
    required TdlibChatPreview chat,
    required MemberDirectoryEntry? member,
    required bool isGroup,
    required Color color,
  }) {
    const radius = 24.0;
    final localAvatar = tdlibCircleAvatarFromLocalPath(
      path: chat.photoLocalPath,
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
    );
    final core = localAvatar ??
        (member != null && !isGroup
            ? FotoMembroWidget(
                size: 48,
                tenantId: _churchId,
                memberId: member.memberDocId,
                imageUrl: member.photoThumbUrl ?? member.photoUrl,
                memberData: member.toMemberDataMap(),
                authUid: member.authUid,
                cpfDigits: member.cpfDigits,
                preferListThumbnail: true,
                imageCacheRevision: member.fotoUrlCacheRevision,
                backgroundColor: color.withValues(alpha: 0.12),
              )
            : CircleAvatar(
                radius: radius,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  isGroup ? Icons.groups_rounded : Icons.chat_bubble_rounded,
                  color: color,
                ),
              ));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGroup ? Icons.groups_rounded : Icons.person_rounded,
              size: 12,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  void _showChatError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
    );
  }

  MemberDirectoryEntry? _memberForChatTitle(String title) {
    final t = title.trim().toLowerCase();
    if (t.isEmpty) return null;
    final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      if (e.displayName.trim().toLowerCase() == t) return e;
    }
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      final n = e.displayName.trim().toLowerCase();
      if (n.isNotEmpty && (t.contains(n) || n.contains(t))) return e;
    }
    return null;
  }

  String get _churchId => ChurchRepository.churchId(widget.tenantId.trim());

  bool get _tdlibReady =>
      TdLibService.instance.isSupported && _auth.phase == TdlibAuthPhase.ready;

  /// TDLib nativo indisponível — seja porque a plataforma não suporta
  /// (Web, ou iOS com o flag de build desligado), seja porque o `init`
  /// tentou e falhou em runtime (linker/plugin ausente no device). Nos dois
  /// casos a UI deve cair no Telegram Web embutido, nunca ficar presa num
  /// cartão de login que nunca vai completar.
  bool get _nativeUnavailable =>
      !TdLibService.instance.isSupported ||
      _auth.phase == TdlibAuthPhase.unsupported;

  List<TdlibChatPreview> get _churchChats {
    final allowed = <int>{..._openedChurchChatIds};
    for (final department in _depts) {
      final data = department.data();
      final id = int.tryParse(
        (data['telegramChatId'] ?? data['tdlibChatId'] ?? '').toString(),
      );
      if (id != null && id != 0) allowed.add(id);
    }
    return _chats.where((chat) => allowed.contains(chat.id)).toList();
  }

  List<TdlibChatPreview> get _visibleChats =>
      _churchOnlyMode ? _churchChats : _chats;

  int get _totalUnread =>
      _visibleChats.fold<int>(0, (sum, c) => sum + c.unreadCount);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final peek = ChurchChatHubDepartmentsService.peekInstant(widget.tenantId);
    if (peek != null && peek.isNotEmpty) {
      _depts = peek;
      _loadingDepts = false;
    }
    ChurchPanelNavigationBridge.instance.registerChatOpenListener(
      _onPendingChatOpen,
    );
    unawaited(_boot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumePendingChatOpen());
    });
  }

  Future<void> _boot() async {
    // Resolve phone + departments in parallel (faster first paint).
    final churchOnlyFuture =
        TdlibChatLocalPrefs.isChurchOnlyMode(_churchId);
    await Future.wait([_resolveMyPhone(), _reloadDepts()]);
    _churchOnlyMode = await churchOnlyFuture;
    if (mounted) setState(() {});
    final svc = TdLibService.instance;
    _authSub = svc.authorizationStateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _auth = snap);
      if (snap.phase == TdlibAuthPhase.ready) {
        // refreshChats+warm já correm no handler ready do serviço — não duplicar.
        unawaited(svc.prefetchChatPhotos(limit: 12));
        unawaited(TdlibPushBridge.onTdlibReady());
        unawaited(_scheduleDeptGroupsSync());
      }
    });
    _chatsSub = svc.chatsStream.listen((list) {
      if (!mounted) return;
      setState(() => _chats = list);
      unawaited(_refreshChatLocalPrefs(list));
    });
    // TDLib init is fully non-blocking — chat UI shows immediately.
    if (svc.isSupported) {
      unawaited(
        svc.init(churchId: _churchId).then((_) {
          if (mounted) setState(() => _auth = svc.currentAuth);
          if (svc.currentAuth.phase == TdlibAuthPhase.ready) {
            unawaited(svc.prefetchChatPhotos(limit: 12));
            unawaited(TdlibPushBridge.onTdlibReady());
            unawaited(_scheduleDeptGroupsSync());
          }
        }),
      );
    } else if (mounted) {
      setState(() => _auth = TdlibAuthSnapshot.unsupported);
    }
  }

  Future<void> _refreshChatLocalPrefs(List<TdlibChatPreview> chats) async {
    final sets = await TdlibChatLocalPrefs.loadMuteArchiveSets(
      _churchId,
      chats.map((c) => c.id),
    );
    if (!mounted) return;
    setState(() {
      _mutedChatIds
        ..clear()
        ..addAll(sets.muted);
      _archivedChatIds
        ..clear()
        ..addAll(sets.archived);
    });
  }

  /// Sync de membros nos grupos só depois da lista ficar usável.
  Future<void> _scheduleDeptGroupsSync() async {
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!mounted || !_tdlibReady) return;
    await _syncAllDeptGroupsInBackground();
  }

  Future<void> _syncAllDeptGroupsInBackground() async {
    if (!_tdlibReady) return;
    var syncedAny = false;
    for (final doc in _depts) {
      final chatId = int.tryParse(
        (doc.data()['telegramChatId'] ?? doc.data()['tdlibChatId'] ?? '')
            .toString(),
      );
      if (chatId == null || chatId == 0) continue;
      try {
        final n = await _syncDeptMembersToChat(chatId, doc);
        if (n > 0) syncedAny = true;
      } catch (_) {}
    }
    if (syncedAny) {
      await TdlibChatLocalPrefs.setLastSyncAt(_churchId, DateTime.now());
    }
  }

  String _formatChatListTime(int? epoch) {
    if (epoch == null || epoch <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (day == today) return hm;
    if (day == today.subtract(const Duration(days: 1))) return 'Ontem';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  ({String deptId, String deptName})? _deptMetaForChat(int chatId) {
    for (final d in _depts) {
      final id = int.tryParse(
        (d.data()['telegramChatId'] ?? d.data()['tdlibChatId'] ?? '').toString(),
      );
      if (id == chatId) {
        return (deptId: d.id, deptName: churchDepartmentNameFromDoc(d));
      }
    }
    return null;
  }

  Future<void> _openTdlibThread({
    required int chatId,
    required String title,
    bool isGroup = false,
    String departmentId = '',
    String departmentName = '',
  }) async {
    setState(() => _openedChurchChatIds.add(chatId));
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => TdlibChatThreadPage(
          chatId: chatId,
          title: title,
          churchId: _churchId,
          isGroup: isGroup,
          departmentId: departmentId,
          departmentName: departmentName,
        ),
      ),
    );
  }

  Future<void> _toggleMuteChat(int chatId) async {
    final next = !_mutedChatIds.contains(chatId);
    await TdlibChatLocalPrefs.setMuted(_churchId, chatId, next);
    try {
      await TdLibService.instance.setChatMuted(chatId, next);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (next) {
        _mutedChatIds.add(chatId);
      } else {
        _mutedChatIds.remove(chatId);
      }
    });
  }

  Future<void> _toggleArchiveChat(int chatId) async {
    final next = !_archivedChatIds.contains(chatId);
    await TdlibChatLocalPrefs.setArchived(_churchId, chatId, next);
    if (!mounted) return;
    setState(() {
      if (next) {
        _archivedChatIds.add(chatId);
      } else {
        _archivedChatIds.remove(chatId);
      }
    });
  }

  Future<void> _resolveMyPhone() async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || _churchId.isEmpty) return;
    try {
      final hit = await ChurchUiMemberPhone.resolve(
        tenantId: _churchId,
        authUid: uid,
      );
      if (!mounted) return;
      if (hit != null && hit.length >= 10) {
        setState(() {
          _myPhoneDigits = hit;
          _phoneCtrl.text = hit.startsWith('55') ? '+$hit' : '+55$hit';
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadDepts({bool forceServer = false}) async {
    if (!mounted) return;
    if (_depts.isEmpty) {
      setState(() {
        _loadingDepts = true;
        _deptError = null;
      });
    }
    try {
      final r = await ChurchChatHubDepartmentsService.load(
        seedTenantId: widget.tenantId,
        // Cache-first no 1º paint; pull-to-refresh pede servidor.
        forceServer: forceServer || _depts.isEmpty,
      );
      if (!mounted) return;
      setState(() {
        _depts = r.docs;
        _loadingDepts = false;
        _deptError = r.docs.isEmpty ? r.softError : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDepts = false;
        _deptError = e;
      });
    }
  }

  void _onPendingChatOpen() => unawaited(_consumePendingChatOpen());

  Future<void> _consumePendingChatOpen() async {
    if (!mounted) return;
    final pending = ChurchPanelNavigationBridge.instance
        .consumePendingChatThreadOpen();
    if (pending == null) return;
    var phone = (pending.phoneDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10 && (pending.peerUid ?? '').isNotEmpty) {
      final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
      final peer = (pending.peerUid ?? '').trim();
      for (final e in snap?.entries ?? const []) {
        if ((e.authUid ?? '').trim() == peer) {
          phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
          break;
        }
      }
    }
    if (phone.length >= 10) {
      await _openMemberDm(
        phone: phone,
        title: pending.displayName ?? 'Conversa',
      );
    }
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _authBusy = true;
      _authLocalError = null;
    });
    try {
      await action();
    } catch (e, st) {
      // Erro real do TDLib (code/message) — sem isto, toda falha de login
      // (telefone inválido, flood-wait, rede) virava a mesma mensagem
      // genérica e era impossível diagnosticar depois.
      debugPrint('[TdLib auth] $e\n$st');
      unawaited(CrashlyticsService.record(e, st, reason: 'tdlib_auth'));
      if (mounted) {
        setState(() => _authLocalError = formatTdlibErrorForUser(e));
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _openMemberDm({
    required String phone,
    required String title,
  }) async {
    if (_tdlibReady) {
      try {
        final chatId = await TdLibService.instance.openPrivateChatByPhone(
          phone,
        );
        if (!mounted) return;
        await _openTdlibThread(
          chatId: chatId,
          title: title,
          isGroup: false,
        );
        return;
      } catch (e) {
        _showChatError(e);
      }
    }
    // Web / fallback: cliente Telegram embutido pelo telefone (sem paste).
    final dm = ChurchTelegramLauncher.dmUrlFromPhone(phone);
    if (dm == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            'Cadastre o telefone do membro (mesmo do Telegram).',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await ChurchTelegramInAppPage.open(
      context,
      urlOrHandle: dm,
      title: title,
      subtitle: 'Conversa privada',
    );
  }

  /// Membros já colocados no departamento pelo pastor / secretário / líder.
  List<MemberDirectoryEntry> _membersOfDepartment(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final name = churchDepartmentNameFromDoc(doc).trim().toLowerCase();
    final deptId = doc.id.trim().toLowerCase();
    final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
    final out = <MemberDirectoryEntry>[];
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      final depts = e.departamentos
          .map((d) => d.trim().toLowerCase())
          .where((d) => d.isNotEmpty)
          .toList();
      final inDept = depts.contains(name) ||
          depts.contains(deptId) ||
          e.departamentos.contains(doc.id);
      if (inDept) out.add(e);
    }
    return out;
  }

  /// Sincroniza o grupo com o cadastro da igreja (sem convite manual).
  Future<int> _syncDeptMembersToChat(
    int chatId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final alreadySynced =
        await TdlibChatLocalPrefs.getSyncedPhones(_churchId, chatId);
    var synced = 0;
    final newlySynced = <String>[];
    for (final e in _membersOfDepartment(doc)) {
      final phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      if (phone.length < 10) continue;
      if (alreadySynced.contains(phone)) continue;
      final ok = await TdLibService.instance.addChatMemberByPhone(
        chatId,
        phone,
      );
      if (ok) {
        synced++;
        newlySynced.add(phone);
      }
    }
    if (newlySynced.isNotEmpty) {
      await TdlibChatLocalPrefs.markPhonesSynced(
        _churchId,
        chatId,
        newlySynced,
      );
      await TdlibChatLocalPrefs.setLastSyncAt(_churchId, DateTime.now());
    }
    return synced;
  }

  Future<void> _toggleChurchOnlyMode(bool value) async {
    setState(() => _churchOnlyMode = value);
    await TdlibChatLocalPrefs.setChurchOnlyMode(_churchId, value);
  }

  void _openGlobalSearch() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => TdlibGlobalSearchPage(churchId: _churchId),
      ),
    );
  }

  void _openSessions() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const TdlibSessionsPage()),
    );
  }

  void _openSyncDashboard() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => TdlibSyncDashboardPage(
          churchId: _churchId,
          departments: _depts,
        ),
      ),
    );
  }

  Future<void> _openDept(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final name = churchDepartmentNameFromDoc(doc);
    final invite = ChurchTelegramLauncher.inviteFromDeptData(data);
    final storedChatId = int.tryParse(
      (data['telegramChatId'] ?? data['tdlibChatId'] ?? '').toString(),
    );

    if (_tdlibReady) {
      try {
        int chatId;
        if (storedChatId != null && storedChatId != 0) {
          chatId = storedChatId;
          // Abrir na hora — histórico carrega no thread (cache/warm local).
          unawaited(_syncDeptMembersToChat(chatId, doc));
        } else {
          // Cria automático e inclui todos do departamento (sem diálogo / link).
          chatId = await _ensureDeptTelegramGroup(doc);
        }
        if (!mounted) return;
        await _openTdlibThread(
          chatId: chatId,
          title: name,
          isGroup: true,
          departmentId: doc.id,
          departmentName: name,
        );
        return;
      } catch (e) {
        _showChatError(e);
        // Continua para fallback web se houver link legado.
      }
    }

    if (invite != null) {
      if (!mounted) return;
      await ChurchTelegramInAppPage.open(
        context,
        urlOrHandle: invite,
        title: name,
        subtitle: 'Grupo do departamento',
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.errorSnackBarWithRetry(
          _tdlibReady
              ? 'Não foi possível abrir o grupo. Tente novamente.'
              : 'Conecte o chat uma vez e toque de novo — o grupo abre automático.',
        ),
      );
    }
  }

  /// Cria o grupo e coloca automaticamente todos os membros do departamento.
  Future<int> _ensureDeptTelegramGroup(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final name = churchDepartmentNameFromDoc(doc);
    final created = await TdLibService.instance.createDepartmentSupergroup(
      title: 'Yahweh · $name',
      description: 'Grupo do departamento $name — $name · Gestão Yahweh',
    );
    final payload = <String, dynamic>{
      'telegramChatId': created.chatId,
      'tdlibChatId': created.chatId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (created.inviteLink != null && created.inviteLink!.isNotEmpty) {
      payload['telegramInviteUrl'] = created.inviteLink;
    }
    await doc.reference.set(payload, SetOptions(merge: true));

    final synced = await _syncDeptMembersToChat(created.chatId, doc);
    if (mounted) {
      final total = _membersOfDepartment(doc).length;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          total == 0
              ? 'Grupo $name pronto. Inclua membros no departamento em Membros.'
              : 'Grupo $name pronto · $synced de $total membro(s) do departamento incluídos.',
        ),
      );
    }
    await _reloadDepts();
    return created.chatId;
  }

  Widget _deptMemberStack(
    List<MemberDirectoryEntry> members,
    Color color,
  ) {
    final show = members.take(3).toList();
    if (show.isEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(Icons.groups_rounded, color: color),
      );
    }
    const size = 48.0;
    final width = size + (show.length - 1) * 16.0;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < show.length; i++)
            Positioned(
              left: i * 16.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: FotoMembroWidget(
                  size: size - 4,
                  tenantId: _churchId,
                  memberId: show[i].memberDocId,
                  imageUrl: show[i].photoThumbUrl ?? show[i].photoUrl,
                  memberData: show[i].toMemberDataMap(),
                  authUid: show[i].authUid,
                  cpfDigits: show[i].cpfDigits,
                  preferListThumbnail: true,
                  imageCacheRevision: show[i].fotoUrlCacheRevision,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    ChurchPanelNavigationBridge.instance.unregisterChatOpenListener(
      _onPendingChatOpen,
    );
    _authSub?.cancel();
    _chatsSub?.cancel();
    _tabs.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _groupsSearchCtrl.dispose();
    _contactsSearchCtrl.dispose();
    _chatsSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = _accent;
    final body = Column(
      children: [
        // Cabeçalho único vem do shell (ModuleHeaderPremium). Sem barra duplicada.
        if (!widget.embeddedInShell)
          Material(
            color: accent,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const Expanded(
                      child: Text(
                        YahwehContactButtonLabels.yahwehChat,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!_tdlibReady &&
            TdLibService.instance.isSupported &&
            _auth.phase != TdlibAuthPhase.initializing &&
            _auth.phase != TdlibAuthPhase.unsupported)
          _buildAuthCard(accent)
        else if (_nativeUnavailable)
          _buildWebHint(accent),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: accent,
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: accent,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(
                icon: Badge(
                  isLabelVisible: _totalUnread > 0,
                  label: Text(
                    _totalUnread > 99 ? '99+' : '$_totalUnread',
                    style: const TextStyle(fontSize: 10),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, size: 20),
                ),
                text: 'Conversas',
              ),
              Tab(
                icon: Badge(
                  isLabelVisible: _depts.isNotEmpty,
                  backgroundColor: const Color(0xFF2563EB),
                  label: Text(
                    '${_depts.length}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  child: const Icon(Icons.groups_rounded, size: 20),
                ),
                text: 'Grupos',
              ),
              const Tab(
                icon: Icon(Icons.people_alt_rounded, size: 20),
                text: 'Contatos',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildChatsTab(accent),
              _buildDeptsTab(accent),
              _buildContactsTab(accent),
            ],
          ),
        ),
      ],
    );

    if (widget.embeddedInShell) {
      return ColoredBox(color: const Color(0xFFF1F5F9), child: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: body,
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required Color accent,
    required String query,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, color: accent),
          suffixIcon: query.trim().isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildWebHint(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: Icon(Icons.public_rounded, color: accent),
          title: const Text(
            TdlibWebParity.bannerTitle,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            TdlibWebParity.bannerBody,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          trailing: FilledButton(
            onPressed: () {
              unawaited(
                ChurchTelegramInAppPage.open(
                  context,
                  urlOrHandle: TdlibWebParity.conversationsHome(),
                  title: YahwehContactButtonLabels.yahwehChat,
                  subtitle: 'Telegram Web · mesma conta',
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(Color accent) {
    final phase = _auth.phase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _auth.message ?? 'Entrar no chat (só na 1ª vez)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Use o mesmo número do seu Telegram. O código chega no app Telegram ou por SMS.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              if (_myPhoneDigits != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Telefone do cadastro: +$_myPhoneDigits',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
              if (_authLocalError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _authLocalError!,
                  style: const TextStyle(color: ThemeCleanPremium.error),
                ),
              ],
              const SizedBox(height: 10),
              if (phase == TdlibAuthPhase.waitPhoneNumber ||
                  phase == TdlibAuthPhase.error) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone Telegram',
                    hintText: '+5562…',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                          () => TdLibService.instance.sendPhoneNumber(
                            _phoneCtrl.text,
                          ),
                        ),
                  child: Text(_authBusy ? 'Enviando…' : 'Continuar'),
                ),
              ],
              if (phase == TdlibAuthPhase.waitCode) ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Código recebido no Telegram ou por SMS',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                          () => TdLibService.instance.sendCode(_codeCtrl.text),
                        ),
                  child: Text(_authBusy ? 'Validando…' : 'Confirmar código'),
                ),
              ],
              if (phase == TdlibAuthPhase.waitPassword) ...[
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Senha 2FA'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                          () => TdLibService.instance.sendPassword(
                            _passwordCtrl.text,
                          ),
                        ),
                  child: Text(_authBusy ? 'Validando…' : 'Entrar'),
                ),
              ],
              if (phase == TdlibAuthPhase.initializing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyAction({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required String cta,
    required VoidCallback onCta,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onCta,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(cta),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsTab(Color accent) {
    if (!_tdlibReady) {
      final webParity = _nativeUnavailable;
      return _buildEmptyAction(
        accent: accent,
        icon: webParity ? Icons.public_rounded : Icons.forum_outlined,
        title: webParity
            ? 'Telegram Web (paridade)'
            : 'Conectando o chat…',
        subtitle: webParity
            ? 'Toque para abrir o Telegram Web embutido — mesma conta, grupos e DMs.'
            : 'Enquanto isso, abra um grupo ou um contato.',
        cta: webParity ? 'Abrir Telegram Web' : 'Ver grupos',
        onCta: () {
          if (webParity) {
            unawaited(
              ChurchTelegramInAppPage.open(
                context,
                urlOrHandle: TdlibWebParity.conversationsHome(),
                title: YahwehContactButtonLabels.yahwehChat,
                subtitle: 'Telegram Web · mesma conta',
              ),
            );
          } else {
            _tabs.animateTo(1);
          }
        },
      );
    }
    final q = _chatsQuery.trim().toLowerCase();
    final churchChats = _visibleChats.where((c) {
      final archived = _archivedChatIds.contains(c.id);
      if (!_chatsShowArchived && archived) return false;
      if (_chatsShowArchived && !archived) return false;
      if (_chatsUnreadOnly && c.unreadCount <= 0) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) ||
          (c.lastMessagePreview ?? '').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final da = a.lastMessageDateEpoch ?? 0;
        final db = b.lastMessageDateEpoch ?? 0;
        if (db != da) return db.compareTo(da);
        final byUnread = b.unreadCount.compareTo(a.unreadCount);
        if (byUnread != 0) return byUnread;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return Column(
      children: [
        _buildSearchField(
          controller: _chatsSearchCtrl,
          hint: 'Pesquisar conversas…',
          accent: accent,
          query: _chatsQuery,
          onChanged: (v) => setState(() => _chatsQuery = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      selected: _churchOnlyMode,
                      label: const Text('Só igreja'),
                      avatar: Icon(
                        Icons.church_rounded,
                        size: 16,
                        color: _churchOnlyMode ? Colors.white : accent,
                      ),
                      selectedColor: accent,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _churchOnlyMode ? Colors.white : accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      onSelected: (v) => unawaited(_toggleChurchOnlyMode(v)),
                    ),
                    FilterChip(
                      selected: _chatsUnreadOnly,
                      label: Text(
                        _totalUnread > 0
                            ? 'Não lidas ($_totalUnread)'
                            : 'Não lidas',
                      ),
                      avatar: Icon(
                        Icons.mark_email_unread_rounded,
                        size: 16,
                        color: _chatsUnreadOnly ? Colors.white : accent,
                      ),
                      selectedColor: accent,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _chatsUnreadOnly ? Colors.white : accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      onSelected: (v) => setState(() => _chatsUnreadOnly = v),
                    ),
                    FilterChip(
                      selected: _chatsShowArchived,
                      label: Text(
                        _archivedChatIds.isEmpty
                            ? 'Arquivo'
                            : 'Arquivo (${_archivedChatIds.length})',
                      ),
                      avatar: Icon(
                        Icons.archive_outlined,
                        size: 16,
                        color: _chatsShowArchived ? Colors.white : accent,
                      ),
                      selectedColor: accent,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color: _chatsShowArchived ? Colors.white : accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      onSelected: (v) => setState(() => _chatsShowArchived = v),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(TdLibService.instance.refreshChats()),
                      icon: Icon(Icons.refresh_rounded, size: 18, color: accent),
                      label: Text('Atualizar', style: TextStyle(color: accent)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Buscar mensagens',
                icon: Icon(Icons.search_rounded, color: accent),
                onPressed: _openGlobalSearch,
              ),
              IconButton(
                tooltip: 'Aparelhos conectados',
                icon: Icon(Icons.devices_rounded, color: accent),
                onPressed: _openSessions,
              ),
              IconButton(
                tooltip: 'Painel de sync',
                icon: Icon(Icons.dashboard_customize_outlined, color: accent),
                onPressed: _openSyncDashboard,
              ),
            ],
          ),
        ),
        Expanded(
          child: churchChats.isEmpty
              ? _buildEmptyAction(
                  accent: accent,
                  icon: Icons.chat_bubble_outline_rounded,
                  title: _chatsShowArchived
                      ? 'Nenhuma conversa arquivada'
                      : (_chatsUnreadOnly
                          ? 'Nenhuma conversa não lida'
                          : 'Comece pelo grupo ou contato'),
                  subtitle: _chatsShowArchived
                      ? 'Segure numa conversa e escolha Arquivar.'
                      : (_chatsUnreadOnly
                          ? 'Desative o filtro “Não lidas” para ver todas.'
                          : 'Toque em Grupos (departamento) ou Contatos para falar.'),
                  cta: _chatsUnreadOnly || _chatsShowArchived
                      ? 'Ver todas'
                      : 'Abrir contatos',
                  onCta: () {
                    if (_chatsUnreadOnly || _chatsShowArchived) {
                      setState(() {
                        _chatsUnreadOnly = false;
                        _chatsShowArchived = false;
                      });
                    } else {
                      _tabs.animateTo(2);
                    }
                  },
                )
              : RefreshIndicator(
                  onRefresh: () => TdLibService.instance.refreshChats(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: churchChats.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = churchChats[i];
                      final member = _memberForChatTitle(c.title);
                      final color = _deptPalette[i % _deptPalette.length];
                      final unread = c.unreadCount > 0;
                      final muted = _mutedChatIds.contains(c.id);
                      final isGroup = c.isGroup ||
                          _deptMetaForChat(c.id) != null;
                      final timeLabel =
                          _formatChatListTime(c.lastMessageDateEpoch);
                      return Material(
                        color: unread
                            ? color.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: color.withValues(
                                alpha: unread ? 0.45 : 0.22,
                              ),
                            ),
                          ),
                          leading: _buildChatLeadingAvatar(
                            chat: c,
                            member: member,
                            isGroup: isGroup,
                            color: color,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: unread
                                        ? FontWeight.w900
                                        : FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (muted)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.notifications_off_outlined,
                                    size: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              if (timeLabel.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    timeLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: unread
                                          ? color
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            c.lastMessagePreview ?? 'Abrir conversa',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          trailing: unread
                              ? CircleAvatar(
                                  radius: 12,
                                  backgroundColor: color,
                                  child: Text(
                                    '${c.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right_rounded,
                                  color: color,
                                ),
                          onTap: () {
                            final meta = _deptMetaForChat(c.id);
                            unawaited(
                              _openTdlibThread(
                                chatId: c.id,
                                title: c.title,
                                isGroup: isGroup,
                                departmentId: meta?.deptId ?? '',
                                departmentName: meta?.deptName ?? '',
                              ),
                            );
                          },
                          onLongPress: () {
                            showModalBottomSheet<void>(
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        muted
                                            ? Icons.notifications_active_outlined
                                            : Icons.notifications_off_outlined,
                                      ),
                                      title: Text(
                                        muted
                                            ? 'Ativar notificações'
                                            : 'Silenciar',
                                      ),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        unawaited(_toggleMuteChat(c.id));
                                      },
                                    ),
                                    ListTile(
                                      leading: Icon(
                                        _archivedChatIds.contains(c.id)
                                            ? Icons.unarchive_outlined
                                            : Icons.archive_outlined,
                                      ),
                                      title: Text(
                                        _archivedChatIds.contains(c.id)
                                            ? 'Desarquivar'
                                            : 'Arquivar',
                                      ),
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        unawaited(_toggleArchiveChat(c.id));
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDeptsTab(Color accent) {
    if (_loadingDepts && _depts.isEmpty) {
      return const ChurchPanelLoadingBody();
    }
    if (_deptError != null && _depts.isEmpty) {
      return ChurchPanelResilientLoadBanner(
        hasLocalData: false,
        isSyncing: false,
        errorTitle: 'Não foi possível carregar departamentos',
        error: _deptError,
        onRetry: () => _reloadDepts(forceServer: true),
      );
    }
    if (_depts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum departamento nesta igreja.\n'
            'Crie em Departamentos — cada igreja fica separada.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final q = _groupsQuery.trim().toLowerCase();
    final filtered = _depts
        .where(
          (d) =>
              q.isEmpty ||
              churchDepartmentNameFromDoc(d).toLowerCase().contains(q),
        )
        .toList();
    return Column(
      children: [
        _buildSearchField(
          controller: _groupsSearchCtrl,
          hint: 'Pesquisar grupos / departamentos…',
          accent: accent,
          query: _groupsQuery,
          onChanged: (v) => setState(() => _groupsQuery = v),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _reloadDepts(forceServer: true),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('Nenhum grupo encontrado.')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      final name = churchDepartmentNameFromDoc(d);
                      final members = _membersOfDepartment(d);
                      final stats = _deptPhoneStats(members);
                      final ready = (d.data()['telegramChatId'] ??
                                  d.data()['tdlibChatId'] ??
                                  '')
                              .toString()
                              .trim()
                              .isNotEmpty ||
                          ChurchTelegramLauncher.inviteFromDeptData(
                                d.data(),
                              ) !=
                              null;
                      final color = _deptPalette[i % _deptPalette.length];
                      final subtitle = stats.total == 0
                          ? 'Sem membros neste departamento ainda'
                          : ready
                              ? '${stats.withPhone}/${stats.total} no Telegram · ${stats.withoutPhone} sem telefone'
                              : '${stats.total} membro${stats.total == 1 ? '' : 's'} · abre automático';
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: color.withValues(alpha: 0.35),
                              ),
                            ),
                            leading: _deptMemberStack(members, color),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(subtitle),
                            trailing: stats.withoutPhone > 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Cobrar telefone',
                                        icon: Icon(
                                          Icons.sms_rounded,
                                          color: color,
                                          size: 22,
                                        ),
                                        onPressed: () =>
                                            _showMissingPhoneBottomSheet(members),
                                      ),
                                      Icon(
                                        Icons.chat_bubble_rounded,
                                        color: color,
                                      ),
                                    ],
                                  )
                                : Icon(
                                    Icons.chat_bubble_rounded,
                                    color: color,
                                  ),
                            onTap: () => unawaited(_openDept(d)),
                            onLongPress: stats.withoutPhone > 0
                                ? () => _showMissingPhoneBottomSheet(members)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsTab(Color accent) {
    final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
    final entries = snap?.entries ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Lista de membros desta igreja ainda a carregar.\n'
            'Abra Membros e volte — cada igreja fica separada.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }
    final q = _contactsQuery.trim().toLowerCase();
    final filtered = entries.where((e) {
      final phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      final okPhone = phone.length >= 10;
      if (_contactsWithPhoneOnly && !okPhone) return false;
      if (q.isEmpty) return true;
      return e.displayName.toLowerCase().contains(q) ||
          phone.contains(q) ||
          e.departamentos.any((d) => d.toLowerCase().contains(q));
    }).toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    final limited = filtered.take(200).toList();
    return Column(
      children: [
        _buildSearchField(
          controller: _contactsSearchCtrl,
          hint: 'Pesquisar contatos por nome…',
          accent: accent,
          query: _contactsQuery,
          onChanged: (v) => setState(() => _contactsQuery = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: _contactsWithPhoneOnly,
              label: const Text('Só com telefone'),
              avatar: Icon(
                Icons.phone_rounded,
                size: 16,
                color: _contactsWithPhoneOnly ? Colors.white : accent,
              ),
              selectedColor: accent,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: _contactsWithPhoneOnly ? Colors.white : accent,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
              onSelected: (v) => setState(() => _contactsWithPhoneOnly = v),
            ),
          ),
        ),
        Expanded(
          child: limited.isEmpty
              ? _buildEmptyAction(
                  accent: accent,
                  icon: Icons.person_search_rounded,
                  title: 'Nenhum contato encontrado',
                  subtitle: _contactsWithPhoneOnly
                      ? 'Desative “Só com telefone” ou cadastre o telefone do membro.'
                      : 'Abra Membros para atualizar a lista desta igreja.',
                  cta: _contactsWithPhoneOnly
                      ? 'Mostrar todos'
                      : 'Ver grupos',
                  onCta: () {
                    if (_contactsWithPhoneOnly) {
                      setState(() => _contactsWithPhoneOnly = false);
                    } else {
                      _tabs.animateTo(1);
                    }
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                  itemCount: limited.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final e = limited[i];
                    final phone =
                        (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
                    final ok = phone.length >= 10;
                    final color = _deptPalette[i % _deptPalette.length];
                    final deptHint = e.departamentos.isEmpty
                        ? null
                        : e.departamentos.take(2).join(' · ');
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: color.withValues(alpha: 0.22),
                          ),
                        ),
                        leading: FotoMembroWidget(
                          size: 48,
                          tenantId: _churchId,
                          memberId: e.memberDocId,
                          imageUrl: e.photoThumbUrl ?? e.photoUrl,
                          memberData: e.toMemberDataMap(),
                          authUid: e.authUid,
                          cpfDigits: e.cpfDigits,
                          preferListThumbnail: true,
                          imageCacheRevision: e.fotoUrlCacheRevision,
                          backgroundColor: color.withValues(alpha: 0.12),
                        ),
                        title: Text(
                          e.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          ok
                              ? (deptHint ?? 'Abrir conversa privada')
                              : 'Sem telefone no cadastro',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        enabled: ok,
                        trailing: Icon(
                          Icons.chat_bubble_rounded,
                          color: ok ? color : Colors.grey,
                        ),
                        onTap: !ok
                            ? null
                            : () => unawaited(
                                  _openMemberDm(
                                    phone: phone,
                                    title: e.displayName,
                                  ),
                                ),
                      ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Resolve telefone do membro logado nesta igreja.
abstract final class ChurchUiMemberPhone {
  ChurchUiMemberPhone._();

  static Future<String?> resolve({
    required String tenantId,
    required String authUid,
  }) async {
    final snap = MembersDirectorySnapshotService.peekMemory(tenantId);
    for (final e in snap?.entries ?? const []) {
      if ((e.authUid ?? '').trim() == authUid) {
        final p = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
        if (p.length >= 10) return p;
      }
    }
    try {
      final doc = await ChurchRepository.churchDoc(
        tenantId,
      ).collection('membros').doc(authUid).get();
      if (doc.exists && doc.data() != null) {
        final p = ChurchMemberContactChat.phoneDigitsFromMember(doc.data()!);
        if (p.length >= 10) return p;
      }
    } catch (_) {}
    return null;
  }
}

/// Thread TDLib — texto + anexo (foto/vídeo/arquivo).
class ChurchYahwehTdlibThreadPage extends StatefulWidget {
  const ChurchYahwehTdlibThreadPage({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<ChurchYahwehTdlibThreadPage> createState() =>
      _ChurchYahwehTdlibThreadPageState();
}

class _ChurchYahwehTdlibThreadPageState
    extends State<ChurchYahwehTdlibThreadPage> {
  final _textCtrl = TextEditingController();
  StreamSubscription<List<TdlibMessageItem>>? _sub;
  List<TdlibMessageItem> _messages = const [];
  bool _sending = false;

  static const _accent = Color(0xFF0D9488);

  @override
  void initState() {
    super.initState();
    _sub = TdLibService.instance.messagesStream.listen((list) {
      if (!mounted) return;
      setState(() => _messages = list);
    });
    unawaited(TdLibService.instance.loadChatHistory(widget.chatId));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final t = _textCtrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await TdLibService.instance.sendTextMessage(widget.chatId, t);
      _textCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _resolveLocalPath() async {
    final result = await YahwehFilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    return materializeTdlibLocalPath(
      path: f.path,
      bytes: f.bytes,
      fileName: f.name.isEmpty ? 'anexo.bin' : f.name,
    );
  }

  Future<void> _pickAndSend() async {
    final path = await _resolveLocalPath();
    if (path == null || path.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            'Não foi possível anexar o ficheiro. Escolha a foto ou o vídeo de novo.',
          ),
        );
      }
      return;
    }
    final name = path.toLowerCase();
    var kind = 'document';
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic')) {
      kind = 'photo';
    } else if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.mkv')) {
      kind = 'video';
    } else if (name.endsWith('.ogg') ||
        name.endsWith('.m4a') ||
        name.endsWith('.mp3')) {
      kind = 'voice';
    }
    setState(() => _sending = true);
    try {
      await TdLibService.instance.sendLocalFile(
        widget.chatId,
        path,
        kind: kind,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final mine = m.isOutgoing;
                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? _accent : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      m.preview,
                      style: TextStyle(
                        color: mine ? Colors.white : const Color(0xFF0F172A),
                        height: 1.35,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Material(
              color: Colors.white,
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _sending ? null : _pickAndSend,
                      icon: Icon(
                        Icons.attach_file_rounded,
                        color: _accent,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        decoration: InputDecoration(
                          hintText: 'Mensagem',
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _sendText(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CircleAvatar(
                      backgroundColor: _accent,
                      child: IconButton(
                        onPressed: _sending ? null : _sendText,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
