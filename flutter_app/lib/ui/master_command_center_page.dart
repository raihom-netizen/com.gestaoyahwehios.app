import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/services/master_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/ui/admin_dashboard_page.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_action_queue_card.dart';
import 'package:gestao_yahweh/ui/widgets/master_church_detail_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:intl/intl.dart';

/// Home unificada do Painel Master — Command Center Super Premium SaaS.
class MasterCommandCenterPage extends StatefulWidget {
  const MasterCommandCenterPage({
    super.key,
    required this.onNavigateTo,
    this.moduleVisible,
  });

  final void Function(AdminMenuItem item) onNavigateTo;
  final bool Function(AdminMenuItem item)? moduleVisible;

  @override
  State<MasterCommandCenterPage> createState() => _MasterCommandCenterPageState();
}

class _MasterCommandCenterPageState extends State<MasterCommandCenterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  MasterDashboardSummary? _summary;
  bool _loadingSummary = true;
  final _clientSearch = TextEditingController();
  String _clientQ = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _clientSearch.addListener(() {
      setState(() => _clientQ = _clientSearch.text.trim().toLowerCase());
    });
    unawaited(_loadSummary());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _clientSearch.dispose();
    super.dispose();
  }

  Future<void> _loadSummary({bool force = false}) async {
    setState(() => _loadingSummary = true);
    try {
      final s = await MasterDashboardCacheService.refresh(force: force);
      if (mounted) setState(() => _summary = s);
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  MasterChurchHealth _healthFor(Map<String, dynamic> data) {
    final g = SubscriptionGuard.evaluate(church: data);
    if (g.isFree) return MasterChurchHealth.free;
    if (g.adminBlocked || g.blocked) return MasterChurchHealth.critical;
    if (g.inGrace || g.statusAssinatura == 'overdue') {
      return MasterChurchHealth.warning;
    }
    return MasterChurchHealth.ok;
  }

  Future<void> _exportClientsCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final b = StringBuffer('id,nome,plano,status\n');
    for (final d in docs) {
      final data = d.data();
      final nome = (data['nome'] ?? data['name'] ?? '').toString().replaceAll(',', ' ');
      final plano = (data['plano'] ?? data['planId'] ?? '').toString();
      final st = SubscriptionGuard.evaluate(church: data).masterBadgeLabel;
      b.writeln('${d.id},$nome,$plano,$st');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copiado para a área de transferência.')),
      );
    }
  }

  Future<void> _exportMasterSummaryCsv(MasterDashboardSummary s) async {
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final b = StringBuffer()
      ..writeln('metrica,valor')
      ..writeln('igrejas,${s.igrejas}')
      ..writeln('usuarios,${s.usuarios}')
      ..writeln('receita,${brl.format(s.receita)}')
      ..writeln('licencas_ativas,${s.licencasAtivas}')
      ..writeln('alertas,${s.alertas}')
      ..writeln('vencimentos_7d,${s.vencimentos7d}')
      ..writeln('bloqueadas,${s.blockedCount}')
      ..writeln('free,${s.freeCount}');
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resumo KPI copiado (CSV).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final s = _summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF0D9488),
                Color(0xFF2563EB),
                Color(0xFF7C3AED),
              ],
            ),
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Visão geral'),
              Tab(text: 'Clientes'),
              Tab(text: 'BI completo'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              RefreshIndicator(
                onRefresh: () => _loadSummary(force: true),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 32),
                  children: [
                    MasterModuleSectionTitle(
                      title: 'Command Center',
                      subtitle:
                          'Centro de comando SaaS — métricas, alertas e atalhos.',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s != null)
                            IconButton(
                              onPressed: () => _exportMasterSummaryCsv(s),
                              icon: const Icon(Icons.download_rounded),
                              tooltip: 'Exportar KPIs (CSV)',
                            ),
                          IconButton(
                            onPressed: () => _loadSummary(force: true),
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Atualizar métricas',
                          ),
                        ],
                      ),
                    ),
                    MasterCacheUpdatedBadge(summary: s),
                    const SizedBox(height: 8),
                    if (_loadingSummary)
                      const Center(child: CircularProgressIndicator())
                    else if (s != null) ...[
                      LayoutBuilder(
                        builder: (_, c) {
                          final w = c.maxWidth;
                          final cols = w > 1100 ? 5 : (w > 700 ? 3 : 2);
                          final children = <Widget>[
                            MasterKpiCard(
                              label: 'Igrejas',
                              value: '${s.igrejas}',
                              icon: Icons.church_rounded,
                              accent: const Color(0xFF2563EB),
                              onTap: () => widget.onNavigateTo(AdminMenuItem.igrejasLista),
                            ),
                            MasterKpiCard(
                              label: 'Usuários',
                              value: '${s.usuarios}',
                              icon: Icons.people_rounded,
                              accent: const Color(0xFF0D9488),
                              onTap: () =>
                                  widget.onNavigateTo(AdminMenuItem.igrejasUsuarios),
                            ),
                            MasterKpiCard(
                              label: 'Licenças ativas',
                              value: '${s.licencasAtivas}',
                              icon: Icons.verified_rounded,
                              accent: const Color(0xFF16A34A),
                              onTap: () =>
                                  widget.onNavigateTo(AdminMenuItem.igrejasPlanos),
                            ),
                            MasterKpiCard(
                              label: 'Receita (amostra)',
                              value: brl.format(s.receita),
                              icon: Icons.payments_rounded,
                              accent: const Color(0xFFF59E0B),
                              onTap: () => widget
                                  .onNavigateTo(AdminMenuItem.igrejasRecebimentos),
                            ),
                            MasterKpiCard(
                              label: 'Alertas',
                              value: '${s.alertas}',
                              icon: Icons.notifications_active_rounded,
                              accent: const Color(0xFFF43F5E),
                              subtitle: s.vencimentos7d > 0
                                  ? '${s.vencimentos7d} vencem em 7d'
                                  : null,
                              onTap: () =>
                                  widget.onNavigateTo(AdminMenuItem.sistemaAlertas),
                            ),
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: children
                                .map((w) => SizedBox(
                                      width: (c.maxWidth - 12 * (cols - 1)) / cols,
                                      child: w,
                                    ))
                                .toList(),
                          );
                        },
                      ),
                      if (s.hasActionQueue) ...[
                        const SizedBox(height: 16),
                        MasterActionQueueCard(
                          items: s.actionQueue,
                          onNavigateTo: widget.onNavigateTo,
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    _QuickModulesGrid(
                      onOpen: widget.onNavigateTo,
                      visible: widget.moduleVisible ?? (_) => true,
                    ),
                  ],
                ),
              ),
              _ClientsTab(
                search: _clientQ,
                searchCtrl: _clientSearch,
                healthFor: _healthFor,
                onExport: _exportClientsCsv,
                onOpen: (id, data) => MasterChurchDetailSheet.show(
                  context,
                  tenantId: id,
                  churchData: data,
                  onNavigateTo: widget.onNavigateTo,
                ),
              ),
              AdminDashboardPage(
                embedInPanel: true,
                onNavigateTo: widget.onNavigateTo,
                masterModuleVisible: widget.moduleVisible,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientsTab extends StatelessWidget {
  const _ClientsTab({
    required this.search,
    required this.searchCtrl,
    required this.healthFor,
    required this.onExport,
    required this.onOpen,
  });

  final String search;
  final TextEditingController searchCtrl;
  final MasterChurchHealth Function(Map<String, dynamic>) healthFor;
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)
      onExport;
  final void Function(String id, Map<String, dynamic> data) onOpen;

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad.left, 12, pad.right, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Filtrar clientes…',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('igrejas')
                .limit(350)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data!.docs;
              if (search.isNotEmpty) {
                docs = docs.where((d) {
                  final data = d.data();
                  final nome =
                      '${data['nome'] ?? data['name'] ?? ''}'.toLowerCase();
                  return nome.contains(search) ||
                      d.id.toLowerCase().contains(search);
                }).toList();
              }
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad.left),
                    child: Row(
                      children: [
                        Text('${docs.length} clientes',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => onExport(docs),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Exportar CSV'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 24),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        final nome =
                            (data['nome'] ?? data['name'] ?? doc.id).toString();
                        final plano =
                            (data['plano'] ?? data['planId'] ?? '—').toString();
                        return MasterPremiumCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: InkWell(
                            onTap: () => onOpen(doc.id, data),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(nome,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          )),
                                      Text(
                                        '$plano · ${doc.id}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                MasterHealthChip(
                                  health: healthFor(data),
                                  compact: true,
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QuickModulesGrid extends StatelessWidget {
  const _QuickModulesGrid({required this.onOpen, required this.visible});

  final void Function(AdminMenuItem item) onOpen;
  final bool Function(AdminMenuItem item) visible;

  static const _items = [
    (AdminMenuItem.igrejasLista, Icons.church_rounded, 'Clientes'),
    (AdminMenuItem.igrejasPlanos, Icons.credit_card_rounded, 'Receita'),
    (AdminMenuItem.sistemaAlertas, Icons.notifications_rounded, 'Alertas'),
    (AdminMenuItem.sistemaAuditoria, Icons.history_rounded, 'Auditoria'),
    (AdminMenuItem.sistemaFeatureFlags, Icons.toggle_on_rounded, 'Flags'),
    (AdminMenuItem.sistemaAvisoGlobal, Icons.campaign_rounded, 'Comunicação'),
    (AdminMenuItem.sistemaArmazenamento, Icons.storage_rounded, 'Storage'),
    (AdminMenuItem.sistemaMultiAdmin, Icons.admin_panel_settings_rounded, 'Admins'),
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = _items.where((t) => visible(t.$1)).toList();
    return MasterPremiumCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: tiles
            .map(
              (t) => ActionChip(
                avatar: Icon(t.$2, size: 18, color: ThemeCleanPremium.primary),
                label: Text(t.$3),
                onPressed: () => onOpen(t.$1),
              ),
            )
            .toList(),
      ),
    );
  }
}
