import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/ui/widgets/finance_transaction_list_tile.dart';
import 'package:gestao_yahweh/services/finance_accounts_service.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/models/finance_account.dart';
import 'package:gestao_yahweh/ui/pages/finance_vinculo_extrato_page.dart';
import 'dart:async' show unawaited;
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/pdf/fornecedor_historico_pdf.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_flow.dart';
import 'package:gestao_yahweh/core/finance_church_ops.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/finance_premium_lancamento_ui.dart'
    show
        FinancePremiumIconAction,
        FinancePremiumStatusPill,
        FinancePremiumVinculoPill;
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/finance_fixo_premium_dialogs.dart';
import 'package:gestao_yahweh/ui/widgets/finance_resumo_charts_section.dart';
import 'package:gestao_yahweh/ui/widgets/controle_total_finance_clone_widgets.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:intl/intl.dart';

/// Saldo consolidado das contas bancárias do tenant (até hoje).
Future<double> fornecedorFinanceLoadSaldoBancos(
  String tenantId, {
  bool forceRefresh = false,
}) async {
  final tid = ChurchRepository.churchId(tenantId);
  final fin = await ChurchFinanceLoadService.loadLancamentos(
    seedTenantId: tid,
    limit: YahwehPerformanceV4.financeChartsSampleLimit,
    forceRefresh: forceRefresh,
  );
  final contas = await ChurchFinanceLoadService.loadContas(
    seedTenantId: tid,
    forceRefresh: forceRefresh,
  );
  final contaIds = contas.docs
      .map((d) => d.id)
      .where((id) => id.trim().isNotEmpty)
      .toSet();
  final saldoMap = financeSaldoPorContaAteInclusive(
    contaIdsAtivas: contaIds,
    lancamentos: fin.docs.map((d) => d.data()),
    ateInclusive: DateTime.now(),
  );
  return saldoMap.values.fold<double>(0, (a, b) => a + b);
}

/// Abre grade de lançamentos (atalho usado em cadastro, agenda e financeiro).
Future<void> openFornecedorFinanceGrid(
  BuildContext context, {
  required String tenantId,
  required String fornecedorId,
  String? fornecedorNome,
  required String panelRole,
  String filtroInicial = 'todos',
  VoidCallback? onChanged,
}) async {
  final tid = ChurchRepository.churchId(tenantId);
  var nome = (fornecedorNome ?? '').trim();
  if (nome.isEmpty) {
    nome = fornecedorId;
    try {
      final fn = await ChurchFornecedoresLoadService.load(
        seedTenantId: tid,
        limit: 200,
      );
      for (final d in fn.docs) {
        if (d.id == fornecedorId.trim()) {
          nome = (d.data()['nome'] ?? nome).toString();
          break;
        }
      }
    } catch (_) {}
  }
  if (!context.mounted) return;
  try {
    // Extrato partilhado com o módulo Membros: mesma grelha do Financeiro
    // (editar valor, anexar comprovante, marcar pendente), gráficos, filtro
    // anual por defeito e exportação PDF. A grelha própria que existia aqui
    // era mais pobre e obrigava a ir ao Financeiro para qualquer alteração.
    await abrirExtratoFinanceiroDoVinculo(
      context,
      tenantId: tenantId,
      tipo: 'fornecedor',
      vinculoId: fornecedorId,
      nome: nome,
      panelRole: panelRole,
      onChanged: onChanged,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível abrir lançamentos: $e'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }
}

void fornecedorShowLancamentoPreview(
  BuildContext context, {
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
}) {
  final m = doc.data();
  final t = financeInferTipo(m);
  final isSaida = t.contains('saida') || t.contains('despesa');
  final isEntrada = t.contains('entrada') || t.contains('receita');
  final isTransfer = t == 'transferencia';
  final v = financeParseValorBr(m['amount'] ?? m['valor']);
  final dt = financeLancamentoDate(m);
  final dataStr = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
  final cor = isTransfer
      ? const Color(0xFF2563EB)
      : (isSaida ? const Color(0xFFB91C1C) : const Color(0xFF15803D));
  final titulo = (m['descricao'] ?? m['categoria'] ?? 'Lançamento').toString();
  final subtitulo = (m['categoria'] ?? '').toString();
  final compUrl = (m['comprovanteUrl'] ?? m['comprovanteLink'] ?? '')
      .toString();
  showFinanceLancamentoDetailsBottomSheet(
    context,
    data: m,
    comprovanteUrl: compUrl,
    dataStr: dataStr,
    isEntrada: isEntrada && !isTransfer,
    isTransfer: isTransfer,
    color: cor,
    valor: v,
    titulo: titulo,
    subtitulo: subtitulo,
  );
}

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
  // O cartao do Financeiro precisa do perfil (permissoes) e das contas (nome
  // do banco em cada linha).
  List<FinanceAccount> _contas = const [];
  UserProfile? _perfil;

  int _revisaoHub = -1;

  /// Recarrega quando um lançamento e criado, editado ou apagado em QUALQUER
  /// ecra — inclusive no módulo Financeiro. Sem isto o financeiro do
  /// fornecedor ficava parado no valor antigo.
  void _aoMudarNoFinanceiro() {
    final r = FinanceTransactionsHub.revision.value;
    if (r == _revisaoHub) return;
    _revisaoHub = r;
    if (mounted) unawaited(_load(force: true));
  }

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_aoMudarNoFinanceiro);
    _load();
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_aoMudarNoFinanceiro);
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = _docs.isEmpty);
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      // Amostra de grafico (60) nao serve para somar o gasto de um
      // fornecedor: le-se o maximo permitido.
      final r = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: FirebasePerformanceLimits.financeiroPage,
        forceRefresh: force,
        forceServer: force,
      ).timeout(PanelResilientLoad.queryCap);
      final fid = widget.fornecedorId.trim();
      final filtered =
          r.docs.where((d) {
            final m = d.data();
            if (fid.isEmpty) {
              return (m['fornecedorId'] ?? '').toString().trim().isNotEmpty;
            }
            return (m['fornecedorId'] ?? '').toString().trim() == fid;
          }).toList()..sort((a, b) {
            final da = financeLancamentoDate(a.data());
            final db = financeLancamentoDate(b.data());
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da);
          });
      List<FinanceAccount> contas = _contas;
      if (contas.isEmpty || force) {
        try {
          contas = await FinanceAccountsService().listOnce(tid);
        } catch (_) {}
      }
      final perfil = _perfil ??
          await perfilParaEditorFinanceiro(tid, panelRole: widget.panelRole);

      if (!mounted) return;
      setState(() {
        _docs = filtered;
        _contas = contas;
        _perfil = perfil;
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

  Future<void> _openGrid({String filtro = 'todos'}) async {
    var nome = widget.fornecedorId;
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final fn = await ChurchFornecedoresLoadService.load(
        seedTenantId: tid,
        limit: 200,
      );
      for (final d in fn.docs) {
        if (d.id == widget.fornecedorId) {
          nome = (d.data()['nome'] ?? nome).toString();
          break;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    await openFornecedorFinanceGrid(
      context,
      tenantId: widget.tenantId,
      fornecedorId: widget.fornecedorId,
      fornecedorNome: nome,
      panelRole: widget.panelRole,
      filtroInicial: filtro,
      onChanged: () => _load(force: true),
    );
    if (mounted) await _load(force: true);
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
      // Leitura pelo gateway (REST na web). O `.collection().where().get()`
      // cru do SDK era o que rebentava aqui com «INTERNAL ASSERTION FAILED»
      // e devolvia «Erro ao gerar PDF» — o mesmo defeito que já tinha
      // derrubado Financeiro, Patrimônio e Escalas.
      final alvo = widget.fornecedorId.trim();
      final compSnap = await ChurchFirestoreAccess.listOnce(
        module: 'fornecedores',
        churchId: tid,
        subcollectionName: 'fornecedor_compromissos',
        limit: 200,
      );
      final compromissos = <Map<String, dynamic>>[];
      for (final d in compSnap.docs) {
        final m = d.data();
        final fid = (m['fornecedorId'] ?? m['fornecedor_id'] ?? '')
            .toString()
            .trim();
        if (fid == alvo) compromissos.add(m);
      }
      final bytes = await buildFornecedorHistoricoPdf(
        branding: branding,
        fornecedorNome: nome,
        lancamentos: _docs.map((d) => d.data()).toList(),
        compromissos: compromissos,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e')));
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
      // Coluna central com largura máxima — o mesmo padrão do Financeiro e
      // do Financeiro geral. Sem isto, no browser cada lançamento ficava
      // sozinho numa faixa de 1900px, com o valor no outro extremo do ecrã.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
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
                  child: ControleTotalSupplierFinanceCard(
                    title: 'Financeiro do fornecedor',
                    subtitle: '${_visible.length} lançamento(s) vinculado(s)',
                    despesas: money.format(totals.despesas),
                    receitas: money.format(totals.receitas),
                    saldo: money.format(totals.saldo),
                    saldoNegativo: totals.saldo < 0,
                    onOpenLancamentos: () => _openGrid(filtro: 'todos'),
                    onOpenPendentes: () => _openGrid(filtro: 'pendentes'),
                    onOpenComprovantes: () => _openGrid(filtro: 'todos'),
                  ),
                ),
              ),
              if (_docs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Material(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openGrid(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.grid_view_rounded,
                                color: ThemeCleanPremium.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Abrir grade de lançamentos (${_docs.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade500,
                              ),
                            ],
                          ),
                        ),
                      ),
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
                        onPressed: () => _openGrid(),
                        icon: const Icon(Icons.grid_view_rounded),
                        label: const Text('Grade'),
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
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final d = _visible[i];
                      final perfil = _perfil;
                      if (perfil == null) {
                        // Sem perfil o editor do Financeiro nao abre; mostrar o
                        // cartao antigo e melhor do que nao mostrar nada.
                        return _LancamentoCard(
                          doc: d,
                          money: money,
                          onTap: () =>
                              fornecedorShowLancamentoPreview(context, doc: d),
                          onEditar: () => widget.onEditar(d),
                          onExcluir: () => widget.onExcluir(d),
                          onRecibo: () => widget.onRecibo(d.data(), d.id),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FinanceTransactionListTile(
                          doc: d,
                          profile: perfil,
                          financeAccounts: _contas,
                          gridSelectionMode: false,
                          isSelected: false,
                          optimisticPaidIds: const <String>{},
                          onEdit: (ctx, id, data, type) async =>
                              widget.onEditar(d),
                          onDelete: (ctx, id) async => widget.onExcluir(d),
                          onConfirmPayment: (ctx, id) async =>
                              widget.onEditar(d),
                          onAttachReceipt: (ctx, id) async =>
                              widget.onEditar(d),
                        ),
                      );
                    }, childCount: _visible.length),
                  ),
                ),
            ],
          ),
        ),
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
  });

  final String tenantId;
  final String panelRole;

  @override
  State<FornecedoresFinanceModuloTab> createState() =>
      _FornecedoresFinanceModuloTabState();
}

class _FornecedoresFinanceModuloTabState
    extends State<FornecedoresFinanceModuloTab> {
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _finance = const [];
  Map<String, String> _nomes = const {};

  String _nomeFornecedor(String fid) {
    final id = fid.trim();
    if (_nomes.containsKey(id)) return _nomes[id]!;
    for (final d in _finance) {
      final m = d.data();
      if ((m['fornecedorId'] ?? '').toString().trim() != id) continue;
      final n = (m['fornecedorNome'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return id;
  }

  Future<void> _openLancamentosGrid(
    String fornecedorId, {
    String filtro = 'todos',
  }) async {
    await openFornecedorFinanceGrid(
      context,
      tenantId: widget.tenantId,
      fornecedorId: fornecedorId,
      fornecedorNome: _nomeFornecedor(fornecedorId),
      panelRole: widget.panelRole,
      filtroInicial: filtro,
      onChanged: () => _load(force: true),
    );
    if (mounted) unawaited(_load(force: true));
  }

  int _revisaoHub = -1;

  /// Qualquer lancamento criado, editado ou apagado noutro ecra tem de mexer
  /// nos totais desta aba — o dinheiro e o mesmo.
  void _aoMudarNoFinanceiro() {
    final r = FinanceTransactionsHub.revision.value;
    if (r == _revisaoHub) return;
    _revisaoHub = r;
    if (mounted) unawaited(_load(force: true));
  }

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_aoMudarNoFinanceiro);
    _load();
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_aoMudarNoFinanceiro);
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = _finance.isEmpty);
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      final nomes = <String, String>{};
      // Nomes instantâneos (RAM) — não bloqueia lançamentos.
      final ram = ChurchFornecedoresLoadService.peekRamAny(tid);
      if (ram != null) {
        for (final d in ram) {
          nomes[d.id] = (d.data()['nome'] ?? d.id).toString();
        }
      }

      final finFuture = ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: YahwehPerformanceV4.financeChartsSampleLimit,
        forceRefresh: force,
        forceServer: force,
      ).timeout(PanelResilientLoad.queryCap);

      // Cadastros em paralelo; UI não espera isto para sair do skeleton.
      final fnFuture = ChurchFornecedoresLoadService.load(
        seedTenantId: tid,
        limit: 200,
        forceRefresh: force,
      ).timeout(
        kIsWeb ? const Duration(seconds: 10) : PanelResilientLoad.queryCap,
        onTimeout: () => ChurchFornecedoresLoadResult(
          churchId: tid,
          docs: const [],
          readSource: 'timeout',
          collectionPath: 'fornecedores',
        ),
      );

      final fin = await finFuture;
      final linked = fin.docs
          .where(
            (d) =>
                (d.data()['fornecedorId'] ?? '').toString().trim().isNotEmpty,
          )
          .toList();
      for (final d in linked) {
        final m = d.data();
        final fid = (m['fornecedorId'] ?? '').toString().trim();
        final n = (m['fornecedorNome'] ?? '').toString().trim();
        if (fid.isNotEmpty && n.isNotEmpty) {
          nomes.putIfAbsent(fid, () => n);
        }
      }

      if (!mounted) return;
      // 1.? pintura: lançamentos já bastam (utilizador disse que estão ok).
      setState(() {
        _nomes = Map<String, String>.from(nomes);
        _finance = linked;
        _loading = false;
      });

      try {
        final fn = await fnFuture;
        for (final d in fn.docs) {
          nomes[d.id] = (d.data()['nome'] ?? d.id).toString();
        }
        if (mounted) setState(() => _nomes = Map<String, String>.from(nomes));
      } catch (_) {}
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
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
                'Financeiro por fornecedor — ${porFn.length} com movimentação',
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ControleTotalSupplierFinanceCard(
                title: 'Financeiro por fornecedor',
                subtitle: '${porFn.length} com movimentação',
                despesas: money.format(totalD),
                receitas: money.format(totalR),
                saldo: money.format(totalR - totalD),
                saldoNegativo: (totalR - totalD) < 0,
                onOpenLancamentos: rows.isEmpty
                    ? () {}
                    : () => _openLancamentosGrid(rows.first.key),
                onOpenPendentes: rows.isEmpty
                    ? () {}
                    : () => _openLancamentosGrid(rows.first.key, filtro: 'pendentes'),
                onOpenComprovantes: rows.isEmpty
                    ? () {}
                    : () => _openLancamentosGrid(rows.first.key),
              ),
            ),
          ),
          if (rows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _TopFornecedoresChart(
                  rows: rows.take(6).map((e) {
                    return (
                      id: e.key,
                      nome: _nomeFornecedor(e.key),
                      valor: e.value.despesas,
                    );
                  }).toList(),
                  money: money,
                  onFornecedorTap: (id) =>
                      _openLancamentosGrid(id, filtro: 'despesas'),
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
                : SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: viewportWidth < 700
                          ? 1
                          : viewportWidth < 1180
                          ? 2
                          : 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 158,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final e = rows[i];
                      final nome = _nomeFornecedor(e.key);
                      final cadastroOk = _nomes.containsKey(e.key);
                      final saldo = e.value.receitas - e.value.despesas;
                      return _FornecedorFinanceGridCard(
                        nome: nome,
                        cadastroOk: cadastroOk,
                        despesas: money.format(e.value.despesas),
                        receitas: money.format(e.value.receitas),
                        saldo: money.format(saldo),
                        saldoNegativo: saldo < 0,
                        onTap: () => _openLancamentosGrid(e.key),
                      );
                    }, childCount: rows.length),
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
  }) : onTap = null, fullWidth = false, icon = null;

  final String label;
  final String value;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;
  final bool fullWidth;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: fullWidth ? double.infinity : null,
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, Colors.white, 0.38)!],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.88),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
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
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

class _TopFornecedoresChart extends StatelessWidget {
  const _TopFornecedoresChart({
    required this.rows,
    required this.money,
    this.onFornecedorTap,
  });

  final List<({String id, String nome, double valor})> rows;
  final NumberFormat money;
  final void Function(String fornecedorId)? onFornecedorTap;

  static const _palette = <Color>[
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFFD97706),
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
  ];

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final total = rows.fold<double>(0, (a, b) => a + b.valor);
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < rows.length; i++) {
      final pct = total <= 0 ? 0.0 : (rows[i].valor / total) * 100;
      sections.add(
        PieChartSectionData(
          value: rows[i].valor <= 0 ? 0.001 : rows[i].valor,
          color: _palette[i % _palette.length],
          radius: 48,
          title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
          titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }
    final legend = Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onFornecedorTap == null
                    ? null
                    : () => onFornecedorTap!(rows[i].id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 6,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            rows[i].nome,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        money.format(rows[i].valor),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: _palette[i % _palette.length],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Top despesas por fornecedor',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            money.format(total),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: Color(0xFFDC2626),
            ),
          ),
          Text(
            'Total no período',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = SizedBox(
                width: 148,
                height: 148,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    startDegreeOffset: -90,
                    sections: sections,
                  ),
                  duration: const Duration(milliseconds: 450),
                ),
              );
              if (constraints.maxWidth < 500) {
                return Column(
                  children: [
                    Center(child: chart),
                    const SizedBox(height: 14),
                    legend,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  chart,
                  const SizedBox(width: 16),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FornecedorFinanceGridCard extends StatelessWidget {
  const _FornecedorFinanceGridCard({
    required this.nome,
    required this.cadastroOk,
    required this.despesas,
    required this.receitas,
    required this.saldo,
    required this.saldoNegativo,
    required this.onTap,
  });

  final String nome;
  final bool cadastroOk;
  final String despesas;
  final String receitas;
  final String saldo;
  final bool saldoNegativo;
  final VoidCallback onTap;

  static String _iniciais(String nome) {
    final parts = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'F';
    if (parts.length == 1) {
      final s = parts.first;
      return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
    }
    return ('${parts.first[0]}${parts[1][0]}').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final saldoColor = saldoNegativo
        ? const Color(0xFFB91C1C)
        : const Color(0xFF0D9488);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                ThemeCleanPremium.primary.withValues(alpha: 0.055),
              ],
            ),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.09),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary,
                          const Color(0xFF1D4ED8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: ThemeCleanPremium.primary.withValues(
                            alpha: 0.22,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _iniciais(nome),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        nome,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.7),
                  ),
                ],
              ),
              if (!cadastroOk) ...[
                const SizedBox(height: 5),
                Text(
                  'Cadastro removido',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: _FornecedorFinanceMetric(
                      label: 'Despesas',
                      value: despesas,
                      color: const Color(0xFFB91C1C),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _FornecedorFinanceMetric(
                      label: 'Receitas',
                      value: receitas,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _FornecedorFinanceMetric(
                      label: 'Saldo',
                      value: saldo,
                      color: saldoColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FornecedorFinanceMetric extends StatelessWidget {
  const _FornecedorFinanceMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Mesmo padrão do card «Finanças no painel» / ControleTotalSupplierFinanceCard:
    // mini-card branco com texto colorido, em vez de pílula com fundo tingido.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
          ),
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
    final dataStr = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: cor.withValues(alpha: 0.12),
                child: Icon(
                  isSaida ? Icons.south_west_rounded : Icons.north_east_rounded,
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

/// Abre grade moderna de lançamentos do fornecedor (Controle Total).
Future<void> showFornecedorLancamentosGridPreview(
  BuildContext context, {
  required String tenantId,
  required String fornecedorId,
  required String fornecedorNome,
  required String panelRole,
  String filtroInicial = 'todos',
  double saldoBancos = 0,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      expand: false,
      builder: (_, scrollController) => _FornecedorLancamentosGridSheet(
        scrollController: scrollController,
        tenantId: tenantId,
        fornecedorId: fornecedorId,
        fornecedorNome: fornecedorNome,
        panelRole: panelRole,
        filtroInicial: filtroInicial,
        saldoBancos: saldoBancos,
        onChanged: onChanged,
      ),
    ),
  );
}

class _FornecedorLancamentosGridSheet extends StatefulWidget {
  const _FornecedorLancamentosGridSheet({
    required this.scrollController,
    required this.tenantId,
    required this.fornecedorId,
    required this.fornecedorNome,
    required this.panelRole,
    required this.filtroInicial,
    required this.saldoBancos,
    this.onChanged,
  });

  final ScrollController scrollController;
  final String tenantId;
  final String fornecedorId;
  final String fornecedorNome;
  final String panelRole;
  final String filtroInicial;
  final double saldoBancos;
  final VoidCallback? onChanged;

  @override
  State<_FornecedorLancamentosGridSheet> createState() =>
      _FornecedorLancamentosGridSheetState();
}

class _FornecedorLancamentosGridSheetState
    extends State<_FornecedorLancamentosGridSheet> {
  late String _filtro;
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial;
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
      );
      final fid = widget.fornecedorId.trim();
      final filtered =
          r.docs.where((d) {
            return (d.data()['fornecedorId'] ?? '').toString().trim() == fid;
          }).toList()..sort((a, b) {
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

  bool _isEntrada(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('entrada') || t.contains('receita');
  }

  bool _isSaida(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('saida') || t.contains('despesa');
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible {
    if (_filtro == 'despesas') {
      return _docs.where((d) => _isSaida(d.data())).toList();
    }
    if (_filtro == 'receitas') {
      return _docs.where((d) => _isEntrada(d.data())).toList();
    }
    if (_filtro == 'pendentes') {
      return _docs.where((d) {
        final m = d.data();
        return financeLancamentoPendentePagamento(m) ||
            financeLancamentoPendenteRecebimento(m);
      }).toList();
    }
    return _docs;
  }

  Future<void> _editar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showFinanceLancamentoEditorForTenant(
      context,
      tenantId: widget.tenantId,
      existingDoc: doc,
      presetFornecedorId: widget.fornecedorId,
      lockFornecedor: true,
      panelRole: widget.panelRole,
    );
    if (ok && mounted) {
      await _load(force: true);
      widget.onChanged?.call();
    }
  }

  Future<void> _excluir(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text(
          'Tem certeza que deseja excluir este lançamento? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      await excluirLancamentoFinanceiroComAuditoria(doc, tid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Lançamento excluído.'),
        );
        await _load(force: true);
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleEfetivacao(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final tipo = financeInferTipo(data);
    if (tipo == 'transferencia') return;
    final isEntrada = _isEntrada(data);
    try {
      if (isEntrada) {
        final atual = data['recebimentoConfirmado'] != false;
        await YahwehDocWrite.update(doc.reference, {'recebimentoConfirmado': !atual});
      } else {
        final atual = data['pagamentoConfirmado'] != false;
        await YahwehDocWrite.update(doc.reference, {'pagamentoConfirmado': !atual});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            isEntrada ? 'Recebimento atualizado.' : 'Pagamento atualizado.',
          ),
        );
        await _load(force: true);
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    }
  }

  Future<void> _anexarComprovante(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await FinanceComprovanteAttachFlow.attachToLancamento(
      context: context,
      tenantId: widget.tenantId,
      docRef: doc.reference,
      docData: doc.data(),
    );
    if (!mounted || !ok) return;
    unawaited(_load(force: true));
    widget.onChanged?.call();
  }

  void _verComprovante(Map<String, dynamic> data) {
    if (!FinanceComprovanteAttachService.hasComprovanteReady(data)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este lançamento ainda não tem comprovante.'),
        ),
      );
      return;
    }
    unawaited(FinanceComprovanteAttachService.viewFromDoc(context, data));
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final visible = _visible;
    final despesasPorCat = <String, double>{};
    final receitasPorCat = <String, double>{};
    var totalD = 0.0, totalR = 0.0;
    for (final d in _docs) {
      final m = d.data();
      final cat = (m['categoria'] ?? 'Outros').toString();
      final v = financeParseValorBr(m['amount'] ?? m['valor']);
      if (_isSaida(m)) {
        despesasPorCat[cat] = (despesasPorCat[cat] ?? 0) + v;
        totalD += v;
      } else if (_isEntrada(m)) {
        receitasPorCat[cat] = (receitasPorCat[cat] ?? 0) + v;
        totalR += v;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fornecedorNome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${visible.length} lançamento(s) · Saldo bancos ${money.format(widget.saldoBancos)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : () => _load(force: true),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'todos', label: Text('Todos')),
                ButtonSegment(value: 'despesas', label: Text('Despesas')),
                ButtonSegment(value: 'receitas', label: Text('Receitas')),
                ButtonSegment(value: 'pendentes', label: Text('Pendentes')),
              ],
              selected: {_filtro},
              onSelectionChanged: (s) => setState(() => _filtro = s.first),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading && _docs.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : visible.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum lançamento neste filtro.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : CustomScrollView(
                    controller: widget.scrollController,
                    slivers: [
                      if (_docs.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: FinanceResumoChartsSection(
                              allLancamentos: _docs,
                              receitasPorCat: receitasPorCat,
                              despesasPorCat: despesasPorCat,
                              totalReceitas: totalR,
                              totalDespesas: totalD,
                              chartYear: DateTime.now().year,
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final doc = visible[i];
                            return _FornecedorLancamentoCtCard(
                              doc: doc,
                              money: money,
                              onTap: () => fornecedorShowLancamentoPreview(
                                context,
                                doc: doc,
                              ),
                              onEditar: () => _editar(doc),
                              onExcluir: () => _excluir(doc),
                              onTogglePagamento: () => _toggleEfetivacao(doc),
                              onComprovante: () => _anexarComprovante(doc),
                              onVerComprovante: () =>
                                  _verComprovante(doc.data()),
                              onRemoverComprovante: () =>
                                  removeFinanceComprovanteForLancamento(
                                    context,
                                    tenantId: widget.tenantId,
                                    doc: doc,
                                    onChanged: () {
                                      unawaited(_load(force: true));
                                      widget.onChanged?.call();
                                    },
                                  ),
                            );
                          }, childCount: visible.length),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Card de lançamento — paridade visual com o módulo Financeiro (Controle Total).
class _FornecedorLancamentoCtCard extends StatelessWidget {
  const _FornecedorLancamentoCtCard({
    required this.doc,
    required this.money,
    required this.onTap,
    required this.onEditar,
    required this.onExcluir,
    required this.onTogglePagamento,
    required this.onComprovante,
    required this.onVerComprovante,
    required this.onRemoverComprovante,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final VoidCallback onTogglePagamento;
  final VoidCallback onComprovante;
  final VoidCallback onVerComprovante;
  final VoidCallback onRemoverComprovante;

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final t = financeInferTipo(m);
    final isSaida = t.contains('saida') || t.contains('despesa');
    final isEntrada = t.contains('entrada') || t.contains('receita');
    final isTransfer = t == 'transferencia';
    final v = financeParseValorBr(m['amount'] ?? m['valor']);
    final dt = financeLancamentoDate(m);
    final dataStr = dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
    final color = isTransfer
        ? const Color(0xFF6366F1)
        : (isSaida ? const Color(0xFFDC2626) : const Color(0xFF15803D));
    final hasComp = FinanceComprovanteAttachService.hasComprovanteReady(m);
    // Upload CT = silencioso (sem spinner/faixa %).
    final pendente = isSaida
        ? financeLancamentoPendentePagamento(m)
        : financeLancamentoPendenteRecebimento(m);
    final titulo = (m['descricao'] ?? m['categoria'] ?? 'Lançamento')
        .toString();
    final subtitulo = (m['categoria'] ?? '').toString();
    final fornNome = (m['fornecedorNome'] ?? '').toString().trim();
    final conciliadoOk = m['conciliado'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
        border: Border(
          left: BorderSide(color: color, width: 3.5),
          top: const BorderSide(color: Color(0xFFE8EEF4)),
          right: const BorderSide(color: Color(0xFFE8EEF4)),
          bottom: const BorderSide(color: Color(0xFFE8EEF4)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withValues(alpha: 0.2),
                            color.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusSm,
                        ),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Icon(
                        isTransfer
                            ? Icons.swap_horiz_rounded
                            : (isEntrada
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded),
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (subtitulo.isNotEmpty)
                            Text(
                              subtitulo,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (fornNome.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: FinancePremiumVinculoPill(
                                label: 'Fornecedor · $fornNome',
                                isMembro: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isTransfer ? money.format(v) : ' ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (dataStr.isNotEmpty)
                      Text(
                        dataStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    if (hasComp)
                      FinancePremiumStatusPill(
                        label: 'Comprovante',
                        icon: Icons.receipt_long_rounded,
                        colors: [
                          ThemeCleanPremium.success,
                          ThemeCleanPremium.success.withValues(alpha: 0.7),
                        ],
                      ),
                    if (!isTransfer && !conciliadoOk)
                      const FinancePremiumStatusPill(
                        label: 'Não conciliado',
                        icon: Icons.receipt_long_outlined,
                        colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                      ),
                    if (pendente)
                      FinancePremiumStatusPill(
                        label: isSaida ? 'A pagar' : 'Pendente',
                        icon: Icons.schedule_rounded,
                        colors: isSaida
                            ? const [Color(0xFFDC2626), Color(0xFFF87171)]
                            : const [Color(0xFFD97706), Color(0xFFFBBF24)],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FinancePremiumIconAction(
                        icon: pendente
                            ? Icons.check_circle_outline_rounded
                            : Icons.undo_rounded,
                        color: const Color(0xFF2563EB),
                        onTap: onTogglePagamento,
                        tooltip: pendente
                            ? (isSaida
                                  ? 'Confirmar pagamento'
                                  : 'Confirmar recebimento')
                            : 'Marcar pendente',
                      ),
                      FinancePremiumIconAction(
                        icon: Icons.edit_rounded,
                        color: ThemeCleanPremium.primary,
                        onTap: onEditar,
                        tooltip: 'Editar',
                      ),
                      FinancePremiumIconAction(
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFDC2626),
                        onTap: onExcluir,
                        tooltip: 'Excluir',
                      ),
                      if (hasComp) ...[
                        FinancePremiumIconAction(
                          icon: Icons.visibility_rounded,
                          color: const Color(0xFF0D9488),
                          onTap: onVerComprovante,
                          tooltip: 'Ver comprovante',
                        ),
                        FinancePremiumIconAction(
                          icon: Icons.link_off_rounded,
                          color: const Color(0xFFDC2626),
                          onTap: onRemoverComprovante,
                          tooltip: 'Remover comprovante',
                        ),
                      ] else
                        FinancePremiumIconAction(
                          icon: Icons.visibility_rounded,
                          color: Colors.grey.shade400,
                          onTap: onVerComprovante,
                          tooltip: 'Sem comprovante',
                        ),
                      FinancePremiumIconAction(
                        icon: hasComp
                            ? Icons.sync_rounded
                            : Icons.photo_camera_rounded,
                        color: const Color(0xFF7C3AED),
                        tooltip: hasComp
                            ? 'Trocar comprovante'
                            : 'Anexar comprovante',
                        onTap: onComprovante,
                      ),
                    ],
                  ),
                ),
              ],
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
