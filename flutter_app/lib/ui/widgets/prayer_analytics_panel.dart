import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_pedidos_oracao_load_service.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/prayer_pedidos_filter.dart';
import 'package:gestao_yahweh/services/prayer_pedidos_report_pdf.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:intl/intl.dart';

/// Painel interno — métricas, gráficos, PDF e limpeza em lote (responsivo Web/iOS/Android).
class PrayerAnalyticsPanel extends StatefulWidget {
  const PrayerAnalyticsPanel({
    super.key,
    required this.tenantId,
    required this.role,
    required this.pedidosDocs,
    required this.onDataChanged,
    this.canSee,
  });

  final String tenantId;
  final String role;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> pedidosDocs;
  final VoidCallback onDataChanged;
  final bool Function(Map<String, dynamic> data)? canSee;

  @override
  State<PrayerAnalyticsPanel> createState() => _PrayerAnalyticsPanelState();
}

class _PrayerAnalyticsPanelState extends State<PrayerAnalyticsPanel> {
  static final _accent = ThemeCleanPremium.primary;
  static final _accentLight = ThemeCleanPremium.primaryLight;
  static const _green = Color(0xFF16A34A);
  static const _amber = Color(0xFFF59E0B);

  static final _dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  PrayerPedidosFilter _filter = const PrayerPedidosFilter();
  DateTime? _draftCustomStart;
  DateTime? _draftCustomEnd;
  String? _selectedCategoryChart;
  String? _selectedStatusChart;
  bool _cleaning = false;
  bool _loadingMeta = true;

  List<String> _departamentos = const [];
  List<MemberDirectoryEntry> _members = const [];
  String? _selectedDepartamento;
  final Map<String, Set<String>> _deptAuthUids = {};

  String get _churchId => ChurchRepository.churchId(widget.tenantId);

  bool get _isLeader =>
      AppPermissions.canDeleteAnyChurchRecords(widget.role);

  bool get _isCustomPeriod => _filter.period == PrayerPeriodPreset.custom;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visibleDocs {
    final canSee = widget.canSee;
    if (canSee == null) return widget.pedidosDocs;
    return widget.pedidosDocs.where((d) => canSee(d.data())).toList();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeta());
  }

  Future<void> _loadMeta() async {
    setState(() => _loadingMeta = true);
    try {
      final deptResult = await ChurchRepository.departamentos.list(
        churchIdHint: _churchId,
        limit: 200,
      );
      final depts = deptResult.items
          .map((d) => (d.data()['nome'] ?? d.data()['name'] ?? d.id)
              .toString()
              .trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      final directory =
          await MembersDirectorySnapshotService.readOnce(_churchId);
      final deptMap = <String, Set<String>>{};
      for (final e in directory.entries) {
        for (final dep in e.departamentos) {
          final key = dep.trim();
          if (key.isEmpty) continue;
          deptMap.putIfAbsent(key, () => <String>{});
          final uid = (e.authUid ?? '').trim();
          if (uid.isNotEmpty) deptMap[key]!.add(uid);
        }
      }

      if (mounted) {
        setState(() {
          _departamentos = depts;
          _members = directory.entries;
          _deptAuthUids
            ..clear()
            ..addAll(deptMap);
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  PrayerPedidosAnalyticsSnapshot get _stats =>
      PrayerPedidosAnalyticsSnapshot.compute(_visibleDocs, _filter);

  static const _catColors = <String, Color>{
    'Saúde': Color(0xFFE53935),
    'Família': Color(0xFF8E24AA),
    'Finanças': Color(0xFF0D47A1),
    'Trabalho': Color(0xFF4A148C),
    'Libertação': Color(0xFFB71C1C),
    'Gratidão': Color(0xFFB45309),
    'Outro': Color(0xFF424242),
  };

  Future<void> _exportPdf() async {
    final stats = _stats;
    final bytes = await PrayerPedidosReportPdf.build(
      churchName: _churchId,
      stats: stats,
      filter: _filter,
      generatedAt: DateTime.now(),
    );
    if (!mounted) return;
    await showPdfActions(
      context,
      bytes: bytes,
      filename: 'pedidos_oracao_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  void _onPeriodSelected(PrayerPeriodPreset preset) {
    setState(() {
      if (preset == PrayerPeriodPreset.custom) {
        final now = DateTime.now();
        _draftCustomStart ??=
            _filter.customStart ?? now.subtract(const Duration(days: 30));
        _draftCustomEnd ??= _filter.customEnd ?? now;
        _filter = _filter.copyWith(period: PrayerPeriodPreset.custom);
      } else {
        _filter = _filter.copyWith(period: preset);
      }
    });
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_draftCustomStart ?? now.subtract(const Duration(days: 30)))
        : (_draftCustomEnd ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _draftCustomStart = picked;
      } else {
        _draftCustomEnd = picked;
      }
      _filter = _filter.copyWith(period: PrayerPeriodPreset.custom);
    });
  }

  void _applyCustomSearch() {
    final start = _draftCustomStart;
    final end = _draftCustomEnd;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a data inicial e a data final.'),
        ),
      );
      return;
    }
    if (end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data final deve ser igual ou posterior à inicial.'),
        ),
      );
      return;
    }
    setState(() {
      _filter = _filter.copyWith(
        period: PrayerPeriodPreset.custom,
        customStart: DateTime(start.year, start.month, start.day),
        customEnd: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
      );
    });
  }

  Future<String?> _pickFromList({
    required String title,
    required List<String> options,
    String? current,
    bool allowClear = true,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? options
                : options
                    .where((o) => o.toLowerCase().contains(q))
                    .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (_, scroll) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (allowClear && current != null)
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, '__clear__'),
                              child: const Text('Limpar'),
                            ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          final sel = item == current;
                          return ListTile(
                            title: Text(item),
                            trailing: sel
                                ? Icon(Icons.check_rounded, color: _accent)
                                : null,
                            onTap: () => Navigator.pop(ctx, item),
                          );
                        },
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

  Future<void> _pickMember({required bool intercessor}) async {
    final options = _members
        .map((e) => e.displayName.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final currentName = intercessor
        ? _memberNameByUid(_filter.intercessorUid)
        : _memberNameByUid(_filter.autorUid);
    final picked = await _pickFromList(
      title: intercessor ? 'Intercessor' : 'Autor do pedido',
      options: options,
      current: currentName,
    );
    if (!mounted || picked == null) return;
    if (picked == '__clear__') {
      setState(() {
        _filter = _filter.copyWith(
          clearAutor: !intercessor,
          clearIntercessor: intercessor,
        );
      });
      return;
    }
    final matches =
        _members.where((e) => e.displayName.trim() == picked).toList();
    if (matches.isEmpty) return;
    final entry = matches.first;
    final uid = (entry.authUid ?? '').trim();
    setState(() {
      _filter = intercessor
          ? _filter.copyWith(intercessorUid: uid)
          : _filter.copyWith(autorUid: uid);
    });
  }

  String? _memberNameByUid(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    for (final e in _members) {
      if (e.authUid == uid) return e.displayName;
    }
    return null;
  }

  String _intercessorChartLabel(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return '—';
    final byUid = _memberNameByUid(trimmed);
    if (byUid != null && byUid.isNotEmpty) return byUid;
    if (trimmed.length > 12) return '${trimmed.substring(0, 10)}…';
    return trimmed;
  }

  Future<void> _pickDepartamento() async {
    if (_departamentos.isEmpty) return;
    final picked = await _pickFromList(
      title: 'Departamento',
      options: _departamentos,
      current: _selectedDepartamento,
    );
    if (!mounted || picked == null) return;
    if (picked == '__clear__') {
      setState(() {
        _selectedDepartamento = null;
        _filter = _filter.copyWith(clearDepartment: true);
      });
      return;
    }
    setState(() {
      _selectedDepartamento = picked;
      _filter = _filter.copyWith(memberAuthUids: _deptAuthUids[picked]);
    });
  }

  Future<void> _confirmCleanup({required bool clearOrandoOnly}) async {
    final stats = _stats;
    if (stats.filteredDocIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum pedido no filtro atual.')),
      );
      return;
    }
    final action = clearOrandoOnly
        ? 'remover todos os intercessores de'
        : 'excluir';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(clearOrandoOnly ? 'Limpar intercessores' : 'Excluir pedidos'),
        content: Text(
          'Confirma $action ${stats.filteredDocIds.length} pedido(s) '
          'com os filtros atuais? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: clearOrandoOnly ? _amber : ThemeCleanPremium.error,
            ),
            child: Text(clearOrandoOnly ? 'Limpar' : 'Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _cleaning = true);
    try {
      if (clearOrandoOnly) {
        await ChurchPedidosOracaoLoadService.clearOrandoFromPedidos(
          seedTenantId: _churchId,
          docIds: stats.filteredDocIds,
        );
      } else {
        await ChurchPedidosOracaoLoadService.deletePedidos(
          seedTenantId: _churchId,
          docIds: stats.filteredDocIds,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clearOrandoOnly
                  ? 'Intercessores removidos.'
                  : 'Pedidos excluídos.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onDataChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final stats = _stats;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final isWide = maxW >= 900;
        final chartHeight = isWide ? 240.0 : 220.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            padding.bottom + 24,
          ),
          children: [
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('Filtros', icon: Icons.tune_rounded),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in PrayerPeriodPreset.values)
                        FilterChip(
                          label: Text(_periodChipLabel(p)),
                          selected: _filter.period == p,
                          selectedColor: _accent.withValues(alpha: 0.18),
                          checkmarkColor: _accent,
                          labelStyle: TextStyle(
                            fontWeight: _filter.period == p
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _filter.period == p ? _accent : null,
                          ),
                          onSelected: (_) => _onPeriodSelected(p),
                        ),
                    ],
                  ),
                  if (_isCustomPeriod) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Período personalizado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _dateFieldButton(
                          label: 'Data inicial',
                          value: _draftCustomStart,
                          onTap: () => _pickCustomDate(isStart: true),
                        ),
                        _dateFieldButton(
                          label: 'Data final',
                          value: _draftCustomEnd,
                          onTap: () => _pickCustomDate(isStart: false),
                        ),
                        FilledButton.icon(
                          onPressed: _applyCustomSearch,
                          icon: const Icon(Icons.search_rounded, size: 20),
                          label: const Text('Pesquisar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            minimumSize: Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterDropdown(
                        label: _filter.categoria ?? 'Categoria',
                        icon: Icons.category_outlined,
                        onTap: () async {
                          final cats = stats.porCategoria.keys.toList()..sort();
                          if (!cats.contains('Outro')) cats.add('Outro');
                          final picked = await _pickFromList(
                            title: 'Categoria',
                            options: cats,
                            current: _filter.categoria,
                          );
                          if (!mounted || picked == null) return;
                          setState(() {
                            _filter = picked == '__clear__'
                                ? _filter.copyWith(clearCategoria: true)
                                : _filter.copyWith(categoria: picked);
                          });
                        },
                      ),
                      _filterDropdown(
                        label: _filter.respondida == null
                            ? 'Status'
                            : (_filter.respondida! ? 'Respondidos' : 'Abertos'),
                        icon: Icons.flag_outlined,
                        onTap: () async {
                          final picked = await showModalBottomSheet<String>(
                            context: context,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    title: const Text('Todos'),
                                    onTap: () => Navigator.pop(ctx, '__clear__'),
                                  ),
                                  ListTile(
                                    title: const Text('Abertos'),
                                    onTap: () => Navigator.pop(ctx, 'open'),
                                  ),
                                  ListTile(
                                    title: const Text('Respondidos'),
                                    onTap: () => Navigator.pop(ctx, 'done'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (!mounted || picked == null) return;
                          setState(() {
                            _filter = picked == '__clear__'
                                ? _filter.copyWith(clearRespondida: true)
                                : _filter.copyWith(
                                    respondida: picked == 'done',
                                  );
                          });
                        },
                      ),
                      _filterDropdown(
                        label: _memberNameByUid(_filter.autorUid) ?? 'Autor',
                        icon: Icons.person_outline_rounded,
                        onTap: () => _pickMember(intercessor: false),
                      ),
                      _filterDropdown(
                        label: _memberNameByUid(_filter.intercessorUid) ??
                            'Intercessor',
                        icon: Icons.volunteer_activism_outlined,
                        onTap: () => _pickMember(intercessor: true),
                      ),
                      if (!_loadingMeta && _departamentos.isNotEmpty)
                        _filterDropdown(
                          label: _selectedDepartamento ?? 'Departamento',
                          icon: Icons.groups_outlined,
                          onTap: _pickDepartamento,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar texto, autor ou categoria…',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _accent.withValues(alpha: 0.85),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (v) => setState(() {
                      _filter = _filter.copyWith(searchText: v);
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _sectionTitle('Resumo', icon: Icons.insights_rounded)),
                TextButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Exportar PDF'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildKpiGrid(stats, maxW),
            const SizedBox(height: 16),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPieChartCard(stats, chartHeight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatusBarChart(stats, chartHeight),
                  ),
                ],
              )
            else ...[
              _buildPieChartCard(stats, chartHeight),
              const SizedBox(height: 12),
              _buildStatusBarChart(stats, chartHeight),
            ],
            const SizedBox(height: 12),
            _buildTopIntercessorsChart(stats, chartHeight),
            if (_isLeader) ...[
              const SizedBox(height: 20),
              _premiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle('Limpeza em lote', icon: Icons.cleaning_services_outlined),
                    Text(
                      '${stats.filteredDocIds.length} pedido(s) no filtro atual.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: maxW >= 520 ? (maxW - 10) / 2 : maxW,
                          child: OutlinedButton.icon(
                            onPressed: _cleaning
                                ? null
                                : () => _confirmCleanup(clearOrandoOnly: true),
                            icon: const Icon(Icons.cleaning_services_outlined),
                            label: const Text('Limpar intercessores'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(
                                ThemeCleanPremium.minTouchTarget,
                                ThemeCleanPremium.minTouchTarget,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: maxW >= 520 ? (maxW - 10) / 2 : maxW,
                          child: FilledButton.icon(
                            onPressed: _cleaning
                                ? null
                                : () => _confirmCleanup(clearOrandoOnly: false),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.error,
                              minimumSize: const Size(
                                ThemeCleanPremium.minTouchTarget,
                                ThemeCleanPremium.minTouchTarget,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Excluir pedidos'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildKpiGrid(PrayerPedidosAnalyticsSnapshot stats, double maxW) {
    final cols = maxW >= 720 ? 4 : 2;
    final gap = 10.0;
    final itemW = (maxW - gap * (cols - 1)) / cols;
    final items = [
      _kpiCard('Total', stats.total, _accentLight),
      _kpiCard('Abertos', stats.abertos, _amber),
      _kpiCard('Respondidos', stats.respondidos, _green),
      _kpiCard('Intercessões', stats.totalIntercessoes, _accent),
    ];
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final w in items)
          SizedBox(width: itemW.clamp(140, maxW), child: w),
      ],
    );
  }

  Widget _buildPieChartCard(
    PrayerPedidosAnalyticsSnapshot stats,
    double height,
  ) {
    return _chartCard(
      title: 'Por categoria',
      subtitle: _selectedCategoryChart ?? 'Toque numa fatia',
      child: SizedBox(
        height: height,
        child: stats.porCategoria.isEmpty
            ? _emptyChart('Sem dados no período')
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 42,
                    sections: _pieSections(stats.porCategoria),
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        if (!event.isInterestedForInteractions) return;
                        final idx =
                            response?.touchedSection?.touchedSectionIndex;
                        if (idx == null) return;
                        final keys = stats.porCategoria.keys.toList();
                        if (idx >= 0 && idx < keys.length) {
                          setState(() {
                            _selectedCategoryChart = keys[idx];
                            _filter = _filter.copyWith(categoria: keys[idx]);
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatusBarChart(
    PrayerPedidosAnalyticsSnapshot stats,
    double height,
  ) {
    final maxVal = math.max(stats.abertos, stats.respondidos);
    final maxY = (maxVal + 1).clamp(2, 999).toDouble();
    return _chartCard(
      title: 'Abertos vs respondidos',
      subtitle: _selectedStatusChart ?? 'Toque numa barra',
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            barGroups: [
              BarChartGroupData(
                x: 0,
                barRods: [
                  BarChartRodData(
                    toY: stats.abertos.toDouble(),
                    gradient: LinearGradient(
                      colors: [_amber, _amber.withValues(alpha: 0.55)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: 32,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
              BarChartGroupData(
                x: 1,
                barRods: [
                  BarChartRodData(
                    toY: stats.respondidos.toDouble(),
                    gradient: LinearGradient(
                      colors: [_green, _green.withValues(alpha: 0.55)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    width: 32,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ],
              ),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Abertos', style: TextStyle(fontSize: 11)),
                      );
                    }
                    if (i == 1) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Respondidos', style: TextStyle(fontSize: 11)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 1,
                  getTitlesWidget: (v, _) {
                    if (v != v.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      '${v.toInt()}',
                      style: const TextStyle(fontSize: 10),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) => FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions) return;
                final idx = response?.spot?.touchedBarGroupIndex;
                if (idx == null) return;
                setState(() {
                  if (idx == 0) {
                    _selectedStatusChart = 'Abertos';
                    _filter = _filter.copyWith(respondida: false);
                  } else {
                    _selectedStatusChart = 'Respondidos';
                    _filter = _filter.copyWith(respondida: true);
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopIntercessorsChart(
    PrayerPedidosAnalyticsSnapshot stats,
    double height,
  ) {
    final top = stats.topIntercessores;
    final maxVal =
        top.isEmpty ? 1 : top.map((e) => e.value).reduce(math.max);
    final maxY = (maxVal + 1).clamp(2, 99).toDouble();

    return _chartCard(
      title: 'Top intercessores',
      subtitle: 'Toque numa barra para filtrar',
      child: SizedBox(
        height: height,
        child: top.isEmpty
            ? _emptyChart('Sem intercessões no período')
            : BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: 0,
                  barGroups: top.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value.toDouble(),
                          gradient: LinearGradient(
                            colors: [_accent, _accentLight],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: top.length <= 3 ? 28 : 18,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= top.length) {
                            return const SizedBox.shrink();
                          }
                          final label =
                              _intercessorChartLabel(top[i].key);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (v, _) {
                          if (v != v.roundToDouble()) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            '${v.toInt()}',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
      ),
    );
  }

  Widget _emptyChart(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _dateFieldButton({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 148),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 16, color: _accent.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Text(
                    value != null ? _dateFmt.format(value) : 'Selecionar',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: value != null
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade500,
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

  List<PieChartSectionData> _pieSections(Map<String, int> data) {
    final total = data.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const [];
    final keys = data.keys.toList();
    return keys.asMap().entries.map((e) {
      final key = e.value;
      final val = data[key] ?? 0;
      final color = _catColors[key] ?? _accentLight;
      return PieChartSectionData(
        value: val.toDouble(),
        title: '${((val / total) * 100).round()}%',
        radius: 48,
        color: color,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _sectionTitle(String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: _accent),
              const SizedBox(width: 8),
            ],
            Text(
              t,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      );

  Widget _premiumCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: child,
    );
  }

  Widget _kpiCard(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: _accent),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ThemeCleanPremium.isMobile(context) ? 120 : 160,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  String _periodChipLabel(PrayerPeriodPreset p) {
    switch (p) {
      case PrayerPeriodPreset.all:
        return 'Todos';
      case PrayerPeriodPreset.week:
        return 'Semana';
      case PrayerPeriodPreset.month:
        return 'Mês';
      case PrayerPeriodPreset.year:
        return 'Ano';
      case PrayerPeriodPreset.custom:
        return 'Personalizado';
    }
  }
}
