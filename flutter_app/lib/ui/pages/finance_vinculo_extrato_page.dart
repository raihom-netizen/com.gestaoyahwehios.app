import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/finance_church_ops.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/pdf/finance_vinculo_extrato_pdf.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/finance_accounts_service.dart';
import 'package:gestao_yahweh/ui/widgets/finance_transaction_list_tile.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Período do extrato. **Ano é o padrão** — a pergunta que se faz de um membro
/// ou de um fornecedor é «quanto no ano», não «quanto neste mês».
enum FinanceExtratoPeriodo { ano, mes, intervalo }

/// Abre o extrato financeiro de um membro ou fornecedor em tela cheia.
///
/// `tipo` é `'membro'` ou `'fornecedor'` — os mesmos valores gravados no
/// lançamento por [FinanceVinculo].
Future<void> abrirExtratoFinanceiroDoVinculo(
  BuildContext context, {
  required String tenantId,
  required String tipo,
  required String vinculoId,
  required String nome,
  String? fotoUrl,
  required String panelRole,
  VoidCallback? onChanged,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FinanceVinculoExtratoPage(
        tenantId: tenantId,
        tipo: tipo,
        vinculoId: vinculoId,
        nome: nome,
        fotoUrl: fotoUrl,
        panelRole: panelRole,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Extrato financeiro de uma pessoa: totais, gráfico, lançamentos e PDF.
///
/// A grelha é a **mesma** do módulo Financeiro ([FinanceTransactionListTile] +
/// [showFinanceLancamentoEditorForTenant]): editar valor, anexar comprovante,
/// marcar pendente e excluir funcionam aqui exatamente como lá. Antes havia um
/// cartão próprio, mais pobre, e o utilizador tinha de ir ao Financeiro para
/// qualquer alteração.
class FinanceVinculoExtratoPage extends StatefulWidget {
  const FinanceVinculoExtratoPage({
    super.key,
    required this.tenantId,
    required this.tipo,
    required this.vinculoId,
    required this.nome,
    required this.panelRole,
    this.fotoUrl,
    this.onChanged,
  });

  final String tenantId;
  final String tipo;
  final String vinculoId;
  final String nome;
  final String panelRole;
  final String? fotoUrl;
  final VoidCallback? onChanged;

  bool get ehMembro => tipo == 'membro';

  @override
  State<FinanceVinculoExtratoPage> createState() =>
      _FinanceVinculoExtratoPageState();
}

class _FinanceVinculoExtratoPageState extends State<FinanceVinculoExtratoPage> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _exportando = false;
  String _erro = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _todos = const [];
  List<FinanceAccount> _contas = const [];
  UserProfile? _perfil;
  int _revisaoHub = -1;

  FinanceExtratoPeriodo _periodo = FinanceExtratoPeriodo.ano;
  late int _ano = DateTime.now().year;
  late int _mes = DateTime.now().month;
  DateTimeRange? _intervalo;

  /// `todos` | `receitas` | `despesas` | `pendentes`
  String _filtroTipo = 'todos';

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_aoMudarNoFinanceiro);
    unawaited(_carregar());
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_aoMudarNoFinanceiro);
    super.dispose();
  }

  /// Editar/excluir a partir de outro sítio do app também tem de refletir aqui.
  void _aoMudarNoFinanceiro() {
    final r = FinanceTransactionsHub.revision.value;
    if (r == _revisaoHub) return;
    _revisaoHub = r;
    if (mounted) unawaited(_carregar(force: true));
  }

  String get _tid => ChurchRepository.churchId(widget.tenantId);

  Future<void> _carregar({bool force = false}) async {
    if (mounted) setState(() => _carregando = _todos.isEmpty);
    try {
      final res = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: _tid,
        limit: YahwehPerformanceV4.financeChartsSampleLimit,
        forceRefresh: force,
        forceServer: force,
      );
      final meus = res.docs.where((d) => _pertence(d.data())).toList()
        ..sort((a, b) {
          final da = financeLancamentoDate(a.data());
          final db = financeLancamentoDate(b.data());
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });

      List<FinanceAccount> contas = _contas;
      if (contas.isEmpty || force) {
        try {
          contas = await FinanceAccountsService().listOnce(_tid);
        } catch (_) {}
      }
      final perfil = _perfil ?? await perfilParaEditorFinanceiro(_tid);

      if (!mounted) return;
      setState(() {
        _todos = meus;
        _contas = contas;
        _perfil = perfil;
        _carregando = false;
        _erro = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar o extrato: $e';
      });
    }
  }

  /// Só o vínculo **individual** conta para a pessoa.
  ///
  /// Um lançamento marcado com várias pessoas fica apenas no histórico geral —
  /// atribuir o valor inteiro a cada uma contaria o mesmo dinheiro várias
  /// vezes, e é exatamente esse total que esta tela existe para responder.
  bool _pertence(Map<String, dynamic> d) {
    if (d['vinculoMultiplo'] == true) return false;
    final alvo = widget.vinculoId.trim();
    if (alvo.isEmpty) return false;
    final chaves = widget.ehMembro
        ? const ['membroId', 'memberId']
        : const ['fornecedorId'];
    for (final k in chaves) {
      if ((d[k] ?? '').toString().trim() == alvo) return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────── período

  bool _noPeriodo(Map<String, dynamic> d) {
    final dt = financeLancamentoDate(d);
    if (dt == null) return false;
    switch (_periodo) {
      case FinanceExtratoPeriodo.ano:
        return dt.year == _ano;
      case FinanceExtratoPeriodo.mes:
        return dt.year == _ano && dt.month == _mes;
      case FinanceExtratoPeriodo.intervalo:
        final r = _intervalo;
        if (r == null) return true;
        final ini = DateTime(r.start.year, r.start.month, r.start.day);
        final fim = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !dt.isBefore(ini) && !dt.isAfter(fim);
    }
  }

  String get _periodoLabel {
    switch (_periodo) {
      case FinanceExtratoPeriodo.ano:
        return 'Ano de $_ano';
      case FinanceExtratoPeriodo.mes:
        return DateFormat('MMMM \'de\' y', 'pt_BR')
            .format(DateTime(_ano, _mes));
      case FinanceExtratoPeriodo.intervalo:
        final r = _intervalo;
        if (r == null) return 'Período livre';
        final f = DateFormat('dd/MM/yyyy', 'pt_BR');
        return '${f.format(r.start)} a ${f.format(r.end)}';
    }
  }

  bool _ehEntrada(Map<String, dynamic> d) {
    final t = financeInferTipo(d);
    return t.contains('entrada') || t.contains('receita');
  }

  bool _ehSaida(Map<String, dynamic> d) {
    final t = financeInferTipo(d);
    return t.contains('saida') || t.contains('despesa');
  }

  bool _ehPendente(Map<String, dynamic> d) =>
      (d['status'] ?? '').toString().trim() == 'pending';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _doPeriodo =>
      _todos.where((d) => _noPeriodo(d.data())).toList();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visiveis {
    final base = _doPeriodo;
    switch (_filtroTipo) {
      case 'receitas':
        return base.where((d) => _ehEntrada(d.data())).toList();
      case 'despesas':
        return base.where((d) => _ehSaida(d.data())).toList();
      case 'pendentes':
        return base.where((d) => _ehPendente(d.data())).toList();
      default:
        return base;
    }
  }

  double get _totalReceitas => _doPeriodo
      .map((d) => d.data())
      .where(_ehEntrada)
      .fold<double>(0, (a, d) => a + financeParseValorBr(d['amount'] ?? d['valor']));

  double get _totalDespesas => _doPeriodo
      .map((d) => d.data())
      .where(_ehSaida)
      .fold<double>(0, (a, d) => a + financeParseValorBr(d['amount'] ?? d['valor']));

  /// Receitas e despesas mês a mês do ano em curso — base do gráfico.
  List<({int mes, double receitas, double despesas})> get _porMes {
    final rec = List<double>.filled(12, 0);
    final des = List<double>.filled(12, 0);
    for (final doc in _doPeriodo) {
      final d = doc.data();
      final dt = financeLancamentoDate(d);
      if (dt == null) continue;
      final v = financeParseValorBr(d['amount'] ?? d['valor']);
      if (_ehEntrada(d)) {
        rec[dt.month - 1] += v;
      } else if (_ehSaida(d)) {
        des[dt.month - 1] += v;
      }
    }
    return [
      for (var i = 0; i < 12; i++)
        (mes: i + 1, receitas: rec[i], despesas: des[i]),
    ];
  }

  // ─────────────────────────────────────────────── ações

  Future<void> _editar(
    BuildContext ctx,
    String docId,
    Map<String, dynamic> data,
    String type,
  ) async {
    final ref = ChurchUiCollections.financeiro(_tid).doc(docId);
    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await ref.get();
    } catch (_) {}
    if (!mounted) return;
    final ok = await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: widget.tenantId,
      existingDoc: snap,
      panelRole: widget.panelRole,
    );
    if (ok && mounted) {
      await _carregar(force: true);
      widget.onChanged?.call();
    }
  }

  Future<void> _excluir(BuildContext ctx, String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text('Esta ação não pode ser desfeita. Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final snap = await ChurchUiCollections.financeiro(_tid).doc(docId).get();
      await excluirLancamentoFinanceiroComAuditoria(snap, _tid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir: $e')),
        );
      }
    }
    if (mounted) {
      await _carregar(force: true);
      widget.onChanged?.call();
    }
  }

  Future<void> _exportarPdf() async {
    if (_exportando) return;
    setState(() => _exportando = true);
    try {
      final branding = await loadReportPdfBranding(_tid);
      final bytes = await buildFinanceVinculoExtratoPdf(
        branding: branding,
        tipo: widget.tipo,
        nome: widget.nome,
        lancamentos: _visiveis.map((d) => d.data()).toList(),
        periodoLabel: _periodoLabel,
      );
      if (!mounted) return;
      final slug = widget.nome
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      await showPdfActions(
        context,
        bytes: bytes,
        filename: 'extrato_${widget.tipo}_${slug}_$_ano.pdf',
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

  Future<void> _escolherIntervalo() async {
    final agora = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(agora.year - 8),
      lastDate: DateTime(agora.year + 1, 12, 31),
      initialDateRange: _intervalo ??
          DateTimeRange(
            start: DateTime(agora.year, agora.month, 1),
            end: agora,
          ),
      locale: const Locale('pt', 'BR'),
    );
    if (r != null && mounted) {
      setState(() {
        _intervalo = r;
        _periodo = FinanceExtratoPeriodo.intervalo;
      });
    }
  }

  // ─────────────────────────────────────────────── UI

  @override
  Widget build(BuildContext context) {
    final receitas = _totalReceitas;
    final despesas = _totalDespesas;
    final saldo = receitas - despesas;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(nome: widget.nome, fotoUrl: widget.fotoUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    widget.ehMembro
                        ? 'Extrato do membro'
                        : 'Extrato do fornecedor',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
                ],
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
      body: _carregando && _todos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _carregar(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                children: [
                  if (_erro.isNotEmpty) _BannerErro(texto: _erro),
                  _barraPeriodo(),
                  const SizedBox(height: 14),
                  _cardsTotais(receitas, despesas, saldo),
                  const SizedBox(height: 14),
                  _grafico(),
                  const SizedBox(height: 14),
                  _barraFiltroTipo(),
                  const SizedBox(height: 10),
                  ..._listaLancamentos(),
                ],
              ),
            ),
    );
  }

  Widget _barraPeriodo() {
    final anos = <int>{
      DateTime.now().year,
      _ano,
      for (final d in _todos)
        if (financeLancamentoDate(d.data()) != null)
          financeLancamentoDate(d.data())!.year,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 18, color: ThemeCleanPremium.primary),
              const SizedBox(width: 6),
              const Text(
                'Período',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                _periodoLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ThemeCleanPremium.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chipPeriodo('Ano', FinanceExtratoPeriodo.ano),
                const SizedBox(width: 8),
                _chipPeriodo('Mês', FinanceExtratoPeriodo.mes),
                const SizedBox(width: 8),
                _chipPeriodo('Período', FinanceExtratoPeriodo.intervalo),
              ],
            ),
          ),
          if (_periodo != FinanceExtratoPeriodo.intervalo) ...[
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
                if (_periodo == FinanceExtratoPeriodo.mes) ...[
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

  Widget _chipPeriodo(String label, FinanceExtratoPeriodo p) {
    final sel = _periodo == p;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
        color: sel ? Colors.white : ThemeCleanPremium.primary,
      ),
      selectedColor: ThemeCleanPremium.primary,
      onSelected: (_) {
        if (p == FinanceExtratoPeriodo.intervalo) {
          unawaited(_escolherIntervalo());
          return;
        }
        setState(() => _periodo = p);
      },
    );
  }

  Widget _cardsTotais(double receitas, double despesas, double saldo) {
    // Sem «saldo dos bancos» de propósito: aqui a conta é só desta pessoa.
    return Row(
      children: [
        Expanded(
          child: _CardTotal(
            titulo: widget.ehMembro ? 'Contribuições' : 'Receitas',
            valor: _money.format(receitas),
            cor: const Color(0xFF15803D),
            icone: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Despesas',
            valor: _money.format(despesas),
            cor: const Color(0xFFB91C1C),
            icone: Icons.trending_down_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Saldo',
            valor: _money.format(saldo),
            cor: saldo >= 0 ? const Color(0xFF1D4ED8) : const Color(0xFFB91C1C),
            icone: Icons.account_balance_wallet_rounded,
          ),
        ),
      ],
    );
  }

  Widget _grafico() {
    final dados = _porMes;
    final maxV = dados.fold<double>(
      0,
      (a, e) => [a, e.receitas, e.despesas].reduce((x, y) => x > y ? x : y),
    );
    final temDados = maxV > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: ThemeCleanPremium.primary),
              const SizedBox(width: 6),
              const Text(
                'Mês a mês',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              const _Legenda(cor: Color(0xFF15803D), texto: 'Entradas'),
              const SizedBox(width: 10),
              const _Legenda(cor: Color(0xFFB91C1C), texto: 'Saídas'),
            ],
          ),
          const SizedBox(height: 12),
          if (!temDados)
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
              height: 132,
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
                                    altura: 96 * (e.receitas / maxV),
                                    cor: const Color(0xFF15803D),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: _Barra(
                                    altura: 96 * (e.despesas / maxV),
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

  Widget _barraFiltroTipo() {
    Widget chip(String v, String label) {
      final sel = _filtroTipo == v;
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
          onSelected: (_) => setState(() => _filtroTipo = v),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('todos', 'Todos (${_doPeriodo.length})'),
                chip('receitas', widget.ehMembro ? 'Contribuições' : 'Receitas'),
                chip('despesas', 'Despesas'),
                chip('pendentes', 'Pendentes'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _listaLancamentos() {
    final docs = _visiveis;
    final perfil = _perfil;
    if (docs.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 34),
          alignment: Alignment.center,
          child: const Text(
            'Nenhum lançamento neste período.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
      ];
    }
    if (perfil == null) {
      // Sem perfil não dá para abrir o editor do Financeiro; mostrar a lista
      // sem ações é melhor do que uma tela vazia.
      return [
        for (final d in docs) _LinhaSimples(data: d.data(), money: _money),
      ];
    }
    return [
      for (final d in docs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FinanceTransactionListTile(
            doc: d,
            profile: perfil,
            financeAccounts: _contas,
            gridSelectionMode: false,
            isSelected: false,
            optimisticPaidIds: const <String>{},
            onEdit: _editar,
            onDelete: _excluir,
            onConfirmPayment: (ctx, id) async {
              final doc = docs.firstWhere((e) => e.id == id, orElse: () => d);
              await _editar(ctx, id, doc.data(), 'expense');
            },
            onAttachReceipt: (ctx, id) async {
              final doc = docs.firstWhere((e) => e.id == id, orElse: () => d);
              await _editar(ctx, id, doc.data(), 'expense');
            },
          ),
        ),
    ];
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nome, this.fotoUrl});

  final String nome;
  final String? fotoUrl;

  @override
  Widget build(BuildContext context) {
    final url = (fotoUrl ?? '').trim();
    final inicial = nome.trim().isEmpty ? '?' : nome.trim()[0].toUpperCase();
    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Color(0x33FFFFFF),
        shape: BoxShape.circle,
      ),
      child: url.isEmpty
          ? Center(
              child: Text(
                inicial,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            )
          : SafeNetworkImage(imageUrl: url, fit: BoxFit.cover),
    );
  }
}

class _CardTotal extends StatelessWidget {
  const _CardTotal({
    required this.titulo,
    required this.valor,
    required this.cor,
    required this.icone,
  });

  final String titulo;
  final String valor;
  final Color cor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(height: 6),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: cor,
              ),
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
      height: altura.isFinite && altura > 0 ? altura.clamp(2.0, 96.0) : 2,
      decoration: BoxDecoration(
        color: cor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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

class _BannerErro extends StatelessWidget {
  const _BannerErro({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaSimples extends StatelessWidget {
  const _LinhaSimples({required this.data, required this.money});

  final Map<String, dynamic> data;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final t = financeInferTipo(data);
    final saida = t.contains('saida') || t.contains('despesa');
    final v = financeParseValorBr(data['amount'] ?? data['valor']);
    final dt = financeLancamentoDate(data);
    return ListTile(
      dense: true,
      leading: Icon(
        saida ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        color: saida ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
      ),
      title: Text(
        (data['descricao'] ?? data['categoria'] ?? 'Lançamento').toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        dt == null ? '' : DateFormat('dd/MM/yyyy', 'pt_BR').format(dt),
      ),
      trailing: Text(
        money.format(v),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: saida ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
        ),
      ),
    );
  }
}
