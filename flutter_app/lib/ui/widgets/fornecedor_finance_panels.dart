import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/pdf/fornecedor_historico_pdf.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart'
    show showFinanceLancamentoEditorForTenant;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/finance_fixo_premium_dialogs.dart';
import 'package:gestao_yahweh/ui/widgets/finance_resumo_charts_section.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:intl/intl.dart';

/// Financeiro de um fornecedor — mesma edição do módulo Financeiro + gráficos.
class FornecedorFinanceHubPanel extends StatefulWidget {
  const FornecedorFinanceHubPanel({
    super.key,
    required this.tenantId,
    required this.fornecedorId,
    required this.panelRole,
    required this.onNovaDespesa,
    required this.onNovaReceita,
    required this.onEditar,
    required this.onExcluir,
    required this.onRecibo,
  });

  final String tenantId;
  final String fornecedorId;
  final String panelRole;
  final VoidCallback onNovaDespesa;
  final VoidCallback onNovaReceita;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
      onEditar;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
      onExcluir;
  final Future<void> Function(Map<String, dynamic> m, String id) onRecibo;

  @override
  State<FornecedorFinanceHubPanel> createState() =>
      _FornecedorFinanceHubPanelState();
}

class _FornecedorFinanceHubPanelState extends State<FornecedorFinanceHubPanel> {
  String _filtro = 'todos';
  bool _loading = true;
  bool _exportingPdf = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = _docs.isEmpty);
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final r = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: YahwehPerformanceV4.financeChartsSampleLimit,
        forceRefresh: force,
        forceServer: force,
      ).timeout(PanelResilientLoad.queryCap);
      final fid = widget.fornecedorId.trim();
      final filtered = r.docs.where((d) {
        final m = d.data();
        return (m['fornecedorId'] ?? '').toString().trim() == fid;
      }).toList()
        ..sort((a, b) {
          final da = financeLancamentoDate(a.data());
          final db = financeLancamentoDate(b.data());
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      if (!mounted) return;
      setState(() {
        _docs = filtered;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible {
    if (_filtro == 'despesas') {
      return _docs.where((d) => _isSaida(d.data())).toList();
    }
    if (_filtro == 'receitas') {
      return _docs.where((d) => _isEntrada(d.data())).toList();
    }
    return _docs;
  }

  bool _isEntrada(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('entrada') || t.contains('receita');
  }

  bool _isSaida(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('saida') || t.contains('despesa');
  }

  ({double despesas, double receitas, double saldo}) _totals(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var d = 0.0, r = 0.0;
    for (final doc in docs) {
      final m = doc.data();
      if (financeInferTipo(m) == 'transferencia') continue;
      final v = financeParseValorBr(m['amount'] ?? m['valor']);
      if (_isSaida(m)) {
        d += v;
      } else if (_isEntrada(m)) {
        r += v;
      }
    }
    return (despesas: d, receitas: r, saldo: r - d);
  }

  Future<void> _exportHistoricoPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final branding = await loadReportPdfBranding(tid);
      final fn = await ChurchFornecedoresLoadService.load(
        seedTenantId: tid,
        limit: 200,
      );
      var nome = widget.fornecedorId;
      for (final d in fn.docs) {
        if (d.id == widget.fornecedorId) {
          nome = (d.data()['nome'] ?? d.id).toString();
          break;
        }
      }
      final compSnap = await ChurchUiCollections.churchDoc(tid)
          .collection('fornecedor_compromissos')
          .where('fornecedorId', isEqualTo: widget.fornecedorId.trim())
          .limit(200)
          .get();
      final bytes = await buildFornecedorHistoricoPdf(
        branding: branding,
        fornecedorNome: nome,
        lancamentos: _docs.map((d) => d.data()).toList(),
        compromissos: compSnap.docs.map((d) => d.data()).toList(),
      );
      if (!mounted) return;
      await showPdfActions(
        context,
        bytes: bytes,
        filename:
            'historico_fornecedor_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final totals = _totals(_docs);
    final year = DateTime.now().year;
    final despesasPorCat = <String, double>{};
    final receitasPorCat = <String, double>{};
    for (final d in _docs) {
      final m = d.data();
      final cat = (m['categoria'] ?? 'Outros').toString();
      final v = financeParseValorBr(m['amount'] ?? m['valor']);
      if (_isSaida(m)) {
        despesasPorCat[cat] = (despesasPorCat[cat] ?? 0) + v;
      } else if (_isEntrada(m)) {
        receitasPorCat[cat] = (receitasPorCat[cat] ?? 0) + v;
      }
    }

    if (_loading && _docs.isEmpty) {
      return const ChurchPanelLoadingBody();
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE2E2),
                        foregroundColor: const Color(0xFFB91C1C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: widget.onNovaDespesa,
                      icon: const Icon(Icons.trending_down_rounded),
                      label: const Text(
                        'Despesa',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDCFCE7),
                        foregroundColor: const Color(0xFF15803D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: widget.onNovaReceita,
                      icon: const Icon(Icons.trending_up_rounded),
                      label: const Text(
                        'Receita',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final cards = [
                    _KpiTile(
                      label: 'Despesas',
                      value: money.format(totals.despesas),
                      color: const Color(0xFFB91C1C),
                      bg: const Color(0xFFFEE2E2),
                    ),
                    _KpiTile(
                      label: 'Receitas',
                      value: money.format(totals.receitas),
                      color: const Color(0xFF15803D),
                      bg: const Color(0xFFDCFCE7),
                    ),
                    _KpiTile(
                      label: 'Saldo',
                      value: money.format(totals.saldo),
                      color: totals.saldo >= 0
                          ? const Color(0xFF0D9488)
                          : const Color(0xFFB91C1C),
                      bg: totals.saldo >= 0
                          ? const Color(0xFFCCFBF1)
                          : const Color(0xFFFEE2E2),
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
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          if (_docs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FinanceResumoChartsSection(
                  allLancamentos: _docs,
                  receitasPorCat: receitasPorCat,
                  despesasPorCat: despesasPorCat,
                  totalReceitas: totals.receitas,
                  totalDespesas: totals.despesas,
                  chartYear: year,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_visible.length} lançamento(s)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _exportingPdf ? null : _exportHistoricoPdf,
                    icon: _exportingPdf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF histórico'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'todos', label: Text('Todos')),
                  ButtonSegment(value: 'despesas', label: Text('Despesas')),
                  ButtonSegment(value: 'receitas', label: Text('Receitas')),
                ],
                selected: {_filtro},
                onSelectionChanged: (s) => setState(() => _filtro = s.first),
              ),
            ),
          ),
          if (_visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Nenhum lançamento vinculado.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final d = _visible[i];
                    return _LancamentoCard(
                      doc: d,
                      money: money,
                      onTap: () => widget.onEditar(d),
                      onEditar: () => widget.onEditar(d),
                      onExcluir: () => widget.onExcluir(d),
                      onRecibo: () => widget.onRecibo(d.data(), d.id),
                    );
                  },
                  childCount: _visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Visão agregada — financeiro de todos os fornecedores no módulo.
class FornecedoresFinanceModuloTab extends StatefulWidget {
  const FornecedoresFinanceModuloTab({
    super.key,
    required this.tenantId,
    required this.panelRole,
    required this.onOpenFornecedorFinance,
  });

  final String tenantId;
  final String panelRole;
  final void Function(String fornecedorId) onOpenFornecedorFinance;

  @override
  State<FornecedoresFinanceModuloTab> createState() =>
      _FornecedoresFinanceModuloTabState();
}

class _FornecedoresFinanceModuloTabState
    extends State<FornecedoresFinanceModuloTab> {
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _finance = const [];
  Map<String, String> _nomes = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = _finance.isEmpty);
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final fn = await ChurchFornecedoresLoadService.load(
        seedTenantId: tid,
        limit: 200,
        forceRefresh: force,
      );
      final nomes = <String, String>{};
      for (final d in fn.docs) {
        nomes[d.id] = (d.data()['nome'] ?? d.id).toString();
      }
      final fin = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: YahwehPerformanceV4.financeChartsSampleLimit,
        forceRefresh: force,
      );
      final linked = fin.docs
          .where((d) =>
              (d.data()['fornecedorId'] ?? '').toString().trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _nomes = nomes;
        _finance = linked;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, ({double despesas, double receitas})> _porFornecedor() {
    final map = <String, ({double despesas, double receitas})>{};
    for (final d in _finance) {
      final m = d.data();
      final fid = (m['fornecedorId'] ?? '').toString().trim();
      if (fid.isEmpty) continue;
      final v = financeParseValorBr(m['amount'] ?? m['valor']);
      final cur = map[fid] ?? (despesas: 0.0, receitas: 0.0);
      final t = financeInferTipo(m);
      if (t.contains('saida') || t.contains('despesa')) {
        map[fid] = (despesas: cur.despesas + v, receitas: cur.receitas);
      } else if (t.contains('entrada') || t.contains('receita')) {
        map[fid] = (despesas: cur.despesas, receitas: cur.receitas + v);
      }
    }
    return map;
  }

  Future<void> _novaComTipo(String presetTipo) async {
    final picked = await showFinancePremiumFornecedorPicker(
      context,
      tenantId: widget.tenantId,
    );
    if (picked == null || !mounted) return;
    final ok = await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: widget.tenantId,
      presetFornecedorId: picked.$1,
      presetFornecedorNome: picked.$2,
      lockFornecedor: true,
      panelRole: widget.panelRole,
      presetNovoTipo: presetTipo,
    );
    if (ok && mounted) unawaited(_load(force: true));
  }

  Future<void> _novaDespesa() => _novaComTipo('saida');

  Future<void> _novaReceita() => _novaComTipo('entrada');

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final porFn = _porFornecedor();
    var totalD = 0.0, totalR = 0.0;
    for (final v in porFn.values) {
      totalD += v.despesas;
      totalR += v.receitas;
    }
    final rows = porFn.entries.toList()
      ..sort((a, b) => b.value.despesas.compareTo(a.value.despesas));

    if (_loading && _finance.isEmpty) {
      return const ChurchPanelLoadingBody();
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE2E2),
                        foregroundColor: const Color(0xFFB91C1C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: _novaDespesa,
                      icon: const Icon(Icons.trending_down_rounded),
                      label: const Text(
                        'Despesa',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDCFCE7),
                        foregroundColor: const Color(0xFF15803D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: _novaReceita,
                      icon: const Icon(Icons.trending_up_rounded),
                      label: const Text(
                        'Receita',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Financeiro por fornecedor · ${porFn.length} com movimentação',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _KpiTile(
                      label: 'Despesas (geral)',
                      value: money.format(totalD),
                      color: const Color(0xFFB91C1C),
                      bg: const Color(0xFFFEE2E2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiTile(
                      label: 'Receitas (geral)',
                      value: money.format(totalR),
                      color: const Color(0xFF15803D),
                      bg: const Color(0xFFDCFCE7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiTile(
                      label: 'Saldo',
                      value: money.format(totalR - totalD),
                      color: const Color(0xFF0D9488),
                      bg: const Color(0xFFCCFBF1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (rows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _TopFornecedoresChart(
                  rows: rows.take(6).map((e) {
                    final nome = _nomes[e.key] ?? e.key;
                    return (nome: nome, valor: e.value.despesas);
                  }).toList(),
                  money: money,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: rows.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Nenhum lançamento com fornecedor.\nCrie despesas no Financeiro ou aqui.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = rows[i];
                        final nome = _nomes[e.key] ?? e.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () =>
                                  widget.onOpenFornecedorFinance(e.key),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.12),
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        color: ThemeCleanPremium.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nome,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Desp: ${money.format(e.value.despesas)} · Rec: ${money.format(e.value.receitas)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: rows.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  final String label;
  final String value;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopFornecedoresChart extends StatelessWidget {
  const _TopFornecedoresChart({required this.rows, required this.money});

  final List<({String nome, double valor})> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxV = rows.fold<double>(0, (a, b) => b.valor > a ? b.valor : a);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top despesas por fornecedor',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ...rows.map((r) {
            final pct = maxV <= 0 ? 0.0 : (r.valor / maxV).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        money.format(r.valor),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFFDC2626).withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _LancamentoCard extends StatelessWidget {
  const _LancamentoCard({
    required this.doc,
    required this.money,
    required this.onTap,
    required this.onEditar,
    required this.onExcluir,
    required this.onRecibo,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final VoidCallback onRecibo;

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final t = financeInferTipo(m);
    final isSaida = t.contains('saida') || t.contains('despesa');
    final v = financeParseValorBr(m['amount'] ?? m['valor']);
    final dt = financeLancamentoDate(m);
    final dataStr =
        dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
    final cor = isSaida ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final conta = isSaida
        ? (m['contaOrigemNome'] ?? m['contaOrigemId'] ?? '').toString()
        : (m['contaDestinoNome'] ?? m['contaDestinoId'] ?? '').toString();
    final hasComp = FinanceComprovanteAttachService.hasComprovanteReady(m);
    final pendente = isSaida
        ? financeLancamentoPendentePagamento(m)
        : financeLancamentoPendenteRecebimento(m);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: cor.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: cor.withValues(alpha: 0.12),
                child: Icon(
                  isSaida
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: cor,
                ),
              ),
              title: Text(
                money.format(v),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: cor,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (m['descricao'] ?? m['categoria'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dataStr.isNotEmpty)
                    Text(
                      '$dataStr · ${m['categoria'] ?? ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  if (conta.isNotEmpty)
                    Text(
                      'Conta: $conta',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (hasComp)
                        const _Badge(
                          label: 'Comprovante',
                          color: Color(0xFF0D9488),
                        ),
                      if (pendente)
                        _Badge(
                          label: isSaida ? 'A pagar' : 'A receber',
                          color: const Color(0xFFEA580C),
                        ),
                      if (m['conciliado'] == true)
                        const _Badge(
                          label: 'Conciliado',
                          color: Color(0xFF2563EB),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) {
                  if (v == 'editar') onEditar();
                  if (v == 'excluir') onExcluir();
                  if (v == 'recibo') onRecibo();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'editar',
                    child: Text('Editar · conta · comprovante'),
                  ),
                  PopupMenuItem(
                    value: 'excluir',
                    child: Text(
                      'Excluir',
                      style: TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'recibo',
                    child: Text('Emitir recibo PDF'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
