import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/pdf/membros_financeiro_geral_pdf.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_relatorios_load_service.dart';
import 'package:gestao_yahweh/ui/pages/finance_vinculo_extrato_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/yahweh_date_range_picker.dart';

/// Linha do quadro: uma pessoa e o que entrou e saiu por causa dela.
class MembroFinanceiroLinha {
  MembroFinanceiroLinha({
    required this.id,
    required this.nome,
    required this.sexo,
    required this.departamentos,
    required this.idade,
  });

  final String id;
  final String nome;

  /// `m`, `f` ou vazio.
  final String sexo;
  final List<String> departamentos;

  /// `null` quando o cadastro não tem data de nascimento.
  final int? idade;

  double receitas = 0;
  double despesas = 0;

  double get saldo => receitas - despesas;
  bool get temMovimento => receitas > 0 || despesas > 0;

  /// Faixa usada nos gráficos: criança (<12), idoso (>=60) ou adulto.
  String get faixa {
    final i = idade;
    if (i == null) return 'adulto';
    if (i < 12) return 'crianca';
    if (i >= 60) return 'idoso';
    return 'adulto';
  }
}

enum _Periodo { ano, mes, intervalo }

enum _Ordem { alfabetica, maisReceita, maisDespesa }

/// Financeiro de **todos os membros** num só quadro.
///
/// A ficha de cada membro já mostra o extrato dele; o que faltava era a visão
/// de cima — quem contribuiu, quanto, e como isso se distribui por sexo, faixa
/// etária e departamento. É a pergunta que o pastor e o tesoureiro fazem no
/// fecho do mês, e que antes só se respondia abrindo membro a membro.
class MembrosFinanceiroGeralPage extends StatefulWidget {
  const MembrosFinanceiroGeralPage({
    super.key,
    required this.tenantId,
    required this.panelRole,
  });

  final String tenantId;
  final String panelRole;

  @override
  State<MembrosFinanceiroGeralPage> createState() =>
      _MembrosFinanceiroGeralPageState();
}

class _MembrosFinanceiroGeralPageState
    extends State<MembrosFinanceiroGeralPage> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _exportando = false;
  String _erro = '';
  int _revisaoHub = -1;

  List<Map<String, dynamic>> _membros = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lancamentos = const [];

  _Periodo _periodo = _Periodo.ano;
  late int _ano = DateTime.now().year;
  late int _mes = DateTime.now().month;
  DateTimeRange? _intervalo;

  _Ordem _ordem = _Ordem.maisReceita;
  String _filtroSexo = 'todos';
  String _filtroDepartamento = 'todos';
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_aoMudarNoFinanceiro);
    unawaited(_carregar());
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_aoMudarNoFinanceiro);
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _aoMudarNoFinanceiro() {
    final r = FinanceTransactionsHub.revision.value;
    if (r == _revisaoHub) return;
    _revisaoHub = r;
    if (mounted) unawaited(_carregar(force: true));
  }

  String get _tid => ChurchRepository.churchId(widget.tenantId);

  Future<void> _carregar({bool force = false}) async {
    if (mounted) setState(() => _carregando = _membros.isEmpty);
    try {
      final res = await Future.wait([
        ChurchRelatoriosLoadService.loadMembrosRows(
          churchIdHint: _tid,
          limit: 800,
          forceRefresh: force,
        ),
        ChurchFinanceLoadService.loadLancamentos(
          seedTenantId: _tid,
          limit: FirebasePerformanceLimits.financeiroPage,
          forceRefresh: force,
          forceServer: force,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _membros = res[0] as List<Map<String, dynamic>>;
        _lancamentos =
            (res[1] as dynamic).docs
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
        _carregando = false;
        _erro = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar: $e';
      });
    }
  }

  // ───────────────────────────────────────────── dados

  static String _txt(Map<String, dynamic> m, List<String> chaves) {
    for (final k in chaves) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static int? _idadeDe(Map<String, dynamic> m) {
    final raw = m['DATA_NASCIMENTO'] ?? m['dataNascimento'] ?? m['birthDate'];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    } else if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      final n = sec is num ? sec.toInt() : int.tryParse('$sec');
      if (n != null && n > 0) {
        dt = DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
    } else if (raw != null) {
      dt = DateTime.tryParse(raw.toString());
    }
    if (dt == null) return null;
    final hoje = DateTime.now();
    var anos = hoje.year - dt.year;
    if (hoje.month < dt.month ||
        (hoje.month == dt.month && hoje.day < dt.day)) {
      anos--;
    }
    return anos < 0 || anos > 130 ? null : anos;
  }

  static List<String> _departamentosDe(Map<String, dynamic> m) {
    final raw = m['DEPARTAMENTOS'] ?? m['departamentos'];
    if (raw is List) {
      return [
        for (final e in raw)
          if ((e ?? '').toString().trim().isNotEmpty) e.toString().trim(),
      ];
    }
    final unico = _txt(m, ['departamento', 'DEPARTAMENTO']);
    return unico.isEmpty ? const [] : [unico];
  }

  bool _noPeriodo(Map<String, dynamic> d) {
    final dt = financeLancamentoDate(d);
    if (dt == null) return false;
    switch (_periodo) {
      case _Periodo.ano:
        return dt.year == _ano;
      case _Periodo.mes:
        return dt.year == _ano && dt.month == _mes;
      case _Periodo.intervalo:
        final r = _intervalo;
        if (r == null) return true;
        final ini = DateTime(r.start.year, r.start.month, r.start.day);
        final fim = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !dt.isBefore(ini) && !dt.isAfter(fim);
    }
  }

  String get _periodoLabel {
    switch (_periodo) {
      case _Periodo.ano:
        return 'Ano de $_ano';
      case _Periodo.mes:
        return DateFormat('MMMM \'de\' y', 'pt_BR').format(DateTime(_ano, _mes));
      case _Periodo.intervalo:
        final r = _intervalo;
        if (r == null) return 'Período livre';
        final f = DateFormat('dd/MM/yyyy', 'pt_BR');
        return '${f.format(r.start)} a ${f.format(r.end)}';
    }
  }

  /// Quadro por pessoa, já filtrado e ordenado.
  List<MembroFinanceiroLinha> get _linhas {
    final porId = <String, MembroFinanceiroLinha>{};
    for (final m in _membros) {
      final id = (m['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final nome = _txt(m, [
        'NOME_COMPLETO',
        'nomeCompleto',
        'NOME',
        'nome',
        'name',
      ]);
      if (nome.isEmpty) continue;
      final sexoRaw = _txt(m, ['SEXO', 'sexo', 'genero']).toLowerCase();
      porId[id] = MembroFinanceiroLinha(
        id: id,
        nome: nome,
        sexo: sexoRaw.startsWith('m')
            ? 'm'
            : (sexoRaw.startsWith('f') ? 'f' : ''),
        departamentos: _departamentosDe(m),
        idade: _idadeDe(m),
      );
    }

    for (final doc in _lancamentos) {
      final d = doc.data();
      // Só vínculo individual: com várias pessoas o valor não é de ninguém
      // em particular e somá-lo a cada uma contaria o mesmo dinheiro várias
      // vezes.
      if (d['vinculoMultiplo'] == true) continue;
      final mid = (d['membroId'] ?? d['memberId'] ?? '').toString().trim();
      if (mid.isEmpty) continue;
      final linha = porId[mid];
      if (linha == null) continue;
      if (!_noPeriodo(d)) continue;
      final t = financeInferTipo(d);
      if (t == 'transferencia') continue;
      final v = financeParseValorBr(d['amount'] ?? d['valor']);
      if (t.contains('entrada') || t.contains('receita')) {
        linha.receitas += v;
      } else if (t.contains('saida') || t.contains('despesa')) {
        linha.despesas += v;
      }
    }

    var out = porId.values.where((l) => l.temMovimento).toList();

    if (_filtroSexo != 'todos') {
      out = out.where((l) => l.sexo == _filtroSexo).toList();
    }
    if (_filtroDepartamento != 'todos') {
      out = out
          .where((l) => l.departamentos.contains(_filtroDepartamento))
          .toList();
    }
    if (_busca.isNotEmpty) {
      final q = _busca.toLowerCase();
      out = out.where((l) => l.nome.toLowerCase().contains(q)).toList();
    }

    switch (_ordem) {
      case _Ordem.alfabetica:
        out.sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );
      case _Ordem.maisReceita:
        out.sort((a, b) => b.receitas.compareTo(a.receitas));
      case _Ordem.maisDespesa:
        out.sort((a, b) => b.despesas.compareTo(a.despesas));
    }
    return out;
  }

  List<String> get _todosDepartamentos {
    final s = <String>{};
    for (final m in _membros) {
      s.addAll(_departamentosDe(m));
    }
    final l = s.toList()..sort();
    return l;
  }

  double get _totalReceitas =>
      _linhas.fold<double>(0, (a, l) => a + l.receitas);

  double get _totalDespesas =>
      _linhas.fold<double>(0, (a, l) => a + l.despesas);

  /// Entradas e saídas mês a mês, só das pessoas visíveis no filtro.
  List<({int mes, double receitas, double despesas})> get _porMes {
    final ids = {for (final l in _linhas) l.id};
    final rec = List<double>.filled(12, 0);
    final des = List<double>.filled(12, 0);
    for (final doc in _lancamentos) {
      final d = doc.data();
      if (d['vinculoMultiplo'] == true) continue;
      final mid = (d['membroId'] ?? d['memberId'] ?? '').toString().trim();
      if (!ids.contains(mid)) continue;
      if (!_noPeriodo(d)) continue;
      final dt = financeLancamentoDate(d);
      if (dt == null) continue;
      final t = financeInferTipo(d);
      final v = financeParseValorBr(d['amount'] ?? d['valor']);
      if (t.contains('entrada') || t.contains('receita')) {
        rec[dt.month - 1] += v;
      } else if (t.contains('saida') || t.contains('despesa')) {
        des[dt.month - 1] += v;
      }
    }
    return [
      for (var i = 0; i < 12; i++)
        (mes: i + 1, receitas: rec[i], despesas: des[i]),
    ];
  }

  Map<String, double> get _receitaPorDepartamento {
    final out = <String, double>{};
    for (final l in _linhas) {
      if (l.receitas <= 0) continue;
      if (l.departamentos.isEmpty) {
        out['Sem departamento'] = (out['Sem departamento'] ?? 0) + l.receitas;
        continue;
      }
      // Sem rateio: quem esta em dois departamentos conta nos dois. E uma
      // leitura de participacao, nao de caixa — somar as fatias nao tem de
      // bater com o total.
      for (final d in l.departamentos) {
        out[d] = (out[d] ?? 0) + l.receitas;
      }
    }
    return out;
  }

  Map<String, double> get _receitaPorPerfil {
    final out = <String, double>{
      'Homens': 0,
      'Mulheres': 0,
      'Crianças': 0,
      'Idosos': 0,
    };
    for (final l in _linhas) {
      if (l.receitas <= 0) continue;
      if (l.faixa == 'crianca') {
        out['Crianças'] = out['Crianças']! + l.receitas;
      } else if (l.faixa == 'idoso') {
        out['Idosos'] = out['Idosos']! + l.receitas;
      } else if (l.sexo == 'm') {
        out['Homens'] = out['Homens']! + l.receitas;
      } else if (l.sexo == 'f') {
        out['Mulheres'] = out['Mulheres']! + l.receitas;
      }
    }
    out.removeWhere((_, v) => v <= 0);
    return out;
  }

  // ───────────────────────────────────────────── ações

  Future<void> _abrirExtrato(MembroFinanceiroLinha l) =>
      abrirExtratoFinanceiroDoVinculo(
        context,
        tenantId: widget.tenantId,
        tipo: 'membro',
        vinculoId: l.id,
        nome: l.nome,
        panelRole: widget.panelRole,
        onChanged: () => unawaited(_carregar(force: true)),
      );

  Future<void> _escolherIntervalo() async {
    final agora = DateTime.now();
    final r = await escolherIntervaloDeDatas(
      context,
      firstDate: DateTime(agora.year - 8),
      lastDate: DateTime(agora.year + 1, 12, 31),
      initialDateRange: _intervalo ??
          DateTimeRange(
            start: DateTime(agora.year, agora.month, 1),
            end: agora,
          ),
    );
    if (r != null && mounted) {
      setState(() {
        _intervalo = r;
        _periodo = _Periodo.intervalo;
      });
    }
  }

  Future<void> _exportarPdf() async {
    if (_exportando) return;
    setState(() => _exportando = true);
    try {
      final branding = await loadReportPdfBranding(_tid);
      final bytes = await buildMembrosFinanceiroGeralPdf(
        branding: branding,
        linhas: _linhas,
        periodoLabel: _periodoLabel,
        filtroLabel: _filtroLabel,
      );
      if (!mounted) return;
      await showPdfActions(
        context,
        bytes: bytes,
        filename: 'financeiro_membros_$_ano.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  String get _filtroLabel {
    final partes = <String>[];
    if (_filtroSexo == 'm') partes.add('Homens');
    if (_filtroSexo == 'f') partes.add('Mulheres');
    if (_filtroDepartamento != 'todos') partes.add(_filtroDepartamento);
    return partes.isEmpty ? 'Todos os membros' : partes.join(' · ');
  }

  // ───────────────────────────────────────────── UI

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    final receitas = _totalReceitas;
    final despesas = _totalDespesas;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Financeiro geral',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              'Contribuições e despesas por membro',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : () => _carregar(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: _exportando ? null : _exportarPdf,
            icon: _exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: _carregando && _membros.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _carregar(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  if (_erro.isNotEmpty) _banner(_erro),
                  _cartaoPeriodo(),
                  const SizedBox(height: 12),
                  _cartoesTotais(receitas, despesas, linhas),
                  const SizedBox(height: 12),
                  _graficoMesAMes(),
                  const SizedBox(height: 12),
                  _graficoDistribuicao(),
                  const SizedBox(height: 12),
                  _barraFiltros(),
                  const SizedBox(height: 10),
                  if (linhas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          'Nenhum membro com movimento no período.\n'
                          'Vincule o membro ao lançar receitas e despesas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final l in linhas) _linhaMembro(l),
                ],
              ),
            ),
    );
  }

  Widget _banner(String texto) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF991B1B),
          ),
        ),
      );

  BoxDecoration get _cardDeco => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      );

  Widget _cartaoPeriodo() {
    final anos = <int>{
      DateTime.now().year,
      _ano,
      for (final d in _lancamentos)
        if (financeLancamentoDate(d.data()) != null)
          financeLancamentoDate(d.data())!.year,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    Widget chip(String label, _Periodo p) {
      final sel = _periodo == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : ThemeCleanPremium.primary,
          ),
          selectedColor: ThemeCleanPremium.primary,
          onSelected: (_) {
            if (p == _Periodo.intervalo) {
              unawaited(_escolherIntervalo());
              return;
            }
            setState(() => _periodo = p);
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'PERÍODO',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _periodoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('Ano', _Periodo.ano),
                chip('Mês atual', _Periodo.mes),
                chip('Período', _Periodo.intervalo),
              ],
            ),
          ),
          if (_periodo != _Periodo.intervalo) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: anos.contains(_ano) ? _ano : anos.first,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in anos)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) => setState(() => _ano = v ?? _ano),
                  ),
                ),
                if (_periodo == _Periodo.mes) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _mes,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Mês',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              DateFormat('MMM', 'pt_BR')
                                  .format(DateTime(2000, m)),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _mes = v ?? _mes),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartoesTotais(
    double receitas,
    double despesas,
    List<MembroFinanceiroLinha> linhas,
  ) {
    // Cada card abre a lista já ordenada pelo que ele mostra — o número e a
    // lista que o explica ficam a um toque.
    return Row(
      children: [
        Expanded(
          child: _CardTotal(
            titulo: 'Contribuições',
            valor: _money.format(receitas),
            cor: const Color(0xFF15803D),
            icone: Icons.trending_up_rounded,
            onTap: () => setState(() => _ordem = _Ordem.maisReceita),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Despesas',
            valor: _money.format(despesas),
            cor: const Color(0xFFB91C1C),
            icone: Icons.trending_down_rounded,
            onTap: () => setState(() => _ordem = _Ordem.maisDespesa),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Saldo',
            valor: _money.format(receitas - despesas),
            cor: receitas - despesas >= 0
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFB91C1C),
            icone: Icons.account_balance_wallet_rounded,
            onTap: () => setState(() => _ordem = _Ordem.alfabetica),
          ),
        ),
      ],
    );
  }

  Widget _graficoMesAMes() {
    final dados = _porMes;
    final maxV = dados.fold<double>(
      0,
      (a, e) => [a, e.receitas, e.despesas].reduce((x, y) => x > y ? x : y),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'EVOLUÇÃO MÊS A MÊS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
              const Spacer(),
              const _Legenda(cor: Color(0xFF15803D), texto: 'Entradas'),
              const SizedBox(width: 8),
              const _Legenda(cor: Color(0xFFB91C1C), texto: 'Saídas'),
            ],
          ),
          const SizedBox(height: 12),
          if (maxV <= 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Sem movimento no período escolhido.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in dados)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _Barra(
                                    altura: 94 * (e.receitas / maxV),
                                    cor: const Color(0xFF15803D),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: _Barra(
                                    altura: 94 * (e.despesas / maxV),
                                    cor: const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              DateFormat('MMM', 'pt_BR')
                                  .format(DateTime(2000, e.mes))
                                  .substring(0, 3),
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _graficoDistribuicao() {
    final perfil = _receitaPorPerfil;
    final depts = _receitaPorDepartamento.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (perfil.isEmpty && depts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'DE ONDE VEM',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          if (perfil.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in perfil.entries)
              _LinhaProporcao(
                rotulo: e.key,
                valor: e.value,
                maximo: perfil.values.reduce((a, b) => a > b ? a : b),
                money: _money,
                cor: const Color(0xFF15803D),
              ),
          ],
          if (depts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'POR DEPARTAMENTO',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 8),
            for (final e in depts.take(8))
              _LinhaProporcao(
                rotulo: e.key,
                valor: e.value,
                maximo: depts.first.value,
                money: _money,
                cor: const Color(0xFF2563EB),
              ),
            const SizedBox(height: 6),
            const Text(
              'Quem está em mais de um departamento conta em todos — é '
              'participação, não caixa; as fatias não somam o total.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barraFiltros() {
    Widget chipSexo(String v, String label) {
      final sel = _filtroSexo == v;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : const Color(0xFF334155),
          ),
          selectedColor: ThemeCleanPremium.primary,
          onSelected: (_) => setState(() => _filtroSexo = v),
        ),
      );
    }

    Widget chipOrdem(_Ordem v, String label) {
      final sel = _ordem == v;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : const Color(0xFF334155),
          ),
          selectedColor: const Color(0xFF7C3AED),
          onSelected: (_) => setState(() => _ordem = v),
        ),
      );
    }

    final depts = _todosDepartamentos;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _buscaCtrl,
            onChanged: (v) => setState(() => _busca = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar membro pelo nome…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chipSexo('todos', 'Todos'),
                chipSexo('m', 'Homens'),
                chipSexo('f', 'Mulheres'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chipOrdem(_Ordem.maisReceita, 'Mais contribuiu'),
                chipOrdem(_Ordem.maisDespesa, 'Mais despesa'),
                chipOrdem(_Ordem.alfabetica, 'A–Z'),
              ],
            ),
          ),
          if (depts.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _filtroDepartamento,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Departamento',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'todos',
                  child: Text('Todos os departamentos'),
                ),
                for (final d in depts)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) =>
                  setState(() => _filtroDepartamento = v ?? 'todos'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linhaMembro(MembroFinanceiroLinha l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => unawaited(_abrirExtrato(l)),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
                if (l.departamentos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.departamentos.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Valor(
                        rotulo: 'Contribuiu',
                        valor: _money.format(l.receitas),
                        cor: const Color(0xFF15803D),
                      ),
                    ),
                    Expanded(
                      child: _Valor(
                        rotulo: 'Despesas',
                        valor: _money.format(l.despesas),
                        cor: const Color(0xFFB91C1C),
                      ),
                    ),
                    Expanded(
                      child: _Valor(
                        rotulo: 'Saldo',
                        valor: _money.format(l.saldo),
                        cor: l.saldo >= 0
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
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

class _CardTotal extends StatelessWidget {
  const _CardTotal({
    required this.titulo,
    required this.valor,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String valor;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cor.withValues(alpha: 0.18),
                      cor.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, size: 17, color: cor),
              ),
              const SizedBox(height: 9),
              Text(
                titulo.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: cor,
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

class _Valor extends StatelessWidget {
  const _Valor({
    required this.rotulo,
    required this.valor,
    required this.cor,
  });

  final String rotulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: cor,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinhaProporcao extends StatelessWidget {
  const _LinhaProporcao({
    required this.rotulo,
    required this.valor,
    required this.maximo,
    required this.money,
    required this.cor,
  });

  final String rotulo;
  final double valor;
  final double maximo;
  final NumberFormat money;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final frac = maximo <= 0 ? 0.0 : (valor / maximo).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              Text(
                money.format(valor),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: cor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.altura, required this.cor});

  final double altura;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura.isFinite && altura > 0 ? altura.clamp(3.0, 94.0) : 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor, cor.withValues(alpha: 0.62)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.cor, required this.texto});

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
