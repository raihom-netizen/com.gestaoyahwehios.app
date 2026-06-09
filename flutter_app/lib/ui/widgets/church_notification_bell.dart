import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_notification_center.dart';
import 'package:gestao_yahweh/ui/pages/notifications_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_foreground_notification_snackbar.dart';
import 'package:intl/intl.dart';

/// Sino unificado no topo do painel — badge + feed rápido.
class ChurchNotificationBell extends StatelessWidget {
  const ChurchNotificationBell({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.onNavigateToShellModule,
    this.iconColor = Colors.white,
  });

  final String tenantId;
  final String cpf;
  final String role;
  final ValueChanged<int> onNavigateToShellModule;
  final Color iconColor;

  void _openSheet(BuildContext context) {
    ThemeCleanPremium.hapticAction();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChurchNotificationFeedScope(
        tenantId: tenantId,
        cpfDigits: cpf.replaceAll(RegExp(r'\D'), ''),
        role: role,
        builder: (context, snapshot) {
          return _NotificationCenterSheet(
            tenantId: tenantId,
            cpf: cpf,
            role: role,
            snapshot: snapshot,
            onNavigateToShellModule: onNavigateToShellModule,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChurchNotificationFeedScope(
      tenantId: tenantId,
      cpfDigits: cpf.replaceAll(RegExp(r'\D'), ''),
      role: role,
      builder: (context, snapshot) {
        final unread = snapshot.unreadCount;
        return IconButton(
          tooltip: unread > 0
              ? 'Notificações ($unread não lidas)'
              : 'Central de notificações',
          onPressed: () => _openSheet(context),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            backgroundColor: const Color(0xFFEF4444),
            child: Icon(
              unread > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: iconColor,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCenterSheet extends StatefulWidget {
  const _NotificationCenterSheet({
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.snapshot,
    required this.onNavigateToShellModule,
  });

  final String tenantId;
  final String cpf;
  final String role;
  final ChurchNotificationFeedSnapshot snapshot;
  final ValueChanged<int> onNavigateToShellModule;

  @override
  State<_NotificationCenterSheet> createState() =>
      _NotificationCenterSheetState();
}

class _NotificationCenterSheetState extends State<_NotificationCenterSheet> {
  static const _filters = <({String id, String label})>[
    (id: 'all', label: 'Todas'),
    (id: 'membro', label: 'Membros'),
    (id: 'pastoral', label: 'Oração'),
    (id: 'aniversario', label: 'Aniversários'),
    (id: 'escala', label: 'Escalas'),
    (id: 'evento', label: 'Eventos'),
  ];

  String _filter = 'all';

  Future<void> _openFullPage() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push<void>(
      ThemeCleanPremium.fadeSlideRoute(
        NotificationsPage(
          tenantId: widget.tenantId,
          cpf: widget.cpf,
          role: widget.role,
          onNavigateToShellModule: widget.onNavigateToShellModule,
        ),
      ),
    );
    if (mounted) {
      await refreshChurchNotificationSeen(context);
    }
  }

  Future<void> _onItemTap(ChurchNotificationItem item) async {
    await ChurchNotificationCenter.markItemRead(item);
    final shell = ChurchNotificationCenter.shellIndexForItem(item);
    if (shell != null && mounted) {
      Navigator.of(context).pop();
      widget.onNavigateToShellModule(shell);
    }
  }

  Future<void> _markAllRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    await ChurchNotificationCenter.markAllRead(
      tenantId: widget.tenantId,
      uid: uid,
    );
    if (mounted) {
      await refreshChurchNotificationSeen(context);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.38,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Central de notificações',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (widget.snapshot.unreadCount > 0)
                      TextButton(
                        onPressed: () => unawaited(_markAllRead()),
                        child: const Text('Marcar lidas'),
                      ),
                    IconButton(
                      tooltip: 'Ver todas',
                      onPressed: () => unawaited(_openFullPage()),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = _filters[i];
                    final selected = _filter == f.id;
                    return FilterChip(
                      label: Text(f.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = f.id),
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color:
                            selected ? Colors.white : const Color(0xFF475569),
                      ),
                      selectedColor: ThemeCleanPremium.primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: selected
                            ? ThemeCleanPremium.primary
                            : const Color(0xFFE2E8F0),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _buildList(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(ScrollController scrollController) {
    if (widget.snapshot.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    var items = widget.snapshot.items;
    if (_filter != 'all') {
      items = items.where((e) => e.module == _filter).toList();
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhuma notificação nesta categoria.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeCleanPremium.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = items[i];
        final dt = item.createdAt;
        final dateTxt =
            dt == null ? '' : DateFormat('dd/MM HH:mm', 'pt_BR').format(dt);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          child: InkWell(
            onTap: () => unawaited(_onItemTap(item)),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(
                  color: item.isRead
                      ? const Color(0xFFE2E8F0)
                      : item.accent.withValues(alpha: 0.35),
                ),
                boxShadow:
                    item.isRead ? null : ThemeCleanPremium.softUiCardShadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontWeight: item.isRead
                                      ? FontWeight.w700
                                      : FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (!item.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: item.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        if (item.body.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            item.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeCleanPremium.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                        if (dateTxt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${gyModuleLabel(item.module)} · $dateTxt',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
