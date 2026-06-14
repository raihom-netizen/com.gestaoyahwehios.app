import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/dashboard/church_dashboard_finance_period.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/panel_finance_chart_service.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

enum DashboardFinanceFocus { all, receitas, despesas, saldo }

/// Hub financeiro do painel — cache-first, cards clicáveis, gráfico misto e drill-down.
class DashboardFinanceHub extends StatefulWidget {
  const DashboardFinanceHub({
    super.key,
    required this.tenantId,
    required this.range,
    required this.preset,
    required this.role,
    this.cpf = '',
    this.podeVerFinanceiro,
    this.permissions,
    this.financeRefreshTick = 0,
    this.isNarrow = false,
  });

  final String tenantId;
  final DateTimeRange range;
  final ChurchDashboardFinancePreset preset;
  final String role;
  final String cpf;
  final bool? podeVerFinanceiro;
  final List<String>? permissions;
  final int financeRefreshTick;
  final bool isNarrow;

  @override
  State<DashboardFinanceHub> createState() => _DashboardFinanceHubState();
}

class _DashboardFinanceHubState extends State<DashboardFinanceHub> {
  static final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = const [];
  PanelFinanceChartData? _chartData;
  DashboardFinanceFocus _focus = DashboardFinanceFocus.all;
  int? _drillBucketIndex;
  bool _loading = true;
  bool _syncing = false;
  String? _softError;

  _DashBuckets? _buckets;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant DashboardFinanceHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.financeRefreshTick != widget.financeRefreshTick ||
        !ChurchDashboardFinancePeriod.sameRange(oldWidget.range, widget.range) ||
        oldWidget.preset != widget.preset) {
      unawaited(_load(forceFresh: oldWidget.financeRefreshTick != widget.financeRefreshTick));
    }
  }

  Future<void> _load({bool forceFresh = false}) async {
    final tid = ChurchRepository.churchId(widget.tenantId);
    if (tid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _buckets = _buildBuckets(widget.range, widget.preset);
    final peek = ChurchFinanceLoadService.peekLancamentosRam(tid, limit: 400);
    if (peek != null && peek.isNotEmpty && mounted) {
      setState(() {
        _allDocs = peek;
        _chartData = _computeChart(peek);
        _loading = false;
      });
    } else if (mounted && _allDocs.isEmpty) {
      setState(() => _loading = true);
    }

    if (mounted) setState(() => _syncing = true);
    try {
      final result = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: 400,
        forceRefresh: forceFresh,
        forceServer: forceFresh,
      ).timeout(PanelResilientLoad.queryCap);
      if (!mounted) return;
      setState(() {
        _allDocs = result.docs;
        _chartData = _computeChart(result.docs);
        _softError = result.docs.isEmpty ? result.softError : null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_allDocs.isEmpty) _softError = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  PanelFinanceChartData _computeChart(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final b = _buckets ?? _buildBuckets(widget.range, widget.preset);
    return PanelFinanceChartService.fromFinanceDocs(
      docs: docs,
      bucketStarts: b.bucketStarts,
      monthlyMode: b.monthlyMode,
      clipRange: widget.range,
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsInRange({
    DateTimeRange? range,
    DashboardFinanceFocus? focus,
  }) {
    final r = range ?? widget.range;
    final f = focus ?? _focus;
    return _allDocs.where((d) {
      final data = d.data();
      final dt = financeLancamentoDate(data);
      if (dt == null || dt.isBefore(r.start) || dt.isAfter(r.end)) return false;
      if (!financeLancamentoEfetivadoParaSaldo(data)) return false;
      if (f == DashboardFinanceFocus.receitas && !financeIsEntrada(data)) {
        return false;
      }
      if (f == DashboardFinanceFocus.despesas && !financeIsSaida(data)) {
        return false;
      }
      if (f == DashboardFinanceFocus.saldo) {
        final t = financeInferTipo(data);
        if (t == 'transferencia') return false;
      }
      if (_drillBucketIndex != null && _buckets != null) {
        final idx = PanelFinanceChartService.bucketIndexForDate(
          dt,
          _buckets!.bucketStarts,
          monthlyMode: _buckets!.monthlyMode,
        );
        if (idx != _drillBucketIndex) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = financeLancamentoDate(a.data());
        final db = financeLancamentoDate(b.data());
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
  }

  ({double receitas, double despesas, double saldo}) _totalsForRange(
    DateTimeRange range,
  ) {
    double r = 0, s = 0;
    for (final d in _allDocs) {
      final data = d.data();
      final dt = financeLancamentoDate(data);
      if (dt == null || dt.isBefore(range.start) || dt.isAfter(range.end)) {
        continue;
      }
      if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
      final v = PanelFinanceChartService.valorAbs(data);
      if (financeIsSaida(data)) {
        s += v;
      } else if (financeIsEntrada(data)) {
        r += v;
      }
    }
    return (receitas: r, despesas: s, saldo: r - s);
  }

  DateTimeRange _previousComparableRange() {
    final cur = widget.range;
    switch (widget.preset) {
      case ChurchDashboardFinancePreset.currentMonth:
        return ChurchDashboardFinancePeriod.resolve(
          preset: ChurchDashboardFinancePreset.previousMonth,
        );
      case ChurchDashboardFinancePreset.previousMonth:
        final start = DateTime(cur.start.year, cur.start.month - 1, 1);
        final end = DateTime(cur.start.year, cur.start.month, 0, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      default:
        final days = cur.end.difference(cur.start).inDays + 1;
        final end = cur.start.subtract(const Duration(days: 1));
        final start = end.subtract(Duration(days: days - 1));
        return DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
        );
    }
  }

  String _trendLabel(double current, double previous) {
    if (current.abs() < 0.01 && previous.abs() < 0.01) return 'Estável';
    if (previous.abs() < 0.01) return current > 0 ? '+100%' : '0%';
    final pct = ((current - previous) / previous.abs()) * 100;
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(0)}% vs período ant.';
  }

  void _openFinance({int? tab, String? openId}) {
    Navigator.push(
      context,
      ThemeCleanPremium.fadeSlideRoute(
        FinancePage(
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          permissions: widget.permissions,
          initialTabIndex: tab ?? 1,
          openLancamentoId: openId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _chartData == null) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final cur = _totalsForRange(widget.range);
    final prev = _totalsForRange(_previousComparableRange());
    final chart = _chartData;
    final b = _buckets ?? _buildBuckets(widget.range, widget.preset);
    final filtered = _docsInRange().take(8).toList();

    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fluxo Financeiro',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_syncing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sincronizando…',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                )
              else
                IconButton(
                  tooltip: 'Abrir Financeiro',
                  onPressed: () => _openFinance(tab: 0),
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
            ],
          ),
          if (_softError != null && _allDocs.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Exibindo últimos dados disponíveis offline.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = widget.isNarrow || c.maxWidth < 520;
              final cards = [
                _KpiCard(
                  label: 'Receitas',
                  value: _money.format(cur.receitas),
                  trend: _trendLabel(cur.receitas, prev.receitas),
                  color: const Color(0xFF2563EB),
                  selected: _focus == DashboardFinanceFocus.receitas,
                  onTap: () => setState(() {
                    _focus = DashboardFinanceFocus.receitas;
                    _drillBucketIndex = null;
                  }),
                ),
                _KpiCard(
                  label: 'Despesas',
                  value: _money.format(cur.despesas),
                  trend: _trendLabel(cur.despesas, prev.despesas),
                  color: const Color(0xFFDC2626),
                  selected: _focus == DashboardFinanceFocus.despesas,
                  onTap: () => setState(() {
                    _focus = DashboardFinanceFocus.despesas;
                    _drillBucketIndex = null;
                  }),
                ),
                _KpiCard(
                  label: 'Saldo',
                  value: _money.format(cur.saldo),
                  trend: _trendLabel(cur.saldo, prev.saldo),
                  color: const Color(0xFF16A34A),
                  selected: _focus == DashboardFinanceFocus.saldo,
                  onTap: () => setState(() {
                    _focus = DashboardFinanceFocus.saldo;
                    _drillBucketIndex = null;
                  }),
                ),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '${ChurchDashboardFinancePeriod.presetLabel(widget.preset)} · '
            'barras = receitas · linha = despesas · toque para filtrar',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.isNarrow ? 200 : 220,
            child: chart == null
                ? Center(
                    child: Text(
                      'Sem movimentação no período.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  )
                : _MixedFinanceChart(
                    labels: b.labels,
                    receitas: chart.entradasByBucket,
                    despesas: chart.saidasByBucket,
                    focus: _focus,
                    selectedIndex: _drillBucketIndex,
                    onBucketTap: (i) => setState(() {
                      _drillBucketIndex = _drillBucketIndex == i ? null : i;
                    }),
                  ),
          ),
          if (_drillBucketIndex != null && _drillBucketIndex! < b.labels.length) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _drillBucketIndex = null),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: Text('Limpar filtro · ${b.labels[_drillBucketIndex!]}'),
              ),
            ),
          ],
          if (filtered.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Lançamentos${_drillBucketIndex != null ? ' filtrados' : ''}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            ...filtered.map((doc) {
              final data = doc.data();
              final desc = (data['descricao'] ?? data['categoria'] ?? 'Lançamento')
                  .toString();
              final v = PanelFinanceChartService.valorAbs(data);
              final entrada = financeIsEntrada(data);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openFinance(openId: doc.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          entrada
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 18,
                          color: entrada
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          _money.format(v),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: entrada
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final String trend;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixedFinanceChart extends StatelessWidget {
  const _MixedFinanceChart({
    required this.labels,
    required this.receitas,
    required this.despesas,
    required this.focus,
    required this.selectedIndex,
    required this.onBucketTap,
  });

  final List<String> labels;
  final List<double> receitas;
  final List<double> despesas;
  final DashboardFinanceFocus focus;
  final int? selectedIndex;
  final ValueChanged<int> onBucketTap;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const Center(child: Text('Sem dados'));
    }
    final maxVal = [
      ...receitas,
      ...despesas,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.15;

    return Stack(
      children: [
        BarChart(
          BarChartData(
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (v, _) => Text(
                    'R\$${v.toInt()}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i >= 0 && i < labels.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: labels.length > 20 ? 7 : 9,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              enabled: true,
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions) return;
                final idx = response?.spot?.touchedBarGroupIndex;
                if (idx != null) onBucketTap(idx);
              },
            ),
            barGroups: List.generate(labels.length, (i) {
              final selected = selectedIndex == i;
              final showR = focus != DashboardFinanceFocus.despesas;
              return BarChartGroupData(
                x: i,
                barRods: [
                  if (showR)
                    BarChartRodData(
                      toY: receitas.length > i ? receitas[i] : 0,
                      width: labels.length > 18 ? 6 : 10,
                      color: selected
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF2563EB).withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
        if (focus != DashboardFinanceFocus.receitas)
          LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions) return;
                  final idx = response?.lineBarSpots?.firstOrNull?.x.toInt();
                  if (idx != null) onBucketTap(idx);
                },
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    labels.length,
                    (i) => FlSpot(
                      i.toDouble(),
                      despesas.length > i ? despesas[i] : 0,
                    ),
                  ),
                  isCurved: true,
                  color: const Color(0xFFDC2626),
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) {
                      final sel = selectedIndex == index;
                      return FlDotCirclePainter(
                        radius: sel ? 5 : 3,
                        color: const Color(0xFFDC2626),
                        strokeWidth: sel ? 2 : 0,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DashBuckets {
  _DashBuckets({
    required this.labels,
    required this.bucketStarts,
    required this.monthlyMode,
  });

  final List<String> labels;
  final List<DateTime> bucketStarts;
  final bool monthlyMode;
}

_DashBuckets _buildBuckets(
  DateTimeRange range,
  ChurchDashboardFinancePreset preset,
) {
  const meses = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  final d0 = DateTime(range.start.year, range.start.month, range.start.day);
  final d1 = DateTime(range.end.year, range.end.month, range.end.day);
  final nDays = d1.difference(d0).inDays + 1;

  if (preset == ChurchDashboardFinancePreset.yearly) {
    final y = range.start.year;
    return _DashBuckets(
      labels: meses,
      bucketStarts: List.generate(12, (i) => DateTime(y, i + 1, 1)),
      monthlyMode: true,
    );
  }

  if (preset == ChurchDashboardFinancePreset.weekly ||
      preset == ChurchDashboardFinancePreset.currentMonth ||
      preset == ChurchDashboardFinancePreset.previousMonth ||
      (preset == ChurchDashboardFinancePreset.custom && nDays <= 40)) {
    final labels = <String>[];
    final starts = <DateTime>[];
    for (var i = 0; i < nDays; i++) {
      final day = d0.add(Duration(days: i));
      labels.add('${day.day}/${day.month}');
      starts.add(day);
    }
    return _DashBuckets(labels: labels, bucketStarts: starts, monthlyMode: false);
  }

  var cursor = DateTime(d0.year, d0.month, 1);
  final labels = <String>[];
  final starts = <DateTime>[];
  while (!cursor.isAfter(d1)) {
    labels.add(meses[cursor.month - 1]);
    starts.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return _DashBuckets(labels: labels, bucketStarts: starts, monthlyMode: true);
}
