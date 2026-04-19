import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart'
    show kFornecedoresModuleIcon;
import 'package:gestao_yahweh/core/brasil_bancos.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/ui/pages/finance_receitas_recorrentes_tabs.dart';
import 'package:gestao_yahweh/ui/widgets/finance_fixo_premium_dialogs.dart';
import 'package:gestao_yahweh/services/finance_audit_log_service.dart';

// ───────────────────────────────────────────────────────────────────────────────
// Categorias padrão (seed quando coleções vazias)
// ───────────────────────────────────────────────────────────────────────────────
const _categoriasReceitaPadrao = [
  'Aluguéis Recebidos',
  'Dízimos',
  'Doações',
  'Inscrições em Eventos',
  'Ofertas Missionárias',
  'Ofertas Voluntárias',
  'Vendas de Produtos',
  'Campanhas',
  'Outros',
];

const _categoriasDespesaPadrao = [
  'Água',
  'Ajuda Social',
  'Energia Elétrica',
  'Eventos',
  'Impostos',
  'Internet',
  'Investimentos em Mídia',
  'Manutenção',
  'Material de Limpeza',
  'Oferta Missionária',
  'Pagamento de Obreiros',
  'Prebenda',
  'Salários',
  'Material de Escritório',
  'Transporte',
  'Alimentação',
  'Outros',
];

const _mesesAbrev = [
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
  'Dez'
];

Future<void> _excluirLancamentoComAuditoria(
  DocumentSnapshot<Map<String, dynamic>> doc,
  String tenantId,
) async {
  await logFinanceiroAuditoria(
    tenantId: tenantId,
    acao: 'exclusao',
    lancamentoId: doc.id,
    dadosAntes: Map<String, dynamic>.from(doc.data() ?? {}),
  );
  await doc.reference.delete();
}

/// Outros módulos (ex.: Fornecedores) — mesma exclusão com auditoria que o Financeiro.
Future<void> excluirLancamentoFinanceiroComAuditoria(
  DocumentSnapshot<Map<String, dynamic>> doc,
  String tenantId,
) =>
    _excluirLancamentoComAuditoria(doc, tenantId);

// Padrão de cores do módulo financeiro: entradas azul, saídas vermelho, saldo positivo verde, negativo vermelho
const Color _financeEntradas = Color(0xFF2563EB); // azul — receitas/entradas
const Color _financeSaidas = Color(0xFFDC2626); // vermelho — despesas/saídas
const Color _financeSaldoPositivo = Color(0xFF16A34A); // verde — saldo positivo
const Color _financeSaldoNegativo =
    Color(0xFFDC2626); // vermelho — saldo negativo
const Color _financeTransferencia =
    Color(0xFF6366F1); // índigo — transferências

/// Rótulo do tipo de conta (alinha com cadastro em Contas).
String _financeTipoContaLabel(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'poupanca':
    case 'poupança':
      return 'Poupança';
    case 'caixa':
      return 'Caixa / numerário';
    default:
      return 'Conta corrente';
  }
}

/// Nome para exibição: `nome` preenchido no Firestore; senão combina banco + tipo (evita linhas vazias quando `nome` é string vazia).
String _financeContaDisplayName(Map<String, dynamic> d) {
  final nome = (d['nome'] ?? '').toString().trim();
  if (nome.isNotEmpty) return nome;
  final banco = (d['bancoNome'] ?? '').toString().trim();
  final tipo = _financeTipoContaLabel(d['tipoConta']?.toString());
  if (banco.isNotEmpty) return '$banco · $tipo';
  return tipo;
}

/// Nome curto do banco para identificação visual na linha da conta.
String _financeContaBancoNome(Map<String, dynamic> d) {
  final banco = (d['bancoNome'] ?? '').toString().trim();
  if (banco.isNotEmpty) return banco;
  final codigo = (d['bancoCodigo'] ?? '').toString().trim();
  if (codigo.isNotEmpty) {
    final fromList = kBrasilBancosComuns.where((b) => b.codigo == codigo);
    if (fromList.isNotEmpty) return fromList.first.nome;
    return 'Banco $codigo';
  }
  return 'Caixa / interno';
}

/// Cor por banco (determinística) para facilitar leitura rápida das contas.
Color _financeContaBancoColor(Map<String, dynamic> d) {
  final banco = _financeContaBancoNome(d).toLowerCase();
  if (banco.contains('nubank')) return const Color(0xFF8A05BE);
  if (banco.contains('itaú') || banco.contains('itau')) return const Color(0xFFEC7000);
  if (banco.contains('bradesco')) return const Color(0xFFCC092F);
  if (banco.contains('santander')) return const Color(0xFFEC0000);
  if (banco.contains('caixa')) return const Color(0xFF0066B3);
  if (banco.contains('banco do brasil')) return const Color(0xFFF9D300);
  if (banco.contains('inter')) return const Color(0xFFFF7A00);
  if (banco.contains('mercado pago')) return const Color(0xFF00A1EA);
  if (banco.contains('picpay')) return const Color(0xFF21C25E);
  const palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFFDC2626),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
  ];
  final idx = banco.hashCode.abs() % palette.length;
  return palette[idx];
}

/// Retorna categorias de despesa do tenant (com seed se vazio). Usado por Despesas Fixas. Sem repetição por nome.
Future<List<String>> _getCategoriasDespesaForTenant(String tenantId) async {
  final col = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('categorias_despesas');
  var snap = await col.orderBy('nome').get();
  if (snap.docs.isEmpty) {
    for (final nome in _categoriasDespesaPadrao) {
      await col
          .add({'nome': nome, 'ordem': _categoriasDespesaPadrao.indexOf(nome)});
    }
    snap = await col.orderBy('nome').get();
  }
  final nomes = snap.docs
      .map((d) => (d.data()['nome'] ?? '').toString())
      .where((s) => s.isNotEmpty);
  final seen = <String>{};
  return nomes.where((n) => seen.add(n)).toList();
}

Future<List<String>> _financeCategoriasReceitaTenant(String tenantId) async {
  final col = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('categorias_receitas');
  var snap = await col.orderBy('nome').get();
  if (snap.docs.isEmpty) {
    for (final nome in _categoriasReceitaPadrao) {
      await col.add(
          {'nome': nome, 'ordem': _categoriasReceitaPadrao.indexOf(nome)});
    }
    snap = await col.orderBy('nome').get();
  }
  final nomes = snap.docs
      .map((d) => (d.data()['nome'] ?? '').toString())
      .where((s) => s.isNotEmpty);
  final seen = <String>{};
  return nomes.where((n) => seen.add(n)).toList();
}

Future<List<({String id, String nome})>> _financeContasAtivasTenant(
    String tenantId) async {
  final snap = await FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('contas')
      .orderBy('nome')
      .get();
  return snap.docs
      .where((d) => d.data()['ativo'] != false)
      .map((d) => (id: d.id, nome: _financeContaDisplayName(d.data())))
      .where((e) => e.nome.isNotEmpty)
      .toList();
}

DateTime? _financeDocDate(Map<String, dynamic> m) {
  final ts = m['createdAt'];
  if (ts is Timestamp) return ts.toDate();
  return null;
}

bool _financeMatchesTipoMovimento(Map<String, dynamic> m, String filtro) {
  if (filtro == 'todos') return true;
  final t = (m['type'] ?? m['tipo'] ?? '').toString().toLowerCase();
  if (filtro == 'receita') {
    return t.contains('entrada') || t.contains('receita');
  }
  if (filtro == 'despesa') {
    return t.contains('saida') ||
        t.contains('saída') ||
        t.contains('despesa');
  }
  if (filtro == 'transferencia') {
    return t == 'transferencia';
  }
  return true;
}

/// PDF Super Premium — lançamentos financeiros (lista completa ou filtrada).
Future<void> exportFinanceiroRelatorioPdf({
  required BuildContext context,
  required String tenantId,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  List<String> filterSummaryLines = const [],
  String filename = 'financeiro_relatorio.pdf',
}) async {
  if (docs.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum lançamento para exportar.')),
      );
    }
    return;
  }
  try {
    final branding = await loadReportPdfBranding(tenantId);
    if (!context.mounted) return;
    double entradas = 0, saidas = 0;
    final data = docs.map((d) {
      final m = d.data();
      final tipo = (m['type'] ?? m['tipo'] ?? 'entrada').toString();
      final valor = (m['amount'] ?? m['valor'] ?? 0) is num
          ? (m['amount'] ?? m['valor'] ?? 0) as num
          : 0.0;
      final tl = tipo.toLowerCase();
      if (tl.contains('entrada') || tl == 'receita') {
        entradas += valor.toDouble();
      } else if (tl != 'transferencia') {
        saidas += valor.toDouble();
      }
      final ts = m['createdAt'];
      String dataStr = '';
      if (ts is Timestamp) {
        dataStr = DateFormat('dd/MM/yyyy').format(ts.toDate());
      }
      return [
        dataStr,
        tipo,
        (m['categoria'] ?? '').toString(),
        (m['descricao'] ?? '').toString(),
        valor.toStringAsFixed(2)
      ];
    }).toList();
    final pdf = await PdfSuperPremiumTheme.newPdfDocument();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: PdfSuperPremiumTheme.pageMargin,
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: PdfSuperPremiumTheme.header(
            'Relatório Financeiro',
            branding: branding,
            extraLines: [
              ...filterSummaryLines,
              if (filterSummaryLines.isNotEmpty) '---',
              'Entradas: R\$${entradas.toStringAsFixed(2)}',
              'Saídas: R\$${saidas.toStringAsFixed(2)}',
              'Saldo: R\$${(entradas - saidas).toStringAsFixed(2)}',
            ],
          ),
        ),
        footer: (ctx) => PdfSuperPremiumTheme.footer(
          ctx,
          churchName: branding.churchName,
        ),
        build: (ctx) => [
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              'Data',
              'Tipo',
              'Categoria',
              'Descrição',
              'Valor (R\$)'
            ],
            data: data,
            accent: branding.accent,
            columnWidths: PdfSuperPremiumTheme.columnWidthsFinanceiroReport,
          ),
        ],
      ),
    );
    final bytes = Uint8List.fromList(await pdf.save());
    if (context.mounted) {
      await showPdfActions(context, bytes: bytes, filename: filename);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar PDF: $e')),
      );
    }
  }
}

/// PDF — despesas agrupadas por fornecedor (nome denormalizado no lançamento).
Future<void> exportFinanceiroDespesasPorFornecedorPdf({
  required BuildContext context,
  required String tenantId,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  List<String> filterSummaryLines = const [],
  String filename = 'financeiro_despesas_por_fornecedor.pdf',
}) async {
  final despesas = docs.where((d) {
    final m = d.data();
    final t = (m['type'] ?? m['tipo'] ?? '').toString().toLowerCase();
    if (t == 'transferencia') return false;
    return t.contains('saida') ||
        t.contains('saída') ||
        t.contains('despesa');
  }).toList();
  if (despesas.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Nenhuma despesa no filtro para agrupar por fornecedor.')),
      );
    }
    return;
  }
  try {
    final branding = await loadReportPdfBranding(tenantId);
    if (!context.mounted) return;
    final agg = <String, ({double total, int n})>{};
    for (final d in despesas) {
      final m = d.data();
      final nome = (m['fornecedorNome'] ?? '').toString().trim();
      final key = nome.isEmpty ? '(Sem fornecedor)' : nome;
      final raw = m['amount'] ?? m['valor'] ?? 0;
      final v = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
      final cur = agg[key] ?? (total: 0.0, n: 0);
      agg[key] = (total: cur.total + v, n: cur.n + 1);
    }
    final totalGeral = agg.values.fold<double>(0, (a, e) => a + e.total);
    final rows = agg.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final data = rows.map((e) {
      final pct = totalGeral > 0 ? (e.value.total / totalGeral * 100) : 0.0;
      return [
        e.key,
        e.value.total.toStringAsFixed(2),
        '${e.value.n}',
        '${pct.toStringAsFixed(1)}%',
      ];
    }).toList();
    final pdf = await PdfSuperPremiumTheme.newPdfDocument();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: PdfSuperPremiumTheme.pageMargin,
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: PdfSuperPremiumTheme.header(
            'Despesas por fornecedor',
            branding: branding,
            extraLines: [
              ...filterSummaryLines,
              if (filterSummaryLines.isNotEmpty) '---',
              'Total despesas: R\$${totalGeral.toStringAsFixed(2)}',
              'Fornecedores distintos: ${agg.length}',
            ],
          ),
        ),
        footer: (ctx) => PdfSuperPremiumTheme.footer(
          ctx,
          churchName: branding.churchName,
        ),
        build: (ctx) => [
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              'Fornecedor',
              'Total (R\$)',
              'Lançamentos',
              '% do total',
            ],
            data: data,
            accent: branding.accent,
            columnWidths: {
              0: const pw.FlexColumnWidth(3.2),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(0.95),
              3: const pw.FlexColumnWidth(0.85),
            },
          ),
        ],
      ),
    );
    final bytes = Uint8List.fromList(await pdf.save());
    if (context.mounted) {
      await showPdfActions(context, bytes: bytes, filename: filename);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar PDF: $e')),
      );
    }
  }
}

Future<void> showFinanceTenantMetasEditor(
  BuildContext context, {
  required String tenantId,
  required FinanceTenantSettings initial,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FinanceMetasEditorSheet(
      tenantId: tenantId,
      initial: initial,
    ),
  );
}

class _FinanceMetasEditorSheet extends StatefulWidget {
  final String tenantId;
  final FinanceTenantSettings initial;

  const _FinanceMetasEditorSheet({
    required this.tenantId,
    required this.initial,
  });

  @override
  State<_FinanceMetasEditorSheet> createState() =>
      _FinanceMetasEditorSheetState();
}

class _FinanceMetasEditorSheetState extends State<_FinanceMetasEditorSheet> {
  late final TextEditingController _limiteCtrl;
  final List<({TextEditingController cat, TextEditingController valor})> _rows =
      [];
  List<String> _catsDespesa = [];
  bool _loadingCats = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _limiteCtrl = TextEditingController(
      text: widget.initial.limiteAprovacaoDespesa > 0
          ? formatBrCurrencyInitial(widget.initial.limiteAprovacaoDespesa)
          : '',
    );
    for (final e in widget.initial.orcamentosDespesa.entries) {
      _rows.add((
        cat: TextEditingController(text: e.key),
        valor: TextEditingController(
          text: e.value > 0 ? formatBrCurrencyInitial(e.value) : '',
        ),
      ));
    }
    if (_rows.isEmpty) {
      _rows.add((
        cat: TextEditingController(),
        valor: TextEditingController(),
      ));
    }
    unawaited(_loadCats());
  }

  Future<void> _loadCats() async {
    try {
      final list = await _getCategoriasDespesaForTenant(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _catsDespesa = list;
        _loadingCats = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingCats = false);
      }
    }
  }

  static double? _parseMoneyField(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    return parseBrCurrencyInput(t);
  }

  void _addRow() {
    setState(() {
      _rows.add((
        cat: TextEditingController(),
        valor: TextEditingController(),
      ));
    });
  }

  Future<void> _salvar() async {
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final lim = _parseMoneyField(_limiteCtrl.text) ?? 0.0;
      final orc = <String, double>{};
      for (final r in _rows) {
        final k = r.cat.text.trim();
        if (k.isEmpty) continue;
        final v = _parseMoneyField(r.valor.text) ?? 0.0;
        if (v > 0) orc[k] = v;
      }
      await FinanceTenantSettings(
        limiteAprovacaoDespesa: lim,
        orcamentosDespesa: orc,
      ).save(widget.tenantId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Metas e orçamentos salvos.'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _limiteCtrl.dispose();
    for (final r in _rows) {
      r.cat.dispose();
      r.valor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ThemeCleanPremium.radiusLg),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Metas do financeiro',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    'Acima deste valor (R\$), despesas de tesoureiro/líderes exigem aprovação de gestor/pastor (quando aplicável).',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _limiteCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [BrCurrencyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Limite para segunda aprovação (R\$)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Orçamento por categoria (despesa)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Linha'),
                      ),
                    ],
                  ),
                  if (_loadingCats)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_catsDespesa.isNotEmpty)
                    Text(
                      'Dica: use o mesmo nome da categoria dos lançamentos.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ..._rows.asMap().entries.map((ie) {
                    final i = ie.key;
                    final r = ie.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: r.cat,
                              decoration: InputDecoration(
                                labelText: 'Categoria (despesa)',
                                border: const OutlineInputBorder(),
                                hintText: _catsDespesa.isEmpty
                                    ? null
                                    : _catsDespesa.take(3).join(', '),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: r.valor,
                              keyboardType: TextInputType.number,
                              inputFormatters: [BrCurrencyInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Teto (R\$)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remover',
                            onPressed: _rows.length <= 1
                                ? null
                                : () => setState(() {
                                      r.cat.dispose();
                                      r.valor.dispose();
                                      _rows.removeAt(i);
                                    }),
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: Color(0xFFDC2626)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _salvar,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Salvando…' : 'Salvar'),
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

// ───────────────────────────────────────────────────────────────────────────────
// FinancePage — Módulo Financeiro Completo (Controle Total)
// ───────────────────────────────────────────────────────────────────────────────
class FinancePage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String? cpf;

  /// Gestor liberou financeiro para este membro (role membro).
  final bool? podeVerFinanceiro;
  final List<String>? permissions;

  /// Aba inicial (0–7): Resumo, Lançamentos, Despesas fixas, Receitas fixas, Conciliação, Categorias, Contas, Relatórios.
  final int? initialTabIndex;

  /// Abre o editor deste lançamento após entrar na página (ex.: painel → despesa).
  final String? openLancamentoId;

  /// Dentro de [IgrejaCleanShell]: sem título duplicado nas abas e [SafeArea] ajustado.
  final bool embeddedInShell;

  const FinancePage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf,
    this.podeVerFinanceiro,
    this.permissions,
    this.initialTabIndex,
    this.openLancamentoId,
    this.embeddedInShell = false,
  });

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final CollectionReference<Map<String, dynamic>> _financeCol;
  late final DocumentReference<Map<String, dynamic>> _tenantRef;
  /// Incrementado após salvar/excluir lançamento — atualiza Resumo + Lançamentos.
  int _financeRevision = 0;

  void _notifyFinanceChanged() {
    if (!mounted) return;
    setState(() => _financeRevision++);
  }

  @override
  void initState() {
    super.initState();
    final rawTab = widget.initialTabIndex ?? 0;
    final idx = rawTab < 0 ? 0 : (rawTab > 7 ? 7 : rawTab);
    _tabCtrl = TabController(length: 8, vsync: this, initialIndex: idx);
    _tenantRef =
        FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId);
    _financeCol = _tenantRef.collection('finance');
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    final openId = widget.openLancamentoId?.trim();
    if (openId != null && openId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLancamento(openId));
    }
  }

  Future<void> _openPendingLancamento(String id) async {
    if (!mounted) return;
    try {
      final doc = await _financeCol.doc(id).get();
      if (!doc.exists || !mounted) return;
      _tabCtrl.index = 1;
      final ok = await showFinanceLancamentoEditorForTenant(context,
          tenantId: widget.tenantId,
          existingDoc: doc,
          panelRole: widget.role);
      if (ok && mounted) _notifyFinanceChanged();
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final canPop = Navigator.canPop(context);
    final showAppBar = !isMobile || canPop;

    if (!AppPermissions.canViewFinance(
      widget.role,
      memberCanViewFinance: widget.podeVerFinanceiro,
      permissions: widget.permissions,
    )) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        appBar: !showAppBar
            ? null
            : AppBar(
                leading: canPop
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.maybePop(context),
                        tooltip: 'Voltar')
                    : null,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        ThemeCleanPremium.primary,
                        Color.lerp(ThemeCleanPremium.primary,
                            const Color(0xFF1E3A8A), 0.22)!,
                      ],
                    ),
                  ),
                ),
                title: const Text('Financeiro',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              ),
        body: const SafeArea(
          child: Center(child: Text('Acesso restrito ao módulo financeiro.')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: !showAppBar
          ? null
          : AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              leading: canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar')
                  : null,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ThemeCleanPremium.primary,
                      Color.lerp(ThemeCleanPremium.primary,
                          const Color(0xFF1E3A8A), 0.22)!,
                    ],
                  ),
                ),
              ),
              title: const Text('Receitas e Despesas',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                      fontSize: 18)),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    tooltip: 'Exportar PDF',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget),
                    ),
                    onPressed: () => _exportarPdf(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: 'Exportar CSV',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget),
                    ),
                    onPressed: () => _exportarCSV(context),
                  ),
                ),
              ],
            ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ThemeCleanPremium.primary,
              Color.lerp(ThemeCleanPremium.primaryLight,
                  ThemeCleanPremium.primary, 0.35)!,
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.42),
              blurRadius: 22,
              offset: const Offset(0, 10),
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          heroTag: 'fab_finance',
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          hoverElevation: 0,
          focusElevation: 0,
          highlightElevation: 0,
          icon: const Icon(Icons.add_rounded, size: 24),
          label: const Text('Lançamento Rápido',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          onPressed: () => _showLancamentoDialog(context),
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        ),
      ),
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: NestedScrollView(
          // Abas + visão por conta sobem com o scroll do conteúdo (web e mobile).
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              if (isMobile && !widget.embeddedInShell)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Financeiro',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: ThemeCleanPremium.onSurface)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          tooltip: 'Exportar PDF',
                          style: IconButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.cardBackground,
                            foregroundColor: ThemeCleanPremium.primary,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            side: BorderSide(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.2),
                            ),
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => _exportarPdf(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_rounded),
                          tooltip: 'Exportar CSV',
                          style: IconButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.cardBackground,
                            foregroundColor: ThemeCleanPremium.primary,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            side: BorderSide(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.2),
                            ),
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => _exportarCSV(context),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: isMobile && widget.embeddedInShell
                    ? Container(
                        color: ThemeCleanPremium.primary,
                        child: ChurchPanelPillTabBar(
                          controller: _tabCtrl,
                          tabs: const [
                            Tab(text: 'Resumo'),
                            Tab(text: 'Lançamentos'),
                            Tab(text: 'Despesas Fixas'),
                            Tab(text: 'Receitas Fixas'),
                            Tab(text: 'Conciliação'),
                            Tab(text: 'Categorias'),
                            Tab(text: 'Contas'),
                            Tab(text: 'Relatórios'),
                          ],
                        ),
                      )
                    : Container(
                        margin: EdgeInsets.symmetric(
                            horizontal: ThemeCleanPremium.spaceLg,
                            vertical: ThemeCleanPremium.spaceSm),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusLg),
                          boxShadow: [
                            ...ThemeCleanPremium.softUiCardShadow,
                            BoxShadow(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                              spreadRadius: -4,
                            ),
                          ],
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TabBar(
                          controller: _tabCtrl,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          splashBorderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          labelColor: ThemeCleanPremium.primary,
                          unselectedLabelColor:
                              ThemeCleanPremium.onSurfaceVariant,
                          labelStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: -0.2),
                          unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              letterSpacing: -0.15),
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                ThemeCleanPremium.primary
                                    .withValues(alpha: 0.14),
                                ThemeCleanPremium.primary
                                    .withValues(alpha: 0.06),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(ThemeCleanPremium.radiusSm),
                            border: Border.all(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Resumo'),
                            Tab(text: 'Lançamentos'),
                            Tab(text: 'Despesas Fixas'),
                            Tab(text: 'Receitas Fixas'),
                            Tab(text: 'Conciliação'),
                            Tab(text: 'Categorias'),
                            Tab(text: 'Contas'),
                            Tab(text: 'Relatórios'),
                          ],
                        ),
                      ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabCtrl,
            children: [
              _ResumoTab(
                key: ValueKey('resumo_${widget.tenantId}_$_financeRevision'),
                financeCol: _financeCol,
                tenantId: widget.tenantId,
                role: widget.role,
                financeRevision: _financeRevision,
                onFinanceChanged: _notifyFinanceChanged,
              ),
              _LancamentosTab(
                key: ValueKey('lanc_${widget.tenantId}_$_financeRevision'),
                financeCol: _financeCol,
                tenantId: widget.tenantId,
                role: widget.role,
                onFinanceChanged: _notifyFinanceChanged,
              ),
              _DespesasFixasTab(
                tenantId: widget.tenantId,
                role: widget.role,
              ),
              FinanceReceitasFixasTab(
                tenantId: widget.tenantId,
                role: widget.role,
              ),
              FinanceConciliacaoReceitasTab(
                tenantId: widget.tenantId,
                role: widget.role,
              ),
              _FinanceCategoriasTab(tenantId: widget.tenantId),
              _FinanceContasTab(
                tenantId: widget.tenantId,
                role: widget.role,
                onEditLancamento: (ctx, doc) =>
                    _showLancamentoDialog(ctx, doc: doc),
              ),
              _FinanceRelatoriosTab(
                financeCol: _financeCol,
                tenantId: widget.tenantId,
                onEditLancamento: (ctx, doc) =>
                    _showLancamentoDialog(ctx, doc: doc),
                onVoltarAoResumo: () {
                  if (_tabCtrl.index != 0) {
                    _tabCtrl.animateTo(0);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Lançamento Rápido (Receita / Despesa / Transferência) ────────────────────
  Future<void> _showLancamentoDialog(BuildContext context,
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final ok = await showFinanceLancamentoEditorForTenant(context,
        tenantId: widget.tenantId,
        existingDoc: doc,
        panelRole: widget.role);
    if (ok && mounted) _notifyFinanceChanged();
  }

  // ─── Exportar CSV ────────────────────────────────────────────────────────────
  Future<void> _exportarCSV(BuildContext context) async {
    final snap = await _financeCol.orderBy('createdAt', descending: true).get();
    if (!mounted) return;
    if (snap.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum lançamento para exportar.')));
      return;
    }
    final buffer = StringBuffer(
        'Tipo,Categoria,CentroCusto,Descrição,Valor,Data,Conciliado,RefExtrato,Fornecedor,Membro,AprovacaoPendente\n');
    for (final d in snap.docs) {
      final data = d.data();
      final tipo = (data['type'] ?? 'entrada').toString();
      final cat = (data['categoria'] ?? '').toString();
      final cc = (data['centroCusto'] ?? '').toString();
      final desc = (data['descricao'] ?? '').toString().replaceAll(',', ' ');
      final valor = (data['amount'] ?? data['valor'] ?? 0).toString();
      final conc = data['conciliado'] == true ? 'sim' : 'nao';
      final ext = (data['extratoRef'] ?? '').toString().replaceAll(',', ' ');
      final forn = (data['fornecedorNome'] ?? '').toString().replaceAll(',', ' ');
      final memb = (data['membroNome'] ?? '').toString().replaceAll(',', ' ');
      final ap = data['aprovacaoPendente'] == true ? 'sim' : 'nao';
      String dataStr = '';
      final ts = data['createdAt'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        dataStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
      buffer.writeln(
          '$tipo,$cat,$cc,$desc,$valor,$dataStr,$conc,$ext,$forn,$memb,$ap');
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Exportar CSV'),
        content: const Text('Arquivo CSV gerado com sucesso.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _exportarPdf(BuildContext context) async {
    final snap = await _financeCol
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    if (!mounted) return;
    await exportFinanceiroRelatorioPdf(
      context: context,
      tenantId: widget.tenantId,
      docs: snap.docs,
      filename: 'financeiro_relatorio.pdf',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB — Relatórios (filtros Super Premium + PDF)
// ═══════════════════════════════════════════════════════════════════════════════

class _FinanceRelatoriosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final Future<void> Function(
          BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc)
      onEditLancamento;
  final VoidCallback onVoltarAoResumo;

  const _FinanceRelatoriosTab({
    required this.financeCol,
    required this.tenantId,
    required this.onEditLancamento,
    required this.onVoltarAoResumo,
  });

  @override
  State<_FinanceRelatoriosTab> createState() => _FinanceRelatoriosTabState();
}

class _FinanceRelatoriosTabState extends State<_FinanceRelatoriosTab> {
  int _streamRetry = 0;
  String _filtroTipo = 'todos';
  String _filtroCategoria = '';
  String? _filtroContaId;
  int? _filtroAno;
  int? _filtroMes;
  DateTime? _dataInicio;
  DateTime? _dataFim;

  List<String> _categoriasExtras = const [];
  List<({String id, String nome})> _contas = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeta());
  }

  Future<void> _loadMeta() async {
    try {
      final cr = await _financeCategoriasReceitaTenant(widget.tenantId);
      final cd = await _getCategoriasDespesaForTenant(widget.tenantId);
      final co = await _financeContasAtivasTenant(widget.tenantId);
      final set = <String>{...cr, ...cd};
      final list = set.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _categoriasExtras = list;
        _contas = co;
      });
    } catch (_) {}
  }

  List<_QueryDocFinance> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) {
      final m = d.data();
      if (!_financeMatchesTipoMovimento(m, _filtroTipo)) return false;
      if (_filtroCategoria.isNotEmpty && (m['categoria'] ?? '') != _filtroCategoria) {
        return false;
      }
      final cid = _filtroContaId;
      if (cid != null && cid.isNotEmpty) {
        if (!_financeLancamentoEnvolveConta(m, cid)) return false;
      }
      final dt = _financeDocDate(m);
      if (_dataInicio != null || _dataFim != null) {
        if (dt == null) return false;
        final day = DateTime(dt.year, dt.month, dt.day);
        if (_dataInicio != null) {
          final s = DateTime(
            _dataInicio!.year,
            _dataInicio!.month,
            _dataInicio!.day,
          );
          if (day.isBefore(s)) return false;
        }
        if (_dataFim != null) {
          final e = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day);
          if (day.isAfter(e)) return false;
        }
        return true;
      }
      if (_filtroAno != null) {
        if (dt == null) return false;
        if (dt.year != _filtroAno) return false;
      }
      if (_filtroMes != null) {
        if (dt == null) return false;
        if (dt.month != _filtroMes) return false;
      }
      return true;
    }).map((d) => _QueryDocFinance(d)).toList();
  }

  List<String> _pdfFilterLines() {
    final lines = <String>[];
    if (_filtroTipo != 'todos') {
      lines.add(
        'Movimento: ${_filtroTipo == 'receita' ? 'Receitas' : _filtroTipo == 'despesa' ? 'Despesas' : 'Transferências'}',
      );
    }
    if (_filtroCategoria.isNotEmpty) {
      lines.add('Categoria: $_filtroCategoria');
    }
    if (_filtroContaId != null && _filtroContaId!.isNotEmpty) {
      var nomeConta = '';
      for (final c in _contas) {
        if (c.id == _filtroContaId) {
          nomeConta = c.nome;
          break;
        }
      }
      lines.add('Conta: ${nomeConta.isNotEmpty ? nomeConta : _filtroContaId}');
    }
    if (_filtroAno != null) lines.add('Ano: $_filtroAno');
    if (_filtroMes != null) lines.add('Mês: $_filtroMes');
    if (_dataInicio != null) {
      lines.add('De: ${_fmtData(_dataInicio!)}');
    }
    if (_dataFim != null) {
      lines.add('Até: ${_fmtData(_dataFim!)}');
    }
    return lines;
  }

  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final anos = List<int>.generate(now.year - 1999, (i) => 2000 + i);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(_streamRetry),
      stream: widget.financeCol
          .orderBy('createdAt', descending: true)
          .limit(2000)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os lançamentos',
            error: snap.error,
            onRetry: () => setState(() => _streamRetry++),
          );
        }
        if (!snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final raw = snap.data!.docs;
        final filtered = _applyFilters(raw);
        filtered.sort((a, b) {
          final da = _financeDocDate(a.doc.data());
          final db = _financeDocDate(b.doc.data());
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });

        double sumEnt = 0, sumSai = 0;
        for (final d in filtered) {
          final m = d.doc.data();
          final t = (m['type'] ?? '').toString().toLowerCase();
          final v = (m['amount'] ?? m['valor'] ?? 0) is num
              ? (m['amount'] ?? m['valor'] ?? 0) as num
              : 0.0;
          if (t.contains('entrada') || t.contains('receita')) {
            sumEnt += v.toDouble();
          } else if (t != 'transferencia') {
            sumSai += v.toDouble();
          }
        }

        return SingleChildScrollView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onVoltarAoResumo,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          ThemeCleanPremium.primary.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      border: Border.all(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
                      ),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Voltar ao resumo financeiro',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    letterSpacing: -0.2,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Retorna à aba Resumo (bancos, caixa e gráficos) sem sair do módulo.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.25,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.dashboard_rounded,
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      const Color(0xFF0EA5E9).withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: ThemeCleanPremium.softUiCardShadow,
                          ),
                          child: Icon(
                            Icons.insights_rounded,
                            color: ThemeCleanPremium.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Relatórios Super Premium',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Filtre por período, tipo (receita/despesa/transferência), categoria e conta. Exporte o PDF com a identidade da igreja.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _filtroTipo,
                      decoration: _financeRelFieldDeco('Tipo'),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'receita', child: Text('Receitas')),
                        DropdownMenuItem(
                            value: 'despesa', child: Text('Despesas')),
                        DropdownMenuItem(
                            value: 'transferencia',
                            child: Text('Transferências')),
                      ],
                      onChanged: (v) =>
                          setState(() => _filtroTipo = v ?? 'todos'),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _filtroCategoria.isEmpty ? null : _filtroCategoria,
                      isExpanded: true,
                      decoration: _financeRelFieldDeco('Categoria'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ..._categoriasExtras.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _filtroCategoria = v ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      value: _filtroContaId,
                      isExpanded: true,
                      decoration: _financeRelFieldDeco('Conta'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ..._contas.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.nome,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filtroContaId = v),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<int?>(
                      value: _filtroAno,
                      decoration: _financeRelFieldDeco('Ano'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...anos.map(
                          (y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filtroAno = v),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<int?>(
                      value: _filtroMes,
                      decoration: _financeRelFieldDeco('Mês'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(_mesesAbrev[i]),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filtroMes = v),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dataInicio ?? now,
                        firstDate: DateTime(2010),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (d != null) setState(() => _dataInicio = d);
                    },
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(
                      _dataInicio != null
                          ? 'De: ${_fmtData(_dataInicio!)}'
                          : 'Data inicial',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      side: BorderSide(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dataFim ?? now,
                        firstDate: DateTime(2010),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (d != null) setState(() => _dataFim = d);
                    },
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      _dataFim != null
                          ? 'Até: ${_fmtData(_dataFim!)}'
                          : 'Data final',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      side: BorderSide(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() {
                      _filtroTipo = 'todos';
                      _filtroCategoria = '';
                      _filtroContaId = null;
                      _filtroAno = null;
                      _filtroMes = null;
                      _dataInicio = null;
                      _dataFim = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('Limpar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${filtered.length} lançamento(s) no filtro',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Receitas: R\$ ${sumEnt.toStringAsFixed(2).replaceAll('.', ',')} · '
                      'Despesas: R\$ ${sumSai.toStringAsFixed(2).replaceAll('.', ',')} · '
                      'Saldo: R\$ ${(sumEnt - sumSai).toStringAsFixed(2).replaceAll('.', ',')}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: filtered.isEmpty
                      ? null
                      : () async {
                          await FirebaseAuth.instance.currentUser
                              ?.getIdToken(true);
                          if (!context.mounted) return;
                          await exportFinanceiroRelatorioPdf(
                            context: context,
                            tenantId: widget.tenantId,
                            docs: filtered.map((e) => e.doc).toList(),
                            filterSummaryLines: _pdfFilterLines(),
                            filename: 'financeiro_relatorio_filtrado.pdf',
                          );
                        },
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text(
                    'Gerar PDF Super Premium (filtros atuais)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: filtered.isEmpty
                      ? null
                      : () async {
                          await FirebaseAuth.instance.currentUser
                              ?.getIdToken(true);
                          if (!context.mounted) return;
                          await exportFinanceiroDespesasPorFornecedorPdf(
                            context: context,
                            tenantId: widget.tenantId,
                            docs: filtered.map((e) => e.doc).toList(),
                            filterSummaryLines: _pdfFilterLines(),
                            filename:
                                'financeiro_despesas_por_fornecedor_filtrado.pdf',
                          );
                        },
                  icon: Icon(kFornecedoresModuleIcon),
                  label: const Text(
                    'PDF — despesas por fornecedor (filtros atuais)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeCleanPremium.primary,
                    side: BorderSide(
                      color:
                          ThemeCleanPremium.primary.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Pré-visualização (máx. 80)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nenhum lançamento com os filtros atuais.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                ...filtered.take(80).map((wrap) {
                  final d = wrap.doc;
                  final m = d.data();
                  final tipo = _financeTipoLabel(m);
                  final desc = (m['descricao'] ?? '').toString();
                  final cat = (m['categoria'] ?? '').toString();
                  final ts = _financeDocDate(m);
                  final dataStr = ts != null
                      ? DateFormat('dd/MM/yyyy').format(ts)
                      : '—';
                  final valor = (m['amount'] ?? m['valor'] ?? 0) is num
                      ? (m['amount'] ?? m['valor'] ?? 0) as num
                      : 0.0;
                  final cor = tipo == 'Receita'
                      ? _financeEntradas
                      : tipo == 'Despesa'
                          ? _financeSaidas
                          : _financeTransferencia;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        onTap: () =>
                            widget.onEditLancamento(context, d),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      desc.isEmpty ? '(sem descrição)' : desc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$dataStr · $tipo · $cat',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cor,
                                  fontSize: 14,
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
                }),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

String _financeTipoLabel(Map<String, dynamic> m) {
  final t = (m['type'] ?? '').toString().toLowerCase();
  if (t == 'transferencia') return 'Transferência';
  if (t.contains('entrada') || t.contains('receita')) return 'Receita';
  if (t.contains('saida') || t.contains('despesa') || t.contains('saída')) {
    return 'Despesa';
  }
  return 'Outro';
}

InputDecoration _financeRelFieldDeco(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
    ),
  );
}

class _QueryDocFinance {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  _QueryDocFinance(this.doc);
}

/// Totais de entradas/saídas no mês por conta (inclui transferências como crédito/débito).
class _TotaisContaMesResumo {
  final double receitas;
  final double despesas;
  double get saldo => receitas - despesas;
  const _TotaisContaMesResumo({required this.receitas, required this.despesas});
}

Map<String, _TotaisContaMesResumo> _totaisReceitaDespesaPorContaNoMes(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DateTime mesRef,
) {
  final start = DateTime(mesRef.year, mesRef.month, 1);
  final end = DateTime(mesRef.year, mesRef.month + 1, 0, 23, 59, 59);
  bool inMes(DateTime dt) => !dt.isBefore(start) && !dt.isAfter(end);

  final receitas = <String, double>{};
  final despesas = <String, double>{};

  void addR(String cid, double v) {
    if (cid.isEmpty) return;
    receitas[cid] = (receitas[cid] ?? 0) + v;
  }

  void addD(String cid, double v) {
    if (cid.isEmpty) return;
    despesas[cid] = (despesas[cid] ?? 0) + v;
  }

  for (final d in docs) {
    final data = d.data();
    final dt = _financeLancamentoInstant(data);
    if (!inMes(dt)) continue;
    final tipo = (data['type'] ?? '').toString().toLowerCase();
    final valor = _parseValor(data['amount'] ?? data['valor']);
    if (valor == 0) continue;

    if (tipo == 'transferencia') {
      addR((data['contaDestinoId'] ?? '').toString(), valor);
      addD((data['contaOrigemId'] ?? '').toString(), valor);
    } else if (tipo.contains('entrada') || tipo.contains('receita')) {
      addR(financeContaDestinoReceitaId(data), valor);
    } else if (tipo.contains('saida') ||
        tipo.contains('saída') ||
        tipo.contains('despesa')) {
      addD((data['contaOrigemId'] ?? '').toString(), valor);
    }
  }

  final ids = {...receitas.keys, ...despesas.keys};
  final out = <String, _TotaisContaMesResumo>{};
  for (final id in ids) {
    out[id] = _TotaisContaMesResumo(
      receitas: receitas[id] ?? 0,
      despesas: despesas[id] ?? 0,
    );
  }
  return out;
}

/// Resumo por conta: lista vertical (todas as contas visíveis) + cartão “Resumo geral”; toque abre extrato.
class _FinanceContasResumoStrip extends StatelessWidget {
  final String tenantId;
  final String role;
  final CollectionReference<Map<String, dynamic>> financeCol;
  final VoidCallback onFinanceChanged;

  const _FinanceContasResumoStrip({
    super.key,
    required this.tenantId,
    required this.role,
    required this.financeCol,
    required this.onFinanceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mesRef = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final mesLabel = DateFormat('MMMM yyyy', 'pt_BR').format(mesRef);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        financeCol.orderBy('createdAt', descending: true).get(),
        FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tenantId)
            .collection('contas')
            .orderBy('nome')
            .get(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.circular(8),
              backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.08),
            ),
          );
        }
        final fin = snap.data![0] as QuerySnapshot<Map<String, dynamic>>;
        final contas = snap.data![1] as QuerySnapshot<Map<String, dynamic>>;
        final totais = _totaisReceitaDespesaPorContaNoMes(fin.docs, mesRef);
        final contasAtivas = contas.docs.where((c) => c.data()['ativo'] != false).toList();

        double gReceitas = 0, gDespesas = 0;
        for (final t in totais.values) {
          gReceitas += t.receitas;
          gDespesas += t.despesas;
        }
        final gSaldo = gReceitas - gDespesas;
        final nf = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

        Future<void> openExtrato({String? contaId, required String title}) async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => _MovimentacoesContaPage(
                financeCol: financeCol,
                tenantId: tenantId,
                role: role,
                contaId: contaId,
                title: title,
                extratoMes: mesRef,
                onEdit: (ctx, doc) async {
                  await showFinanceLancamentoEditorForTenant(
                    ctx,
                    tenantId: tenantId,
                    existingDoc: doc,
                    panelRole: role,
                  );
                },
              ),
            ),
          );
          onFinanceChanged();
        }

        final deep = Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.38)!;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary.withValues(alpha: 0.2),
                          ThemeCleanPremium.primary.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.dashboard_customize_rounded,
                        size: 20, color: ThemeCleanPremium.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Visão por conta · $mesLabel',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.25,
                          ),
                        ),
                        Text(
                          'Todas as contas visíveis — toque para abrir o extrato',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => openExtrato(
                    contaId: null,
                    title: 'Resumo geral · $mesLabel',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ThemeCleanPremium.primary,
                          deep,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                        ...ThemeCleanPremium.softUiCardShadow,
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.summarize_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Resumo geral (todas as contas)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: -0.2,
                                  color: Colors.white.withValues(alpha: 0.98),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  _stripInlineLight(
                                    'Receitas',
                                    nf.format(gReceitas),
                                    valueColor: const Color(0xFFBBF7D0),
                                  ),
                                  _stripInlineLight(
                                    'Despesas',
                                    nf.format(gDespesas),
                                    valueColor: const Color(0xFFFECDD3),
                                  ),
                                  _stripInlineLight(
                                    'Saldo',
                                    nf.format(gSaldo),
                                    strong: true,
                                    valueColor: gSaldo >= 0
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFFFCA5A5),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.open_in_new_rounded,
                            size: 20, color: Colors.white.withValues(alpha: 0.85)),
                      ],
                    ),
                  ),
                ),
              ),
              if (contasAtivas.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        size: 18, color: ThemeCleanPremium.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Contas (${contasAtivas.length})',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              for (final c in contasAtivas) ...[
                Builder(
                  builder: (context) {
                    final id = c.id;
                    final contaData = c.data();
                    final nome = _financeContaDisplayName(contaData);
                    final bancoNome = _financeContaBancoNome(contaData);
                    final tipoConta =
                        _financeTipoContaLabel(contaData['tipoConta']?.toString());
                    final contaAccent = _financeContaBancoColor(contaData);
                    final t = totais[id] ??
                        const _TotaisContaMesResumo(receitas: 0, despesas: 0);
                    final saldoCor = t.saldo >= 0
                        ? _financeSaldoPositivo
                        : _financeSaldoNegativo;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => openExtrato(
                            contaId: id,
                            title: '$nome · $mesLabel',
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.12),
                              ),
                              boxShadow: [
                                ...ThemeCleanPremium.softUiCardShadow,
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 18,
                                  spreadRadius: -4,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              // [Row] + [CrossAxisAlignment.stretch] dentro de [Column] com altura
                              // ilimitada (scroll) zera a altura dos cartões — [IntrinsicHeight] fixa.
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
                                          colors: [
                                            contaAccent,
                                            Color.lerp(contaAccent, deep, 0.45)!,
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            14, 14, 12, 14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    nome,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 15,
                                                      letterSpacing: -0.35,
                                                      height: 1.15,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Flexible(
                                                  child: Text(
                                                    nf.format(t.saldo),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.right,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 16,
                                                      letterSpacing: -0.45,
                                                      color: saldoCor,
                                                    ),
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: Colors.grey.shade400,
                                                  size: 22,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '$bancoNome · $tipoConta',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600,
                                                letterSpacing: -0.08,
                                              ),
                                            ),
                                            if (t.receitas > 0 ||
                                                t.despesas > 0) ...[
                                              const SizedBox(height: 10),
                                              _FinanceContasResumoStrip
                                                  ._fluxoReceitaDespesaMiniBar(
                                                t.receitas,
                                                t.despesas,
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
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Barra fina Receitas vs Despesas no mês (visual premium; o saldo fica na linha de cima).
  static Widget _fluxoReceitaDespesaMiniBar(double receitas, double despesas) {
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
              child: ColoredBox(
                color: _financeEntradas.withValues(alpha: 0.9),
              ),
            ),
            Expanded(
              flex: b,
              child: ColoredBox(
                color: _financeSaidas.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Totais no cartão “Resumo geral” (fundo gradiente escuro).
  static Widget _stripInlineLight(
    String k,
    String v, {
    bool strong = false,
    Color? valueColor,
  }) {
    final vc = valueColor ?? Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$k: ',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: strong ? 14 : 12.5,
            fontWeight: FontWeight.w900,
            color: vc,
            letterSpacing: -0.25,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — Resumo (gráficos + totalizadores)
// ═══════════════════════════════════════════════════════════════════════════════
class _ResumoTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;
  final int financeRevision;
  final VoidCallback onFinanceChanged;

  const _ResumoTab({
    super.key,
    required this.financeCol,
    required this.tenantId,
    required this.role,
    required this.financeRevision,
    required this.onFinanceChanged,
  });

  @override
  State<_ResumoTab> createState() => _ResumoTabState();
}

class _ResumoTabState extends State<_ResumoTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  late Future<QuerySnapshot<Map<String, dynamic>>> _futureContas;
  late Future<FinanceTenantSettings> _futureSettings;
  String _periodFilter = 'mes_atual';
  DateTime? _periodStart;
  DateTime? _periodEnd;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);
  static DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _endOfMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 0, 23, 59, 59);
  static DateTime _startOfYear(DateTime d) => DateTime(d.year, 1, 1);
  static DateTime _endOfYear(DateTime d) =>
      DateTime(d.year, 12, 31, 23, 59, 59);

  /// Fim do intervalo do filtro atual — usado para saldo cumulativo por conta (até essa data).
  DateTime _periodEndForSaldo() {
    final now = DateTime.now();
    switch (_periodFilter) {
      case 'mes_anterior':
        return _endOfMonth(DateTime(now.year, now.month - 1));
      case 'mes_atual':
        return _endOfMonth(now);
      case 'diario':
        return _endOfDay(now);
      case 'semanal':
        return _endOfDay(now);
      case 'anual':
        return _endOfYear(now);
      case 'periodo':
        if (_periodStart != null && _periodEnd != null) {
          return _endOfDay(_periodEnd!);
        }
        return _endOfMonth(now);
      default:
        return _endOfMonth(now);
    }
  }

  bool _inRange(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    switch (_periodFilter) {
      case 'mes_anterior':
        final prev = DateTime(now.year, now.month - 1);
        return !dt.isBefore(_startOfMonth(prev)) &&
            !dt.isAfter(_endOfMonth(prev));
      case 'mes_atual':
        return !dt.isBefore(_startOfMonth(now)) &&
            !dt.isAfter(_endOfMonth(now));
      case 'diario':
        return !dt.isBefore(_startOfDay(now)) && !dt.isAfter(_endOfDay(now));
      case 'semanal':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return !dt.isBefore(_startOfDay(weekStart)) &&
            !dt.isAfter(_endOfDay(now));
      case 'anual':
        return !dt.isBefore(_startOfYear(now)) && !dt.isAfter(_endOfYear(now));
      case 'periodo':
        if (_periodStart != null && _periodEnd != null) {
          return !dt.isBefore(_startOfDay(_periodStart!)) &&
              !dt.isAfter(_endOfDay(_periodEnd!));
        }
        return true;
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = widget.financeCol.orderBy('createdAt', descending: true).get();
    _futureContas = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('contas')
        .orderBy('nome')
        .get();
    _futureSettings = FinanceTenantSettings.load(widget.tenantId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.financeCol.orderBy('createdAt', descending: true).get();
      _futureContas = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas')
          .orderBy('nome')
          .get();
      _futureSettings = FinanceTenantSettings.load(widget.tenantId);
    });
  }

  Widget _buildPieChart(List<MapEntry<String, double>> entries, double total,
      List<Color> cores, String title) {
    if (entries.isEmpty || total <= 0) {
      return _ChartCard(
        title: title,
        icon: Icons.pie_chart_rounded,
        child: SizedBox(
            height: 180,
            child: Center(
                child: Text('Sem dados para o período.',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)))),
      );
    }
    final sections = entries.asMap().entries.map((e) {
      final pct = e.value.value / total;
      return PieChartSectionData(
        value: pct,
        title: '',
        color: cores[e.key % cores.length],
        radius: 60,
        titleStyle: const TextStyle(fontSize: 0),
      );
    }).toList();
    return _ChartCard(
      title: title,
      icon: Icons.pie_chart_rounded,
      child: SizedBox(
        height: 220,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                            .format(total),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text('Total',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    ...entries.take(6).toList().asMap().entries.map((ie) {
                      final e = ie.value;
                      final idx = ie.key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: cores[idx % cores.length],
                                    borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(
                                    '${e.key}: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(e.value)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            ThemeCleanPremium.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 180,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    sectionsSpace: 3,
                    centerSpaceRadius: 36,
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 400),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_future, _futureContas, _futureSettings]),
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar o resumo financeiro',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final financeSnap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final contasSnap = snap.data != null && snap.data!.length > 1
            ? snap.data![1] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final settings = snap.data != null && snap.data!.length > 2
            ? snap.data![2] as FinanceTenantSettings
            : const FinanceTenantSettings();
        final allDocs = financeSnap?.docs ?? [];
        final docs = allDocs.where((d) {
          final dt = _parseDate(d.data()['createdAt'] ?? d.data()['date']);
          return _inRange(dt);
        }).toList();
        final contasDocs = contasSnap?.docs ?? [];
        double totalReceitas = 0, totalDespesas = 0;
        final entradasMes = <int, double>{};
        final saidasMes = <int, double>{};
        final now = DateTime.now();

        final receitasPorCat = <String, double>{};
        final despesasPorCat = <String, double>{};
        for (final d in docs) {
          final data = d.data();
          final tipo = (data['type'] ?? 'entrada').toString().toLowerCase();
          if (tipo == 'transferencia') continue;
          if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
          final valor = _parseValor(data['amount'] ?? data['valor']);
          final dt = _parseDate(data['createdAt'] ?? data['date']);
          final cat = (data['categoria'] ?? 'Outros').toString().trim();
          final catKey = cat.isEmpty ? 'Outros' : cat;
          final isEntrada =
              tipo.contains('entrada') || tipo.contains('receita');

          if (isEntrada) {
            totalReceitas += valor;
            receitasPorCat[catKey] = (receitasPorCat[catKey] ?? 0) + valor;
          } else {
            totalDespesas += valor;
            despesasPorCat[catKey] = (despesasPorCat[catKey] ?? 0) + valor;
          }

          if (dt.year == now.year) {
            if (isEntrada) {
              entradasMes[dt.month] = (entradasMes[dt.month] ?? 0) + valor;
            } else {
              saidasMes[dt.month] = (saidasMes[dt.month] ?? 0) + valor;
            }
          }
        }

        final saldo = totalReceitas - totalDespesas;

        double aReceberPendente = 0, aPagarPendente = 0;
        for (final d in docs) {
          final data = d.data();
          final tipo = (data['type'] ?? 'entrada').toString().toLowerCase();
          if (tipo == 'transferencia') continue;
          final valor = _parseValor(data['amount'] ?? data['valor']);
          if (financeLancamentoPendenteRecebimento(data)) {
            aReceberPendente += valor;
          }
          if (financeLancamentoPendentePagamento(data)) {
            aPagarPendente += valor;
          }
        }
        final fluxoPrevistoResumo = saldo + aReceberPendente - aPagarPendente;

        // Saldo por conta até o fim do período filtrado (inclui saldo arrastado dos meses anteriores).
        final periodEndSaldo = _periodEndForSaldo();
        final idsAtivos = <String>{};
        for (final c in contasDocs) {
          if (c.data()['ativo'] == false) continue;
          idsAtivos.add(c.id);
        }
        final saldoPorConta = financeSaldoPorContaAteInclusive(
          contaIdsAtivas: idsAtivos,
          lancamentos: allDocs.map((d) => d.data()),
          ateInclusive: periodEndSaldo,
        );

        final saldoTotalContas =
            saldoPorConta.values.fold(0.0, (a, b) => a + b);
        final cutoff30 = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 30));
        double net30 = 0;
        for (final d in allDocs) {
          final data = d.data();
          final tipo = (data['type'] ?? 'entrada').toString().toLowerCase();
          if (tipo == 'transferencia') continue;
          if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
          final dt = _parseDate(data['createdAt'] ?? data['date']);
          final day = DateTime(dt.year, dt.month, dt.day);
          if (day.isBefore(cutoff30)) {
            continue;
          }
          final valor = _parseValor(data['amount'] ?? data['valor']);
          final isEntrada =
              tipo.contains('entrada') || tipo.contains('receita');
          if (isEntrada) {
            net30 += valor;
          } else {
            net30 -= valor;
          }
        }
        final previsao30 = saldoTotalContas + net30;

        final orcamentoAlerts = <({String cat, double gasto, double teto, double pct})>[];
        for (final e in settings.orcamentosDespesa.entries) {
          if (e.value <= 0) continue;
          final gasto = despesasPorCat[e.key] ?? 0;
          final pct = e.value > 0 ? gasto / e.value : 0.0;
          orcamentoAlerts
              .add((cat: e.key, gasto: gasto, teto: e.value, pct: pct));
        }
        orcamentoAlerts.sort((a, b) => b.pct.compareTo(a.pct));

        final canMetas =
            AppPermissions.canManageFinanceTenantSettings(widget.role);

        final contasAtivas =
            contasDocs.where((c) => c.data()['ativo'] != false).toList();

        final padH = ThemeCleanPremium.isNarrow(context) ? 10.0 : ThemeCleanPremium.spaceLg;
        return SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.symmetric(
              horizontal: padH, vertical: ThemeCleanPremium.spaceXl),
          child: Column(
            children: [
              _FinanceContasResumoStrip(
                key: ValueKey(
                    'fin_strip_${widget.tenantId}_${widget.financeRevision}'),
                tenantId: widget.tenantId,
                role: widget.role,
                financeCol: widget.financeCol,
                onFinanceChanged: widget.onFinanceChanged,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              // Filtros por período
              SingleChildScrollView(
                primary: false,
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                child: Row(
                  children: [
                    _FilterChipPeriod(
                      label: 'Mês anterior',
                      selected: _periodFilter == 'mes_anterior',
                      onTap: () =>
                          setState(() => _periodFilter = 'mes_anterior'),
                    ),
                    const SizedBox(width: 10),
                    _FilterChipPeriod(
                      label: 'Mês atual',
                      selected: _periodFilter == 'mes_atual',
                      onTap: () => setState(() => _periodFilter = 'mes_atual'),
                    ),
                    const SizedBox(width: 10),
                    _FilterChipPeriod(
                      label: 'Diário',
                      selected: _periodFilter == 'diario',
                      onTap: () => setState(() => _periodFilter = 'diario'),
                    ),
                    const SizedBox(width: 10),
                    _FilterChipPeriod(
                      label: 'Semanal',
                      selected: _periodFilter == 'semanal',
                      onTap: () => setState(() => _periodFilter = 'semanal'),
                    ),
                    const SizedBox(width: 10),
                    _FilterChipPeriod(
                      label: 'Anual',
                      selected: _periodFilter == 'anual',
                      onTap: () => setState(() => _periodFilter = 'anual'),
                    ),
                    const SizedBox(width: 10),
                    _FilterChipPeriod(
                      label: _periodFilter == 'periodo' &&
                              _periodStart != null &&
                              _periodEnd != null
                          ? '${_periodStart!.day}/${_periodStart!.month} - ${_periodEnd!.day}/${_periodEnd!.month}'
                          : 'Por período',
                      selected: _periodFilter == 'periodo',
                      onTap: () async {
                        final start = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (start == null || !mounted) return;
                        final end = await showDatePicker(
                          context: context,
                          initialDate: start,
                          firstDate: start,
                          lastDate: DateTime(2035),
                        );
                        if (mounted && end != null)
                          setState(() {
                            _periodFilter = 'periodo';
                            _periodStart = start;
                            _periodEnd = end;
                          });
                      },
                    ),
                  ],
                ),
              ),
              // Totalizadores (Receitas e Despesas clicáveis → lista com editar/remover/comprovantes)
              LayoutBuilder(builder: (context, c) {
                final narrow = c.maxWidth < 500;
                final cardReceitas = _TotalizadorCard(
                  label: 'Receitas',
                  valor: totalReceitas,
                  icon: Icons.trending_up_rounded,
                  color: _financeEntradas,
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ListaLancamentosPorTipoPage(
                          financeCol: widget.financeCol,
                          tenantId: widget.tenantId,
                          role: widget.role,
                          tipo: 'entrada',
                          titulo: 'Receitas',
                          onEdit: (ctx, doc) async {
                            await showFinanceLancamentoEditorForTenant(ctx,
                                tenantId: widget.tenantId,
                                existingDoc: doc,
                                panelRole: widget.role);
                          },
                        ),
                      ),
                    );
                    if (mounted) _refresh();
                  },
                );
                final cardDespesas = _TotalizadorCard(
                  label: 'Despesas',
                  valor: totalDespesas,
                  icon: Icons.trending_down_rounded,
                  color: _financeSaidas,
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ListaLancamentosPorTipoPage(
                          financeCol: widget.financeCol,
                          tenantId: widget.tenantId,
                          role: widget.role,
                          tipo: 'saida',
                          titulo: 'Despesas',
                          onEdit: (ctx, doc) async {
                            await showFinanceLancamentoEditorForTenant(ctx,
                                tenantId: widget.tenantId,
                                existingDoc: doc,
                                panelRole: widget.role);
                          },
                        ),
                      ),
                    );
                    if (mounted) _refresh();
                  },
                );
                final cardSaldo = _TotalizadorCard(
                    label: 'Saldo',
                    valor: saldo,
                    icon: Icons.account_balance_rounded,
                    color: saldo >= 0
                        ? _financeSaldoPositivo
                        : _financeSaldoNegativo);
                final cards = [cardReceitas, cardDespesas, cardSaldo];
                if (narrow) {
                  return Column(children: [
                    for (final c in cards) ...[c, const SizedBox(height: 12)],
                  ]);
                }
                return Row(children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ]);
              }),
              if (canMetas ||
                  settings.limiteAprovacaoDespesa > 0 ||
                  orcamentoAlerts.isNotEmpty) ...[
                SizedBox(height: ThemeCleanPremium.spaceMd),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Orçamento e metas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (canMetas)
                      TextButton.icon(
                        onPressed: () async {
                          await showFinanceTenantMetasEditor(
                            context,
                            tenantId: widget.tenantId,
                            initial: settings,
                          );
                          if (mounted) {
                            _refresh();
                          }
                        },
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Configurar'),
                      ),
                  ],
                ),
                if (settings.limiteAprovacaoDespesa > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Despesas acima de ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(settings.limiteAprovacaoDespesa)} podem exigir segunda aprovação.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                for (final a in orcamentoAlerts) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.cat,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${(a.pct * 100).clamp(0, 999).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: a.pct >= 1.0
                                    ? const Color(0xFFB91C1C)
                                    : (a.pct >= 0.8
                                        ? const Color(0xFFCA8A04)
                                        : Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: a.pct > 1 ? 1.0 : a.pct,
                            backgroundColor: Colors.grey.shade200,
                            color: a.pct >= 1.0
                                ? const Color(0xFFFCA5A5)
                                : (a.pct >= 0.8
                                    ? const Color(0xFFFDE047)
                                    : ThemeCleanPremium.primary
                                        .withValues(alpha: 0.55)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gasto no período: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(a.gasto)} · Teto: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(a.teto)}',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        if (a.pct >= 1.0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Orçamento ultrapassado para esta categoria.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade800,
                              ),
                            ),
                          )
                        else if (a.pct >= 0.8)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Atenção: próximo do limite.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Material(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    onTap: null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        border: Border.all(
                          color:
                              ThemeCleanPremium.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_graph_rounded,
                                  size: 20, color: ThemeCleanPremium.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Projeção de caixa (30 dias)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Saldo atual nas contas + resultado líquido dos últimos 30 dias.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              Text(
                                'Saldo nas contas: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(saldoTotalContas)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text(
                                'Líquido 30 dias: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(net30)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text(
                                'Projeção: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(previsao30)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: previsao30 >= 0
                                      ? const Color(0xFF0D9488)
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
              ),
              if (aReceberPendente > 0.009 || aPagarPendente > 0.009) ...[
                SizedBox(height: ThemeCleanPremium.spaceMd),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Previsão (em aberto no período)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Receitas não confirmadas e despesas não pagas.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  Widget wArec = _TotalizadorCard(
                    label: 'A receber',
                    valor: aReceberPendente,
                    icon: Icons.schedule_send_rounded,
                    color: const Color(0xFF0891B2),
                  );
                  Widget wApag = _TotalizadorCard(
                    label: 'A pagar',
                    valor: aPagarPendente,
                    icon: Icons.pending_actions_rounded,
                    color: const Color(0xFFEA580C),
                  );
                  Widget wFluxo = _TotalizadorCard(
                    label: 'Saldo + previsão',
                    valor: fluxoPrevistoResumo,
                    icon: Icons.insights_rounded,
                    color: fluxoPrevistoResumo >= 0
                        ? const Color(0xFF0D9488)
                        : const Color(0xFFB91C1C),
                  );
                  if (narrow) {
                    return Column(
                      children: [
                        wArec,
                        const SizedBox(height: 12),
                        wApag,
                        const SizedBox(height: 12),
                        wFluxo,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: wArec),
                      const SizedBox(width: 12),
                      Expanded(child: wApag),
                      const SizedBox(width: 12),
                      Expanded(child: wFluxo),
                    ],
                  );
                }),
              ],
              SizedBox(height: ThemeCleanPremium.spaceLg),
              // Gráfico de barras Receitas x Despesas
              _ChartCard(
                title: 'Receitas x Despesas por Mês',
                child: SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      barGroups: List.generate(12, (i) {
                        final m = i + 1;
                        return BarChartGroupData(x: m, barRods: [
                          BarChartRodData(
                              toY: entradasMes[m] ?? 0,
                              color: _financeEntradas,
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4))),
                          BarChartRodData(
                              toY: saidasMes[m] ?? 0,
                              color: _financeSaidas,
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4))),
                        ]);
                      }),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                              color: Colors.grey.shade200, strokeWidth: 1)),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 50,
                                getTitlesWidget: (v, _) => Text(
                                    'R\$${v.toInt()}',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600)))),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final i = v.toInt();
                                  if (i >= 1 && i <= 12)
                                    return Text(_mesesAbrev[i - 1],
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600));
                                  return const SizedBox();
                                })),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Legenda
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(color: _financeEntradas, label: 'Receitas'),
                  const SizedBox(width: 20),
                  _LegendDot(color: _financeSaidas, label: 'Despesas'),
                ],
              ),
              // Gráficos pizza — Receitas e Despesas por categoria
              SizedBox(height: ThemeCleanPremium.spaceLg + 4),
              LayoutBuilder(builder: (ctx, c) {
                final narrow = c.maxWidth < 500;
                final coresReceita = [
                  _financeEntradas,
                  const Color(0xFF3B82F6),
                  const Color(0xFF60A5FA),
                  const Color(0xFF93C5FD),
                  const Color(0xFF1D4ED8),
                  const Color(0xFF1E40AF)
                ];
                final coresDespesa = [
                  const Color(0xFFDC2626),
                  const Color(0xFFEA580C),
                  const Color(0xFFE11D48),
                  const Color(0xFFF87171),
                  const Color(0xFFB91C1C),
                  const Color(0xFF991B1B)
                ];
                final receitaEntries = receitasPorCat.entries
                    .where((e) => e.value > 0)
                    .toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final despesaEntries = despesasPorCat.entries
                    .where((e) => e.value > 0)
                    .toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                Widget pieReceitas = _buildPieChart(receitaEntries,
                    totalReceitas, coresReceita, 'Receitas por categoria');
                Widget pieDespesas = _buildPieChart(despesaEntries,
                    totalDespesas, coresDespesa, 'Despesas por categoria');

                if (narrow) {
                  return Column(
                    children: [
                      pieReceitas,
                      const SizedBox(height: 20),
                      pieDespesas,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pieReceitas),
                    const SizedBox(width: 16),
                    Expanded(child: pieDespesas),
                  ],
                );
              }),
              // Saldos das contas (clicável → movimentações)
              if (contasAtivas.isNotEmpty) ...[
                SizedBox(height: ThemeCleanPremium.spaceLg + 4),
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: ThemeCleanPremium.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        child: Icon(Icons.account_balance_wallet_rounded,
                            size: 20, color: ThemeCleanPremium.primary),
                      ),
                      const SizedBox(width: 12),
                      Text('Saldos das contas',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurface,
                              letterSpacing: -0.2)),
                    ],
                  ),
                ),
                LayoutBuilder(builder: (context, cx) {
                  final narrow = cx.maxWidth < 400;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: contasAtivas.map((c) {
                      final id = c.id;
                      final nome = _financeContaDisplayName(c.data());
                      final saldoConta = saldoPorConta[id] ?? 0.0;
                      return SizedBox(
                        width: narrow ? double.infinity : 180,
                        child: _ContaSaldoCard(
                          nome: nome,
                          saldo: saldoConta,
                          onTap: () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _MovimentacoesContaPage(
                                  financeCol: widget.financeCol,
                                  tenantId: widget.tenantId,
                                  role: widget.role,
                                  contaId: id,
                                  title: nome,
                                  extratoMes: null,
                                  onEdit: (ctx, doc) async {
                                    await showFinanceLancamentoEditorForTenant(
                                        ctx,
                                        tenantId: widget.tenantId,
                                        existingDoc: doc,
                                        panelRole: widget.role);
                                  },
                                ),
                              ),
                            );
                            if (mounted) _refresh();
                          },
                        ),
                      );
                    }).toList(),
                  );
                }),
              ],
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Card de saldo da conta (Resumo) — clicável para ver movimentações
// ═══════════════════════════════════════════════════════════════════════════════
class _ContaSaldoCard extends StatelessWidget {
  final String nome;
  final double saldo;
  final VoidCallback onTap;

  const _ContaSaldoCard(
      {required this.nome, required this.saldo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cor = saldo >= 0 ? _financeSaldoPositivo : _financeSaldoNegativo;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
            boxShadow: [
              ...ThemeCleanPremium.softUiCardShadow,
              BoxShadow(
                  color: cor.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
            border: Border.all(color: cor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: cor.withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                child:
                    Icon(Icons.account_balance_rounded, color: cor, size: 24),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nome,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('R\$ ${saldo.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cor)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Movimentações da conta: receitas (conta destino), despesas (conta origem) e transferências.
// ═══════════════════════════════════════════════════════════════════════════════

bool _financeLancamentoEnvolveConta(Map<String, dynamic> data, String contaId) {
  if (contaId.isEmpty) return false;
  final origem = (data['contaOrigemId'] ?? '').toString();
  final destino = (data['contaDestinoId'] ?? '').toString();
  final tipo = (data['type'] ?? 'entrada').toString().toLowerCase();
  if (tipo == 'transferencia') {
    return origem == contaId || destino == contaId;
  }
  if (tipo.contains('entrada') || tipo.contains('receita')) {
    return financeContaDestinoReceitaId(data) == contaId;
  }
  if (tipo.contains('saida') ||
      tipo.contains('saída') ||
      tipo.contains('despesa')) {
    return origem == contaId;
  }
  return origem == contaId || destino == contaId;
}

class _MovimentacoesContaPage extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;
  /// Uma conta específica, ou `null` para todas (extrato geral).
  final String? contaId;
  final String title;
  /// Se não nulo, restringe ao mês civil (extrato mensal).
  final DateTime? extratoMes;
  final Future<void> Function(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) onEdit;

  const _MovimentacoesContaPage({
    required this.financeCol,
    required this.tenantId,
    required this.role,
    required this.contaId,
    required this.title,
    this.extratoMes,
    required this.onEdit,
  });

  @override
  State<_MovimentacoesContaPage> createState() =>
      _MovimentacoesContaPageState();
}

class _MovimentacoesContaPageState extends State<_MovimentacoesContaPage> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.financeCol.orderBy('createdAt', descending: true).get();
  }

  void _refresh() {
    setState(() {
      _future = widget.financeCol.orderBy('createdAt', descending: true).get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title,
            style: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: -0.2)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
                minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget))),
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ChurchPanelErrorBody(
              title: 'Não foi possível carregar os lançamentos',
              error: snap.error,
              onRetry: _refresh,
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const ChurchPanelLoadingBody();
          }
          var docs = snap.data?.docs ?? [];
          docs = docs.where((d) {
            final data = d.data();
            if (widget.extratoMes != null) {
              final t = _financeLancamentoInstant(data);
              if (t.year != widget.extratoMes!.year ||
                  t.month != widget.extratoMes!.month) {
                return false;
              }
            }
            final cid = widget.contaId;
            if (cid != null && cid.isNotEmpty) {
              return _financeLancamentoEnvolveConta(data, cid);
            }
            return true;
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_rounded,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text('Nenhum lançamento nesta conta.',
                      style:
                          TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Receitas, despesas e transferências vinculadas a esta conta aparecem aqui. Toque em um lançamento para ver detalhes; use editar, excluir ou o ícone de comprovante para trocar o arquivo.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
                    ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 4),
                child: Text('${docs.length} movimentação(ões)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                    await _future;
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceLg,
                        80),
                    itemCount: docs.length,
                    itemBuilder: (context, i) => _LancamentoCard(
                      doc: docs[i],
                      tenantId: widget.tenantId,
                      role: widget.role,
                      onEdit: () async {
                        await widget.onEdit(context, docs[i]);
                        if (mounted) _refresh();
                      },
                      onDelete: () => _excluirLancamento(docs[i]),
                      onApprove: () async {
                        try {
                          await FirebaseAuth.instance.currentUser
                              ?.getIdToken(true);
                          await docs[i].reference.update({
                            'aprovacaoPendente': false,
                            'aprovadoPorUid':
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                            'aprovadoEm': FieldValue.serverTimestamp(),
                          });
                          if (mounted) _refresh();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro: $e')));
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _excluirLancamento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Excluir lançamento',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content:
            const Text('Tem certeza que deseja excluir este lançamento?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _excluirLancamentoComAuditoria(doc, widget.tenantId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lançamento excluído.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
      _refresh();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Lista de Receitas ou Despesas (ao clicar no card no Resumo) — editar, remover, comprovantes
// ═══════════════════════════════════════════════════════════════════════════════
class _ListaLancamentosPorTipoPage extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;
  final String tipo;
  final String titulo;
  final Future<void> Function(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) onEdit;

  const _ListaLancamentosPorTipoPage({
    required this.financeCol,
    required this.tenantId,
    required this.role,
    required this.tipo,
    required this.titulo,
    required this.onEdit,
  });

  @override
  State<_ListaLancamentosPorTipoPage> createState() =>
      _ListaLancamentosPorTipoPageState();
}

class _ListaLancamentosPorTipoPageState
    extends State<_ListaLancamentosPorTipoPage> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.financeCol.orderBy('createdAt', descending: true).get();
  }

  void _refresh() {
    setState(() {
      _future = widget.financeCol.orderBy('createdAt', descending: true).get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            widget.tipo == 'entrada' ? _financeEntradas : _financeSaidas,
        foregroundColor: Colors.white,
        title: Text(widget.titulo,
            style: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: -0.2)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
                minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget))),
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ChurchPanelErrorBody(
              title: 'Não foi possível carregar os lançamentos',
              error: snap.error,
              onRetry: _refresh,
            );
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const ChurchPanelLoadingBody();
          }
          var docs = snap.data?.docs ?? [];
          docs = docs.where((d) {
            final t = (d.data()['type'] ?? '').toString().toLowerCase();
            if (widget.tipo == 'entrada')
              return t.contains('entrada') || t.contains('receita');
            return t.contains('saida') || t.contains('despesa');
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      widget.tipo == 'entrada'
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 64,
                      color: Colors.grey.shade400),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text('Nenhuma ${widget.titulo.toLowerCase()} encontrada.',
                      style:
                          TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          final rows = _buildLancamentosGroupedByDay(docs);

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
                    ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 4),
                child: Text('${docs.length} lançamento(s)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700)),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                    await _future;
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceLg,
                        80),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      if (row.isHeader) {
                        return _FinanceDayHeaderTile(day: row.day!);
                      }
                      final doc = row.doc!;
                      return _LancamentoCard(
                        doc: doc,
                        tenantId: widget.tenantId,
                        role: widget.role,
                        onEdit: () async {
                          await widget.onEdit(context, doc);
                          if (mounted) _refresh();
                        },
                        onDelete: () => _excluirLancamento(doc),
                        onApprove: () async {
                          try {
                            await FirebaseAuth.instance.currentUser
                                ?.getIdToken(true);
                            await doc.reference.update({
                              'aprovacaoPendente': false,
                              'aprovadoPorUid':
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                              'aprovadoEm': FieldValue.serverTimestamp(),
                            });
                            if (mounted) _refresh();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erro: $e')));
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _excluirLancamento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Excluir lançamento',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
            'Tem certeza que deseja excluir este lançamento? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _excluirLancamentoComAuditoria(doc, widget.tenantId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lançamento excluído.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
      _refresh();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — Lançamentos (lista completa com edição, exclusão, comprovantes)
// ═══════════════════════════════════════════════════════════════════════════════
class _LancamentosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;
  final VoidCallback? onFinanceChanged;

  const _LancamentosTab({
    super.key,
    required this.financeCol,
    required this.tenantId,
    required this.role,
    this.onFinanceChanged,
  });

  @override
  State<_LancamentosTab> createState() => _LancamentosTabState();
}

class _LancamentosTabState extends State<_LancamentosTab> {
  String _filtroTipo = 'todos';
  String _filtroCategoria = 'todas';
  /// todos | pendente_aprovacao | nao_conciliados | a_pagar | pagos | a_receber | recebidos | futuras_despesas | futuras_receitas
  String _filtroExtra = 'todos';
  /// `__geral__` ou id da conta em `contas`.
  String _filtroContaId = '__geral__';
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  late Future<QuerySnapshot<Map<String, dynamic>>> _futureContas;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = widget.financeCol.orderBy('createdAt', descending: true).get();
    _futureContas = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('contas')
        .orderBy('nome')
        .get();
  }

  void _refresh() {
    setState(() {
      _future = widget.financeCol.orderBy('createdAt', descending: true).get();
      _futureContas = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas')
          .orderBy('nome')
          .get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_future, _futureContas]),
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os lançamentos',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final financeSnap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final contasSnap = snap.data != null && snap.data!.length > 1
            ? snap.data![1] as QuerySnapshot<Map<String, dynamic>>
            : null;
        var docs = financeSnap?.docs ?? [];
        final contasAtivasDocs = (contasSnap?.docs ?? [])
            .where((c) => c.data()['ativo'] != false)
            .toList();

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ThemeCleanPremium.cardBackground,
                      ThemeCleanPremium.primary.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusXl),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.15),
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            ThemeCleanPremium.primary.withValues(alpha: 0.14),
                            ThemeCleanPremium.primary.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                          color:
                              ThemeCleanPremium.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(Icons.receipt_long_rounded,
                          size: 44, color: ThemeCleanPremium.primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Nenhum lançamento ainda',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use o botão Lançamento Rápido para registrar receitas, despesas ou transferências.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Filtros
        if (_filtroTipo != 'todos') {
          docs = docs.where((d) {
            final tipo = (d.data()['type'] ?? '').toString().toLowerCase();
            if (_filtroTipo == 'entrada') {
              return tipo.contains('entrada') || tipo.contains('receita');
            }
            return tipo.contains('saida') || tipo.contains('despesa');
          }).toList();
        }
        if (_filtroContaId != '__geral__' && _filtroContaId.isNotEmpty) {
          docs = docs
              .where((d) =>
                  _financeLancamentoEnvolveConta(d.data(), _filtroContaId))
              .toList();
        }
        final docsPorTipo = docs;
        final distinctCats = docsPorTipo
            .map((d) => (d.data()['categoria'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (_filtroCategoria != 'todas') {
          docs = docs
              .where((d) => (d.data()['categoria'] ?? '') == _filtroCategoria)
              .toList();
        }
        if (_filtroExtra == 'pendente_aprovacao') {
          docs = docs
              .where((d) => d.data()['aprovacaoPendente'] == true)
              .toList();
        } else if (_filtroExtra == 'nao_conciliados') {
          docs = docs.where((d) {
            final tipo = (d.data()['type'] ?? '').toString().toLowerCase();
            if (tipo == 'transferencia') return false;
            return d.data()['conciliado'] != true;
          }).toList();
        } else if (_filtroExtra == 'a_pagar') {
          docs = docs
              .where((d) => financeLancamentoPendentePagamento(d.data()))
              .toList();
        } else if (_filtroExtra == 'pagos') {
          docs = docs.where((d) {
            final data = d.data();
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (tipo == 'transferencia') return false;
            if (!tipo.contains('saida') && !tipo.contains('despesa')) {
              return false;
            }
            return !financeLancamentoPendentePagamento(data);
          }).toList();
        } else if (_filtroExtra == 'a_receber') {
          docs = docs
              .where((d) => financeLancamentoPendenteRecebimento(d.data()))
              .toList();
        } else if (_filtroExtra == 'recebidos') {
          docs = docs.where((d) {
            final data = d.data();
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (tipo == 'transferencia') return false;
            if (!tipo.contains('entrada') && !tipo.contains('receita')) {
              return false;
            }
            return !financeLancamentoPendenteRecebimento(data);
          }).toList();
        } else if (_filtroExtra == 'futuras_despesas') {
          final hoje =
              DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          docs = docs.where((d) {
            final data = d.data();
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (!tipo.contains('saida') && !tipo.contains('despesa')) {
              return false;
            }
            if (!financeLancamentoPendentePagamento(data)) return false;
            final dia = _financeLancamentoDiaSomente(data);
            return dia.isAfter(hoje);
          }).toList();
        } else if (_filtroExtra == 'futuras_receitas') {
          final hoje =
              DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          docs = docs.where((d) {
            final data = d.data();
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (!tipo.contains('entrada') && !tipo.contains('receita')) {
              return false;
            }
            if (!financeLancamentoPendenteRecebimento(data)) return false;
            final dia = _financeLancamentoDiaSomente(data);
            return dia.isAfter(hoje);
          }).toList();
        }

        final rows = _buildLancamentosGroupedByDay(docs);

        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _future;
          },
          child: CustomScrollView(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceLg,
                  vertical: ThemeCleanPremium.spaceSm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceSm,
                    vertical: ThemeCleanPremium.spaceSm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.cardBackground,
                      ThemeCleanPremium.primary.withValues(alpha: 0.03),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  boxShadow: [
                    ...ThemeCleanPremium.softUiCardShadow,
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          border: Border.all(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.12)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: contasAtivasDocs.any((c) => c.id == _filtroContaId)
                                ? _filtroContaId
                                : '__geral__',
                            isExpanded: true,
                            icon: const Icon(
                                Icons.account_balance_wallet_rounded, size: 20),
                            items: [
                              const DropdownMenuItem(
                                value: '__geral__',
                                child: Text('Geral (todas as contas)'),
                              ),
                              ...contasAtivasDocs.map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    _financeContaDisplayName(c.data()),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _filtroContaId = v ?? '__geral__'),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filtroTipo,
                                isExpanded: true,
                                icon: const Icon(Icons.filter_list_rounded,
                                    size: 20),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'todos', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'entrada', child: Text('Receitas')),
                                  DropdownMenuItem(
                                      value: 'saida', child: Text('Despesas')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _filtroTipo = v ?? 'todos'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filtroCategoria,
                                isExpanded: true,
                                icon: const Icon(Icons.category_rounded, size: 20),
                                items: [
                                  const DropdownMenuItem(
                                      value: 'todas',
                                      child: Text('Todas categorias')),
                                  ...distinctCats.map(
                                    (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c,
                                            overflow: TextOverflow.ellipsis)),
                                  ),
                                ],
                                onChanged: (v) => setState(
                                    () => _filtroCategoria = v ?? 'todas'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filtroExtra,
                                isExpanded: true,
                                icon: const Icon(Icons.filter_alt_rounded,
                                    size: 20),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'todos',
                                      child: Text('Todos (extra)')),
                                  DropdownMenuItem(
                                      value: 'pendente_aprovacao',
                                      child: Text('Pendente aprovação')),
                                  DropdownMenuItem(
                                      value: 'nao_conciliados',
                                      child: Text('Pend. conciliação')),
                                  DropdownMenuItem(
                                      value: 'a_pagar',
                                      child: Text('A pagar')),
                                  DropdownMenuItem(
                                      value: 'pagos', child: Text('Pagos')),
                                  DropdownMenuItem(
                                      value: 'a_receber',
                                      child: Text('A receber')),
                                  DropdownMenuItem(
                                      value: 'recebidos',
                                      child: Text('Recebidos')),
                                  DropdownMenuItem(
                                      value: 'futuras_despesas',
                                      child: Text('Despesas futuras pend.')),
                                  DropdownMenuItem(
                                      value: 'futuras_receitas',
                                      child: Text('Receitas futuras pend.')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _filtroExtra = v ?? 'todos'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
              ),
              SliverToBoxAdapter(
                child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      '${docs.length} lançamento${docs.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 4,
                    ThemeCleanPremium.spaceLg, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                    final row = rows[i];
                    if (row.isHeader) {
                      return _FinanceDayHeaderTile(day: row.day!);
                    }
                    final doc = row.doc!;
                    return _LancamentoCard(
                      doc: doc,
                      tenantId: widget.tenantId,
                      role: widget.role,
                      onEdit: () => _editarLancamento(doc),
                      onDelete: () => _excluirLancamento(doc),
                      onApprove: () async {
                        try {
                          await FirebaseAuth.instance.currentUser
                              ?.getIdToken(true);
                          await doc.reference.update({
                            'aprovacaoPendente': false,
                            'aprovadoPorUid':
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                            'aprovadoEm': FieldValue.serverTimestamp(),
                          });
                          if (mounted) _refresh();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro: $e')));
                          }
                        }
                      },
                    );
                  },
                  childCount: rows.length,
                ),
              ),
            ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editarLancamento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showFinanceLancamentoEditorForTenant(context,
        tenantId: widget.tenantId,
        existingDoc: doc,
        panelRole: widget.role);
    if (ok && mounted) {
      widget.onFinanceChanged?.call();
    }
  }

  Future<void> _excluirLancamento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Excluir Lançamento',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
            'Tem certeza que deseja excluir este lançamento? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _excluirLancamentoComAuditoria(doc, widget.tenantId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
      return;
    }
    if (mounted) {
      widget.onFinanceChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lançamento excluído.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
    }
  }
}

// ─── Card de Lançamento Individual ────────────────────────────────────────────
class _LancamentoCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final String tenantId;
  final String role;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onApprove;

  const _LancamentoCard(
      {required this.doc,
      required this.tenantId,
      required this.role,
      required this.onEdit,
      required this.onDelete,
      required this.onApprove});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? {};
    final tipo = (data['type'] ?? 'entrada').toString().toLowerCase();
    final isTransfer = tipo == 'transferencia';
    final isEntrada =
        !isTransfer && (tipo.contains('entrada') || tipo.contains('receita'));
    final valor = _parseValor(data['amount'] ?? data['valor']);
    final categoria =
        (data['categoria'] ?? data['title'] ?? 'Sem categoria').toString();
    final descricao = (data['descricao'] ?? '').toString();
    final origemNome = (data['contaOrigemNome'] ?? '').toString();
    final destinoNome = (data['contaDestinoNome'] ?? '').toString();
    final dt = _parseDate(data['createdAt'] ?? data['date']);
    final dataStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final comprovanteUrl = (data['comprovanteUrl'] ?? '').toString();
    final pendenteRecorrencia = data['pendenteConciliacaoRecorrencia'] == true;
    final pendenteAprovacao = data['aprovacaoPendente'] == true;
    final conciliadoOk = data['conciliado'] == true;
    final centroCusto =
        (data['centroCusto'] ?? '').toString().trim();
    final vinculoLinha = financeLancamentoVinculoLabel(data);
    final podeAprovar = pendenteAprovacao &&
        AppPermissions.canApproveFinanceDespesaPendente(role);

    final color = isTransfer
        ? _financeTransferencia
        : (isEntrada ? _financeEntradas : _financeSaidas);
    final titulo = isTransfer ? 'Transferência' : categoria;
    final subtitulo = isTransfer
        ? (origemNome.isNotEmpty && destinoNome.isNotEmpty
            ? '$origemNome → $destinoNome'
            : descricao)
        : descricao;

    final baseBorder = const Color(0xFFE8EEF4);
    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: pendenteRecorrencia
            ? const Color(0xFFFFFBF0)
            : ThemeCleanPremium.cardBackground,
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
          top: BorderSide(
              color: pendenteRecorrencia ? Colors.amber.shade300 : baseBorder),
          right: BorderSide(
              color: pendenteRecorrencia ? Colors.amber.shade300 : baseBorder),
          bottom: BorderSide(
              color: pendenteRecorrencia ? Colors.amber.shade300 : baseBorder),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          onTap: () => showFinanceLancamentoDetailsBottomSheet(context,
              data: data,
              comprovanteUrl: comprovanteUrl,
              dataStr: dataStr,
              isEntrada: isEntrada,
              isTransfer: isTransfer,
              color: color,
              valor: valor,
              titulo: titulo,
              subtitulo: subtitulo),
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: pendenteRecorrencia
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.2),
                              color.withValues(alpha: 0.08),
                            ],
                          ),
                    color: pendenteRecorrencia ? Colors.amber.shade100 : null,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    border: Border.all(
                      color: pendenteRecorrencia
                          ? Colors.amber.shade300
                          : color.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    pendenteRecorrencia
                        ? Icons.schedule_rounded
                        : (isTransfer
                            ? Icons.swap_horiz_rounded
                            : (isEntrada
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded)),
                    color: pendenteRecorrencia
                        ? Colors.amber.shade900
                        : color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (subtitulo.isNotEmpty)
                        Text(subtitulo,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      if (vinculoLinha != null && !isTransfer)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                vinculoLinha.startsWith('Membro')
                                    ? Icons.person_rounded
                                    : Icons.handshake_rounded,
                                size: 13,
                                color: ThemeCleanPremium.primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  vinculoLinha,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: ThemeCleanPremium.primary,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (centroCusto.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Projeto: $centroCusto',
                            style: TextStyle(
                                fontSize: 11,
                                color: ThemeCleanPremium.primary,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(dataStr,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          if (pendenteRecorrencia) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Conciliar',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                          if (comprovanteUrl.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.attach_file_rounded,
                                size: 14, color: Colors.grey.shade500),
                          ],
                          if (pendenteAprovacao) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Aprovar',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.deepOrange.shade900,
                                ),
                              ),
                            ),
                          ],
                          if (!isTransfer && !conciliadoOk) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Extrato',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isTransfer
                          ? 'R\$ ${valor.toStringAsFixed(2)}'
                          : '${isEntrada ? '+' : '-'} R\$ ${valor.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: color),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (podeAprovar)
                          _MiniButton(
                            icon: Icons.verified_rounded,
                            color: const Color(0xFF059669),
                            onTap: onApprove,
                            tooltip: 'Aprovar despesa'),
                        if (podeAprovar) const SizedBox(width: 6),
                        _MiniButton(
                            icon: Icons.edit_rounded,
                            color: ThemeCleanPremium.primary,
                            onTap: onEdit,
                            tooltip: 'Editar'),
                        const SizedBox(width: 6),
                        _MiniButton(
                            icon: Icons.delete_outline_rounded,
                            color: const Color(0xFFDC2626),
                            onTap: onDelete,
                            tooltip: 'Excluir'),
                        const SizedBox(width: 6),
                        _MiniButton(
                          icon: Icons.camera_alt_rounded,
                          color: const Color(0xFF7C3AED),
                          tooltip: 'Comprovante',
                          onTap: () => uploadFinanceComprovanteForLancamento(
                              context,
                              tenantId: tenantId,
                              doc: doc),
                        ),
                      ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — Despesas Fixas
// ═══════════════════════════════════════════════════════════════════════════════
class _DespesasFixasTab extends StatefulWidget {
  final String tenantId;
  final String role;

  const _DespesasFixasTab({required this.tenantId, required this.role});

  @override
  State<_DespesasFixasTab> createState() => _DespesasFixasTabState();
}

class _DespesasFixasTabState extends State<_DespesasFixasTab> {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('despesas_fixas');

  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = _col.orderBy('descricao').get();
  }

  void _refresh() {
    setState(() {
      _future = _col.orderBy('descricao').get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar as despesas fixas',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        final docs = snap.data?.docs ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Despesas mensais recorrentes (${docs.length})',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _addOuEditar(context, onSaved: _refresh),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Adicionar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData)
              const Expanded(child: ChurchPanelLoadingBody())
            else if (docs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat_rounded,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Nenhuma despesa fixa cadastrada.',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text(
                          'Adicione despesas recorrentes como Água, Luz, Aluguel, etc.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final desc = (d['descricao'] ?? '').toString();
                      final titularLinha = titularNomeFinanceFixo(d);
                      final vt = (d['vinculoTipo'] ?? 'nenhum').toString();
                      final valor = _parseValor(d['valor']);
                      final vencimento = (d['diaVencimento'] ?? '').toString();
                      final ativo = d['ativo'] != false;
                      DateTime? di;
                      DateTime? df;
                      try {
                        final ti = d['dataInicio'];
                        if (ti is Timestamp) di = ti.toDate();
                        final tf = d['dataFim'];
                        if (tf is Timestamp) df = tf.toDate();
                      } catch (_) {}
                      final totalParcelas = (d['totalParcelas'] is int)
                          ? d['totalParcelas'] as int?
                          : int.tryParse('${d['totalParcelas']}');
                      final aPartir = (d['aPartirDaParcela'] is int)
                          ? d['aPartirDaParcela'] as int?
                          : int.tryParse('${d['aPartirDaParcela']}');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.repeat_rounded,
                                color: Color(0xFFDC2626), size: 22),
                          ),
                          title: Text(desc,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (titularLinha.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: vt == 'fornecedor'
                                              ? const Color(0xFFF3E8FF)
                                              : const Color(0xFFEFF6FF),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          vt == 'fornecedor'
                                              ? 'Fornecedor'
                                              : 'Membro',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: vt == 'fornecedor'
                                                ? const Color(0xFF7C3AED)
                                                : const Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          titularLinha,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text('R\$ ${valor.toStringAsFixed(2)} / mês',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700)),
                              if (vencimento.isNotEmpty)
                                Text('Vencimento: dia $vencimento',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500)),
                              if (di != null && df != null)
                                Text(
                                    'Período: ${DateFormat('dd/MM/yyyy').format(di)} a ${DateFormat('dd/MM/yyyy').format(df)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (totalParcelas != null && totalParcelas > 0)
                                Text(
                                    'Parcelas: total $totalParcelas${aPartir != null && aPartir >= 1 ? ", controlar a partir da $aPartirª" : ""}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: ativo
                                      ? const Color(0xFFF0FDF4)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  ativo ? 'Ativa' : 'Inativa',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: ativo
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded,
                                    size: 20),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                onSelected: (v) async {
                                  if (v == 'edit')
                                    _addOuEditar(context,
                                        doc: docs[i], onSaved: _refresh);
                                  if (v == 'toggle') {
                                    await docs[i]
                                        .reference
                                        .update({'ativo': !ativo});
                                    if (mounted) _refresh();
                                  }
                                  if (v == 'delete')
                                    _excluir(context, docs[i],
                                        onDeleted: _refresh);
                                  if (v == 'lancar')
                                    _lancarDespesaFixa(context, d);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'lancar',
                                      child: Row(children: [
                                        Icon(Icons.add_circle_rounded,
                                            size: 18),
                                        SizedBox(width: 8),
                                        Text('Lançar este mês')
                                      ])),
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        Icon(Icons.edit_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Editar')
                                      ])),
                                  PopupMenuItem(
                                      value: 'toggle',
                                      child: Row(children: [
                                        Icon(
                                            ativo
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 18),
                                        SizedBox(width: 8),
                                        Text(ativo ? 'Desativar' : 'Ativar')
                                      ])),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        Icon(Icons.delete_outline_rounded,
                                            size: 18, color: Color(0xFFDC2626)),
                                        SizedBox(width: 8),
                                        Text('Excluir',
                                            style: TextStyle(
                                                color: Color(0xFFDC2626)))
                                      ])),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _addOuEditar(BuildContext context,
      {DocumentSnapshot<Map<String, dynamic>>? doc,
      VoidCallback? onSaved}) async {
    final isEdit = doc != null;
    final data = doc?.data();
    final descCtrl =
        TextEditingController(text: isEdit ? (data?['descricao'] ?? '') : '');
    final valorCtrl = TextEditingController(
        text: isEdit ? formatBrCurrencyInitial(_parseValor(data?['valor'])) : '');
    final diaCtrl = TextEditingController(
        text: isEdit ? (data?['diaVencimento'] ?? '').toString() : '');
    final parcelasCtrl = TextEditingController(
        text: isEdit ? (data?['totalParcelas'] ?? '').toString() : '');
    final aPartirCtrl = TextEditingController(
        text: isEdit ? (data?['aPartirDaParcela'] ?? '').toString() : '1');
    String categoria = isEdit ? (data?['categoria'] ?? '') : '';
    DateTime? dataInicio;
    DateTime? dataFim;
    try {
      final ti = data?['dataInicio'];
      if (ti is Timestamp) dataInicio = ti.toDate();
      final tf = data?['dataFim'];
      if (tf is Timestamp) dataFim = tf.toDate();
    } catch (_) {}

    final di0 = dataInicio ?? DateTime.now();
    final dataInicioCtrl = TextEditingController(
      text: formatBrDateDdMmYyyy(di0),
    );
    final dataFimCtrl = TextEditingController(
      text: dataFim == null ? '' : formatBrDateDdMmYyyy(dataFim),
    );

    final categoriasList =
        await _getCategoriasDespesaForTenant(widget.tenantId);
    if (categoria.isNotEmpty && !categoriasList.contains(categoria))
      categoria = '';

    var vinculoTipo = 'nenhum';
    String? membroId;
    var membroNome = '';
    String? fornecedorId;
    var fornecedorNome = '';
    if (isEdit) {
      vinculoTipo = (data?['vinculoTipo'] ?? '').toString();
      if (vinculoTipo.isEmpty) {
        final mid0 = (data?['membroId'] ?? '').toString().trim();
        final fid0 = (data?['fornecedorId'] ?? '').toString().trim();
        if (fid0.isNotEmpty) {
          vinculoTipo = 'fornecedor';
        } else if (mid0.isNotEmpty) {
          vinculoTipo = 'membro';
        } else {
          vinculoTipo = 'nenhum';
        }
      }
      membroId = (data?['membroId'] ?? '').toString();
      if (membroId.isEmpty) membroId = null;
      membroNome = (data?['membroNome'] ?? '').toString();
      fornecedorId = (data?['fornecedorId'] ?? '').toString();
      if (fornecedorId.isEmpty) fornecedorId = null;
      fornecedorNome = (data?['fornecedorNome'] ?? '').toString();
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit_rounded : Icons.add_circle_rounded,
                  color: ThemeCleanPremium.primary),
              const SizedBox(width: 10),
              Text(isEdit ? 'Editar Despesa Fixa' : 'Nova Despesa Fixa',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: categoria.isNotEmpty ? categoria : null,
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.category_rounded),
                  ),
                  items: categoriasList
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDlgState(() {
                    categoria = v ?? '';
                    if (descCtrl.text.isEmpty) descCtrl.text = categoria;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: 'Descrição',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                FinanceFixoVinculoSegmentDespesa(
                  value: vinculoTipo,
                  onChanged: (v) => setDlgState(() {
                    vinculoTipo = v;
                    if (v == 'nenhum') {
                      membroId = null;
                      membroNome = '';
                      fornecedorId = null;
                      fornecedorNome = '';
                    } else if (v == 'membro') {
                      fornecedorId = null;
                      fornecedorNome = '';
                    } else {
                      membroId = null;
                      membroNome = '';
                    }
                  }),
                ),
                if (vinculoTipo != 'nenhum') ...[
                  const SizedBox(height: 12),
                  FinanceFixoTitularCard(
                    vinculoTipo: vinculoTipo,
                    tituloPlaceholder: vinculoTipo == 'membro'
                        ? 'Titular (membro)'
                        : 'Titular (fornecedor)',
                    nomeExibicao:
                        vinculoTipo == 'membro' ? membroNome : fornecedorNome,
                    onTap: () async {
                      if (vinculoTipo == 'membro') {
                        final picked = await showFinancePremiumMemberPicker(
                          context,
                          tenantId: widget.tenantId,
                        );
                        if (picked == null) return;
                        setDlgState(() {
                          membroId = picked.$1;
                          membroNome = picked.$2;
                        });
                      } else {
                        final picked = await showFinancePremiumFornecedorPicker(
                          context,
                          tenantId: widget.tenantId,
                        );
                        if (picked == null) return;
                        setDlgState(() {
                          fornecedorId = picked.$1;
                          fornecedorNome = picked.$2;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrCurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: r'Valor mensal (R$)',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: diaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Dia de vencimento (1-31)',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.calendar_today_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Período (início e fim)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dataInicioCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [BrDateDdMmYyyyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Data início (DD/MM/AAAA)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          prefixIcon:
                              const Icon(Icons.event_rounded, size: 18),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month_rounded),
                            onPressed: () async {
                              final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: dataInicio ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030));
                              if (d != null) {
                                setDlgState(() {
                                  dataInicio = d;
                                  dataFim = d.add(const Duration(days: 365));
                                  dataInicioCtrl.text =
                                      formatBrDateDdMmYyyy(d);
                                  dataFimCtrl.text =
                                      formatBrDateDdMmYyyy(dataFim!);
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (v) {
                          final p = parseBrDateDdMmYyyy(v.trim());
                          if (p != null) setDlgState(() => dataInicio = p);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: dataFimCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [BrDateDdMmYyyyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Data fim (DD/MM/AAAA)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          prefixIcon:
                              const Icon(Icons.event_rounded, size: 18),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month_rounded),
                            onPressed: () async {
                              final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: dataFim ??
                                      dataInicio?.add(
                                          const Duration(days: 365)) ??
                                      DateTime.now()
                                          .add(const Duration(days: 365)),
                                  firstDate: dataInicio ?? DateTime(2020),
                                  lastDate: DateTime(2030));
                              if (d != null) {
                                setDlgState(() {
                                  dataFim = d;
                                  dataFimCtrl.text = formatBrDateDdMmYyyy(d);
                                });
                              }
                            },
                          ),
                        ),
                        onChanged: (v) {
                          final p = parseBrDateDdMmYyyy(v.trim());
                          if (p != null) setDlgState(() => dataFim = p);
                        },
                      ),
                    ),
                  ],
                ),
                if (dataInicio != null && dataFim != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'Ao marcar início, fim = 1 ano depois. Ajuste se precisar.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ),
                const SizedBox(height: 16),
                Text('Controle por parcelas',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: parcelasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Total parcelas',
                          hintText: 'Ex: 12',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          prefixIcon:
                              const Icon(Icons.format_list_numbered_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: aPartirCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Controlar a partir da parcela',
                          hintText: 'Ex: 1',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          prefixIcon: const Icon(Icons.play_arrow_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'Ex.: total 12 parcelas, controlar a partir da 3ª',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton.icon(
              onPressed: () {
                final valor = parseBrCurrencyInput(valorCtrl.text);
                if (descCtrl.text.trim().isEmpty || valor <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Preencha descrição e valor.')));
                  return;
                }
                if (vinculoTipo == 'membro' &&
                    (membroId == null || membroId!.isEmpty)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Selecione um membro ou mude o vínculo.')));
                  return;
                }
                if (vinculoTipo == 'fornecedor' &&
                    (fornecedorId == null || fornecedorId!.isEmpty)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content:
                          Text('Selecione um fornecedor ou mude o vínculo.')));
                  return;
                }
                final di = parseBrDateDdMmYyyy(dataInicioCtrl.text.trim());
                if (di == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content:
                          Text('Informe a data de início (DD/MM/AAAA).')));
                  return;
                }
                final df = parseBrDateDdMmYyyy(dataFimCtrl.text.trim());
                final payload = <String, dynamic>{
                  'descricao': descCtrl.text.trim(),
                  'valor': valor,
                  'categoria': categoria,
                  'diaVencimento': int.tryParse(diaCtrl.text) ?? 0,
                  'ativo': true,
                  'vinculoTipo': vinculoTipo,
                };
                if (vinculoTipo == 'nenhum') {
                  payload['titularNome'] = FieldValue.delete();
                  payload['membroId'] = FieldValue.delete();
                  payload['membroNome'] = FieldValue.delete();
                  payload['fornecedorId'] = FieldValue.delete();
                  payload['fornecedorNome'] = FieldValue.delete();
                } else if (vinculoTipo == 'membro') {
                  payload['membroId'] = membroId;
                  payload['membroNome'] = membroNome;
                  payload['titularNome'] = membroNome;
                  payload['fornecedorId'] = FieldValue.delete();
                  payload['fornecedorNome'] = FieldValue.delete();
                } else {
                  payload['fornecedorId'] = fornecedorId;
                  payload['fornecedorNome'] = fornecedorNome;
                  payload['titularNome'] = fornecedorNome;
                  payload['membroId'] = FieldValue.delete();
                  payload['membroNome'] = FieldValue.delete();
                }
                payload['dataInicio'] =
                    Timestamp.fromDate(DateTime(di.year, di.month, di.day));
                if (df != null) {
                  payload['dataFim'] =
                      Timestamp.fromDate(DateTime(df.year, df.month, df.day));
                }
                final tot = int.tryParse(parcelasCtrl.text);
                if (tot != null && tot > 0) payload['totalParcelas'] = tot;
                final part = int.tryParse(aPartirCtrl.text);
                if (part != null && part >= 1)
                  payload['aPartirDaParcela'] = part;
                Navigator.pop(ctx, payload);
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Salvar'),
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary),
            ),
          ],
        ),
      ),
    );

    valorCtrl.dispose();
    descCtrl.dispose();
    diaCtrl.dispose();
    parcelasCtrl.dispose();
    aPartirCtrl.dispose();
    dataInicioCtrl.dispose();
    dataFimCtrl.dispose();

    if (result == null) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (isEdit) {
      await doc.reference.set(result, SetOptions(merge: true));
    } else {
      final clean = Map<String, dynamic>.from(result)
        ..removeWhere((_, v) => v is FieldValue);
      await _col.add(clean);
    }
    if (context.mounted) {
      onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              isEdit ? 'Despesa fixa atualizada!' : 'Despesa fixa adicionada!',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _excluir(BuildContext context, DocumentSnapshot doc,
      {VoidCallback? onDeleted}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Text('Excluir Despesa Fixa')
        ]),
        content:
            const Text('Tem certeza que deseja excluir esta despesa fixa?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await doc.reference.delete();
    if (context.mounted) {
      onDeleted?.call();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Despesa fixa excluída.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _lancarDespesaFixa(
      BuildContext context, Map<String, dynamic> despesa) async {
    final now = DateTime.now();
    final start = despesa['dataInicio'] is Timestamp
        ? (despesa['dataInicio'] as Timestamp).toDate()
        : null;
    final end = despesa['dataFim'] is Timestamp
        ? (despesa['dataFim'] as Timestamp).toDate()
        : null;
    final totalParcelas = (despesa['totalParcelas'] is int)
        ? despesa['totalParcelas'] as int?
        : int.tryParse('${despesa['totalParcelas']}');
    final aPartir = (despesa['aPartirDaParcela'] is int)
        ? (despesa['aPartirDaParcela'] as int?)
        : int.tryParse('${despesa['aPartirDaParcela']}') ?? 1;

    if (start != null) {
      final startMonth = DateTime(now.year, now.month);
      final rangeStart = DateTime(start.year, start.month);
      if (startMonth.isBefore(rangeStart)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Despesa só pode ser lançada a partir de ${_mesesAbrev[start.month - 1]}/${start.year}.')),
          );
        }
        return;
      }
    }
    if (end != null) {
      final startMonth = DateTime(now.year, now.month);
      final rangeEnd = DateTime(end.year, end.month);
      if (startMonth.isAfter(rangeEnd)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Período da despesa terminou em ${_mesesAbrev[end.month - 1]}/${end.year}.')),
          );
        }
        return;
      }
    }
    if (start != null && totalParcelas != null && totalParcelas > 0) {
      final mesesDesdeInicio =
          (now.year - start.year) * 12 + (now.month - start.month) + 1;
      if (mesesDesdeInicio < (aPartir ?? 1)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Controle a partir da parcela ${aPartir ?? 1}. Este mês = parcela $mesesDesdeInicio.')),
          );
        }
        return;
      }
      if (mesesDesdeInicio > totalParcelas) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Total de $totalParcelas parcelas já foi atingido.')),
          );
        }
        return;
      }
    }

    final vt =
        (despesa['vinculoTipo'] ?? 'nenhum').toString();
    final lanc = <String, dynamic>{
      'type': 'saida',
      'amount': despesa['valor'] ?? 0,
      'categoria': despesa['categoria'] ?? despesa['descricao'] ?? '',
      'descricao': '${despesa['descricao'] ?? ''} (Despesa Fixa)',
      'createdAt': Timestamp.fromDate(now),
    };
    final tn = (despesa['titularNome'] ?? '').toString().trim();
    if (tn.isNotEmpty) lanc['titularNome'] = tn;
    if (vt != 'nenhum') lanc['vinculoTipo'] = vt;
    if (vt == 'membro') {
      final mid = (despesa['membroId'] ?? '').toString().trim();
      if (mid.isNotEmpty) {
        lanc['membroId'] = mid;
        lanc['membroNome'] = (despesa['membroNome'] ?? '').toString();
      }
    } else if (vt == 'fornecedor') {
      final fid = (despesa['fornecedorId'] ?? '').toString().trim();
      if (fid.isNotEmpty) {
        lanc['fornecedorId'] = fid;
        lanc['fornecedorNome'] = (despesa['fornecedorNome'] ?? '').toString();
      }
    }
    await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('finance')
        .add(lanc);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Despesa "${despesa['descricao']}" lançada em ${_mesesAbrev[now.month - 1]}/${now.year}!')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB — Categorias (Despesas e Receitas) — listagem, adicionar, remover
// ═══════════════════════════════════════════════════════════════════════════════
class _FinanceCategoriasTab extends StatelessWidget {
  final String tenantId;

  const _FinanceCategoriasTab({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('igrejas').doc(tenantId);
    final colDespesas = ref.collection('categorias_despesas');
    final colReceitas = ref.collection('categorias_receitas');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategoriasSection(
            title: 'Despesas',
            color: const Color(0xFFDC2626),
            collection: colDespesas,
            tenantId: tenantId,
            padrao: _categoriasDespesaPadrao,
          ),
          const SizedBox(height: 24),
          _CategoriasSection(
            title: 'Receitas',
            color: _financeEntradas,
            collection: colReceitas,
            tenantId: tenantId,
            padrao: _categoriasReceitaPadrao,
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _CategoriasSection extends StatefulWidget {
  final String title;
  final Color color;
  final CollectionReference<Map<String, dynamic>> collection;
  final String tenantId;
  final List<String> padrao;

  const _CategoriasSection({
    required this.title,
    required this.color,
    required this.collection,
    required this.tenantId,
    required this.padrao,
  });

  @override
  State<_CategoriasSection> createState() => _CategoriasSectionState();
}

class _CategoriasSectionState extends State<_CategoriasSection> {
  int _categoriasStreamRetry = 0;

  Future<void> _seedIfEmpty() async {
    final snap = await widget.collection.orderBy('nome').get();
    if (snap.docs.isEmpty) {
      for (final nome in widget.padrao) {
        await widget.collection
            .add({'nome': nome, 'ordem': widget.padrao.indexOf(nome)});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('cat_stream_${widget.title}_$_categoriasStreamRetry'),
      stream: widget.collection.orderBy('nome').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: ChurchPanelErrorBody(
              title: 'Não foi possível carregar as categorias',
              error: snap.error,
              onRetry: () => setState(() => _categoriasStreamRetry++),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: const ChurchPanelLoadingBody(),
          );
        }
        final docsRaw = snap.data?.docs ?? [];
        // Remove duplicatas por nome (mantém primeiro doc de cada nome).
        final seenNomes = <String>{};
        final docs = docsRaw.where((d) {
          final nome = (d.data()['nome'] ?? '').toString().trim();
          return nome.isNotEmpty && seenNomes.add(nome);
        }).toList();
        // Ordenação alfabética (despesas e receitas).
        docs.sort((a, b) {
          final na = (a.data()['nome'] ?? '').toString().trim().toLowerCase();
          final nb = (b.data()['nome'] ?? '').toString().trim().toLowerCase();
          return na.compareTo(nb);
        });
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: widget.color.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Nenhuma categoria de ${widget.title.toLowerCase()}.',
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    await _seedIfEmpty();
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Categorias padrão carregadas.',
                              style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.green));
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text('Carregar categorias padrão'),
                  style: FilledButton.styleFrom(backgroundColor: widget.color),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: widget.color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(ThemeCleanPremium.radiusMd)),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: widget.color),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _showAddCategoria(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('ADICIONAR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.color,
                        side: BorderSide(color: widget.color),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final nome = (d.data()['nome'] ?? '').toString();
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(nome,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Colors.grey.shade600, size: 22),
                      onPressed: () =>
                          _confirmarExcluir(context, d.reference, nome),
                      style:
                          IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddCategoria(BuildContext context) async {
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: Text('Nova categoria - ${widget.title}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome da categoria',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Adicionar'),
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary),
          ),
        ],
      ),
    );
    if (nome != null && nome.isNotEmpty && context.mounted) {
      await widget.collection.add({'nome': nome, 'ordem': 999});
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Categoria adicionada.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
    }
  }

  Future<void> _confirmarExcluir(
      BuildContext context, DocumentReference ref, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir categoria'),
        content: Text(
            'Excluir "$nome"? Lançamentos que usam esta categoria não serão alterados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.delete();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Categoria excluída.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB — Contas (cadastro para transferências)
// ═══════════════════════════════════════════════════════════════════════════════
class _FinanceContasTab extends StatefulWidget {
  final String tenantId;
  final String role;
  final Future<void> Function(
          BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc)
      onEditLancamento;

  const _FinanceContasTab({
    required this.tenantId,
    required this.role,
    required this.onEditLancamento,
  });

  @override
  State<_FinanceContasTab> createState() => _FinanceContasTabState();
}

class _FinanceContasTabState extends State<_FinanceContasTab> {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas');

  CollectionReference<Map<String, dynamic>> get _financeCol =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('finance');

  static String _contaSubtitle(Map<String, dynamic> d) {
    final tipo = _financeTipoContaLabel(d['tipoConta']?.toString());
    final banco = (d['bancoNome'] ?? '').toString().trim();
    final ag = (d['agencia'] ?? '').toString().trim();
    final nc = (d['numeroConta'] ?? '').toString().trim();
    final parts = <String>[tipo];
    if (banco.isNotEmpty) parts.add(banco);
    if (ag.isNotEmpty) parts.add('Ag. $ag');
    if (nc.isNotEmpty) parts.add('Conta $nc');
    return parts.join(' · ');
  }

  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = _col.orderBy('nome').get();
  }

  void _refresh() {
    setState(() {
      _future = _col.orderBy('nome').get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar as contas',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        final docs = snap.data?.docs ?? [];
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  ThemeCleanPremium.spaceLg,
                  ThemeCleanPremium.spaceSm,
                  ThemeCleanPremium.spaceLg,
                  ThemeCleanPremium.spaceSm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Contas, bancos e caixas (transferências e extrato)',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        _showAddConta(context, _col, onSaved: _refresh),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Nova conta'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: ThemeCleanPremium.spaceLg, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                    ),
                  ),
                ],
              ),
            ),
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData)
              const Expanded(child: ChurchPanelLoadingBody())
            else if (docs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Nenhuma conta cadastrada.',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text(
                          'Adicione contas (ex.: Caixa da Tesouraria, Caixa de Eventos) para usar em transferências.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      ThemeCleanPremium.spaceLg,
                      ThemeCleanPremium.spaceSm,
                      ThemeCleanPremium.spaceLg,
                      100),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final nome = _financeContaDisplayName(data);
                    final ativo = data['ativo'] != false;
                    final sub = _contaSubtitle(data);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: ThemeCleanPremium.spaceLg,
                            vertical: 12),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _MovimentacoesContaPage(
                                financeCol: _financeCol,
                                tenantId: widget.tenantId,
                                role: widget.role,
                                contaId: d.id,
                                title: nome.isNotEmpty ? nome : 'Conta',
                                extratoMes: null,
                                onEdit: (ctx, doc) =>
                                    widget.onEditLancamento(ctx, doc),
                              ),
                            ),
                          );
                          if (mounted) _refresh();
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                          ),
                          child: Icon(Icons.account_balance_rounded,
                              color: ThemeCleanPremium.primary, size: 22),
                        ),
                        title: Text(nome,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sub.isNotEmpty)
                              Text(sub,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700)),
                            if (!ativo)
                              Text('Inativa',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800)),
                          ],
                        ),
                        isThreeLine: sub.isNotEmpty || !ativo,
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) async {
                            if (v == 'edit')
                              _showEditConta(context, _col, d,
                                  onSaved: _refresh);
                            if (v == 'toggle') {
                              await d.reference.update({'ativo': !ativo});
                              if (mounted) _refresh();
                            }
                            if (v == 'delete')
                              await _confirmarExcluirConta(
                                  context, d.reference, nome,
                                  onDeleted: _refresh);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Editar')
                                ])),
                            PopupMenuItem(
                                value: 'toggle',
                                child: Row(children: [
                                  Icon(
                                      ativo
                                          ? Icons.pause_rounded
                                          : Icons.check_circle_rounded,
                                      size: 18),
                                  SizedBox(width: 8),
                                  Text(ativo ? 'Desativar' : 'Ativar')
                                ])),
                            const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 18, color: Color(0xFFDC2626)),
                                  SizedBox(width: 8),
                                  Text('Excluir',
                                      style:
                                          TextStyle(color: Color(0xFFDC2626)))
                                ])),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showAddConta(
      BuildContext context, CollectionReference<Map<String, dynamic>> col,
      {VoidCallback? onSaved}) async {
    await _showContaEditor(context, col, null, onSaved: onSaved);
  }

  Future<void> _showEditConta(
      BuildContext context,
      CollectionReference<Map<String, dynamic>> col,
      DocumentSnapshot<Map<String, dynamic>> doc,
      {VoidCallback? onSaved}) async {
    await _showContaEditor(context, col, doc, onSaved: onSaved);
  }

  Future<void> _showContaEditor(
    BuildContext context,
    CollectionReference<Map<String, dynamic>> col,
    DocumentSnapshot<Map<String, dynamic>>? existing, {
    VoidCallback? onSaved,
  }) async {
    final d = existing?.data();
    final nomeCtrl = TextEditingController(text: (d?['nome'] ?? '').toString());
    final agenciaCtrl = TextEditingController(text: (d?['agencia'] ?? '').toString());
    final contaCtrl = TextEditingController(text: (d?['numeroConta'] ?? '').toString());
    final obsCtrl = TextEditingController(text: (d?['observacao'] ?? '').toString());

    var bancoSel = kBrasilBancosComuns.first;
    final cod = (d?['bancoCodigo'] ?? '').toString();
    final nm = (d?['bancoNome'] ?? '').toString();
    if (nm.isNotEmpty || cod.isNotEmpty) {
      final ix = kBrasilBancosComuns.indexWhere(
        (o) =>
            o.codigo == cod && o.nome.toLowerCase() == nm.toLowerCase(),
      );
      if (ix >= 0) {
        bancoSel = kBrasilBancosComuns[ix];
      } else {
        bancoSel = BrasilBancoOption(
            codigo: cod, nome: nm.isNotEmpty ? nm : 'Instituição');
      }
    }

    String tipoConta = (d?['tipoConta'] ?? 'corrente').toString().toLowerCase();
    if (!['corrente', 'poupanca', 'caixa'].contains(tipoConta)) {
      tipoConta = 'corrente';
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            final bankOptions = List<BrasilBancoOption>.from(kBrasilBancosComuns);
            if (!bankOptions.any((o) =>
                o.codigo == bancoSel.codigo && o.nome == bancoSel.nome)) {
              bankOptions.insert(0, bancoSel);
            }
            return Padding(
              padding: EdgeInsets.only(
                left: ThemeCleanPremium.spaceLg,
                right: ThemeCleanPremium.spaceLg,
                top: ThemeCleanPremium.spaceMd,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + ThemeCleanPremium.spaceLg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      existing == null ? 'Nova conta ou caixa' : 'Editar conta',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Defina banco, tipo e agência para controle e extratos.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome de exibição *',
                        hintText: 'Ex.: Conta principal, Caixa culto',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BrasilBancoOption>(
                      value: bankOptions.contains(bancoSel) ? bancoSel : bankOptions.first,
                      decoration: const InputDecoration(
                        labelText: 'Banco / instituição',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance_rounded),
                      ),
                      isExpanded: true,
                      items: bankOptions
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(
                                  b.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDlg(() => bancoSel = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Tipo', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'corrente',
                            label: Text('Corrente'),
                            icon: Icon(Icons.credit_card_rounded, size: 18)),
                        ButtonSegment(
                            value: 'poupanca',
                            label: Text('Poupança'),
                            icon: Icon(Icons.savings_rounded, size: 18)),
                        ButtonSegment(
                            value: 'caixa',
                            label: Text('Caixa'),
                            icon: Icon(Icons.payments_rounded, size: 18)),
                      ],
                      selected: {tipoConta},
                      onSelectionChanged: (s) {
                        if (s.isNotEmpty) setDlg(() => tipoConta = s.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: agenciaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Agência',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.store_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: contaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nº conta (opcional)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.numbers_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observação (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        final n = nomeCtrl.text.trim();
                        if (n.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Informe o nome da conta.')),
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: Text(existing == null ? 'Cadastrar' : 'Salvar'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: ThemeCleanPremium.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true || !context.mounted) return;

    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) return;

    final payload = <String, dynamic>{
      'nome': nome,
      'bancoCodigo': bancoSel.codigo,
      'bancoNome': bancoSel.nome,
      'agencia': agenciaCtrl.text.trim(),
      'numeroConta': contaCtrl.text.trim(),
      'tipoConta': tipoConta,
      'observacao': obsCtrl.text.trim(),
      'ativo': d?['ativo'] ?? true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existing == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await col.add(payload);
    } else {
      await existing.reference.set(payload, SetOptions(merge: true));
    }

    if (context.mounted) {
      onSaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            existing == null ? 'Conta cadastrada.' : 'Conta atualizada.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _confirmarExcluirConta(
      BuildContext context, DocumentReference ref, String nome,
      {VoidCallback? onDeleted}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir conta'),
        content: Text(
            'Excluir "$nome"? Transferências já lançadas não serão alteradas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.delete();
      if (context.mounted) {
        onDeleted?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Conta excluída.', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ═══════════════════════════════════════════════════════════════════════════════

class _TotalizadorCard extends StatelessWidget {
  final String label;
  final double valor;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _TotalizadorCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: ThemeCleanPremium.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text('R\$ ${valor.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.4)),
            ],
          ),
        ),
      ],
    );
    final decoration = BoxDecoration(
      color: ThemeCleanPremium.cardBackground,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
      boxShadow: [
        ...ThemeCleanPremium.softUiCardShadow,
        BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -2),
      ],
      border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
    );
    if (onTap == null)
      return Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          decoration: decoration,
          child: child);
    return Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                decoration: decoration,
                child: child)));
  }
}

class _FilterChipPeriod extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipPeriod(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.16),
                      ThemeCleanPremium.primary.withValues(alpha: 0.07),
                    ],
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
                        blurRadius: 14,
                        offset: const Offset(0, 5))
                  ]
                : ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
                color: selected
                    ? ThemeCleanPremium.primary.withValues(alpha: 0.38)
                    : const Color(0xFFE2E8F0),
                width: selected ? 1.5 : 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.15,
                  color: selected
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;

  const _ChartCard({required this.title, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    final chartIcon = icon ?? Icons.bar_chart_rounded;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.05),
              blurRadius: 22,
              offset: const Offset(0, 8)),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      ThemeCleanPremium.primary.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                  ),
                ),
                child:
                    Icon(chartIcon, size: 20, color: ThemeCleanPremium.primary),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceSm),
              Text(title,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                      letterSpacing: -0.3)),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _MiniButton(
      {required this.icon,
      required this.color,
      required this.onTap,
      required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(
                minWidth: ThemeCleanPremium.minTouchTarget,
                minHeight: ThemeCleanPremium.minTouchTarget),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.16),
                  color.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Lista fornecedores ativos para o dropdown do lançamento.
Future<List<({String id, String nome})>> _fornecedoresParaFinanceDropdown(
    String tenantId) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('fornecedores')
        .orderBy('nome')
        .limit(400)
        .get();
    final out = <({String id, String nome})>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['status'] == 'inativo') continue;
      final n = (m['nome'] ?? '').toString().trim();
      out.add((id: d.id, nome: n.isEmpty ? d.id : n));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Membros ativos para vincular receita/despesa (nome denormalizado no lançamento).
Future<List<({String id, String nome})>> _membrosParaFinanceDropdown(
    String tenantId) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros')
        .limit(600)
        .get();
    final out = <({String id, String nome})>[];
    for (final d in snap.docs) {
      final m = d.data();
      final st = (m['STATUS'] ?? m['status'] ?? '').toString().toLowerCase();
      if (st == 'inativo' ||
          st == 'recusado' ||
          st == 'bloqueado' ||
          st == 'cancelado') {
        continue;
      }
      var n = (m['NOME_COMPLETO'] ?? m['nome'] ?? '').toString().trim();
      if (n.isEmpty) continue;
      out.add((id: d.id, nome: n));
    }
    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  } catch (_) {
    return const [];
  }
}

/// Texto único para cartão / extrato (fornecedor e/ou membro).
String? financeLancamentoVinculoLabel(Map<String, dynamic> data) {
  final fn = (data['fornecedorNome'] ?? '').toString().trim();
  final mn = (data['membroNome'] ?? '').toString().trim();
  if (fn.isEmpty && mn.isEmpty) return null;
  if (fn.isNotEmpty && mn.isNotEmpty) {
    return 'Fornecedor · $fn · Membro · $mn';
  }
  if (fn.isNotEmpty) return 'Fornecedor · $fn';
  return 'Membro · $mn';
}

/// Editor de lançamento (mesmo fluxo do módulo financeiro) — reutilizável no painel.
/// Retorna `true` se gravou com sucesso.
Future<bool> showFinanceLancamentoEditorForTenant(
  BuildContext context, {
  required String tenantId,
  DocumentSnapshot<Map<String, dynamic>>? existingDoc,
  String? presetFornecedorId,
  String? presetFornecedorNome,
  bool lockFornecedor = false,
  String? panelRole,
  /// Só para **novo** lançamento: `entrada`, `saida` ou `transferencia`.
  String? presetNovoTipo,
}) async {
  final financeCol = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('finance');

  final isEdit = existingDoc != null;
  final data = existingDoc?.data();

  String tipo = isEdit ? (data?['type'] ?? 'entrada').toString() : 'entrada';
  if (tipo != 'entrada' && tipo != 'saida' && tipo != 'transferencia') {
    tipo = 'entrada';
  }
  if (!isEdit && presetNovoTipo != null) {
    final p = presetNovoTipo.trim().toLowerCase();
    if (p == 'entrada' || p == 'saida' || p == 'transferencia') {
      tipo = p;
    }
  }
  final amtInicial =
      isEdit ? _parseValor(data?['amount'] ?? data?['valor']) : 0.0;
  final valorCtrl = TextEditingController(
      text: isEdit && amtInicial > 0
          ? formatBrCurrencyInitial(amtInicial)
          : '');
  final descCtrl = TextEditingController(
      text: isEdit
          ? (data?['descricao'] ?? data?['anotacoes'] ?? '').toString()
          : '');
  String categoria = isEdit ? (data?['categoria'] ?? '').toString() : '';
  String? contaOrigemId = isEdit
      ? ((data?['contaOrigemId'] ?? '').toString().isEmpty
          ? null
          : (data?['contaOrigemId']).toString())
      : null;
  String? contaDestinoId;
  if (isEdit && data != null) {
    final id = financeContaDestinoReceitaId(data);
    contaDestinoId = id.isEmpty ? null : id;
  }
  DateTime dataSel = DateTime.now();
  if (isEdit) {
    final ts = data?['createdAt'] ?? data?['date'];
    if (ts is Timestamp) dataSel = ts.toDate();
  }

  final catsReceita = await _financeCategoriasReceitaTenant(tenantId);
  final catsDespesa = await _getCategoriasDespesaForTenant(tenantId);
  final contas = await _financeContasAtivasTenant(tenantId);
  final fornecedoresOpts = await _fornecedoresParaFinanceDropdown(tenantId);
  final membrosOpts = await _membrosParaFinanceDropdown(tenantId);
  final settings = await FinanceTenantSettings.load(tenantId);

  final centroCustoCtrl = TextEditingController(
      text: isEdit ? (data?['centroCusto'] ?? '').toString() : '');
  final extratoRefCtrl = TextEditingController(
      text: isEdit ? (data?['extratoRef'] ?? '').toString() : '');

  String? fornecedorId = isEdit
      ? (data?['fornecedorId'] ?? '').toString().trim()
      : (presetFornecedorId ?? '').trim();
  if (fornecedorId.isEmpty) fornecedorId = null;
  var fornecedorNome = isEdit
      ? (data?['fornecedorNome'] ?? '').toString().trim()
      : (presetFornecedorNome ?? '').trim();
  if (fornecedorId != null && fornecedorNome.isEmpty) {
    for (final f in fornecedoresOpts) {
      if (f.id == fornecedorId) {
        fornecedorNome = f.nome;
        break;
      }
    }
  }

  final membroIdRaw =
      isEdit ? (data?['membroId'] ?? '').toString().trim() : '';
  String? membroId = membroIdRaw.isEmpty ? null : membroIdRaw;
  var membroNome = isEdit
      ? (data?['membroNome'] ?? '').toString().trim()
      : '';
  if (membroId != null && membroNome.isEmpty) {
    for (final x in membrosOpts) {
      if (x.id == membroId) {
        membroNome = x.nome;
        break;
      }
    }
  }

  /// nenhum | fornecedor | membro — mutuamente exclusivo (exc. lock de fornecedor).
  var vinculoTipo = 'nenhum';
  if (lockFornecedor && fornecedorId != null) {
    vinculoTipo = 'fornecedor';
  } else if (isEdit) {
    if (fornecedorId != null && fornecedorId.isNotEmpty) {
      vinculoTipo = 'fornecedor';
    } else if (membroId != null && membroId.isNotEmpty) {
      vinculoTipo = 'membro';
    }
  }

  if (categoria.isNotEmpty) {
    if (tipo == 'entrada' && !catsReceita.contains(categoria)) categoria = '';
    if (tipo == 'saida' && !catsDespesa.contains(categoria)) categoria = '';
  }
  if (contaOrigemId != null && !contas.any((c) => c.id == contaOrigemId)) {
    contaOrigemId = null;
  }
  if (contaDestinoId != null && !contas.any((c) => c.id == contaDestinoId)) {
    contaDestinoId = null;
  }
  if (tipo == 'entrada') {
    contaOrigemId = null;
  } else if (tipo == 'saida') {
    contaDestinoId = null;
  }

  if (!context.mounted) return false;
  String t = tipo;
  String cat = categoria;
  String? coId = contaOrigemId;
  String? cdId = contaDestinoId;
  DateTime dataSelLocal = dataSel;
  var recebimentoConfirmado =
      isEdit ? (data?['recebimentoConfirmado'] != false) : true;
  var pagamentoConfirmado =
      isEdit ? (data?['pagamentoConfirmado'] != false) : true;
  var conciliado = isEdit ? (data?['conciliado'] == true) : false;
  XFile? comprovanteFile;
  String nomeConta(String? id) {
    if (id == null) return '';
    for (final c in contas) {
      if (c.id == id) return c.nome;
    }
    return '';
  }

  final dataCtrl = TextEditingController(text: formatBrDateDdMmYyyy(dataSel));

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        final isTransfer = t == 'transferencia';
        final cats = t == 'entrada'
            ? catsReceita
            : (t == 'saida' ? catsDespesa : <String>[]);
        if (cat.isNotEmpty && cats.isNotEmpty && !cats.contains(cat)) cat = '';
        final contaFieldId = t == 'entrada' ? cdId : coId;
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary,
                        ThemeCleanPremium.primary.withOpacity(0.82),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 4, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            isEdit
                                ? Icons.edit_note_rounded
                                : Icons.payments_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEdit ? 'Editar lançamento' : 'Transação',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Controle por conta ou caixa',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          tooltip: 'Fechar',
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'entrada',
                        label: Text('Receita'),
                        icon: Icon(Icons.trending_up_rounded)),
                    ButtonSegment(
                        value: 'saida',
                        label: Text('Despesa'),
                        icon: Icon(Icons.trending_down_rounded)),
                    ButtonSegment(
                        value: 'transferencia',
                        label: Text('Transferência'),
                        icon: Icon(Icons.swap_horiz_rounded)),
                  ],
                  selected: {t},
                  onSelectionChanged: (s) => setDlgState(() {
                    final prev = t;
                    t = s.first;
                    cat = '';
                    if (t == 'transferencia') {
                      fornecedorId = null;
                      fornecedorNome = '';
                      membroId = null;
                      membroNome = '';
                      vinculoTipo = 'nenhum';
                    }
                    if (t == 'entrada') {
                      recebimentoConfirmado = true;
                    } else if (t == 'saida') {
                      pagamentoConfirmado = true;
                    }
                    if (t == 'transferencia' || prev == 'transferencia') {
                      coId = null;
                      cdId = null;
                    } else if (prev == 'entrada' && t == 'saida') {
                      coId = cdId;
                      cdId = null;
                    } else if (prev == 'saida' && t == 'entrada') {
                      cdId = coId;
                      coId = null;
                    }
                  }),
                  style: SegmentedButton.styleFrom(
                    selectedForegroundColor: t == 'entrada'
                        ? _financeEntradas
                        : t == 'saida'
                            ? _financeSaidas
                            : _financeTransferencia,
                    selectedBackgroundColor: t == 'entrada'
                        ? const Color(0xFFEFF6FF)
                        : t == 'saida'
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFEEF2FF),
                  ),
                ),
                const SizedBox(height: 16),
                if (!isTransfer) ...[
                  DropdownButtonFormField<String>(
                    value: cat.isNotEmpty ? cat : null,
                    decoration: InputDecoration(
                      labelText: 'Categoria',
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon: const Icon(Icons.category_rounded),
                    ),
                    items: cats
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => cat = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  if (!isTransfer) ...[
                    if (lockFornecedor && fornecedorId != null)
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Fornecedor / prestador',
                          filled: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          prefixIcon: const Icon(Icons.handshake_rounded),
                        ),
                        child: Text(
                          fornecedorNome.isEmpty
                              ? fornecedorId!
                              : fornecedorNome,
                          style: const TextStyle(fontSize: 15),
                        ),
                      )
                    else ...[
                      Text(
                        'Vincular a (opcional)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'nenhum',
                            label: Text('Nenhum'),
                            icon: Icon(Icons.close_rounded, size: 18),
                          ),
                          ButtonSegment(
                            value: 'fornecedor',
                            label: Text('Fornecedor'),
                            icon: Icon(Icons.handshake_rounded, size: 18),
                          ),
                          ButtonSegment(
                            value: 'membro',
                            label: Text('Membro'),
                            icon: Icon(Icons.person_rounded, size: 18),
                          ),
                        ],
                        selected: {vinculoTipo},
                        onSelectionChanged: (s) => setDlgState(() {
                          vinculoTipo = s.first;
                          if (vinculoTipo != 'fornecedor') {
                            fornecedorId = null;
                            fornecedorNome = '';
                          }
                          if (vinculoTipo != 'membro') {
                            membroId = null;
                            membroNome = '';
                          }
                        }),
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (vinculoTipo == 'fornecedor')
                        DropdownButtonFormField<String>(
                          value: fornecedorId != null &&
                                  fornecedoresOpts.any((e) => e.id == fornecedorId)
                              ? fornecedorId
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Fornecedor / prestador',
                            filled: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm)),
                            prefixIcon: const Icon(Icons.handshake_rounded),
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Selecione…'),
                            ),
                            ...fornecedoresOpts.map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  e.nome,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setDlgState(() {
                            fornecedorId = v;
                            fornecedorNome = '';
                            if (v != null) {
                              for (final f in fornecedoresOpts) {
                                if (f.id == v) {
                                  fornecedorNome = f.nome;
                                  break;
                                }
                              }
                            }
                          }),
                        ),
                      if (vinculoTipo == 'fornecedor' && fornecedoresOpts.isEmpty)
                        Text(
                          'Cadastre fornecedores em Financeiro → Fornecedores.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              height: 1.35),
                        ),
                      if (vinculoTipo == 'membro')
                        DropdownButtonFormField<String>(
                          value: membroId != null &&
                                  membrosOpts.any((e) => e.id == membroId)
                              ? membroId
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Membro',
                            filled: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm)),
                            prefixIcon: const Icon(Icons.person_rounded),
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Selecione…'),
                            ),
                            ...membrosOpts.map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  e.nome,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setDlgState(() {
                            membroId = v;
                            membroNome = '';
                            if (v != null) {
                              for (final x in membrosOpts) {
                                if (x.id == v) {
                                  membroNome = x.nome;
                                  break;
                                }
                              }
                            }
                          }),
                        ),
                      if (vinculoTipo == 'membro' && membrosOpts.isEmpty)
                        Text(
                          'Nenhum membro ativo. Cadastre em Membros.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              height: 1.35),
                        ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if (contas.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: contaFieldId != null &&
                              contas.any((e) => e.id == contaFieldId)
                          ? contaFieldId
                          : null,
                      decoration: InputDecoration(
                        labelText: t == 'entrada'
                            ? 'Conta / caixa (crédito)'
                            : 'Conta / caixa (débito)',
                        hintText: 'Onde o valor entra ou sai',
                        filled: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        prefixIcon: const Icon(
                            Icons.account_balance_wallet_rounded),
                      ),
                      items: contas
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.nome)))
                          .toList(),
                      onChanged: (v) => setDlgState(() {
                        if (t == 'entrada') {
                          cdId = v;
                          coId = null;
                        } else {
                          coId = v;
                          cdId = null;
                        }
                      }),
                    ),
                  if (contas.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        border: Border.all(
                            color: Colors.orange.shade200, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: Colors.orange.shade800, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cadastre contas em Financeiro → Contas para vincular receitas e despesas.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.orange.shade900,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (t == 'entrada') ...[
                    const SizedBox(height: 14),
                    Text(
                      'Situação da receita',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Recebido'),
                          icon: Icon(Icons.check_circle_outline_rounded),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Pendente'),
                          icon: Icon(Icons.schedule_rounded),
                        ),
                      ],
                      selected: {recebimentoConfirmado},
                      onSelectionChanged: (s) =>
                          setDlgState(() => recebimentoConfirmado = s.first),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Só entra no saldo da conta quando estiver Recebido.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  if (t == 'saida') ...[
                    const SizedBox(height: 14),
                    Text(
                      'Situação da despesa',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Pago'),
                          icon: Icon(Icons.check_circle_outline_rounded),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Pendente'),
                          icon: Icon(Icons.schedule_rounded),
                        ),
                      ],
                      selected: {pagamentoConfirmado},
                      onSelectionChanged: (s) =>
                          setDlgState(() => pagamentoConfirmado = s.first),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Só sai do saldo da conta quando estiver Pago.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (isTransfer) ...[
                  DropdownButtonFormField<String>(
                    value: coId != null && contas.any((e) => e.id == coId)
                        ? coId
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Conta de origem',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon:
                          const Icon(Icons.account_balance_wallet_rounded),
                    ),
                    items: contas
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.nome)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => coId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: cdId != null && contas.any((e) => e.id == cdId)
                        ? cdId
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Conta de destino',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon: const Icon(Icons.account_balance_rounded),
                    ),
                    items: contas
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.nome)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => cdId = v),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: isTransfer
                        ? 'Anotações (opcional)'
                        : 'Descrição (opcional)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrCurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: r'Valor (R$)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dataCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrDateDdMmYyyyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Data (DD/MM/AAAA)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm)),
                    prefixIcon: const Icon(Icons.calendar_today_rounded,
                        size: 20, color: ThemeCleanPremium.onSurfaceVariant),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month_rounded),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: dataSelLocal,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDlgState(() {
                            dataSelLocal = picked;
                            dataCtrl.text = formatBrDateDdMmYyyy(picked);
                          });
                        }
                      },
                    ),
                  ),
                  onChanged: (v) {
                    final p = parseBrDateDdMmYyyy(v.trim());
                    if (p != null) setDlgState(() => dataSelLocal = p);
                  },
                ),
                const SizedBox(height: 12),
                if (!isTransfer) ...[
                  TextField(
                    controller: centroCustoCtrl,
                    decoration: InputDecoration(
                      labelText: 'Centro de custo / projeto (opcional)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon: const Icon(Icons.hub_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: extratoRefCtrl,
                    decoration: InputDecoration(
                      labelText: 'Ref. extrato / ID bancário (opcional)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon: const Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: conciliado,
                    onChanged: (v) => setDlgState(() => conciliado = v),
                    title: const Text('Conciliado com extrato'),
                    subtitle: const Text(
                        'Marque após conferir com o extrato ou app do banco.'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        size: 20, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text('Comprovante',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ],
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () async {
                    final source = await showDialog<ImageSource>(
                      context: ctx,
                      builder: (c) => SimpleDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusLg)),
                        title: const Text('Anexar comprovante'),
                        children: [
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.pop(c, ImageSource.camera),
                            child: const Row(children: [
                              Icon(Icons.camera_alt_rounded),
                              SizedBox(width: 12),
                              Text('Câmera')
                            ]),
                          ),
                          SimpleDialogOption(
                            onPressed: () =>
                                Navigator.pop(c, ImageSource.gallery),
                            child: const Row(children: [
                              Icon(Icons.photo_library_rounded),
                              SizedBox(width: 12),
                              Text('Galeria / Arquivo')
                            ]),
                          ),
                        ],
                      ),
                    );
                    if (source == null) return;
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(
                        source: source, maxWidth: 1200, imageQuality: 80);
                    if (xfile != null) {
                      comprovanteFile = xfile;
                      setDlgState(() {});
                    }
                  },
                  icon: Icon(
                      comprovanteFile != null
                          ? Icons.check_circle_rounded
                          : Icons.add_photo_alternate_rounded,
                      size: 20),
                  label: Text(comprovanteFile != null
                      ? 'Comprovante anexado'
                      : 'Anexar comprovante'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: comprovanteFile != null
                        ? ThemeCleanPremium.success
                        : null,
                  ),
                ),
                if (comprovanteFile != null)
                  TextButton.icon(
                    onPressed: () => setDlgState(() {
                      comprovanteFile = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Remover'),
                    style: TextButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.error),
                  ),
                if (isEdit &&
                    (data?['comprovanteUrl'] ?? '').toString().isNotEmpty &&
                    comprovanteFile == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Comprovante atual já anexado.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ),
              ],
                    ),
                  ),
                ),
                Material(
                  color: Theme.of(ctx)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.4),
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final valor = parseBrCurrencyInput(valorCtrl.text);
                            final parsedData =
                                parseBrDateDdMmYyyy(dataCtrl.text.trim());
                            if (parsedData == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Informe a data (DD/MM/AAAA).')));
                              return;
                            }
                            dataSelLocal = parsedData;
                            if (valor <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Informe um valor válido.')));
                              return;
                            }
                            if (!isTransfer && cat.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Selecione uma categoria.')));
                              return;
                            }
                            if (!isTransfer && contas.isNotEmpty) {
                              if (t == 'entrada' && cdId == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Selecione a conta ou caixa da receita.')));
                                return;
                              }
                              if (t == 'saida' && coId == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Selecione a conta ou caixa da despesa.')));
                                return;
                              }
                            }
                            if (isTransfer &&
                                (coId == null ||
                                    cdId == null ||
                                    coId == cdId)) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Selecione contas de origem e destino diferentes.')));
                              return;
                            }
                            final map = <String, dynamic>{
                              'type': t,
                              'amount': valor,
                              'descricao': descCtrl.text.trim(),
                              'createdAt':
                                  Timestamp.fromDate(dataSelLocal),
                            };
                            if (!isTransfer) {
                              map['categoria'] = cat;
                              map['centroCusto'] = centroCustoCtrl.text.trim();
                              map['extratoRef'] = extratoRefCtrl.text.trim();
                              map['conciliado'] = conciliado;
                            }
                            if (!isTransfer) {
                              final fid = fornecedorId;
                              final mid = membroId;
                              if (lockFornecedor &&
                                  fid != null &&
                                  fid.isNotEmpty) {
                                map['fornecedorId'] = fid;
                                map['fornecedorNome'] = fornecedorNome;
                              } else if (!lockFornecedor) {
                                if (vinculoTipo == 'fornecedor' &&
                                    fid != null &&
                                    fid.isNotEmpty) {
                                  map['fornecedorId'] = fid;
                                  map['fornecedorNome'] = fornecedorNome;
                                }
                                if (vinculoTipo == 'membro' &&
                                    mid != null &&
                                    mid.isNotEmpty) {
                                  map['membroId'] = mid;
                                  map['membroNome'] = membroNome;
                                }
                              }
                              if (t == 'entrada') {
                                map['recebimentoConfirmado'] =
                                    recebimentoConfirmado;
                              } else {
                                map['pagamentoConfirmado'] =
                                    pagamentoConfirmado;
                              }
                            }
                            if (isTransfer) {
                              map['contaOrigemId'] = coId;
                              map['contaDestinoId'] = cdId;
                              map['contaOrigemNome'] = nomeConta(coId);
                              map['contaDestinoNome'] = nomeConta(cdId);
                            } else if (contas.isNotEmpty) {
                              if (t == 'entrada') {
                                map['contaDestinoId'] = cdId;
                                map['contaDestinoNome'] = nomeConta(cdId);
                              } else {
                                map['contaOrigemId'] = coId;
                                map['contaOrigemNome'] = nomeConta(coId);
                              }
                            }
                            if (t == 'saida') {
                              final lim = settings.limiteAprovacaoDespesa;
                              final need = lim > 0 &&
                                  valor > lim &&
                                  AppPermissions
                                      .despesaFinanceiraExigeSegundaAprovacao(
                                          panelRole);
                              map['aprovacaoPendente'] = need;
                            }
                            Navigator.pop(ctx, map);
                          },
                          icon: Icon(isEdit
                              ? Icons.save_rounded
                              : Icons.check_rounded),
                          label:
                              Text(isEdit ? 'Salvar' : 'Adicionar'),
                          style: FilledButton.styleFrom(
                              backgroundColor:
                                  ThemeCleanPremium.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  if (result == null || !context.mounted) {
    valorCtrl.dispose();
    descCtrl.dispose();
    dataCtrl.dispose();
    centroCustoCtrl.dispose();
    extratoRefCtrl.dispose();
    return false;
  }

  try {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (isEdit) {
      final novoComp = comprovanteFile;
      if (novoComp != null) {
        final ref = FirebaseStorage.instance
            .ref('igrejas/$tenantId/comprovantes/${existingDoc.id}.jpg');
        final bytes = await novoComp.readAsBytes();
        final compressed = await ImageHelper.compressImage(
          bytes,
          minWidth: 800,
          minHeight: 600,
          quality: 70,
        );
        await ref.putData(
            compressed,
            SettableMetadata(
                contentType: 'image/jpeg',
                cacheControl: 'public, max-age=31536000'));
        final url = await ref.getDownloadURL();
        result['comprovanteUrl'] = url;
      } else if ((data?['comprovanteUrl'] ?? '').toString().isNotEmpty) {
        result['comprovanteUrl'] = data?['comprovanteUrl'];
      }
      final patch = Map<String, dynamic>.from(result);
      final tt = (patch['type'] ?? '').toString();
      if (tt == 'entrada') {
        patch['contaOrigemId'] = FieldValue.delete();
        patch['contaOrigemNome'] = FieldValue.delete();
        patch['pagamentoConfirmado'] = FieldValue.delete();
      } else if (tt == 'saida') {
        patch['contaDestinoId'] = FieldValue.delete();
        patch['contaDestinoNome'] = FieldValue.delete();
        patch['recebimentoConfirmado'] = FieldValue.delete();
      } else if (tt == 'transferencia') {
        patch['pagamentoConfirmado'] = FieldValue.delete();
        patch['recebimentoConfirmado'] = FieldValue.delete();
        patch['fornecedorId'] = FieldValue.delete();
        patch['fornecedorNome'] = FieldValue.delete();
        patch['membroId'] = FieldValue.delete();
        patch['membroNome'] = FieldValue.delete();
      }
      if (tt != 'transferencia') {
        final fid = patch['fornecedorId'];
        if (fid == null ||
            (fid is String && fid.toString().trim().isEmpty)) {
          patch['fornecedorId'] = FieldValue.delete();
          patch['fornecedorNome'] = FieldValue.delete();
        }
        final mid = patch['membroId'];
        if (mid == null ||
            (mid is String && mid.toString().trim().isEmpty)) {
          patch['membroId'] = FieldValue.delete();
          patch['membroNome'] = FieldValue.delete();
        }
      }
      await existingDoc.reference.update(patch);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lançamento atualizado!',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
    } else {
      final docRef = await financeCol.add(result);
      final novoCompAdd = comprovanteFile;
      if (novoCompAdd != null) {
        final ref = FirebaseStorage.instance
            .ref('igrejas/$tenantId/comprovantes/${docRef.id}.jpg');
        final bytesNew = await novoCompAdd.readAsBytes();
        final compressedNew = await ImageHelper.compressImage(
          bytesNew,
          minWidth: 800,
          minHeight: 600,
          quality: 70,
        );
        await ref.putData(
            compressedNew,
            SettableMetadata(
                contentType: 'image/jpeg',
                cacheControl: 'public, max-age=31536000'));
        final urlNew = await ref.getDownloadURL();
        await docRef.update({'comprovanteUrl': urlNew});
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lançamento salvo!',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
    return false;
  } finally {
    valorCtrl.dispose();
    descCtrl.dispose();
    dataCtrl.dispose();
    centroCustoCtrl.dispose();
    extratoRefCtrl.dispose();
  }
}

Future<void> uploadFinanceComprovanteForLancamento(
  BuildContext context, {
  required String tenantId,
  required DocumentSnapshot<Map<String, dynamic>> doc,
}) async {
  final picker = ImagePicker();
  final jaTem = ((doc.data()?['comprovanteUrl'] ?? '') as Object?)
          ?.toString()
          .trim()
          .isNotEmpty ==
      true;
  final source = await showDialog<ImageSource>(
    context: context,
    builder: (ctx) => SimpleDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
      title: Text(jaTem ? 'Trocar comprovante' : 'Anexar comprovante'),
      children: [
        if (!kIsWeb)
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              child: const Row(children: [
                Icon(Icons.camera_alt_rounded),
                SizedBox(width: 12),
                Text('Câmera')
              ])),
        SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Row(children: [
              Icon(Icons.photo_library_rounded),
              SizedBox(width: 12),
              Text('Galeria / Arquivo')
            ])),
      ],
    ),
  );
  if (source == null) return;

  final xfile = await picker.pickImage(
      source: source, maxWidth: 1200, imageQuality: 80);
  if (xfile == null) return;

  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Enviando comprovante...')));

  try {
    final ref = FirebaseStorage.instance
        .ref('igrejas/$tenantId/comprovantes/${doc.id}.jpg');
    final bytes = await xfile.readAsBytes();
    final compressed = await ImageHelper.compressImage(
      bytes,
      minWidth: 800,
      minHeight: 600,
      quality: 70,
    );
    await ref.putData(
        compressed,
        SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public, max-age=31536000'));
    final url = await ref.getDownloadURL();
    await doc.reference.update({'comprovanteUrl': url});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              jaTem ? 'Comprovante atualizado!' : 'Comprovante anexado!',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    }
  }
}

void showFinanceLancamentoDetailsBottomSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String comprovanteUrl,
  required String dataStr,
  required bool isEntrada,
  required bool isTransfer,
  required Color color,
  required double valor,
  required String titulo,
  required String subtitulo,
}) {
  final tipoLabel =
      isTransfer ? 'Transferência' : (isEntrada ? 'Receita' : 'Despesa');
  final origemNome = (data['contaOrigemNome'] ?? '').toString();
  final destinoNome = (data['contaDestinoNome'] ?? '').toString();
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    isTransfer
                        ? Icons.swap_horiz_rounded
                        : (isEntrada
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded),
                    color: color,
                    size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(tipoLabel,
                        style: TextStyle(
                            fontSize: 13,
                            color: color,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Text('R\$ ${valor.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ],
          ),
          const SizedBox(height: 16),
          if (isTransfer &&
              origemNome.isNotEmpty &&
              destinoNome.isNotEmpty) ...[
            Text('Conta de origem',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(origemNome, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text('Conta de destino',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(destinoNome, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          if (isTransfer &&
              (data['descricao'] ?? '').toString().trim().isNotEmpty) ...[
            Text('Anotações',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text((data['descricao'] ?? '').toString(),
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          if (subtitulo.isNotEmpty && !isTransfer) ...[
            Text('Descrição',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(subtitulo, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          if (!isTransfer) ...[
            Builder(
              builder: (_) {
                final fn = (data['fornecedorNome'] ?? '').toString().trim();
                final mn = (data['membroNome'] ?? '').toString().trim();
                if (fn.isEmpty && mn.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fn.isNotEmpty) ...[
                      Text('Fornecedor',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600)),
                      Text(fn, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 8),
                    ],
                    if (mn.isNotEmpty) ...[
                      Text('Membro',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600)),
                      Text(mn, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
          Text('Data',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          Text(dataStr, style: const TextStyle(fontSize: 15)),
          if (!isTransfer) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isEntrada
                      ? (data['recebimentoConfirmado'] == false
                          ? Icons.schedule_rounded
                          : Icons.verified_rounded)
                      : (data['pagamentoConfirmado'] == false
                          ? Icons.schedule_rounded
                          : Icons.verified_rounded),
                  size: 20,
                  color: (isEntrada
                          ? (data['recebimentoConfirmado'] == false)
                          : (data['pagamentoConfirmado'] == false))
                      ? Colors.amber.shade800
                      : Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEntrada
                        ? (data['recebimentoConfirmado'] == false
                            ? 'Receita pendente (ainda não entra no saldo da conta).'
                            : 'Receita recebida (entra no saldo da conta).')
                        : (data['pagamentoConfirmado'] == false
                            ? 'Despesa pendente (ainda não sai do saldo da conta).'
                            : 'Despesa paga (sai do saldo da conta).'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: (isEntrada
                              ? (data['recebimentoConfirmado'] == false)
                              : (data['pagamentoConfirmado'] == false))
                          ? Colors.amber.shade900
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (comprovanteUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Comprovante',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SafeNetworkImage(
                  imageUrl: comprovanteUrl,
                  height: 200,
                  fit: BoxFit.cover,
                  errorWidget: const Text('Erro ao carregar imagem')),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
double _parseValor(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return parseBrCurrencyInput(raw.toString());
}

DateTime _parseDate(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String && raw.length >= 10)
    return DateTime.tryParse(raw.substring(0, 10)) ?? DateTime.now();
  if (raw is Map) {
    final sec = raw['seconds'] ?? raw['_seconds'];
    if (sec != null)
      return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
  }
  return DateTime.now();
}

/// Data do lançamento (mesma lógica do card: createdAt ou date).
DateTime _financeLancamentoInstant(Map<String, dynamic> data) =>
    _parseDate(data['createdAt'] ?? data['date']);

DateTime _financeLancamentoDiaSomente(Map<String, dynamic> data) {
  final d = _financeLancamentoInstant(data);
  return DateTime(d.year, d.month, d.day);
}

int _compareFinanceDocsChrono(
  DocumentSnapshot<Map<String, dynamic>> a,
  DocumentSnapshot<Map<String, dynamic>> b,
) {
  final da = _financeLancamentoInstant(a.data() ?? {});
  final db = _financeLancamentoInstant(b.data() ?? {});
  final c = da.compareTo(db);
  if (c != 0) return c;
  return a.id.compareTo(b.id);
}

/// Linha da lista: cabeçalho de dia ou cartão de lançamento.
class _FinanceLancamentoListRow {
  const _FinanceLancamentoListRow.header(DateTime d)
      : isHeader = true,
        day = d,
        doc = null;

  const _FinanceLancamentoListRow.item(DocumentSnapshot<Map<String, dynamic>> d)
      : isHeader = false,
        day = null,
        doc = d;

  final bool isHeader;
  final DateTime? day;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
}

List<_FinanceLancamentoListRow> _buildLancamentosGroupedByDay(
  List<DocumentSnapshot<Map<String, dynamic>>> docs,
) {
  if (docs.isEmpty) return [];
  final sorted = List<DocumentSnapshot<Map<String, dynamic>>>.from(docs)
    ..sort(_compareFinanceDocsChrono);
  final rows = <_FinanceLancamentoListRow>[];
  DateTime? prevDia;
  for (final d in sorted) {
    final data = d.data() ?? {};
    final dia = _financeLancamentoDiaSomente(data);
    if (prevDia == null ||
        dia.year != prevDia.year ||
        dia.month != prevDia.month ||
        dia.day != prevDia.day) {
      prevDia = dia;
      rows.add(_FinanceLancamentoListRow.header(dia));
    }
    rows.add(_FinanceLancamentoListRow.item(d));
  }
  return rows;
}

class _FinanceDayHeaderTile extends StatelessWidget {
  const _FinanceDayHeaderTile({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final s =
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.12),
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 16, color: ThemeCleanPremium.primary.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Text(
            s,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color.lerp(
                      ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.35) ??
                  ThemeCleanPremium.primary,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
