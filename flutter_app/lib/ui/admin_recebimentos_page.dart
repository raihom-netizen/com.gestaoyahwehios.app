import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';

/// Recebimentos líquidos do Mercado Pago — por igreja, por período, com
/// gráficos clicáveis (mês a mês / ano a ano).
///
/// ⭐ Leitura 100% REST ([[project_web_rest_gateway_total_fix]]): a versão
/// anterior usava `watchQuery` (poll com `.get()` do SDK), e cada ciclo abria
/// um alvo de listen novo — era o que rebentava com
/// `FIRESTORE INTERNAL ASSERTION FAILED` nesta tela.
class AdminRecebimentosPage extends StatefulWidget {
  const AdminRecebimentosPage({super.key});

  @override
  State<AdminRecebimentosPage> createState() => _AdminRecebimentosPageState();
}

/// Janela de tempo escolhida no topo da tela.
enum _Periodo { hoje, semana, mes, ano, personalizado }

class _Recebimento {
  const _Recebimento({
    required this.tenantId,
    required this.amount,
    required this.status,
    required this.type,
    required this.at,
    required this.source,
  });

  final String tenantId;
  final double amount;
  final String status;
  final String type;
  final DateTime? at;
  final String source;

  bool get aprovado {
    final s = status.toLowerCase();
    return s.isEmpty || s == 'approved' || s == 'paid' || s == 'accredited';
  }
}

class _AdminRecebimentosPageState extends State<AdminRecebimentosPage> {
  static const Color _cTeal = Color(0xFF0D9488);
  static const Color _cBlue = Color(0xFF2563EB);
  static const Color _cIndigo = Color(0xFF4F46E5);
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cGreen = Color(0xFF16A34A);
  static const Color _cSlate = Color(0xFF64748B);

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  List<_Recebimento> _todos = const [];
  List<MasterChurchListItem> _igrejas = const [];
  bool _loading = true;
  String? _erro;

  String _igrejaFiltro = '';
  _Periodo _periodo = _Periodo.mes;
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customEnd = DateTime.now();

  bool _graficoAnual = false;
  int _ano = DateTime.now().year;
  int? _mesSelecionado;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // ---------------------------------------------------------------- dados

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _erro = null;
      });
    }
    try {
      final db = firebaseDefaultFirestore;
      final limite = YahwehPerformanceV4.masterPaymentsSampleLimit;
      final results = await Future.wait([
        _safeList(db.collection('sales'), limite),
        _safeList(db.collection('mp_payments'), limite),
        MasterChurchesListService.loadFast().catchError(
          (_) => const <MasterChurchListItem>[],
        ),
      ]);

      final sales = results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      final mp = results[1] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      final igrejas = results[2] as List<MasterChurchListItem>;

      final lista = <_Recebimento>[];
      for (final d in sales) {
        final data = d.data();
        lista.add(
          _Recebimento(
            tenantId: (data['tenantId'] ?? data['igrejaId'] ?? '').toString(),
            amount: _num(data['amount']),
            status: (data['status'] ?? '').toString(),
            type: (data['type'] ?? 'payment').toString(),
            at: _data(data['createdAt']),
            source: 'sales',
          ),
        );
      }
      for (final d in mp) {
        final data = d.data();
        final raw = data['raw'] is Map
            ? Map<String, dynamic>.from(data['raw'] as Map)
            : const <String, dynamic>{};
        lista.add(
          _Recebimento(
            tenantId: (data['tenantId'] ?? data['igrejaId'] ?? '').toString(),
            amount: _num(data['amount'] ?? raw['transaction_amount']),
            status: (data['status'] ?? '').toString(),
            type: (data['type'] ?? 'payment').toString(),
            at: _data(data['createdAt'] ?? raw['date_approved']),
            source: 'mp',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _todos = lista.where((e) => e.aprovado).toList()
          ..sort((a, b) {
            final da = a.at, db2 = b.at;
            if (da == null && db2 == null) return 0;
            if (da == null) return 1;
            if (db2 == null) return -1;
            return db2.compareTo(da);
          });
        _igrejas = igrejas;
        _loading = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = _mensagemErro(e);
      });
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _safeList(
    CollectionReference<Map<String, dynamic>> col,
    int limite,
  ) async {
    try {
      return await firestoreListDocsSafe(col, limit: limite);
    } catch (_) {
      // Uma coleção ausente/sem permissão não pode derrubar a tela toda.
      return const [];
    }
  }

  String _mensagemErro(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'Sem permissão para ler os recebimentos. Confirme o login de '
          'administrador do painel master.';
    }
    return 'Não foi possível carregar os recebimentos agora. '
        'Toque em Atualizar.';
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _data(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  String _nomeIgreja(String id) {
    if (id.trim().isEmpty) return 'Sem igreja';
    for (final i in _igrejas) {
      if (i.id == id) {
        return '${i.data['nome'] ?? i.data['name'] ?? id}';
      }
    }
    return id;
  }

  // -------------------------------------------------------------- filtros

  List<_Recebimento> get _porIgreja => _igrejaFiltro.isEmpty
      ? _todos
      : _todos.where((e) => e.tenantId == _igrejaFiltro).toList();

  DateTimeRange get _intervalo {
    final agora = DateTime.now();
    switch (_periodo) {
      case _Periodo.hoje:
        final i = DateTime(agora.year, agora.month, agora.day);
        return DateTimeRange(start: i, end: agora);
      case _Periodo.semana:
        final base = agora.subtract(Duration(days: agora.weekday - 1));
        return DateTimeRange(
          start: DateTime(base.year, base.month, base.day),
          end: agora,
        );
      case _Periodo.mes:
        return DateTimeRange(
          start: DateTime(agora.year, agora.month, 1),
          end: agora,
        );
      case _Periodo.ano:
        return DateTimeRange(start: DateTime(agora.year, 1, 1), end: agora);
      case _Periodo.personalizado:
        return DateTimeRange(
          start: DateTime(
            _customStart.year,
            _customStart.month,
            _customStart.day,
          ),
          end: DateTime(
            _customEnd.year,
            _customEnd.month,
            _customEnd.day,
            23,
            59,
            59,
          ),
        );
    }
  }

  List<_Recebimento> get _visiveis {
    final r = _intervalo;
    return _porIgreja.where((e) {
      final at = e.at;
      if (at == null) return false;
      if (at.isBefore(r.start) || at.isAfter(r.end)) return false;
      final mes = _mesSelecionado;
      if (mes != null && (at.year != _ano || at.month != mes)) return false;
      return true;
    }).toList();
  }

  double _totalEntre(DateTime inicio, DateTime fim) {
    var soma = 0.0;
    for (final e in _porIgreja) {
      final at = e.at;
      if (at == null) continue;
      if (at.isBefore(inicio) || at.isAfter(fim)) continue;
      soma += e.amount;
    }
    return soma;
  }

  List<int> get _anosDisponiveis {
    final anos = <int>{DateTime.now().year};
    for (final e in _porIgreja) {
      final at = e.at;
      if (at != null) anos.add(at.year);
    }
    final lista = anos.toList()..sort();
    return lista;
  }

  /// Séries do gráfico: 12 meses do ano escolhido, ou os últimos anos.
  List<({String label, double valor, int chave})> get _serie {
    if (_graficoAnual) {
      return _anosDisponiveis
          .map(
            (a) => (
              label: '$a',
              valor: _totalEntre(
                DateTime(a, 1, 1),
                DateTime(a, 12, 31, 23, 59, 59),
              ),
              chave: a,
            ),
          )
          .toList();
    }
    const meses = [
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
    return List.generate(12, (i) {
      final m = i + 1;
      final fim = m == 12
          ? DateTime(_ano, 12, 31, 23, 59, 59)
          : DateTime(_ano, m + 1, 1).subtract(const Duration(seconds: 1));
      return (
        label: meses[i],
        valor: _totalEntre(DateTime(_ano, m, 1), fim),
        chave: m,
      );
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              padding.bottom + 32,
            ),
            children: [
              _cabecalho(),
              const SizedBox(height: 16),
              if (_erro != null) ...[_bannerErro(), const SizedBox(height: 16)],
              _filtros(),
              const SizedBox(height: 16),
              _kpis(),
              const SizedBox(height: 16),
              _cartaoGrafico(),
              const SizedBox(height: 16),
              _secao(
                'Cobranças recebidas',
                'Toque numa barra do gráfico para filtrar por mês.',
              ),
              const SizedBox(height: 10),
              _listaCobrancas(),
              const SizedBox(height: 22),
              _secao('Licenças por igreja', 'Contato direto com o gestor.'),
              const SizedBox(height: 10),
              _listaLicencas(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cIndigo, _cBlue],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: _cIndigo.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recebimentos líquidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Mercado Pago — por igreja, mês e ano.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _bannerErro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: _cAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _cAmber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _erro!,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Atualizar')),
        ],
      ),
    );
  }

  Widget _secao(String titulo, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: const TextStyle(fontSize: 12.5, color: _cSlate),
        ),
      ],
    );
  }

  Widget _filtros() {
    return MasterPremiumCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.church_rounded, size: 18, color: _cIndigo),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _igrejaFiltro,
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Todas as igrejas'),
                        ),
                        ..._igrejas.map(
                          (i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(
                              '${i.data['nome'] ?? i.data['name'] ?? i.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _igrejaFiltro = v ?? ''),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chipPeriodo('Hoje', _Periodo.hoje, _cTeal),
                _chipPeriodo('Semana', _Periodo.semana, _cBlue),
                _chipPeriodo('Mês', _Periodo.mes, _cIndigo),
                _chipPeriodo('Ano', _Periodo.ano, _cGreen),
                _chipPeriodo('Personalizado', _Periodo.personalizado, _cAmber),
              ],
            ),
            if (_periodo == _Periodo.personalizado) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_rounded, size: 17),
                      label: Text(
                        DateFormat('dd/MM/yyyy').format(_customStart),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _escolherData(inicio: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('até'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_rounded, size: 17),
                      label: Text(
                        DateFormat('dd/MM/yyyy').format(_customEnd),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _escolherData(inicio: false),
                    ),
                  ),
                ],
              ),
            ],
            if (_mesSelecionado != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.filter_alt_rounded, size: 16),
                  label: Text(
                    'Filtrado: ${_serie.firstWhere((e) => e.chave == _mesSelecionado, orElse: () => (label: '—', valor: 0.0, chave: 0)).label}/$_ano',
                  ),
                  onDeleted: () => setState(() => _mesSelecionado = null),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _escolherData({required bool inicio}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: inicio ? _customStart : _customEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (inicio) {
        _customStart = d;
      } else {
        _customEnd = d;
      }
    });
  }

  Widget _chipPeriodo(String label, _Periodo p, Color cor) {
    final ativo = _periodo == p;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() {
        _periodo = p;
        _mesSelecionado = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: ativo ? cor : cor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cor.withValues(alpha: ativo ? 1 : 0.32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: ativo ? Colors.white : cor,
          ),
        ),
      ),
    );
  }

  Widget _kpis() {
    final agora = DateTime.now();
    final hoje = _totalEntre(
      DateTime(agora.year, agora.month, agora.day),
      agora,
    );
    final semanaBase = agora.subtract(Duration(days: agora.weekday - 1));
    final semana = _totalEntre(
      DateTime(semanaBase.year, semanaBase.month, semanaBase.day),
      agora,
    );
    final mes = _totalEntre(DateTime(agora.year, agora.month, 1), agora);
    final ano = _totalEntre(DateTime(agora.year, 1, 1), agora);

    return LayoutBuilder(
      builder: (context, c) {
        final colunas = c.maxWidth >= 720 ? 4 : 2;
        final largura = (c.maxWidth - (colunas - 1) * 10) / colunas;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _kpi('Hoje', hoje, _cTeal, _Periodo.hoje, largura),
            _kpi('Esta semana', semana, _cBlue, _Periodo.semana, largura),
            _kpi('Este mês', mes, _cIndigo, _Periodo.mes, largura),
            _kpi('Este ano', ano, _cGreen, _Periodo.ano, largura),
          ],
        );
      },
    );
  }

  Widget _kpi(
    String label,
    double valor,
    Color cor,
    _Periodo p,
    double largura,
  ) {
    final ativo = _periodo == p && _mesSelecionado == null;
    return SizedBox(
      width: largura,
      child: InkWell(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        onTap: () => setState(() {
          _periodo = p;
          _mesSelecionado = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: ativo
                  ? [cor, cor.withValues(alpha: 0.78)]
                  : [
                      cor.withValues(alpha: 0.10),
                      cor.withValues(alpha: 0.06),
                    ],
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(
              color: cor.withValues(alpha: ativo ? 1 : 0.28),
            ),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: cor.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ativo ? Colors.white70 : cor,
                ),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _moeda.format(valor),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ativo ? Colors.white : cor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartaoGrafico() {
    final serie = _serie;
    final maior = serie.fold<double>(0, (a, e) => e.valor > a ? e.valor : a);
    final totalPeriodo = _visiveis.fold<double>(0, (a, e) => a + e.amount);

    return MasterPremiumCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _graficoAnual ? 'Receita por ano' : 'Receita por mês',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _graficoAnual
                            ? 'Toque numa barra para abrir o ano.'
                            : 'Toque numa barra para filtrar o mês.',
                        style: const TextStyle(fontSize: 12, color: _cSlate),
                      ),
                    ],
                  ),
                ),
                _alternador(),
              ],
            ),
            if (!_graficoAnual) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Ano anterior',
                    onPressed: () => setState(() {
                      _ano--;
                      _mesSelecionado = null;
                    }),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    '$_ano',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Próximo ano',
                    onPressed: _ano >= DateTime.now().year
                        ? null
                        : () => setState(() {
                            _ano++;
                            _mesSelecionado = null;
                          }),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  const Spacer(),
                  Text(
                    _moeda.format(totalPeriodo),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _cIndigo,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: maior <= 0
                  ? const Center(
                      child: Text(
                        'Sem receita registrada neste recorte.',
                        style: TextStyle(color: _cSlate, fontSize: 13),
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maior * 1.22,
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maior / 3,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: _cSlate.withValues(alpha: 0.14),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 26,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= serie.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    serie[i].label,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: _cSlate,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                              '${serie[group.x].label}\n${_moeda.format(rod.toY)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          touchCallback: (event, resp) {
                            if (!event.isInterestedForInteractions) return;
                            final spot = resp?.spot;
                            if (spot == null) return;
                            final item = serie[spot.touchedBarGroupIndex];
                            setState(() {
                              if (_graficoAnual) {
                                _ano = item.chave;
                                _graficoAnual = false;
                                _mesSelecionado = null;
                                _periodo = _Periodo.personalizado;
                                _customStart = DateTime(_ano, 1, 1);
                                _customEnd = DateTime(_ano, 12, 31);
                              } else {
                                _periodo = _Periodo.personalizado;
                                _customStart = DateTime(_ano, item.chave, 1);
                                _customEnd = item.chave == 12
                                    ? DateTime(_ano, 12, 31)
                                    : DateTime(
                                        _ano,
                                        item.chave + 1,
                                        1,
                                      ).subtract(const Duration(days: 1));
                                _mesSelecionado =
                                    _mesSelecionado == item.chave
                                    ? null
                                    : item.chave;
                              }
                            });
                          },
                        ),
                        barGroups: [
                          for (var i = 0; i < serie.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: serie[i].valor,
                                  width: serie.length > 6 ? 12 : 22,
                                  borderRadius: BorderRadius.circular(6),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: serie[i].chave == _mesSelecionado
                                        ? [_cGreen, _cTeal]
                                        : [_cIndigo, _cBlue],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alternador() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _alternadorBotao('Mensal', !_graficoAnual, () {
            setState(() => _graficoAnual = false);
          }),
          _alternadorBotao('Anual', _graficoAnual, () {
            setState(() {
              _graficoAnual = true;
              _mesSelecionado = null;
            });
          }),
        ],
      ),
    );
  }

  Widget _alternadorBotao(String label, bool ativo, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: ativo ? _cIndigo : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ativo ? Colors.white : _cSlate,
          ),
        ),
      ),
    );
  }

  Widget _listaCobrancas() {
    if (_loading) return _esqueleto(3);
    final itens = _visiveis;
    if (itens.isEmpty) {
      return _vazio(
        Icons.receipt_long_rounded,
        'Nenhuma cobrança neste recorte.',
      );
    }
    return Column(
      children: [
        for (final r in itens.take(120))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MasterPremiumCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _cGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        r.type == 'preapproval'
                            ? Icons.autorenew_rounded
                            : Icons.payments_rounded,
                        color: _cGreen,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nomeIgreja(r.tenantId),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${r.type == 'preapproval' ? 'Assinatura' : 'Pagamento'}'
                            '${r.status.isEmpty ? '' : ' • ${r.status}'}'
                            '${r.at == null ? '' : ' • ${DateFormat('dd/MM/yyyy').format(r.at!)}'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _cSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _moeda.format(r.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        color: _cGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _listaLicencas() {
    if (_loading) return _esqueleto(2);
    final igrejas = _igrejaFiltro.isEmpty
        ? _igrejas
        : _igrejas.where((e) => e.id == _igrejaFiltro).toList();
    if (igrejas.isEmpty) {
      return _vazio(Icons.church_rounded, 'Nenhuma licença cadastrada.');
    }
    return Column(
      children: [
        for (final i in igrejas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _cartaoLicenca(i),
          ),
      ],
    );
  }

  Widget _cartaoLicenca(MasterChurchListItem item) {
    final d = item.data;
    final nome = '${d['nome'] ?? d['name'] ?? item.id}';
    final license = d['license'] is Map
        ? Map<String, dynamic>.from(d['license'] as Map)
        : const <String, dynamic>{};
    final status = '${license['status'] ?? d['licenseStatus'] ?? '—'}';
    final ativa = status.toLowerCase() == 'active';
    final email = '${d['gestorEmail'] ?? d['gestor_email'] ?? d['email'] ?? ''}'
        .trim();
    final telefone =
        '${d['gestorTelefone'] ?? d['gestor_telefone'] ?? d['telefone'] ?? ''}'
            .trim();
    final gestor = '${d['gestorNome'] ?? d['responsavel'] ?? ''}'.trim();
    final cor = ativa ? _cGreen : _cAmber;

    return MasterPremiumCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    ativa ? Icons.verified_rounded : Icons.schedule_rounded,
                    color: cor,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          'Licença: $status',
                          if (gestor.isNotEmpty) gestor,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 12, color: _cSlate),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (email.isNotEmpty || telefone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (email.isNotEmpty)
                    _acao(Icons.copy_rounded, 'Copiar e-mail', _cIndigo, () {
                      Clipboard.setData(ClipboardData(text: email));
                      ScaffoldMessenger.of(context).showSnackBar(
                        ThemeCleanPremium.successSnackBar(
                          'E-mail do gestor copiado.',
                        ),
                      );
                    }),
                  if (email.isNotEmpty)
                    _acao(Icons.email_rounded, 'E-mail', _cBlue, () {
                      unawaited(launchUrl(Uri.parse('mailto:$email')));
                    }),
                  if (telefone.isNotEmpty)
                    _acao(Icons.chat_rounded, 'WhatsApp', _cGreen, () {
                      final tel = telefone.replaceAll(RegExp(r'[^\d+]'), '');
                      final link = tel.startsWith('+')
                          ? 'https://wa.me/$tel'
                          : 'https://wa.me/55$tel';
                      unawaited(launchUrl(Uri.parse(link)));
                    }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _acao(IconData icon, String label, Color cor, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cor.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _esqueleto(int linhas) {
    return Column(
      children: List.generate(
        linhas,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(color: _cSlate.withValues(alpha: 0.14)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vazio(IconData icon, String texto) {
    return MasterPremiumCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
        child: Column(
          children: [
            Icon(icon, size: 44, color: _cSlate.withValues(alpha: 0.45)),
            const SizedBox(height: 10),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _cSlate, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
