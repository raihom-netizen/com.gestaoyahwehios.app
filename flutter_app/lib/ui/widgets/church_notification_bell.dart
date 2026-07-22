import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_notification_center.dart';
import 'package:gestao_yahweh/ui/pages/notifications_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_login_ui.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_bank_notification_tile.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_foreground_notification_snackbar.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_module_icon_badge.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// Grid de filtros por módulo — padrão visual Controle Total (PNG + accent).
class NotificationCenterModuleFilterGrid extends StatelessWidget {
  const NotificationCenterModuleFilterGrid({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.unreadForFilter,
  });

  final String selectedId;
  final ValueChanged<String> onSelected;
  final int Function(String filterId)? unreadForFilter;

  static const filters = <({
    String id,
    String label,
    String? moduleKey,
    bool emblem,
    IconData? icon,
  })>[
    (id: 'all', label: 'Todas', moduleKey: null, emblem: false, icon: Icons.apps_rounded),
    (id: 'membro', label: 'Membros', moduleKey: 'membro', emblem: false, icon: null),
    (id: 'pastoral', label: 'Oração', moduleKey: 'pastoral', emblem: false, icon: null),
    (id: 'aniversario', label: 'Aniversários', moduleKey: 'aniversario', emblem: false, icon: null),
    (id: 'escala', label: 'Escalas', moduleKey: 'escala', emblem: false, icon: null),
    (id: 'evento', label: 'Eventos', moduleKey: 'evento', emblem: false, icon: null),
    (id: 'aviso', label: 'Avisos', moduleKey: 'aviso', emblem: true, icon: null),
    (id: 'visitante', label: 'Visitantes', moduleKey: 'visitante', emblem: false, icon: null),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: filters.length,
        itemBuilder: (context, i) {
          final f = filters[i];
          final selected = selectedId == f.id;
          final accent = f.id == 'all'
              ? ThemeCleanPremium.primary
              : gyModuleAccentColor(f.moduleKey ?? f.id);
          final unread = unreadForFilter?.call(f.id) ?? 0;

          return _FilterTile(
            label: f.label,
            selected: selected,
            accent: accent,
            unread: unread,
            onTap: () => onSelected(f.id),
            child: _FilterIcon(
              filterId: f.id,
              moduleKey: f.moduleKey,
              emblem: f.emblem,
              icon: f.icon,
              accent: accent,
              selected: selected,
            ),
          );
        },
      ),
    );
  }
}

class _FilterIcon extends StatelessWidget {
  const _FilterIcon({
    required this.filterId,
    required this.moduleKey,
    required this.emblem,
    required this.accent,
    required this.selected,
    this.icon,
  });

  final String filterId;
  final String? moduleKey;
  final bool emblem;
  final IconData? icon;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 38.0;
    if (filterId == 'all') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: selected
                ? [accent, Color.lerp(accent, Colors.white, 0.35)!]
                : [const Color(0xFF0B1B4B), const Color(0xFF1D4ED8)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(icon ?? Icons.apps_rounded, color: Colors.white, size: 20),
      );
    }
    if (emblem && moduleKey == 'aviso') {
      return YahwehAvisosEmblemIcon(size: size);
    }
    if (moduleKey != null) {
      return YahwehModuleIconBadge(
        moduleKey: moduleKey,
        accent: accent,
        size: size,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Icon(icon ?? Icons.notifications_rounded, color: accent, size: 20),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    required this.child,
    this.unread = 0,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  if (unread > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: selected ? accent : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
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
  String _filter = 'all';

  int _unreadForFilter(String filterId) {
    if (filterId == 'all') return widget.snapshot.unreadCount;
    return widget.snapshot.items
        .where((e) => !e.isRead && e.module == filterId)
        .length;
  }

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
    final unread = widget.snapshot.unreadCount;

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.42,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 28,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kChurchWisdomLoginNavy,
                      Color.lerp(kChurchWisdomLoginNavy, kChurchWisdomLoginTeal, 0.45)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: kChurchWisdomLoginNavy.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Central de notificações',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (unread > 0)
                            Text(
                              '$unread não ${unread == 1 ? 'lida' : 'lidas'}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (unread > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => unawaited(_markAllRead()),
                          child: Text(
                            'Marcar lidas',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Ver todas',
                      onPressed: () => unawaited(_openFullPage()),
                      icon: const Icon(
                        Icons.open_in_new_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotificationCenterModuleFilterGrid(
                selectedId: _filter,
                onSelected: (id) => setState(() => _filter = id),
                unreadForFilter: _unreadForFilter,
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
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 40,
                  color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Nenhuma notificação nesta categoria.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: ThemeCleanPremium.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = items[i];
        final dt = item.createdAt;
        final dateTxt =
            dt == null ? '' : DateFormat('dd/MM · HH:mm', 'pt_BR').format(dt);
        return GestaoBankNotificationTile(
          title: item.title,
          body: item.body,
          module: item.module,
          dateLabel: dateTxt.isEmpty
              ? gyModuleLabel(item.module)
              : '${gyModuleLabel(item.module)} · $dateTxt',
          isRead: item.isRead,
          onTap: () => unawaited(_onItemTap(item)),
        );
      },
    );
  }
}
