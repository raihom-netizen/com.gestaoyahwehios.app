import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class GraficoUltraModerno extends StatelessWidget {
  final List<double> valores;
  final List<String> labels;
  final String titulo;
  const GraficoUltraModerno({super.key, required this.valores, required this.labels, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < valores.length; i++) FlSpot(i.toDouble(), valores[i]),
                      ],
                      isCurved: true,
                      color: Colors.cyan,
                      barWidth: 5,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: true, color: Colors.cyan.withOpacity(0.18)),
                      shadow: const Shadow(color: Colors.black26, blurRadius: 8),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) => Text(labels[v.toInt() % labels.length]),
                      ),
                    ),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: true, horizontalInterval: 5),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: Colors.blueGrey[900]!,
                      getTooltipItems: (touchedSpots) => touchedSpots
                          .map((spot) => LineTooltipItem(
                                '${labels[spot.x.toInt()]}\n${spot.y.toStringAsFixed(1)}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
