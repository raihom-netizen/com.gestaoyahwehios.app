import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

class VisitorsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  const VisitorsPage({super.key, required this.tenantId, required this.role});

  @override
  State<VisitorsPage> createState() => _VisitorsPageState();
}

/// Aba principal: Do Dia (cadastros de hoje, em aberto) | Histórico (consultas)
enum _TabVisitante { doDia, historico }

/// Quem pode gerir visitantes (igual critério da lista no módulo).
bool churchVisitorManagementRole(String role) {
  final r = role.toLowerCase();
  return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
}

/// Abre a ficha completa do visitante (editar, follow-up, excluir) sem trocar o módulo do shell.
Future<void> openChurchVisitorFichaFromDashboard(
  BuildContext context, {
  required String tenantId,
  required String role,
  required String visitorDocId,
}) async {
  await FirebaseAuth.instance.currentUser?.getIdToken(true);
  final snap = await FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('visitantes')
      .doc(visitorDocId)
      .get();
  if (!context.mounted) return;
  if (!snap.exists || snap.data() == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visitante não encontrado.')),
    );
    return;
  }
  final visitor = _VisitorData(id: snap.id, data: snap.data()!);
  final membersRef = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('membros');
  final canManage = churchVisitorManagementRole(role);
  final isMobile = ThemeCleanPremium.isMobile(context);
  if (isMobile) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _VisitorDetailsPage(
          tenantId: tenantId,
          visitor: visitor,
          canManage: canManage,
          canConvertVisitor: AppPermissions.canConvertVisitorToMember(role),
          membersRef: membersRef,
        ),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: _VisitorDetailsPage(
            tenantId: tenantId,
            visitor: visitor,
            canManage: canManage,
            canConvertVisitor: AppPermissions.canConvertVisitorToMember(role),
            membersRef: membersRef,
            isDialog: true,
          ),
        ),
      ),
    );
  }
}

class _VisitorsPageState extends State<VisitorsPage> {
  _TabVisitante _tab = _TabVisitante.doDia;
  String _searchNome = '';
  DateTime? _filtroData;
  int? _filtroDia;
  int? _filtroMes;
  int? _filtroAno;
  late Future<QuerySnapshot<Map<String, dynamic>>> _visitantesFuture;

  bool get _canManage => churchVisitorManagementRole(widget.role);

  CollectionReference<Map<String, dynamic>> get _visitantesRef =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('visitantes');

  CollectionReference<Map<String, dynamic>> get _membersRef =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisitantes() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 200));
    return _visitantesRef.orderBy('createdAt', descending: true).get();
  }

  void _refresh() {
    setState(() {
      _visitantesFuture = _loadVisitantes();
    });
  }

  @override
  void initState() {
    super.initState();
    _visitantesFuture = _loadVisitantes();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final tt = Theme.of(context).textTheme;

    final showAppBar = !isMobile || Navigator.canPop(context);
    return Scaffold(
      appBar: !showAppBar
          ? null
          : AppBar(
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              title: const Text('Visitantes / Primeiro Contato'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _refresh,
                  tooltip: 'Atualizar',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(
                      ThemeCleanPremium.minTouchTarget,
                      ThemeCleanPremium.minTouchTarget,
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openVisitorForm(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Novo Visitante'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _visitantesFuture,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: ThemeCleanPremium.pagePadding(context),
                child: ChurchPanelErrorBody(
                  title: 'Não foi possível carregar os visitantes',
                  error: snap.error,
                  onRetry: _refresh,
                ),
              );
            }

            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const ChurchPanelLoadingBody();
            }

            final allDocs = snap.data?.docs ?? [];
            final allVisitors = allDocs
                .map((d) => _VisitorData(id: d.id, data: d.data()))
                .toList();

            final filtered = _applyFilters(allVisitors);

            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: ThemeCleanPremium.pagePadding(context),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (isMobile) ...[
                          Text(
                            'Visitantes',
                            style: tt.headlineMedium?.copyWith(
                              color: ThemeCleanPremium.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                        ],
                        _SummaryCards(visitors: allVisitors, isMobile: isMobile),
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _buildTabBar(context),
                        const SizedBox(height: ThemeCleanPremium.spaceMd),
                        if (_tab == _TabVisitante.historico) ...[
                          _buildFiltrosHistorico(context, tt),
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                        ] else ...[
                          _buildSearchField(tt),
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                        ],
                        const SizedBox(height: ThemeCleanPremium.spaceMd),
                      ]),
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(tt),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ThemeCleanPremium.isNarrow(context)
                            ? ThemeCleanPremium.spaceSm
                            : ThemeCleanPremium.spaceLg,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _VisitorCard(
                            visitor: filtered[i],
                            tenantId: widget.tenantId,
                            canManage: _canManage,
                            onTap: () => _openVisitorDetails(context, filtered[i]),
                            onEdit: () => _openVisitorForm(context, visitor: filtered[i]),
                            onDelete: () => _confirmDelete(context, filtered[i]),
                          ),
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Material(
      color: ThemeCleanPremium.cardBackground,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      elevation: 0,
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: _tab == _TabVisitante.doDia ? ThemeCleanPremium.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              child: InkWell(
                onTap: () => setState(() => _tab = _TabVisitante.doDia),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.today_rounded, size: 20, color: _tab == _TabVisitante.doDia ? Colors.white : ThemeCleanPremium.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('Do Dia', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _tab == _TabVisitante.doDia ? Colors.white : ThemeCleanPremium.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: _tab == _TabVisitante.historico ? ThemeCleanPremium.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              child: InkWell(
                onTap: () => setState(() => _tab = _TabVisitante.historico),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded, size: 20, color: _tab == _TabVisitante.historico ? Colors.white : ThemeCleanPremium.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('Histórico', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _tab == _TabVisitante.historico ? Colors.white : ThemeCleanPremium.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _mesesAbr = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  static String _mesAbr(int month) => month >= 1 && month <= 12 ? _mesesAbr[month - 1] : '$month';

  Widget _buildFiltrosHistorico(BuildContext context, TextTheme tt) {
    final now = DateTime.now();
    return Wrap(
      spacing: ThemeCleanPremium.spaceXs,
      runSpacing: ThemeCleanPremium.spaceXs,
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            onChanged: (v) => setState(() => _searchNome = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Buscar por nome',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _filtroData ?? now, firstDate: DateTime(2020), lastDate: now);
            if (d != null) setState(() { _filtroData = d; });
          },
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: Text(_filtroData != null ? '${_filtroData!.day.toString().padLeft(2,'0')}/${_filtroData!.month.toString().padLeft(2,'0')}/${_filtroData!.year}' : 'Data'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroDia,
          decoration: InputDecoration(
            labelText: 'Dia',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(31, (i) => DropdownMenuItem<int?>(value: i + 1, child: Text('${i + 1}')))],
          onChanged: (v) => setState(() => _filtroDia = v),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroMes,
          decoration: InputDecoration(
            labelText: 'Mês',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(12, (i) => DropdownMenuItem<int?>(value: i + 1, child: Text(_mesAbr(i + 1))))],
          onChanged: (v) => setState(() => _filtroMes = v),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroAno,
          decoration: InputDecoration(
            labelText: 'Ano',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(now.year - 2019, (i) => DropdownMenuItem<int?>(value: 2020 + i, child: Text('${2020 + i}')))],
          onChanged: (v) => setState(() => _filtroAno = v),
        ),
        if (_filtroData != null || _filtroDia != null || _filtroMes != null || _filtroAno != null)
          TextButton.icon(
            onPressed: () => setState(() { _filtroData = null; _filtroDia = null; _filtroMes = null; _filtroAno = null; }),
            icon: const Icon(Icons.clear_rounded, size: 18),
            label: const Text('Limpar'),
          ),
      ],
    );
  }

  Widget _buildSearchField(TextTheme tt) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchNome = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou telefone…',
          prefixIcon: const Icon(Icons.search_rounded, color: ThemeCleanPremium.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: const BorderSide(color: ThemeCleanPremium.primaryLight, width: 2),
          ),
          filled: true,
          fillColor: ThemeCleanPremium.cardBackground,
        ),
      ),
    );
  }

  Widget _buildEmptyState(TextTheme tt) {
    final hasFilters = _searchNome.isNotEmpty || _filtroData != null || _filtroDia != null || _filtroMes != null || _filtroAno != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Text(
            hasFilters ? 'Nenhum visitante encontrado' : (_tab == _TabVisitante.doDia ? 'Nenhum visitante hoje' : 'Nenhum visitante no histórico'),
            style: tt.titleMedium?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceXs),
          Text(
            hasFilters ? 'Tente outro filtro' : (_tab == _TabVisitante.doDia ? 'Cadastros do culto aparecem aqui' : 'Adicione o primeiro visitante com o botão +'),
            style: tt.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  List<_VisitorData> _applyFilters(List<_VisitorData> all) {
    var result = all;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    if (_tab == _TabVisitante.doDia) {
      result = result.where((v) {
        final d = v.createdAt;
        return d != null && !d.isBefore(startOfToday) && d.isBefore(endOfToday);
      }).toList();
    } else {
      result = result.where((v) {
        final d = v.createdAt;
        return d != null && d.isBefore(startOfToday);
      }).toList();
    }

    if (_searchNome.isNotEmpty) {
      result = result.where((v) {
        final name = (v.data['nome'] ?? '').toString().toLowerCase();
        final phone = (v.data['telefone'] ?? '').toString().toLowerCase();
        return name.contains(_searchNome) || phone.contains(_searchNome);
      }).toList();
    }

    if (_tab == _TabVisitante.historico) {
      if (_filtroData != null) {
        final s = DateTime(_filtroData!.year, _filtroData!.month, _filtroData!.day);
        final e = s.add(const Duration(days: 1));
        result = result.where((v) {
          final d = v.createdAt;
          return d != null && !d.isBefore(s) && d.isBefore(e);
        }).toList();
      }
      if (_filtroDia != null) {
        result = result.where((v) => (v.createdAt?.day ?? 0) == _filtroDia).toList();
      }
      if (_filtroMes != null) {
        result = result.where((v) => (v.createdAt?.month ?? 0) == _filtroMes).toList();
      }
      if (_filtroAno != null) {
        result = result.where((v) => (v.createdAt?.year ?? 0) == _filtroAno).toList();
      }
    }

    return result;
  }

  // ─── Cadastro / Edição ──────────────────────────────────────────────────────
  void _openVisitorForm(BuildContext context, {_VisitorData? visitor}) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    void onClose() {
      if (mounted) _refresh();
    }
    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _VisitorFormSheet(
          tenantId: widget.tenantId,
          visitor: visitor,
        ),
      ).then((_) => onClose());
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _VisitorFormSheet(
              tenantId: widget.tenantId,
              visitor: visitor,
              isDialog: true,
            ),
          ),
        ),
      ).then((_) => onClose());
    }
  }

  // ─── Detalhes ───────────────────────────────────────────────────────────────
  void _openVisitorDetails(BuildContext context, _VisitorData visitor) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _VisitorDetailsPage(
            tenantId: widget.tenantId,
            visitor: visitor,
            canManage: _canManage,
            canConvertVisitor: AppPermissions.canConvertVisitorToMember(widget.role),
            membersRef: _membersRef,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: _VisitorDetailsPage(
              tenantId: widget.tenantId,
              visitor: visitor,
              canManage: _canManage,
              canConvertVisitor: AppPermissions.canConvertVisitorToMember(widget.role),
              membersRef: _membersRef,
              isDialog: true,
            ),
          ),
        ),
      );
    }
  }

  // ─── Excluir ────────────────────────────────────────────────────────────────
  Future<void> _confirmDelete(BuildContext context, _VisitorData visitor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Excluir visitante?'),
        content: Text('Deseja excluir "${visitor.nome}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await _visitantesRef.doc(visitor.id).delete();
      if (context.mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visitante excluído', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorData {
  final String id;
  final Map<String, dynamic> data;

  _VisitorData({required this.id, required this.data});

  String get nome => (data['nome'] ?? '').toString();
  String get telefone => (data['telefone'] ?? '').toString();
  String get email => (data['email'] ?? '').toString();
  String get status => (data['status'] ?? 'Novo').toString();
  String get comoConheceu => (data['comoConheceu'] ?? '').toString();
  String get observacoes => (data['observacoes'] ?? '').toString();
  int get followupCount => (data['followupCount'] ?? 0) as int;

  DateTime? get createdAt {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Summary Cards
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryCards extends StatelessWidget {
  final List<_VisitorData> visitors;
  final bool isMobile;

  const _SummaryCards({required this.visitors, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));

    final thisMonth = visitors.where((v) {
      final d = v.createdAt;
      return d != null && d.isAfter(startOfMonth);
    }).length;

    final thisWeekNew = visitors.where((v) {
      final d = v.createdAt;
      return d != null && d.isAfter(startOfWeek) && v.status == 'Novo';
    }).length;

    final accompanying = visitors.where((v) => v.status == 'Em acompanhamento').length;
    final converted = visitors.where((v) => v.status == 'Convertido').length;

    final cards = [
      _SummaryCardData('Este Mês', '$thisMonth', Icons.calendar_month_rounded, const Color(0xFF3B82F6)),
      _SummaryCardData('Novos (Semana)', '$thisWeekNew', Icons.fiber_new_rounded, const Color(0xFF8B5CF6)),
      _SummaryCardData('Acompanhamento', '$accompanying', Icons.support_agent_rounded, const Color(0xFFF59E0B)),
      _SummaryCardData('Convertidos', '$converted', Icons.verified_rounded, const Color(0xFF16A34A)),
    ];

    if (isMobile) {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: ThemeCleanPremium.spaceSm),
          itemBuilder: (_, i) => SizedBox(width: 156, child: _buildCard(context, cards[i])),
        ),
      );
    }

    return Wrap(
      spacing: ThemeCleanPremium.spaceMd,
      runSpacing: ThemeCleanPremium.spaceMd,
      children: cards.map((c) => SizedBox(width: 200, child: _buildCard(context, c))).toList(),
    );
  }

  Widget _buildCard(BuildContext context, _SummaryCardData c) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(c.icon, color: c.color, size: 22),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          Text(
            c.value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            c.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SummaryCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCardData(this.label, this.value, this.icon, this.color);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Card
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorCard extends StatelessWidget {
  final _VisitorData visitor;
  final String tenantId;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VisitorCard({
    required this.visitor,
    required this.tenantId,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final badge = _statusBadge(visitor.status);
    final dateStr = _formatDate(visitor.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: Material(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Row(
              children: [
                _avatar(visitor.nome),
                const SizedBox(width: ThemeCleanPremium.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              visitor.nome,
                              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: ThemeCleanPremium.spaceXs),
                          badge,
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (visitor.telefone.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: ThemeCleanPremium.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                visitor.telefone,
                                style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      if (visitor.email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined, size: 14, color: ThemeCleanPremium.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                visitor.email,
                                style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: tt.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11),
                          ),
                          if (visitor.followupCount > 0) ...[
                            const SizedBox(width: ThemeCleanPremium.spaceSm),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primaryLight.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.forum_outlined, size: 12, color: ThemeCleanPremium.primaryLight),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${visitor.followupCount}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primaryLight),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: ThemeCleanPremium.onSurfaceVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Editar')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: ThemeCleanPremium.error), SizedBox(width: 8), Text('Excluir', style: TextStyle(color: ThemeCleanPremium.error))])),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 22,
      backgroundColor: ThemeCleanPremium.primaryLight.withOpacity(0.12),
      child: Text(
        initial,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: ThemeCleanPremium.primary,
        ),
      ),
    );
  }

  static Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Novo':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        break;
      case 'Em acompanhamento':
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFC2410C);
        break;
      case 'Convertido':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'Desistente':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Form (Bottom Sheet / Dialog)
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorFormSheet extends StatefulWidget {
  final String tenantId;
  final _VisitorData? visitor;
  final bool isDialog;

  const _VisitorFormSheet({
    required this.tenantId,
    this.visitor,
    this.isDialog = false,
  });

  @override
  State<_VisitorFormSheet> createState() => _VisitorFormSheetState();
}

class _VisitorFormSheetState extends State<_VisitorFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _obsCtrl;
  String _comoConheceu = 'Convite';
  bool _saving = false;

  static const _origens = ['Convite', 'Redes Sociais', 'Passou na frente', 'Outro'];

  bool get _isEdit => widget.visitor != null;

  @override
  void initState() {
    super.initState();
    final v = widget.visitor;
    _nomeCtrl = TextEditingController(text: v?.nome ?? '');
    _telCtrl = TextEditingController(text: v?.telefone ?? '');
    _emailCtrl = TextEditingController(text: v?.email ?? '');
    _obsCtrl = TextEditingController(text: v?.observacoes ?? '');
    if (v != null && _origens.contains(v.comoConheceu)) {
      _comoConheceu = v.comoConheceu;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('visitantes');

    final payload = <String, dynamic>{
      'nome': _nomeCtrl.text.trim(),
      'telefone': _telCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'comoConheceu': _comoConheceu,
      'observacoes': _obsCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (_isEdit) {
        await ref.doc(widget.visitor!.id).update(payload);
      } else {
        payload['status'] = 'Novo';
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['followupCount'] = 0;
        await ref.add(payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final body = Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Editar Visitante' : 'Novo Visitante',
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    constraints: const BoxConstraints(minWidth: ThemeCleanPremium.minTouchTarget, minHeight: ThemeCleanPremium.minTouchTarget),
                  ),
                ],
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              TextFormField(
                controller: _nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome *', prefixIcon: Icon(Icons.person_outline_rounded)),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: _telCtrl,
                decoration: const InputDecoration(labelText: 'Telefone', prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.email_outlined)),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              DropdownButtonFormField<String>(
                value: _comoConheceu,
                decoration: const InputDecoration(labelText: 'Como conheceu a igreja', prefixIcon: Icon(Icons.info_outline_rounded)),
                items: _origens.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) { if (v != null) setState(() => _comoConheceu = v); },
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: _obsCtrl,
                decoration: const InputDecoration(labelText: 'Observações', prefixIcon: Icon(Icons.note_alt_outlined)),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              SizedBox(
                height: ThemeCleanPremium.minTouchTarget,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isEdit ? 'Salvar Alterações' : 'Cadastrar Visitante'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.isDialog) return body;

    return Container(
      decoration: const BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusLg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          body,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Details Page (Full page mobile / Dialog desktop)
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorDetailsPage extends StatefulWidget {
  final String tenantId;
  final _VisitorData visitor;
  final bool canManage;
  /// Secretariado, gestor, pastor, tesoureiro, ADM — não o papel [membro].
  final bool canConvertVisitor;
  final CollectionReference<Map<String, dynamic>> membersRef;
  final bool isDialog;

  const _VisitorDetailsPage({
    required this.tenantId,
    required this.visitor,
    required this.canManage,
    required this.canConvertVisitor,
    required this.membersRef,
    this.isDialog = false,
  });

  @override
  State<_VisitorDetailsPage> createState() => _VisitorDetailsPageState();
}

class _VisitorDetailsPageState extends State<_VisitorDetailsPage> {
  late DocumentReference<Map<String, dynamic>> _visitorDoc;
  late CollectionReference<Map<String, dynamic>> _followupsRef;
  late Future<QuerySnapshot<Map<String, dynamic>>> _followupsFuture;

  Future<QuerySnapshot<Map<String, dynamic>>> _loadFollowups() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (FirebaseAuth.instance.currentUser == null) {
        throw Exception('Faça login para ver os follow-ups.');
      }
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      return await _followupsRef.orderBy('data', descending: true).get();
    } catch (e) {
      if (e.toString().contains('permission-denied') || e.toString().contains('PERMISSION_DENIED')) {
        await Future.delayed(const Duration(milliseconds: 300));
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        return await _followupsRef.orderBy('data', descending: true).get();
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _visitorDoc = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('visitantes')
        .doc(widget.visitor.id);
    _followupsRef = _visitorDoc.collection('followups');
    _followupsFuture = _loadFollowups();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isMobile = ThemeCleanPremium.isMobile(context);

    final content = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _visitorDoc.snapshots(),
      builder: (context, vSnap) {
        if (vSnap.hasError) {
          return Center(child: Text('Erro: ${vSnap.error}'));
        }
        if (vSnap.connectionState == ConnectionState.waiting && !vSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final vData = vSnap.data?.data();
        if (vData == null) {
          return const Center(child: Text('Visitante não encontrado'));
        }

        final current = _VisitorData(id: widget.visitor.id, data: vData);

        return SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoHeader(context, current, tt),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              if (widget.canManage) ...[
                _buildActionButtons(context, current),
                const SizedBox(height: ThemeCleanPremium.spaceLg),
              ],
              Text('Timeline de Follow-up', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildFollowupTimeline(context, tt),
            ],
          ),
        );
      },
    );

    if (widget.isDialog) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.visitor.nome),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
              constraints: const BoxConstraints(minWidth: ThemeCleanPremium.minTouchTarget, minHeight: ThemeCleanPremium.minTouchTarget),
            ),
          ),
          body: content,
        ),
      );
    }

    return Scaffold(
      appBar: isMobile
          ? null
          : AppBar(title: Text(widget.visitor.nome)),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Padding(
                padding: const EdgeInsets.fromLTRB(ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceSm, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                      constraints: const BoxConstraints(minWidth: ThemeCleanPremium.minTouchTarget, minHeight: ThemeCleanPremium.minTouchTarget),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceXs),
                    Expanded(
                      child: Text(
                        widget.visitor.nome,
                        style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => _addFollowup(context),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Follow-up'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildInfoHeader(BuildContext context, _VisitorData v, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: ThemeCleanPremium.primaryLight.withOpacity(0.12),
                child: Text(
                  v.nome.isNotEmpty ? v.nome[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ThemeCleanPremium.primary),
                ),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.nome, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    _VisitorCard._statusBadge(v.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          _infoRow(Icons.phone_outlined, 'Telefone', v.telefone.isEmpty ? '—' : v.telefone),
          _infoRow(Icons.email_outlined, 'E-mail', v.email.isEmpty ? '—' : v.email),
          _infoRow(Icons.info_outline_rounded, 'Como conheceu', v.comoConheceu.isEmpty ? '—' : v.comoConheceu),
          _infoRow(Icons.calendar_today_outlined, 'Primeiro contato', _VisitorCard._formatDate(v.createdAt)),
          if (v.observacoes.isNotEmpty)
            _infoRow(Icons.note_alt_outlined, 'Observações', v.observacoes),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ThemeCleanPremium.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurface))),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, _VisitorData v) {
    return Wrap(
      spacing: ThemeCleanPremium.spaceSm,
      runSpacing: ThemeCleanPremium.spaceSm,
      children: [
        SizedBox(
          height: ThemeCleanPremium.minTouchTarget,
          child: OutlinedButton.icon(
            onPressed: () => _changeStatus(context, v),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Alterar Status'),
          ),
        ),
        if (widget.canConvertVisitor && v.status != 'Convertido')
          SizedBox(
            height: ThemeCleanPremium.minTouchTarget,
            child: FilledButton.icon(
              onPressed: () => _convertToMember(context, v),
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text('Converter para Membro'),
              style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.success),
            ),
          ),
      ],
    );
  }

  Widget _buildFollowupTimeline(BuildContext context, TextTheme tt) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _followupsFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Erro ao carregar follow-ups: ${snap.error}', style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() { _followupsFuture = _loadFollowups(); }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.surfaceVariant,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            child: Column(
              children: [
                Icon(Icons.forum_outlined, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Text('Nenhum follow-up registrado', style: tt.bodyMedium?.copyWith(color: ThemeCleanPremium.onSurfaceVariant)),
              ],
            ),
          );
        }

        return Column(
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final isLast = i == docs.length - 1;
            return _FollowupTimelineItem(data: d, isLast: isLast);
          }),
        );
      },
    );
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  Future<void> _changeStatus(BuildContext context, _VisitorData v) async {
    const statuses = ['Novo', 'Em acompanhamento', 'Convertido', 'Desistente'];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Alterar Status'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        children: statuses.map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, s),
            padding: const EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg, vertical: ThemeCleanPremium.spaceSm),
            child: Row(
              children: [
                _VisitorCard._statusBadge(s),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                if (s == v.status) const Icon(Icons.check_rounded, size: 18, color: ThemeCleanPremium.primary),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (picked != null && picked != v.status && context.mounted) {
      await _visitorDoc.update({'status': picked, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _convertToMember(BuildContext context, _VisitorData v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Converter para Membro'),
        content: Text('Deseja converter "${v.nome}" em membro da igreja?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.success),
            child: const Text('Converter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await widget.membersRef.add({
        'nome': v.nome,
        'telefone': v.telefone,
        'email': v.email,
        'status': 'ativo',
        'origemVisitante': true,
        'visitanteId': v.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _visitorDoc.update({
        'status': 'Convertido',
        'convertedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visitante convertido para membro com sucesso!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  Future<void> _addFollowup(BuildContext context) async {
    final tipoCtrl = ValueNotifier<String>('Ligação');
    final notasCtrl = TextEditingController();
    final responsavelCtrl = TextEditingController();
    const tipos = ['Ligação', 'WhatsApp', 'Visita', 'Outro'];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusLg)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('Novo Follow-up', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              ValueListenableBuilder<String>(
                valueListenable: tipoCtrl,
                builder: (_, tipo, __) => DropdownButtonFormField<String>(
                  value: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo de contato', prefixIcon: Icon(Icons.category_outlined)),
                  items: tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) { if (v != null) tipoCtrl.value = v; },
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: responsavelCtrl,
                decoration: const InputDecoration(labelText: 'Responsável', prefixIcon: Icon(Icons.person_outline_rounded)),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: notasCtrl,
                decoration: const InputDecoration(labelText: 'Notas', prefixIcon: Icon(Icons.note_alt_outlined)),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              SizedBox(
                height: ThemeCleanPremium.minTouchTarget,
                child: FilledButton.icon(
                  onPressed: () async {
                    await _followupsRef.add({
                      'tipo': tipoCtrl.value,
                      'notas': notasCtrl.text.trim(),
                      'responsavel': responsavelCtrl.text.trim(),
                      'data': FieldValue.serverTimestamp(),
                    });
                    await _visitorDoc.update({
                      'followupCount': FieldValue.increment(1),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Registrar Follow-up'),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
            ],
          ),
        ),
      ),
    );

    tipoCtrl.dispose();
    notasCtrl.dispose();
    responsavelCtrl.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up registrado!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Follow-up Timeline Item
// ═══════════════════════════════════════════════════════════════════════════════

class _FollowupTimelineItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLast;

  const _FollowupTimelineItem({required this.data, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final tipo = (data['tipo'] ?? '').toString();
    final notas = (data['notas'] ?? '').toString();
    final responsavel = (data['responsavel'] ?? '').toString();
    final ts = data['data'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
        : '—';

    final tipoIcon = _tipoIcon(tipo);
    final tipoColor = _tipoColor(tipo);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tipoColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: tipoColor.withOpacity(0.3), width: 3),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ThemeCleanPremium.spaceSm),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(tipoIcon, size: 16, color: tipoColor),
                      const SizedBox(width: 6),
                      Text(tipo, style: tt.labelLarge?.copyWith(color: tipoColor, fontSize: 13)),
                      const Spacer(),
                      Text(dateStr, style: tt.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                  if (notas.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(notas, style: tt.bodyMedium?.copyWith(color: ThemeCleanPremium.onSurface, height: 1.4)),
                  ],
                  if (responsavel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 12, color: ThemeCleanPremium.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(responsavel, style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'Ligação': return Icons.phone_rounded;
      case 'WhatsApp': return Icons.chat_rounded;
      case 'Visita': return Icons.home_rounded;
      default: return Icons.more_horiz_rounded;
    }
  }

  static Color _tipoColor(String tipo) {
    switch (tipo) {
      case 'Ligação': return const Color(0xFF3B82F6);
      case 'WhatsApp': return const Color(0xFF22C55E);
      case 'Visita': return const Color(0xFFF59E0B);
      default: return const Color(0xFF8B5CF6);
    }
  }
}
