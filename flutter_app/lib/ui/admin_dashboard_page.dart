import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/skeleton_loader.dart';
import 'package:gestao_yahweh/ui/admin_menu_lateral.dart';
import 'package:intl/intl.dart';

/// Painel Master — Dashboard SaaS Super Premium: KPIs, gráficos de novas igrejas, usuários, recebimentos PIX/cartão, vencimentos e acessos.
class AdminDashboardPage extends StatefulWidget {
  final bool embedInPanel;
  final void Function(AdminMenuItem item)? onNavigateTo;

  const AdminDashboardPage({super.key, this.embedInPanel = false, this.onNavigateTo});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  int _usuarios = 0;
  int _igrejas = 0;
  double _receita = 0;
  int _alertas = 0;
  int _licencasIgrejas = 0;
  double _receitaMp = 0;
  List<Map<String, dynamic>> _receitaPorMes = [];
  int _subscriptionsAtivas = 0;
  int _acessosRecentes = 0;

  /// Novas igrejas por mês (últimos 12 meses)
  List<Map<String, dynamic>> _igrejasPorMes = [];
  /// Novos usuários por mês (últimos 12 meses)
  List<Map<String, dynamic>> _usuariosPorMes = [];
  /// Receita PIX vs Cartão (para pizza)
  double _receitaPix = 0;
  double _receitaCartao = 0;
  /// Próximos vencimentos: { nome, dataVencimento, tenantId }
  List<Map<String, dynamic>> _proximosVencimentos = [];
  /// Acessos por dia (últimos 14 dias) para minigráfico
  List<MapEntry<String, int>> _acessosPorDia = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _loadDashboardData().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('Dashboard'),
      );
    } on TimeoutException {
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is Map) {
      final sec = v['seconds'] ?? v['_seconds'];
      if (sec != null) return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
    }
    return DateTime.tryParse(v.toString());
  }

  static bool _isRevenueStatusCountable(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    return s == 'approved' || s == 'paid' || s == 'accredited';
  }

  Future<void> _loadDashboardData() async {
    final db = FirebaseFirestore.instance;
    int usersCount = 0;
    int tenantsCount = 0;
    double receitaPag = 0;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> salesDocs = [];
    int alertasCount = 0;
    int licencasIgrejas = 0;
    int subsAtivas = 0;
    int acessosRecentes = 0;
    final byMonthIgrejas = <String, int>{};
    final byMonthUsuarios = <String, int>{};
    double receitaPix = 0, receitaCartao = 0;
    final List<Map<String, dynamic>> proximosVenc = [];
    final List<MapEntry<String, int>> acessosDia = [];

    final now = DateTime.now();
    final mesesKeys = <String>[];
    for (var i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      mesesKeys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    for (final k in mesesKeys) {
      byMonthIgrejas[k] = 0;
      byMonthUsuarios[k] = 0;
    }

    try {
      final usersSnap = await db.collection('users').get();
      usersCount += usersSnap.size;
      for (final d in usersSnap.docs) {
        final dt = _parseDate(d.data()['createdAt'] ?? d.data()['created_at']);
        if (dt != null) {
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          if (byMonthUsuarios.containsKey(key)) byMonthUsuarios[key] = (byMonthUsuarios[key] ?? 0) + 1;
        }
      }
    } catch (_) {}
    try {
      final usuariosSnap = await db.collection('usuarios').get();
      usersCount += usuariosSnap.size;
    } catch (_) {}
    try {
      final tenantsSnap = await db.collection('igrejas').get();
      tenantsCount = tenantsSnap.size;
      for (final d in tenantsSnap.docs) {
        final data = d.data();
        final lic = data['license'] as Map?;
        if (lic != null && (lic['status'] ?? '').toString().toLowerCase() == 'active') licencasIgrejas++;
        final dt = _parseDate(data['createdAt'] ?? data['created_at'] ?? data['dataCadastro']);
        if (dt != null) {
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          if (byMonthIgrejas.containsKey(key)) byMonthIgrejas[key] = (byMonthIgrejas[key] ?? 0) + 1;
        }
        final validUntil = _parseDate(lic?['validUntil'] ?? lic?['valid_until'] ?? data['vencimento']);
        if (validUntil != null && validUntil.isAfter(now)) {
          proximosVenc.add({
            'nome': (data['name'] ?? data['nome'] ?? data['slug'] ?? d.id).toString(),
            'dataVencimento': validUntil,
            'tenantId': d.id,
          });
        }
      }
      proximosVenc.sort((a, b) => (a['dataVencimento'] as DateTime).compareTo(b['dataVencimento'] as DateTime));
      if (proximosVenc.length > 10) proximosVenc.removeRange(10, proximosVenc.length);
    } catch (_) {}
    try {
      final pagSnap = await db.collection('pagamentos').get();
      receitaPag = pagSnap.docs.fold(0.0, (a, b) => a + (double.tryParse(b.data()['valor']?.toString() ?? '') ?? 0));
    } catch (_) {}
    try {
      final salesSnap = await db.collection('sales').get();
      salesDocs = salesSnap.docs.where((d) {
        final status = (d.data()['status'] ?? '').toString();
        return _isRevenueStatusCountable(status);
      }).toList();
      for (final d in salesDocs) {
        final data = d.data();
        final method = (data['payment_method'] ?? data['paymentMethod'] ?? data['payment_type'] ?? '').toString().toLowerCase();
        final amt = (data['amount'] ?? 0);
        final val = amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0;
        if (method.contains('pix')) receitaPix += val;
        else if (method.contains('card') || method.contains('credit') || method.contains('cartão')) receitaCartao += val;
        else receitaCartao += val;
      }
    } catch (_) {}
    try {
      final alertasSnap = await db.collection('alertas').get();
      alertasCount = alertasSnap.size;
    } catch (_) {}
    try {
      final subSnap = await db.collection('subscriptions').where('status', isEqualTo: 'active').get();
      subsAtivas = subSnap.size;
    } catch (_) {}
    try {
      final analyticsSnap = await db.collection('analytics').orderBy('createdAt', descending: true).limit(500).get();
      acessosRecentes = analyticsSnap.size;
      final byDay = <String, int>{};
      for (final d in analyticsSnap.docs) {
        final dt = _parseDate(d.data()['createdAt']);
        if (dt != null) {
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          byDay[key] = (byDay[key] ?? 0) + 1;
        }
      }
      final sorted = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      if (sorted.length > 14) acessosDia.addAll(sorted.sublist(sorted.length - 14));
      else acessosDia.addAll(sorted);
    } catch (_) {}
    try {
      final configSnap = await db.doc('config/analytics').get();
      if (configSnap.exists) {
        final daily = configSnap.data()?['daily'] as Map<String, dynamic>?;
        if (daily != null && daily.isNotEmpty) {
          final list = daily.entries
              .map((e) => MapEntry(e.key, (e.value is num) ? (e.value as num).toInt() : int.tryParse(e.value.toString()) ?? 0))
              .toList();
          list.sort((a, b) => a.key.compareTo(b.key));
          if (list.length > 14) acessosDia.clear();
          acessosDia.addAll(list.length > 14 ? list.sublist(list.length - 14) : list);
        }
      }
    } catch (_) {}

    _receitaPorMes = _buildReceitaPorMes(salesDocs);
    _igrejasPorMes = mesesKeys.map((k) {
      final parts = k.split('-');
      final y = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 1;
      return {'key': k, 'label': '${m.toString().padLeft(2, '0')}/${y.toString().substring(2)}', 'valor': byMonthIgrejas[k] ?? 0};
    }).toList();
    _usuariosPorMes = mesesKeys.map((k) {
      final parts = k.split('-');
      final y = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 1;
      return {'key': k, 'label': '${m.toString().padLeft(2, '0')}/${y.toString().substring(2)}', 'valor': byMonthUsuarios[k] ?? 0};
    }).toList();

    _usuarios = usersCount;
    _igrejas = tenantsCount;
    _receita = receitaPag;
    _receitaMp = salesDocs.fold(0.0, (a, b) {
      final amt = (b.data()['amount'] ?? 0);
      return a + (amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0);
    });
    if (_receitaMp > 0) _receita += _receitaMp;
    _licencasIgrejas = licencasIgrejas;
    _receitaPix = receitaPix;
    _receitaCartao = receitaCartao;
    _alertas = alertasCount;
    _subscriptionsAtivas = subsAtivas > 0 ? subsAtivas : _licencasIgrejas;
    _acessosRecentes = acessosRecentes;
    _proximosVencimentos = proximosVenc;
    _acessosPorDia = acessosDia;
  }

  List<Map<String, dynamic>> _buildReceitaPorMes(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final byMonth = <String, double>{};
    for (final d in docs) {
      final data = d.data();
      final createdAt = data['createdAt'];
      if (createdAt == null) continue;
      DateTime? dt = _parseDate(createdAt);
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final amt = (data['amount'] ?? 0);
      final val = amt is num ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0;
      byMonth[key] = (byMonth[key] ?? 0) + val;
    }
    final now = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (var i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      result.add({
        'key': key,
        'label': '${d.month.toString().padLeft(2, '0')}/${d.year.toString().substring(2)}',
        'valor': byMonth[key] ?? 0.0,
      });
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 700;
    final padding = ThemeCleanPremium.pagePadding(context);

    if (_loading) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SkeletonLoader(itemCount: 1, itemHeight: 80),
            const SizedBox(height: 24),
            const SkeletonLoader(itemCount: 5, itemHeight: 100),
            const SizedBox(height: 24),
            const SkeletonLoader(itemCount: 3, itemHeight: 200),
          ],
        ),
      );
    }

    final body = RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WelcomeStrip(),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            _ChartCard(
              title: 'Dashboard de crescimento (BI)',
              icon: Icons.rocket_launch_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Novas igrejas vs. novos usuários — últimos 12 meses',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  _masterGrowthBiChart(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _growthLegendDot(const Color(0xFF2563EB), 'Igrejas'),
                      const SizedBox(width: 20),
                      _growthLegendDot(const Color(0xFF0D9488), 'Usuários'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            _KpiGrid(
              usuarios: _usuarios,
              igrejas: _igrejas,
              licencasAtivas: _subscriptionsAtivas > 0 ? _subscriptionsAtivas : _licencasIgrejas,
              recebimentos: _receita,
              acessos: _acessosRecentes,
              onNavigateTo: widget.onNavigateTo,
              isNarrow: isNarrow,
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            LayoutBuilder(
              builder: (_, c) {
                final w = c.maxWidth;
                final single = w < 600;
                return single
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ChartCard(title: 'Novas igrejas por mês', icon: Icons.church_rounded, child: _barChart(_igrejasPorMes, ThemeCleanPremium.primary)),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _ChartCard(title: 'Novos usuários por mês', icon: Icons.people_rounded, child: _barChart(_usuariosPorMes, Colors.teal.shade600)),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _ChartCard(title: 'Recebimentos por mês', icon: Icons.trending_up_rounded, child: _lineChartReceita()),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _ChartCard(title: 'Recebimentos PIX vs Cartão', icon: Icons.pie_chart_rounded, child: _piePixCartao()),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _VencimentosCard(items: _proximosVencimentos, onNavigateTo: widget.onNavigateTo),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _AcessosCard(acessosPorDia: _acessosPorDia, total: _acessosRecentes, onNavigateTo: widget.onNavigateTo),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 1, child: _ChartCard(title: 'Novas igrejas por mês', icon: Icons.church_rounded, child: _barChart(_igrejasPorMes, ThemeCleanPremium.primary))),
                              const SizedBox(width: ThemeCleanPremium.spaceLg),
                              Expanded(flex: 1, child: _ChartCard(title: 'Novos usuários por mês', icon: Icons.people_rounded, child: _barChart(_usuariosPorMes, Colors.teal.shade600))),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _ChartCard(title: 'Recebimentos por mês', icon: Icons.trending_up_rounded, child: _lineChartReceita()),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 1, child: _ChartCard(title: 'Recebimentos PIX vs Cartão', icon: Icons.pie_chart_rounded, child: _piePixCartao())),
                              const SizedBox(width: ThemeCleanPremium.spaceLg),
                              Expanded(flex: 1, child: _VencimentosCard(items: _proximosVencimentos, onNavigateTo: widget.onNavigateTo)),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _AcessosCard(acessosPorDia: _acessosPorDia, total: _acessosRecentes, onNavigateTo: widget.onNavigateTo),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );

    if (widget.embedInPanel) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Master'),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _barChart(List<Map<String, dynamic>> data, Color color) {
    if (data.isEmpty) return const SizedBox(height: 180, child: Center(child: Text('Sem dados')));
    final maxY = data.fold<double>(0, (m, e) {
      final v = (e['valor'] is int) ? (e['valor'] as int).toDouble() : (e['valor'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY * 1.15 : 4,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i >= 0 && i < data.length) {
                    final label = data[i]['label'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(label.length > 5 ? label.substring(0, 5) : label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    );
                  }
                  return const SizedBox();
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY > 0 ? null : 1, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (data[i]['valor'] is int) ? (data[i]['valor'] as int).toDouble() : (data[i]['valor'] as num?)?.toDouble() ?? 0,
                    color: color.withOpacity(0.85),
                    width: 12,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ],
                showingTooltipIndicators: [],
              ),
          ],
        ),
      ),
    );
  }

  Widget _lineChartReceita() {
    if (_receitaPorMes.isEmpty) return const SizedBox(height: 180, child: Center(child: Text('Sem dados de receita')));
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < _receitaPorMes.length; i++) FlSpot(i.toDouble(), (_receitaPorMes[i]['valor'] as num).toDouble())],
              isCurved: true,
              color: Colors.green.shade600,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.12)),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i >= 0 && i < _receitaPorMes.length) {
                    final label = _receitaPorMes[i]['label'] as String? ?? '';
                    return Padding(padding: const EdgeInsets.only(top: 8), child: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)));
                  }
                  return const SizedBox();
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) => Text('R\$${v.toInt()}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _piePixCartao() {
    final total = _receitaPix + _receitaCartao;
    if (total <= 0) return const SizedBox(height: 180, child: Center(child: Text('Sem dados PIX/Cartão')));
    final pixPct = (_receitaPix / total * 100).round();
    final cartaoPct = 100 - pixPct;
    final pixVal = _receitaPix > 0 ? _receitaPix : 0.001;
    final cartaoVal = _receitaCartao > 0 ? _receitaCartao : 0.001;
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(value: pixVal, title: 'PIX\n$pixPct%', color: const Color(0xFF0D9488), radius: 48, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  PieChartSectionData(value: cartaoVal, title: 'Cartão\n$cartaoPct%', color: const Color(0xFF1E40AF), radius: 48, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendRow(const Color(0xFF0D9488), 'PIX', _receitaPix),
              const SizedBox(height: 8),
              _legendRow(const Color(0xFF1E40AF), 'Cartão', _receitaCartao),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, double value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text('$label: R\$ ${value.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
      ],
    );
  }

  Widget _growthLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _masterGrowthBiChart() {
    if (_igrejasPorMes.isEmpty) {
      return const SizedBox(height: 160, child: Center(child: Text('Sem dados')));
    }
    final n = _igrejasPorMes.length;
    final spotsI = <FlSpot>[];
    final spotsU = <FlSpot>[];
    double maxY = 4;
    for (var i = 0; i < n; i++) {
      final vi = (_igrejasPorMes[i]['valor'] is int)
          ? (_igrejasPorMes[i]['valor'] as int).toDouble()
          : (_igrejasPorMes[i]['valor'] as num?)?.toDouble() ?? 0;
      final vu = i < _usuariosPorMes.length
          ? ((_usuariosPorMes[i]['valor'] is int)
              ? (_usuariosPorMes[i]['valor'] as int).toDouble()
              : (_usuariosPorMes[i]['valor'] as num?)?.toDouble() ?? 0)
          : 0.0;
      spotsI.add(FlSpot(i.toDouble(), vi));
      spotsU.add(FlSpot(i.toDouble(), vu));
      if (vi > maxY) maxY = vi;
      if (vu > maxY) maxY = vu;
    }
    maxY = maxY < 4 ? 4 : maxY * 1.12;
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spotsI,
              isCurved: true,
              color: const Color(0xFF2563EB),
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
            LineChartBarData(
              spots: spotsU,
              isCurved: true,
              color: const Color(0xFF0D9488),
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i >= 0 && i < _igrejasPorMes.length) {
                    final label = _igrejasPorMes[i]['label'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        label.length > 5 ? label.substring(0, 5) : label,
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, meta) => Text(
                  '${v.toInt()}',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
        duration: const Duration(milliseconds: 450),
      ),
    );
  }
}

class _WelcomeStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg, vertical: ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ThemeCleanPremium.primary.withOpacity(0.08), ThemeCleanPremium.primary.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: ThemeCleanPremium.primary.withOpacity(0.12)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            ),
            child: const Icon(Icons.analytics_rounded, color: ThemeCleanPremium.primary, size: 28),
          ),
          const SizedBox(width: ThemeCleanPremium.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface, letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text('Visão geral: igrejas, usuários, recebimentos PIX/cartão, vencimentos e acessos ao domínio.', style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int usuarios;
  final int igrejas;
  final int licencasAtivas;
  final double recebimentos;
  final int acessos;
  final void Function(AdminMenuItem item)? onNavigateTo;
  final bool isNarrow;

  const _KpiGrid({
    required this.usuarios,
    required this.igrejas,
    required this.licencasAtivas,
    required this.recebimentos,
    required this.acessos,
    this.onNavigateTo,
    required this.isNarrow,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.people_rounded, label: 'Usuários', value: usuarios.toDouble(), prefix: '', color: ThemeCleanPremium.primary, item: AdminMenuItem.igrejasUsuarios),
      (icon: Icons.church_rounded, label: 'Igrejas', value: igrejas.toDouble(), prefix: '', color: Colors.blue.shade700, item: AdminMenuItem.igrejasLista),
      (icon: Icons.badge_rounded, label: 'Licenças ativas', value: licencasAtivas.toDouble(), prefix: '', color: Colors.green.shade700, item: AdminMenuItem.igrejasRecebimentos),
      (icon: Icons.receipt_long_rounded, label: 'Recebimentos', value: recebimentos, prefix: 'R\$ ', color: Colors.orange.shade700, item: AdminMenuItem.igrejasRecebimentos),
      (icon: Icons.public_rounded, label: 'Acessos', value: acessos.toDouble(), prefix: '', color: Colors.purple.shade700, item: AdminMenuItem.sistemaAcessos),
    ];
    return LayoutBuilder(
      builder: (_, c) {
        final count = isNarrow ? 2 : (c.maxWidth > 900 ? 5 : 4);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: isNarrow ? 1.0 : 1.5,
          children: items.map((e) {
            final card = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: e.color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(e.icon, color: e.color, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(e.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Text('${e.prefix}${e.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: e.color)),
                ],
              ),
            );
            if (onNavigateTo != null) {
              return Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd), onTap: () => onNavigateTo!(e.item), child: card));
            }
            return card;
          }).toList(),
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ChartCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _VencimentosCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(AdminMenuItem item)? onNavigateTo;

  const _VencimentosCard({required this.items, this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 10),
              const Text('Próximos vencimentos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nenhum vencimento próximo',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            ...items.map((e) {
              final dt = e['dataVencimento'] as DateTime?;
              final nome = (e['nome'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 10),
                    Expanded(child: Text(nome, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                    Text(dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '—', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              );
            }),
          if (onNavigateTo != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: () => onNavigateTo!(AdminMenuItem.igrejasRecebimentos),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Ver recebimentos'),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcessosCard extends StatelessWidget {
  final List<MapEntry<String, int>> acessosPorDia;
  final int total;
  final void Function(AdminMenuItem item)? onNavigateTo;

  const _AcessosCard({required this.acessosPorDia, required this.total, this.onNavigateTo});

  @override
  Widget build(BuildContext context) {
    final maxH = acessosPorDia.isEmpty ? 1 : acessosPorDia.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 10),
              const Text('Acessos ao domínio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const Spacer(),
              Text('Total: $total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 16),
          if (acessosPorDia.isEmpty)
            const SizedBox(height: 100, child: Center(child: Text('Sem dados de acessos')))
          else
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < acessosPorDia.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(acessosPorDia[i].value.toString(), style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                            const SizedBox(height: 2),
                            Container(
                              height: (maxH > 0 ? (acessosPorDia[i].value / maxH) : 0) * 70 + 8,
                              decoration: BoxDecoration(
                                color: Colors.purple.shade400.withOpacity(0.8),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(acessosPorDia[i].key.length >= 10 ? acessosPorDia[i].key.substring(5) : acessosPorDia[i].key, style: TextStyle(fontSize: 8, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (onNavigateTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: () => onNavigateTo!(AdminMenuItem.sistemaAcessos),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Ver acessos'),
              ),
            ),
        ],
      ),
    );
  }
}
