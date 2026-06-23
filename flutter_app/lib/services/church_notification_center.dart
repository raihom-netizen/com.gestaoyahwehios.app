import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/internal_notification_inbox_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_foreground_notification_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
enum ChurchNotificationSource { tenant, inbox, live }

/// Item unificado da central (push FCM + `notificacoes` + painel ao vivo).
class ChurchNotificationItem {
  const ChurchNotificationItem({
    required this.id,
    required this.source,
    required this.type,
    required this.title,
    this.body = '',
    this.createdAt,
    this.isRead = false,
    this.shellIndex,
    this.inboxRef,
    this.meta = const {},
  });

  final String id;
  final ChurchNotificationSource source;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;
  final int? shellIndex;
  final DocumentReference<Map<String, dynamic>>? inboxRef;
  final Map<String, dynamic> meta;

  String get module => ChurchNotificationCenter.moduleForType(type);

  IconData get icon => ChurchNotificationCenter.iconForType(type);

  Color get accent => gyModuleAccentColor(module);
}

class ChurchNotificationFeedSnapshot {
  const ChurchNotificationFeedSnapshot({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = true,
  });

  final List<ChurchNotificationItem> items;
  final int unreadCount;
  final bool loading;
}

abstract final class ChurchNotificationSeenPrefs {
  ChurchNotificationSeenPrefs._();

  static String _key(String tenantId, String uid) =>
      'church_notif_seen_${tenantId.trim()}_${uid.trim()}';

  static Future<DateTime> lastSeenAt(String tenantId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_key(tenantId, uid));
      if (ms == null) return DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static Future<void> markAllTenantSeen(String tenantId, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _key(tenantId, uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }
}

abstract final class ChurchNotificationCenter {
  ChurchNotificationCenter._();

  static bool isStaffRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'pastor' ||
        r == 'pastora' ||
        r == 'secretario' ||
        r == 'secretaria' ||
        r == 'lider' ||
        r == 'lÃ­der';
  }

  static String moduleForType(String type) {
    switch (type) {
      case 'novo_aviso':
        return 'aviso';
      case 'novo_evento':
        return 'evento';
      case 'nova_escala':
      case 'escala':
      case 'escala_publicada':
      case 'escala_lembrete_24h':
      case 'escala_lembrete_1h':
        return 'escala';
      case 'aniversariantes_dia':
      case 'birthday_daily':
        return 'aniversario';
      case 'novo_membro':
      case 'new_member':
        return 'membro';
      case 'pedido_oracao':
      case 'novo_pedido_oracao':
        return 'pastoral';
      default:
        return 'generico';
    }
  }

  static IconData iconForType(String type) {
    switch (type) {
      case 'novo_aviso':
        return Icons.campaign_rounded;
      case 'novo_evento':
        return Icons.event_rounded;
      case 'nova_escala':
      case 'escala':
      case 'escala_publicada':
      case 'escala_lembrete_24h':
      case 'escala_lembrete_1h':
        return Icons.calendar_month_rounded;
      case 'aniversariantes_dia':
      case 'birthday_daily':
        return Icons.cake_rounded;
      case 'novo_membro':
      case 'new_member':
        return Icons.person_add_alt_1_rounded;
      case 'pedido_oracao':
      case 'novo_pedido_oracao':
        return Icons.volunteer_activism_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  static int? shellIndexForItem(ChurchNotificationItem item) {
    if (item.shellIndex != null) return item.shellIndex;
    switch (item.type) {
      case 'novo_aviso':
        return kChurchShellIndexMural;
      case 'novo_evento':
        return kChurchShellIndexEvents;
      case 'nova_escala':
      case 'escala':
      case 'escala_publicada':
      case 'escala_lembrete_24h':
      case 'escala_lembrete_1h':
        return kChurchShellIndexMySchedules;
      case 'aniversariantes_dia':
      case 'birthday_daily':
        return kChurchShellIndexPainel;
      case 'novo_membro':
      case 'new_member':
        final pub = item.meta['publicSignup'] == true ||
            item.meta['publicSignup']?.toString() == '1' ||
            item.meta['publicSignup']?.toString() == 'true';
        return pub ? kChurchShellIndexAprovacoes : kChurchShellIndexMembers;
      case 'pedido_oracao':
      case 'novo_pedido_oracao':
        return ChurchShellIndices.pedidosOracao;
      default:
        return null;
    }
  }

  static DateTime? _ts(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  static List<ChurchNotificationItem> buildFeed({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> tenantDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> inboxDocs,
    required PanelDashboardSnapshot panel,
    required DateTime lastSeenAt,
    required bool includeLive,
  }) {
    final items = <ChurchNotificationItem>[];
    final now = DateTime.now();

    if (includeLive) {
      if (panel.pendingMembersCount > 0) {
        items.add(
          ChurchNotificationItem(
            id: 'live_pending_members',
            source: ChurchNotificationSource.live,
            type: 'novo_membro',
            title: panel.pendingMembersCount == 1
                ? '1 membro aguardando aprovaÃ§Ã£o'
                : '${panel.pendingMembersCount} membros aguardando aprovaÃ§Ã£o',
            body: 'Cadastros pendentes no painel.',
            createdAt: now,
            isRead: true,
            shellIndex: kChurchShellIndexAprovacoes,
          ),
        );
      }
      if (panel.openPrayerRequestsCount > 0) {
        items.add(
          ChurchNotificationItem(
            id: 'live_open_prayers',
            source: ChurchNotificationSource.live,
            type: 'pedido_oracao',
            title: panel.openPrayerRequestsCount == 1
                ? '1 pedido de oraÃ§Ã£o aberto'
                : '${panel.openPrayerRequestsCount} pedidos de oraÃ§Ã£o abertos',
            body: 'A igreja aguarda intercessÃ£o pastoral.',
            createdAt: now,
            isRead: true,
            shellIndex: ChurchShellIndices.pedidosOracao,
          ),
        );
      }
      if (panel.birthdaysToday.isNotEmpty) {
        final names = panel.birthdaysToday
            .take(3)
            .map((m) => m.displayName)
            .join(', ');
        final extra = panel.birthdaysToday.length > 3
            ? ' +${panel.birthdaysToday.length - 3}'
            : '';
        items.add(
          ChurchNotificationItem(
            id: 'live_birthdays_today',
            source: ChurchNotificationSource.live,
            type: 'aniversariantes_dia',
            title: panel.birthdaysToday.length == 1
                ? 'Aniversariante hoje'
                : '${panel.birthdaysToday.length} aniversariantes hoje',
            body: '$names$extra',
            createdAt: now,
            isRead: true,
            shellIndex: kChurchShellIndexPainel,
          ),
        );
      }
      for (final raw in panel.upcomingEventos.take(2)) {
        final title =
            (raw['title'] ?? raw['titulo'] ?? 'Evento').toString().trim();
        final start = _ts(raw['startAt']);
        items.add(
          ChurchNotificationItem(
            id: 'live_evt_${raw['id'] ?? title}',
            source: ChurchNotificationSource.live,
            type: 'novo_evento',
            title: title.isEmpty ? 'PrÃ³ximo evento' : title,
            body: start == null
                ? 'Confira a agenda da igreja.'
                : DateFormat('dd/MM Â· HH:mm', 'pt_BR').format(start),
            createdAt: start ?? now,
            isRead: true,
            shellIndex: kChurchShellIndexEvents,
          ),
        );
      }
    }

    for (final d in tenantDocs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString();
      final created = _ts(m['createdAt']);
      final read = created != null && !created.isAfter(lastSeenAt);
      items.add(
        ChurchNotificationItem(
          id: 't_${d.id}',
          source: ChurchNotificationSource.tenant,
          type: type.isEmpty ? 'generico' : type,
          title: (m['title'] ?? 'NotificaÃ§Ã£o').toString(),
          body: (m['body'] ?? '').toString(),
          createdAt: created,
          isRead: read,
          meta: Map<String, dynamic>.from(m),
        ),
      );
    }

    for (final d in inboxDocs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString();
      items.add(
        ChurchNotificationItem(
          id: 'p_${d.id}',
          source: ChurchNotificationSource.inbox,
          type: type.isEmpty ? 'generico' : type,
          title: (m['title'] ?? 'NotificaÃ§Ã£o').toString(),
          body: (m['body'] ?? '').toString(),
          createdAt: _ts(m['createdAt']),
          isRead: m['read'] == true,
          inboxRef: d.reference,
          meta: m['meta'] is Map
              ? Map<String, dynamic>.from(m['meta'] as Map)
              : const {},
        ),
      );
    }

    items.sort((a, b) {
      final da = a.createdAt;
      final db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final seen = <String>{};
    final deduped = <ChurchNotificationItem>[];
    for (final it in items) {
      final key = '${it.type}|${it.title}|${it.body}';
      if (seen.contains(key)) continue;
      seen.add(key);
      deduped.add(it);
    }
    return deduped.take(80).toList();
  }

  static int countUnread(List<ChurchNotificationItem> items) =>
      items.where((e) => !e.isRead).length;

  static Future<void> markAllRead({
    required String tenantId,
    required String uid,
  }) async {
    await ChurchNotificationSeenPrefs.markAllTenantSeen(tenantId, uid);
    await InternalNotificationInboxService.markAllRead(uid);
  }

  static Future<void> markItemRead(ChurchNotificationItem item) async {
    if (item.source == ChurchNotificationSource.inbox &&
        item.inboxRef != null) {
      await InternalNotificationInboxService.markRead(item.inboxRef!);
    }
  }

  static CollectionReference<Map<String, dynamic>> tenantNotificacoes(
    String tenantId,
  ) =>
      ChurchOperationalPaths.churchDoc(tenantId).collection('notificacoes');
}

/// Agrega streams do painel + caixa pessoal + `notificacoes` da igreja.
class ChurchNotificationFeedScope extends StatefulWidget {
  const ChurchNotificationFeedScope({
    super.key,
    required this.tenantId,
    required this.cpfDigits,
    required this.role,
    required this.builder,
  });

  final String tenantId;
  final String cpfDigits;
  final String role;
  final Widget Function(
    BuildContext context,
    ChurchNotificationFeedSnapshot snapshot,
  ) builder;

  @override
  State<ChurchNotificationFeedScope> createState() =>
      _ChurchNotificationFeedScopeState();
}

class _ChurchNotificationFeedScopeState extends State<ChurchNotificationFeedScope> {
  List<String> _deptIds = const [];
  bool _deptReady = false;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tenantDocs = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _inboxDocs = const [];
  PanelDashboardSnapshot _panel = const PanelDashboardSnapshot();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _tenantSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inboxSub;
  StreamSubscription<PanelDashboardSnapshot>? _panelSub;

  bool get _isStaff => ChurchNotificationCenter.isStaffRole(widget.role);

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(ChurchNotificationFeedScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId.trim() != widget.tenantId.trim() ||
        oldWidget.cpfDigits != widget.cpfDigits ||
        oldWidget.role != widget.role) {
      _rebind();
    }
  }

  Future<void> _bootstrap() async {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    _lastSeen = await ChurchNotificationSeenPrefs.lastSeenAt(
      widget.tenantId,
      uid,
    );
    await _loadDepartments();
    _rebind();
  }

  Future<void> _loadDepartments() async {
    final cpf = widget.cpfDigits;
    final tid = widget.tenantId.trim();
    if (cpf.length != 11 || tid.isEmpty) {
      if (mounted) setState(() => _deptReady = true);
      return;
    }
    try {
      final col = ChurchOperationalPaths.churchDoc(tid).collection('membros');
      DocumentSnapshot<Map<String, dynamic>>? doc;
      final byId = await col.doc(cpf).get(
            const GetOptions(source: Source.serverAndCache),
          );
      if (byId.exists) {
        doc = byId;
      } else {
        final q = await col
            .where('CPF', isEqualTo: cpf)
            .limit(1)
            .get(const GetOptions(source: Source.serverAndCache));
        if (q.docs.isNotEmpty) doc = q.docs.first;
      }
      final raw = doc?.data()?['DEPARTAMENTOS'];
      final ids = raw is List
          ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : <String>[];
      if (mounted) {
        setState(() {
          _deptIds = ids;
          _deptReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _deptReady = true);
    }
  }

  void _rebind() {
    _tenantSub?.cancel();
    _inboxSub?.cancel();
    _panelSub?.cancel();

    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return;

    _panelSub = PanelDashboardSnapshotService.watch(tid).listen((p) {
      if (!mounted) return;
      setState(() => _panel = p);
    });

    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _inboxSub = InternalNotificationInboxService.watch(uid, limit: 60)
          .listen((snap) {
        if (!mounted) return;
        setState(() => _inboxDocs = snap.docs);
      });
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> tenantStream;
    if (_isStaff) {
      tenantStream = ChurchNotificationCenter.tenantNotificacoes(tid)
          .orderBy('createdAt', descending: true)
          .limit(80)
          .watchSafe();
    } else if (widget.cpfDigits.length == 11) {
      tenantStream = ChurchNotificationCenter.tenantNotificacoes(tid)
          .where('memberCpfs', arrayContains: widget.cpfDigits)
          .watchSafe();
    } else {
      tenantStream = Stream<QuerySnapshot<Map<String, dynamic>>>.value(
        const MergedFirestoreQuerySnapshot([]),
      );
    }

    _tenantSub = tenantStream.listen((snap) {
      if (!mounted) return;
      setState(() => _tenantDocs = snap.docs);
    });

    if (!_isStaff &&
        _deptReady &&
        _deptIds.isNotEmpty &&
        _deptIds.length <= 10) {
      ChurchNotificationCenter.tenantNotificacoes(tid)
          .where('departmentId', whereIn: _deptIds)
          .watchSafe()
          .listen((deptSnap) {
        if (!mounted) return;
        final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in _tenantDocs) {
          map[d.id] = d;
        }
        for (final d in deptSnap.docs) {
          map[d.id] = d;
        }
        setState(() => _tenantDocs = map.values.toList());
      });
    }
  }

  @override
  void dispose() {
    _tenantSub?.cancel();
    _inboxSub?.cancel();
    _panelSub?.cancel();
    super.dispose();
  }

  ChurchNotificationFeedSnapshot _snapshot() {
    final items = ChurchNotificationCenter.buildFeed(
      tenantDocs: _tenantDocs,
      inboxDocs: _inboxDocs,
      panel: _panel,
      lastSeenAt: _lastSeen,
      includeLive: _isStaff,
    );
    return ChurchNotificationFeedSnapshot(
      items: items,
      unreadCount: ChurchNotificationCenter.countUnread(items),
      loading: !_deptReady && !_isStaff,
    );
  }

  Future<void> refreshSeen() async {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    _lastSeen = await ChurchNotificationSeenPrefs.lastSeenAt(
      widget.tenantId,
      uid,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _ChurchNotificationFeedInherited(
      refreshSeen: refreshSeen,
      child: widget.builder(context, _snapshot()),
    );
  }
}

class _ChurchNotificationFeedInherited extends InheritedWidget {
  const _ChurchNotificationFeedInherited({
    required this.refreshSeen,
    required super.child,
  });

  final Future<void> Function() refreshSeen;

  static _ChurchNotificationFeedInherited? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ChurchNotificationFeedInherited>();
  }

  @override
  bool updateShouldNotify(_ChurchNotificationFeedInherited oldWidget) => false;
}

Future<void> refreshChurchNotificationSeen(BuildContext context) async {
  await _ChurchNotificationFeedInherited.of(context)?.refreshSeen();
}

