import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/services/panel_finance_chart_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Gráficos premium do Resumo Financeiro — [PanelFinanceChartService] + categorias.
class FinanceResumoChartsSection extends StatelessWidget {
  const FinanceResumoChartsSection({
    super.key,
    required this.allLancamentos,
    required this.receitasPorCat,
    required this.despesasPorCat,
    required this.totalReceitas,
    required this.totalDespesas,
    this.chartYear,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> allLancamentos;
  final Map<String, double> receitasPorCat;
  final Map<String, double> despesasPorCat;
  final double totalReceitas;
  final double totalDespesas;
  final int? chartYear;

  static const _mesesAbrev = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];

  static const _corReceita = Color(0xFF2563EB);
  static const _corDespesa = Color(0xFFDC2626);

  PanelFinanceChartData _yearChartData(int year) {
    final bucketStarts =
        List.generate(12, (i) => DateTime(year, i + 1, 1));
    final yearDocs = allLancamentos.where((d) {
      final data = d.data();
      if (!financeLancamentoEfetivadoParaSaldo(data)) return false;
      final dt = financeLancamentoDate(data);
      return dt != null && dt.year == year;
    }).toList();
    return PanelFinanceChartService.fromFinanceDocs(
      docs: yearDocs,
      bucketStarts: bucketStarts,
      monthlyMode: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final year = chartYear ?? DateTime.now().year;
    final chart = _yearChartData(year);
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartShell(
          title: 'Receitas x Despesas · $year',
          icon: Icons.bar_chart_rounded,
          child: SizedBox(
            height: 240,
            child: chart.hasValues
                ? _MixedBarLineChart(
                    labels: _mesesAbrev,
                    receitas: chart.entradasByBucket,
                    despesas: chart.saidasByBucket,
                  )
                : Center(
                    child: Text(
                      'Sem movimentação efetivada em $year.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendChip(color: _corReceita, label: 'Receitas'),
            const SizedBox(width: 16),
            _LegendChip(color: _corDespesa, label: 'Despesas (linha)'),
          ],
        ),
        if (chart.hasValues) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 4,
            children: [
              Text(
                'Receitas: ${money.format(chart.totalEntradas)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: _corReceita,
                ),
              ),
              Text(
                'Despesas: ${money.format(chart.totalSaidas)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: _corDespesa,
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: ThemeCleanPremium.spaceLg + 4),
        LayoutBuilder(
          builder: (ctx, c) {
            final narrow = c.maxWidth < 500;
            final pieR = _CategoryPieCard(
              title: 'Receitas por categoria',
              entries: receitasPorCat,
              total: totalReceitas,
              colors: const [
                _corReceita,
                Color(0xFF3B82F6),
                Color(0xFF60A5FA),
                Color(0xFF93C5FD),
                Color(0xFF1D4ED8),
                Color(0xFF1E40AF),
              ],
            );
            final pieD = _CategoryPieCard(
              title: 'Despesas por categoria',
              entries: despesasPorCat,
              total: totalDespesas,
              colors: const [
                Color(0xFFDC2626),
                Color(0xFFEA580C),
                Color(0xFFE11D48),
                Color(0xFFF87171),
                Color(0xFFB91C1C),
                Color(0xFF991B1B),
              ],
            );
            if (narrow) {
              return Column(
                children: [pieR, const SizedBox(height: 20), pieD],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pieR),
                const SizedBox(width: 16),
                Expanded(child: pieD),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ChartShell extends StatelessWidget {
  const _ChartShell({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: ThemeCleanPremium.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MixedBarLineChart extends StatelessWidget {
  const _MixedBarLineChart({
    required this.labels,
    required this.receitas,
    required this.despesas,
  });

  final List<String> labels;
  final List<double> receitas;
  final List<double> despesas;

  @override
  Widget build(BuildContext context) {
    final maxVal = [...receitas, ...despesas]
        .fold<double>(0, (a, b) => b > a ? b : a);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.12;

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
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
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
                            fontSize: 9,
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
            barGroups: List.generate(labels.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: i < receitas.length ? receitas[i] : 0,
                    width: 8,
                    color: FinanceResumoChartsSection._corReceita
                        .withValues(alpha: 0.88),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(labels.length, (i) {
                  final y = i < despesas.length ? despesas[i] : 0.0;
                  return FlSpot(i.toDouble(), y);
                }),
                isCurved: true,
                curveSmoothness: 0.22,
                color: FinanceResumoChartsSection._corDespesa,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: FinanceResumoChartsSection._corDespesa,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: FinanceResumoChartsSection._corDespesa
                      .withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryPieCard extends StatelessWidget {
  const _CategoryPieCard({
    required this.title,
    required this.entries,
    required this.total,
    required this.colors,
  });

  final String title;
  final Map<String, double> entries;
  final double total;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final sorted = entries.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    if (sorted.isEmpty || total <= 0) {
      return _ChartShell(
        title: title,
        icon: Icons.pie_chart_rounded,
        child: SizedBox(
          height: 160,
          child: Center(
            child: Text(
              'Sem dados para o período.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final sections = sorted.asMap().entries.map((e) {
      return PieChartSectionData(
        value: e.value.value,
        title: '',
        color: colors[e.key % colors.length],
        radius: 58,
      );
    }).toList();

    return _ChartShell(
      title: title,
      icon: Icons.pie_chart_rounded,
      child: SizedBox(
        height: 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: PieChart(
                PieChartData(
                  sections: sections,
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  startDegreeOffset: -90,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    money.format(total),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Total no período',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...sorted.take(5).toList().asMap().entries.map((ie) {
                    final e = ie.value;
                    final pct = (e.value / total * 100).clamp(0, 999);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[ie.key % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}
