import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/dashboard/church_ministry_intel.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Painel "Saúde ministerial & BI" no dashboard da igreja (pastéis, responsivo).
class ChurchMinistryHealthPanel extends StatefulWidget {
  final String tenantId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs;
  final bool canViewFinance;
  final VoidCallback? onNavigateToMembers;
  final VoidCallback? onRefreshDashboard;

  const ChurchMinistryHealthPanel({
    super.key,
    required this.tenantId,
    required this.memberDocs,
    required this.canViewFinance,
    this.onNavigateToMembers,
    this.onRefreshDashboard,
  });

  @override
  State<ChurchMinistryHealthPanel> createState() =>
      _ChurchMinistryHealthPanelState();
}

class _ChurchMinistryHealthPanelState extends State<ChurchMinistryHealthPanel> {
  bool _loading = true;
  String? _error;
  ChurchMinistryIntel? _intel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChurchMinistryHealthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.memberDocs.length != widget.memberDocs.length) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.tenantId.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId.trim());
      final futures = <Future<dynamic>>[
        base.collection('escalas').orderBy('date', descending: true).limit(400).get(),
        base.collection('noticias').orderBy('createdAt', descending: true).limit(200).get(),
        base.collection('visitantes').orderBy('createdAt', descending: true).limit(300).get(),
      ];
      if (widget.canViewFinance) {
        futures.add(base
            .collection('finance')
            .orderBy('createdAt', descending: true)
            .limit(250)
            .get());
      }
      futures.add(base.get());
      final out = await Future.wait(futures);
      var i = 0;
      final esc = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      final not = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      final vis = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      List<QueryDocumentSnapshot<Map<String, dynamic>>> finDocs = const [];
      if (widget.canViewFinance) {
        finDocs = (out[i++] as QuerySnapshot<Map<String, dynamic>>).docs;
      }
      final church =
          (out[i] as DocumentSnapshot<Map<String, dynamic>>).data();

      final intel = ChurchMinistryIntelService.build(
        members: widget.memberDocs,
        escalas: esc.docs,
        noticias: not.docs,
        visitantes: vis.docs,
        financeDocs: finDocs,
        churchData: church,
        includeFinance: widget.canViewFinance,
      );
      if (mounted) {
        setState(() {
          _intel = intel;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar o painel de inteligência.';
          _loading = false;
        });
      }
    }
  }

  static final _brMoney = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < ThemeCleanPremium.breakpointMobile;

    if (_loading) {
      return _shell(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_error != null) {
      return _shell(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(_error!, style: TextStyle(color: Colors.grey.shade700))),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar'),
              ),
            ],
          ),
        ),
      );
    }
    final intel = _intel!;
    return _shell(
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
                      'Saúde ministerial & inteligência',
                      style: TextStyle(
                        fontSize: narrow ? 17 : 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Últimos ${ChurchMinistryIntelService.staleDays} dias · escalas, eventos (RSVP) e visitantes',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Atualizar dados',
                onPressed: () {
                  _load();
                  widget.onRefreshDashboard?.call();
                },
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpiChip(
                icon: Icons.volunteer_activism_rounded,
                color: const Color(0xFFEF4444),
                label: 'Atenção pastoral',
                value: '${intel.alerts.length}',
                subtitle: 'sem engajamento recente',
              ),
              _kpiChip(
                icon: Icons.how_to_reg_rounded,
                color: const Color(0xFF8B5CF6),
                label: 'Visitantes (mês)',
                value: '${intel.funnel.novosNoMes}',
                subtitle: '${intel.funnel.convertidosNoMes} integrados · ${intel.funnel.emAcompanhamento} em acompanhamento',
              ),
            ],
          ),
          if (intel.alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Membros que precisam de atenção / visita',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            ...intel.alerts.take(8).map((a) => _alertTile(a)),
            if (intel.alerts.length > 8)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onNavigateToMembers,
                  icon: const Icon(Icons.people_rounded, size: 18),
                  label: Text('Ver todos (${intel.alerts.length})'),
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text(
            'Movimento de membros (12 meses)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Novos cadastros, batismos registrados e saídas (inativações por mês)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: narrow ? 200 : 220,
            child: _TriLineChart(flow: intel.last12Months),
          ),
          const SizedBox(height: 16),
          _funnelCard(intel.funnel, narrow),
          if (widget.canViewFinance && intel.finance != null) ...[
            const SizedBox(height: 20),
            _financeBlock(intel.finance!, narrow),
          ],
          const SizedBox(height: 12),
          Text(
            'Contribuições por membro: quando os lançamentos financeiros passarem a registrar CPF, o algoritmo poderá incluir esse sinal.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _kpiChip({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
                Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertTile(MemberPastoralAlert a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_search_rounded, color: Colors.red.shade400, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(a.summary, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _funnelCard(VisitorFunnelSnapshot f, bool narrow) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEEF2FF),
            const Color(0xFFF5F3FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Funil de visitantes',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Visitante → Acompanhamento → Membro (convertido)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          if (narrow)
            Column(
              children: [
                _funnelStep('Neste mês', f.novosNoMes, Icons.person_add_rounded, const Color(0xFF6366F1)),
                const SizedBox(height: 8),
                _funnelStep('Em acompanhamento', f.emAcompanhamento, Icons.support_agent_rounded, const Color(0xFF8B5CF6)),
                const SizedBox(height: 8),
                _funnelStep('Integrados no mês', f.convertidosNoMes, Icons.verified_rounded, const Color(0xFF10B981)),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _funnelStep('Novos (mês)', f.novosNoMes, Icons.person_add_rounded, const Color(0xFF6366F1))),
                const SizedBox(width: 8),
                Expanded(child: _funnelStep('Acompanhamento', f.emAcompanhamento, Icons.support_agent_rounded, const Color(0xFF8B5CF6))),
                const SizedBox(width: 8),
                Expanded(child: _funnelStep('Integrados (mês)', f.convertidosNoMes, Icons.verified_rounded, const Color(0xFF10B981))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _funnelStep(String label, int n, IconData icon, Color c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _financeBlock(ChurchFinanceInsight fi, bool narrow) {
    final meta = fi.metaValor != null && fi.metaValor! > 0;
    final pct = meta && fi.metaAcumulado != null
        ? (fi.metaAcumulado!.clamp(0.0, fi.metaValor!) / fi.metaValor!).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: Colors.green.shade700, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Resumo financeiro inteligente',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (narrow) ...[
            _finRow('Média de entradas (6 meses)', _brMoney.format(fi.mediaEntradasMensal)),
            _finRow('Média de saídas (6 meses)', _brMoney.format(fi.mediaSaidasMensal)),
            _finRow('Projeção de saídas (próx. mês)', _brMoney.format(fi.projecaoSaidasProxMes)),
          ] else
            Row(
              children: [
                Expanded(child: _finRow('Média entradas / mês', _brMoney.format(fi.mediaEntradasMensal))),
                Expanded(child: _finRow('Média saídas / mês', _brMoney.format(fi.mediaSaidasMensal))),
                Expanded(child: _finRow('Projeção saídas', _brMoney.format(fi.projecaoSaidasProxMes))),
              ],
            ),
          if (meta) ...[
            const SizedBox(height: 14),
            Text(
              fi.metaTitulo ?? 'Meta ministerial',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.green.shade900),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 14,
                backgroundColor: Colors.white,
                color: const Color(0xFF22C55E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_brMoney.format(fi.metaAcumulado ?? 0)} de ${_brMoney.format(fi.metaValor!)} (${(pct * 100).toStringAsFixed(0)}%)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              'Edite em Cadastro da igreja → seção Meta ministerial (painel).',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _finRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TriLineChart extends StatelessWidget {
  final List<MonthlyMemberFlow> flow;

  const _TriLineChart({required this.flow});

  @override
  Widget build(BuildContext context) {
    if (flow.isEmpty) {
      return const Center(child: Text('Sem dados'));
    }
    final spotsN = <FlSpot>[];
    final spotsB = <FlSpot>[];
    final spotsS = <FlSpot>[];
    double maxY = 4;
    for (var i = 0; i < flow.length; i++) {
      final f = flow[i];
      spotsN.add(FlSpot(i.toDouble(), f.novos.toDouble()));
      spotsB.add(FlSpot(i.toDouble(), f.batismos.toDouble()));
      spotsS.add(FlSpot(i.toDouble(), f.saidas.toDouble()));
      maxY = [maxY, f.novos.toDouble(), f.batismos.toDouble(), f.saidas.toDouble()]
          .reduce((a, b) => a > b ? a : b);
    }
    maxY = maxY < 4 ? 4 : maxY * 1.15;

    String labelX(double v) {
      final i = v.toInt();
      if (i < 0 || i >= flow.length) return '';
      final p = flow[i].key.split('-');
      if (p.length < 2) return '';
      final m = int.tryParse(p[1]) ?? 1;
      const abbr = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      return abbr[(m - 1).clamp(0, 11)];
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  labelX(v),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spotsN,
            isCurved: true,
            color: const Color(0xFF3B82F6),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: spotsB,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: spotsS,
            isCurved: true,
            color: const Color(0xFFF97316),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
    );
  }
}
