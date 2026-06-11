import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// KPI hero — estilo Controle Total (gradiente suave, tipografia forte).
class FinancePremiumKpiHero extends StatelessWidget {
  const FinancePremiumKpiHero({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ac = accent ?? ThemeCleanPremium.primary;
    final deep = Color.lerp(ac, const Color(0xFF0F172A), 0.35)!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ac, deep],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: ac.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          ...ThemeCleanPremium.softUiCardShadow,
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de conta bancária — saldo atual em destaque.
class FinancePremiumAccountCard extends StatelessWidget {
  const FinancePremiumAccountCard({
    super.key,
    required this.nome,
    required this.saldoAtual,
    required this.receitasMes,
    required this.despesasMes,
    this.bancoSubtitle = '',
    this.accent,
    this.leading,
    this.onTap,
    this.onTransfer,
  });

  final String nome;
  final double saldoAtual;
  final double receitasMes;
  final double despesasMes;
  final String bancoSubtitle;
  final Color? accent;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onTransfer;

  static final _nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    final ac = accent ?? ThemeCleanPremium.primary;
    final saldoPos = saldoAtual >= 0;
    final saldoColor =
        saldoPos ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ac.withValues(alpha: 0.14)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [ac, Color.lerp(ac, const Color(0xFF0F172A), 0.45)!],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (leading != null) ...[
                                leading!,
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  nome,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: -0.35,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              Text(
                                _nf.format(saldoAtual),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: -0.45,
                                  color: saldoColor,
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400, size: 22),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bancoSubtitle.isEmpty
                                ? 'Saldo atual'
                                : '$bancoSubtitle · Saldo atual',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (receitasMes > 0 || despesasMes > 0) ...[
                            const SizedBox(height: 10),
                            FinancePremiumFluxoMiniBar(
                              receitas: receitasMes,
                              despesas: despesasMes,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _fluxoChip(
                                  'Receitas',
                                  _nf.format(receitasMes),
                                  Icons.trending_up_rounded,
                                  const Color(0xFF10B981),
                                ),
                                const SizedBox(width: 8),
                                _fluxoChip(
                                  'Despesas',
                                  _nf.format(despesasMes),
                                  Icons.trending_down_rounded,
                                  const Color(0xFFEF4444),
                                ),
                              ],
                            ),
                          ],
                          if (onTransfer != null) ...[
                            const SizedBox(height: 12),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onTransfer,
                                borderRadius: BorderRadius.circular(14),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF4F46E5),
                                        Color.lerp(ac, const Color(0xFF818CF8), 0.5)!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4F46E5)
                                            .withValues(alpha: 0.28),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Transferir entre contas',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fluxoChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.16),
              color.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra Receitas vs Despesas (estilo Controle Total).
class FinancePremiumFluxoMiniBar extends StatelessWidget {
  const FinancePremiumFluxoMiniBar({
    super.key,
    required this.receitas,
    required this.despesas,
  });

  final double receitas;
  final double despesas;

  @override
  Widget build(BuildContext context) {
    final total = receitas + despesas;
    if (total <= 0) return const SizedBox.shrink();
    final rFrac = (receitas / total).clamp(0.04, 0.96);
    final g = (rFrac * 1000).round().clamp(1, 999);
    final b = (1000 - g).clamp(1, 999);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(
              flex: g,
              child: const ColoredBox(color: Color(0xFF34D399)),
            ),
            Expanded(
              flex: b,
              child: const ColoredBox(color: Color(0xFFF87171)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gráfico de barras mensal — entradas vs saídas.
class FinancePremiumMonthlyBarChart extends StatelessWidget {
  const FinancePremiumMonthlyBarChart({
    super.key,
    required this.entradasPorMes,
    required this.saidasPorMes,
    this.monthLabels,
  });

  final Map<int, double> entradasPorMes;
  final Map<int, double> saidasPorMes;
  final List<String>? monthLabels;

  static const _meses = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D',
  ];

  @override
  Widget build(BuildContext context) {
    final months = <int>{...entradasPorMes.keys, ...saidasPorMes.keys}.toList()
      ..sort();
    if (months.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'Sem movimentação no período',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }

    double maxY = 0;
    for (final m in months) {
      maxY = [
        maxY,
        entradasPorMes[m] ?? 0,
        saidasPorMes[m] ?? 0,
      ].reduce((a, b) => a > b ? a : b);
    }
    if (maxY <= 0) maxY = 1;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (v) => FlLine(
              color: const Color(0xFFE2E8F0),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= months.length) {
                    return const SizedBox.shrink();
                  }
                  final m = months[i];
                  final label = monthLabels != null && i < monthLabels!.length
                      ? monthLabels![i]
                      : (m >= 1 && m <= 12 ? _meses[m - 1] : '$m');
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: entradasPorMes[months[i]] ?? 0,
                    color: const Color(0xFF10B981),
                    width: 10,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                  BarChartRodData(
                    toY: saidasPorMes[months[i]] ?? 0,
                    color: const Color(0xFFEF4444),
                    width: 10,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
                barsSpace: 4,
              ),
          ],
        ),
      ),
    );
  }
}

/// Item de lançamento — card horizontal premium.
class FinancePremiumLancamentoTile extends StatelessWidget {
  const FinancePremiumLancamentoTile({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.isEntrada,
    required this.dataLabel,
    this.badge,
    this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final String valor;
  final bool isEntrada;
  final String dataLabel;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        isEntrada ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final bg = isEntrada
        ? const Color(0xFFECFDF5)
        : const Color(0xFFFEF2F2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isEntrada
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      valor,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dataLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (badge != null && badge!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
