import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/services/church_dashboard_current_service.dart';
import 'package:gestao_yahweh/services/church_finance_aggregates_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Dobra hero do painel — 7 blocos sempre visíveis acima da dobra (sem scroll longo).
class DashboardIntelligentHero extends StatefulWidget {
  const DashboardIntelligentHero({
    super.key,
    required this.tenantId,
    required this.panel,
    required this.kpis,
    required this.canViewFinance,
    required this.onNavigateToShellModule,
    required this.onOpenAniversariantes,
  });

  final String tenantId;
  final PanelDashboardSnapshot panel;
  final ChurchDashboardCurrent kpis;
  final bool canViewFinance;
  final ValueChanged<int> onNavigateToShellModule;
  final VoidCallback onOpenAniversariantes;

  @override
  State<DashboardIntelligentHero> createState() =>
      _DashboardIntelligentHeroState();
}

class _DashboardIntelligentHeroState extends State<DashboardIntelligentHero> {
  int _upcomingEscalas = 0;
  String? _nextEscalaLabel;
  bool _escalasLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEscalas();
  }

  @override
  void didUpdateWidget(DashboardIntelligentHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId.trim() != widget.tenantId.trim()) {
      _loadEscalas();
    }
  }

  Future<void> _loadEscalas() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      if (mounted) {
        setState(() {
          _escalasLoading = false;
          _upcomingEscalas = 0;
          _nextEscalaLabel = null;
        });
      }
      return;
    }
    setState(() => _escalasLoading = true);
    try {
      await ChurchTenantResilientReads.preparePanelRead();
      final snap = await ChurchTenantResilientReads.escalasRecent(tid, limit: 48);
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final upcoming = <({DateTime dt, String title})>[];
      for (final doc in snap.docs) {
        final m = doc.data();
        final raw = m['date'];
        if (raw is! Timestamp) continue;
        final dt = raw.toDate();
        if (dt.isBefore(startOfToday)) continue;
        final title = (m['title'] ?? m['departmentName'] ?? 'Escala')
            .toString()
            .trim();
        upcoming.add((dt: dt, title: title.isEmpty ? 'Escala' : title));
      }
      upcoming.sort((a, b) => a.dt.compareTo(b.dt));
      if (!mounted) return;
      setState(() {
        _upcomingEscalas = upcoming.length;
        if (upcoming.isEmpty) {
          _nextEscalaLabel = null;
        } else {
          final first = upcoming.first;
          _nextEscalaLabel =
              '${DateFormat('dd/MM', 'pt_BR').format(first.dt)} · ${first.title}';
        }
        _escalasLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _escalasLoading = false;
        _upcomingEscalas = 0;
        _nextEscalaLabel = null;
      });
    }
  }

  int _membersCount() {
    if (widget.panel.membersTotalCount > 0) {
      return widget.panel.membersTotalCount;
    }
    return widget.kpis.totalMembers;
  }

  int _visitorsCount() {
    if (widget.panel.newVisitorsCount > 0) {
      return widget.panel.newVisitorsCount;
    }
    return widget.kpis.newVisitors;
  }

  int _birthdaysTodayCount() {
    if (widget.panel.birthdaysToday.isNotEmpty) {
      return widget.panel.birthdaysToday.length;
    }
    return widget.kpis.birthdaysToday;
  }

  int _eventsCount() {
    final n = widget.panel.upcomingEventos.length;
    if (n > 0) return n;
    return widget.kpis.totalUpcomingEvents;
  }

  String? _nextEventLabel() {
    final list = widget.panel.upcomingEventos;
    if (list.isEmpty) return null;
    final first = list.first;
    final title =
        (first['title'] ?? first['titulo'] ?? 'Evento').toString().trim();
    final start = first['startAt'];
    if (start is Timestamp) {
      return '${DateFormat('dd/MM', 'pt_BR').format(start.toDate())} · $title';
    }
    return title.isEmpty ? 'Próximo evento' : title;
  }

  String? _latestAvisoLabel() {
    if (widget.panel.homeAvisos.isNotEmpty) {
      return widget.panel.homeAvisos.first.title;
    }
    if (widget.panel.recentAvisos.isNotEmpty) {
      final a = widget.panel.recentAvisos.first;
      return (a['title'] ?? a['titulo'] ?? 'Aviso').toString().trim();
    }
    return null;
  }

  int _avisosCount() {
    if (widget.panel.homeAvisos.isNotEmpty) {
      return widget.panel.homeAvisos.length;
    }
    return widget.panel.recentAvisos.length;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final cols = isWide ? 4 : 2;
    final aspect = isWide ? 1.22 : 1.08;
    final nfCompact = NumberFormat.compactCurrency(
      locale: 'pt_BR',
      symbol: r'R$',
      decimalDigits: 0,
    );

    Widget financeTile() {
      if (!widget.canViewFinance) {
        return _HeroTile(
          icon: Icons.lock_outline_rounded,
          iconTint: const Color(0xFF94A3B8),
          iconBg: const Color(0xFFF1F5F9),
          label: 'Financeiro',
          value: '—',
          subtitle: 'Acesso restrito',
        );
      }
      return StreamBuilder<ChurchFinanceAggregates>(
        stream: ChurchFinanceAggregatesService.watch(widget.tenantId),
        builder: (context, snap) {
          final agg = snap.data ?? const ChurchFinanceAggregates();
          final saldo = nfCompact.format(agg.saldoAtual);
          final fluxo = agg.receitasMes - agg.despesasMes;
          final fluxoLabel = fluxo >= 0
              ? '+${nfCompact.format(fluxo)} no mês'
              : '${nfCompact.format(fluxo)} no mês';
          return _HeroTile(
            icon: Icons.account_balance_wallet_rounded,
            iconTint: const Color(0xFF059669),
            iconBg: const Color(0xFFD1FAE5),
            label: 'Financeiro',
            value: saldo,
            subtitle: agg.hasData ? fluxoLabel : 'Sem lançamentos',
            onTap: () =>
                widget.onNavigateToShellModule(kChurchShellIndexFinanceiro),
          );
        },
      );
    }

    final tiles = <Widget>[
      _HeroTile(
        icon: Icons.people_alt_rounded,
        iconTint: const Color(0xFF2563EB),
        iconBg: const Color(0xFFDBEAFE),
        label: 'Membros ativos',
        value: '${_membersCount()}',
        subtitle: widget.panel.pendingMembersCount > 0
            ? '${widget.panel.pendingMembersCount} pendente(s)'
            : 'Cadastro ativo',
        onTap: () => widget.onNavigateToShellModule(kChurchShellIndexMembers),
      ),
      _HeroTile(
        icon: Icons.person_add_alt_1_rounded,
        iconTint: const Color(0xFF0D9488),
        iconBg: const Color(0xFFCCFBF1),
        label: 'Visitantes do mês',
        value: '${_visitorsCount()}',
        subtitle: _visitorsCount() > 0 ? 'Novos este mês' : 'Nenhum novo',
        onTap: () =>
            widget.onNavigateToShellModule(ChurchShellIndices.visitantes),
      ),
      _HeroTile(
        icon: Icons.event_rounded,
        iconTint: const Color(0xFF7C3AED),
        iconBg: const Color(0xFFEDE9FE),
        label: 'Próximos eventos',
        value: '${_eventsCount()}',
        subtitle: _nextEventLabel() ?? 'Nenhum agendado',
        onTap: () => widget.onNavigateToShellModule(kChurchShellIndexEvents),
      ),
      _HeroTile(
        icon: Icons.calendar_month_rounded,
        iconTint: const Color(0xFFEA580C),
        iconBg: const Color(0xFFFFEDD5),
        label: 'Próximas escalas',
        value: _escalasLoading ? '…' : '$_upcomingEscalas',
        subtitle: _nextEscalaLabel ?? 'Nenhuma próxima',
        onTap: () =>
            widget.onNavigateToShellModule(kChurchShellIndexEscalaGeral),
      ),
      _HeroTile(
        icon: Icons.cake_rounded,
        iconTint: const Color(0xFFDB2777),
        iconBg: const Color(0xFFFCE7F3),
        label: 'Aniversariantes',
        value: '${_birthdaysTodayCount()}',
        subtitle: _birthdaysTodayCount() > 0
            ? 'Hoje na igreja'
            : 'Ninguém hoje',
        onTap: widget.onOpenAniversariantes,
      ),
      financeTile(),
      _HeroTile(
        icon: Icons.campaign_rounded,
        iconTint: const Color(0xFFD97706),
        iconBg: const Color(0xFFFEF3C7),
        label: 'Últimos avisos',
        value: '${_avisosCount()}',
        subtitle: _latestAvisoLabel() ?? 'Nenhum aviso',
        onTap: () => widget.onNavigateToShellModule(kChurchShellIndexMural),
      ),
    ];

    final updatedAt = widget.panel.cacheUpdatedAt;
    String? cacheLabel;
    if (updatedAt != null) {
      final diff = DateTime.now().difference(updatedAt.toDate());
      if (diff.inMinutes < 2) {
        cacheLabel = 'Atualizado agora';
      } else if (diff.inMinutes < 60) {
        cacheLabel = 'Atualizado há ${diff.inMinutes} min';
      } else if (diff.inHours < 24) {
        cacheLabel = 'Atualizado há ${diff.inHours} h';
      } else {
        cacheLabel =
            'Atualizado ${DateFormat('dd/MM HH:mm').format(updatedAt.toDate())}';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      padding: EdgeInsets.all(
        ThemeCleanPremium.isMobile(context)
            ? ThemeCleanPremium.spaceSm
            : ThemeCleanPremium.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visão da igreja',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: ThemeCleanPremium.isMobile(context) ? 16 : 18,
                        color: ThemeCleanPremium.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat("EEEE, d 'de' MMMM", 'pt_BR')
                          .format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (cacheLabel != null)
                Text(
                  cacheLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: aspect,
            children: tiles,
          ),
        ],
      ),
    );
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.icon,
    required this.iconTint,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconTint;
  final Color iconBg;
  final String label;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final minSide = ThemeCleanPremium.minTouchTarget;
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                ThemeCleanPremium.hapticAction();
                onTap!();
              },
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minSide, minWidth: minSide),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 16, color: iconTint),
                    ),
                    const Spacer(),
                    Text(
                      value,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: ThemeCleanPremium.isMobile(context) ? 17 : 19,
                        color: ThemeCleanPremium.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
