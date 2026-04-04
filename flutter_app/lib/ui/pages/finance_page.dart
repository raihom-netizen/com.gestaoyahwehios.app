import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

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

// Padrão de cores do módulo financeiro: entradas azul, saídas vermelho, saldo positivo verde, negativo vermelho
const Color _financeEntradas = Color(0xFF2563EB); // azul — receitas/entradas
const Color _financeSaidas = Color(0xFFDC2626); // vermelho — despesas/saídas
const Color _financeSaldoPositivo = Color(0xFF16A34A); // verde — saldo positivo
const Color _financeSaldoNegativo =
    Color(0xFFDC2626); // vermelho — saldo negativo
const Color _financeTransferencia =
    Color(0xFF6366F1); // índigo — transferências

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

  const FinancePage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf,
    this.podeVerFinanceiro,
    this.permissions,
  });

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final CollectionReference<Map<String, dynamic>> _financeCol;
  late final DocumentReference<Map<String, dynamic>> _tenantRef;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tenantRef =
        FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId);
    _financeCol = _tenantRef.collection('finance');
    FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  /// Garante categorias de receita no Firestore; retorna lista de nomes (sem repetição).
  Future<List<String>> _getCategoriasReceita() async {
    final col = _tenantRef.collection('categorias_receitas');
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

  /// Garante categorias de despesa no Firestore; retorna lista de nomes (sem repetição).
  Future<List<String>> _getCategoriasDespesa() async {
    final col = _tenantRef.collection('categorias_despesas');
    var snap = await col.orderBy('nome').get();
    if (snap.docs.isEmpty) {
      for (final nome in _categoriasDespesaPadrao) {
        await col.add(
            {'nome': nome, 'ordem': _categoriasDespesaPadrao.indexOf(nome)});
      }
      snap = await col.orderBy('nome').get();
    }
    final nomes = snap.docs
        .map((d) => (d.data()['nome'] ?? '').toString())
        .where((s) => s.isNotEmpty);
    final seen = <String>{};
    return nomes.where((n) => seen.add(n)).toList();
  }

  /// Lista contas ativas (id, nome) para transferências.
  Future<List<({String id, String nome})>> _getContas() async {
    final snap = await _tenantRef.collection('contas').orderBy('nome').get();
    return snap.docs
        .where((d) => d.data()['ativo'] != false)
        .map((d) => (id: d.id, nome: (d.data()['nome'] ?? '').toString()))
        .where((e) => e.nome.isNotEmpty)
        .toList();
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
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                title: const Text('Financeiro'),
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
              leading: canPop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar')
                  : null,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Receitas e Despesas',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  tooltip: 'Exportar PDF',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget)),
                  onPressed: () => _exportarPdf(context),
                ),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'Exportar CSV',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget)),
                  onPressed: () => _exportarCSV(context),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_finance',
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text('Lançamento Rápido',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        onPressed: () => _showLancamentoDialog(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Padding(
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
                      style:
                          IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => _exportarPdf(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded),
                      tooltip: 'Exportar CSV',
                      style:
                          IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: () => _exportarCSV(context),
                    ),
                  ],
                ),
              ),
            Container(
              margin: EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceLg,
                  vertical: ThemeCleanPremium.spaceSm),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: TabBar(
                controller: _tabCtrl,
                labelColor: ThemeCleanPremium.primary,
                unselectedLabelColor: ThemeCleanPremium.onSurfaceVariant,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Resumo'),
                  Tab(text: 'Lançamentos'),
                  Tab(text: 'Despesas Fixas'),
                  Tab(text: 'Categorias'),
                  Tab(text: 'Contas'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _ResumoTab(
                    financeCol: _financeCol,
                    tenantId: widget.tenantId,
                    role: widget.role,
                  ),
                  _LancamentosTab(
                    financeCol: _financeCol,
                    tenantId: widget.tenantId,
                    role: widget.role,
                  ),
                  _DespesasFixasTab(
                    tenantId: widget.tenantId,
                    role: widget.role,
                  ),
                  _FinanceCategoriasTab(tenantId: widget.tenantId),
                  _FinanceContasTab(tenantId: widget.tenantId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Lançamento Rápido (Receita / Despesa / Transferência) ────────────────────
  Future<void> _showLancamentoDialog(BuildContext context,
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isEdit = doc != null;
    final data = doc?.data();

    String tipo = isEdit ? (data?['type'] ?? 'entrada').toString() : 'entrada';
    if (tipo != 'entrada' && tipo != 'saida' && tipo != 'transferencia')
      tipo = 'entrada';
    final valorCtrl = TextEditingController(
        text:
            isEdit ? (data?['amount'] ?? data?['valor'] ?? '').toString() : '');
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
    String? contaDestinoId = isEdit
        ? ((data?['contaDestinoId'] ?? '').toString().isEmpty
            ? null
            : (data?['contaDestinoId']).toString())
        : null;
    DateTime dataSel = DateTime.now();
    if (isEdit) {
      final ts = data?['createdAt'] ?? data?['date'];
      if (ts is Timestamp) dataSel = ts.toDate();
    }

    final catsReceita = await _getCategoriasReceita();
    final catsDespesa = await _getCategoriasDespesa();
    final contas = await _getContas();
    if (categoria.isNotEmpty) {
      if (tipo == 'entrada' && !catsReceita.contains(categoria)) categoria = '';
      if (tipo == 'saida' && !catsDespesa.contains(categoria)) categoria = '';
    }
    if (contaOrigemId != null && !contas.any((c) => c.id == contaOrigemId))
      contaOrigemId = null;
    if (contaDestinoId != null && !contas.any((c) => c.id == contaDestinoId))
      contaDestinoId = null;

    if (!mounted) return;
    String t = tipo;
    String cat = categoria;
    String? coId = contaOrigemId;
    String? cdId = contaDestinoId;
    DateTime dataSelLocal = dataSel;
    XFile? comprovanteFile;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isTransfer = t == 'transferencia';
          final cats = t == 'entrada'
              ? catsReceita
              : (t == 'saida' ? catsDespesa : <String>[]);
          if (cat.isNotEmpty && cats.isNotEmpty && !cats.contains(cat))
            cat = '';
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            title: Row(
              children: [
                Icon(isEdit ? Icons.edit_rounded : Icons.add_circle_rounded,
                    color: ThemeCleanPremium.primary),
                const SizedBox(width: 10),
                Text(isEdit ? 'Editar Lançamento' : 'Transação',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                      t = s.first;
                      cat = '';
                      coId = null;
                      cdId = null;
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
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        prefixIcon: const Icon(Icons.category_rounded),
                      ),
                      items: cats
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setDlgState(() => cat = v ?? ''),
                    ),
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: r'Valor (R$)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm)),
                      prefixIcon: const Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: dataSelLocal,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null)
                        setDlgState(() => dataSelLocal = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 20,
                              color: ThemeCleanPremium.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Text(
                            '${dataSelLocal.day.toString().padLeft(2, '0')}/${dataSelLocal.month.toString().padLeft(2, '0')}/${dataSelLocal.year}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton.icon(
                onPressed: () {
                  final valor =
                      double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
                  if (valor <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Informe um valor válido.')));
                    return;
                  }
                  if (!isTransfer && cat.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Selecione uma categoria.')));
                    return;
                  }
                  if (isTransfer &&
                      (coId == null || cdId == null || coId == cdId)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text(
                            'Selecione contas de origem e destino diferentes.')));
                    return;
                  }
                  final map = <String, dynamic>{
                    'type': t,
                    'amount': valor,
                    'descricao': descCtrl.text.trim(),
                    'createdAt': Timestamp.fromDate(dataSelLocal),
                  };
                  if (!isTransfer) map['categoria'] = cat;
                  if (isTransfer) {
                    map['contaOrigemId'] = coId;
                    map['contaDestinoId'] = cdId;
                    map['contaOrigemNome'] =
                        contas.where((e) => e.id == coId).firstOrNull?.nome ??
                            '';
                    map['contaDestinoNome'] =
                        contas.where((e) => e.id == cdId).firstOrNull?.nome ??
                            '';
                  }
                  Navigator.pop(ctx, map);
                },
                icon: Icon(isEdit ? Icons.save_rounded : Icons.check_rounded),
                label: Text(isEdit ? 'Salvar' : 'Adicionar'),
                style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (isEdit) {
        if (comprovanteFile != null) {
          final ref = FirebaseStorage.instance
              .ref('igrejas/${widget.tenantId}/comprovantes/${doc!.id}.jpg');
          final bytes = await comprovanteFile!.readAsBytes();
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
          result['comprovanteUrl'] = data!['comprovanteUrl'];
        }
        await doc!.reference.update(result);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Lançamento atualizado!',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green));
      } else {
        final docRef = await _financeCol.add(result);
        if (comprovanteFile != null) {
          final ref = FirebaseStorage.instance
              .ref('igrejas/${widget.tenantId}/comprovantes/${docRef.id}.jpg');
          final bytes = await comprovanteFile!.readAsBytes();
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
          await docRef.update({'comprovanteUrl': url});
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Lançamento salvo!',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
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
    final buffer = StringBuffer('Tipo,Categoria,Descrição,Valor,Data\n');
    for (final d in snap.docs) {
      final data = d.data();
      final tipo = (data['type'] ?? 'entrada').toString();
      final cat = (data['categoria'] ?? '').toString();
      final desc = (data['descricao'] ?? '').toString().replaceAll(',', ' ');
      final valor = (data['amount'] ?? data['valor'] ?? 0).toString();
      String dataStr = '';
      final ts = data['createdAt'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        dataStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
      buffer.writeln('$tipo,$cat,$desc,$valor,$dataStr');
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
    try {
      final snap = await _financeCol
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum lançamento para exportar.')));
        return;
      }
      final branding = await loadReportPdfBranding(widget.tenantId);
      if (!mounted) return;
      final docs = snap.docs;
      double entradas = 0, saidas = 0;
      final data = docs.map((d) {
        final m = d.data();
        final tipo = (m['type'] ?? m['tipo'] ?? 'entrada').toString();
        final valor = (m['amount'] ?? m['valor'] ?? 0) is num
            ? (m['amount'] ?? m['valor'] ?? 0) as num
            : 0.0;
        if (tipo.toLowerCase().contains('entrada') || tipo == 'receita')
          entradas += valor.toDouble();
        else if (tipo != 'transferencia') saidas += valor.toDouble();
        final ts = m['createdAt'];
        String dataStr = '';
        if (ts is Timestamp)
          dataStr = DateFormat('dd/MM/yyyy').format(ts.toDate());
        return [
          dataStr,
          tipo,
          (m['categoria'] ?? '').toString(),
          (m['descricao'] ?? '').toString(),
          valor.toStringAsFixed(2)
        ];
      }).toList();
      final pdf = pw.Document();
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
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted)
        await showPdfActions(context,
            bytes: bytes, filename: 'financeiro_relatorio.pdf');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao exportar PDF: $e')));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — Resumo (gráficos + totalizadores)
// ═══════════════════════════════════════════════════════════════════════════════
class _ResumoTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;

  const _ResumoTab({
    required this.financeCol,
    required this.tenantId,
    required this.role,
  });

  @override
  State<_ResumoTab> createState() => _ResumoTabState();
}

class _ResumoTabState extends State<_ResumoTab> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _future;
  late final Future<QuerySnapshot<Map<String, dynamic>>> _futureContas;
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
      future: Future.wait([_future, _futureContas]),
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

        // Saldo por conta (apenas transferências: usa TODOS os docs — saldo acumulado)
        final saldoPorConta = <String, double>{};
        for (final c in contasDocs) {
          if (c.data()['ativo'] == false) continue;
          final id = c.id;
          saldoPorConta[id] = 0.0;
        }
        for (final d in allDocs) {
          final data = d.data();
          final tipo = (data['type'] ?? '').toString().toLowerCase();
          if (tipo != 'transferencia') continue;
          final valor = _parseValor(data['amount'] ?? data['valor']);
          final origemId = (data['contaOrigemId'] ?? '').toString();
          final destinoId = (data['contaDestinoId'] ?? '').toString();
          if (destinoId.isNotEmpty && saldoPorConta.containsKey(destinoId))
            saldoPorConta[destinoId] = (saldoPorConta[destinoId] ?? 0) + valor;
          if (origemId.isNotEmpty && saldoPorConta.containsKey(origemId))
            saldoPorConta[origemId] = (saldoPorConta[origemId] ?? 0) - valor;
        }

        final parent = context.findAncestorStateOfType<_FinancePageState>();
        final contasAtivas =
            contasDocs.where((c) => c.data()['ativo'] != false).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceLg,
              vertical: ThemeCleanPremium.spaceXl),
          child: Column(
            children: [
              // Filtros por período
              SingleChildScrollView(
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
                            await parent?._showLancamentoDialog(ctx, doc: doc);
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
                            await parent?._showLancamentoDialog(ctx, doc: doc);
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
                      final nome = (c.data()['nome'] ?? '').toString();
                      final saldoConta = saldoPorConta[id] ?? 0.0;
                      final cor = saldoConta >= 0
                          ? _financeSaldoPositivo
                          : _financeSaldoNegativo;
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
                                  contaNome: nome,
                                  onEdit: (ctx, doc) async {
                                    await parent?._showLancamentoDialog(ctx,
                                        doc: doc);
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
// Movimentações da conta (entradas e saídas — transferências que envolvem a conta)
// ═══════════════════════════════════════════════════════════════════════════════
class _MovimentacoesContaPage extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> financeCol;
  final String tenantId;
  final String role;
  final String contaId;
  final String contaNome;
  final Future<void> Function(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) onEdit;

  const _MovimentacoesContaPage({
    required this.financeCol,
    required this.tenantId,
    required this.role,
    required this.contaId,
    required this.contaNome,
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
        title: Text(widget.contaNome,
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
              title: 'Não foi possível carregar as transferências',
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
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (tipo != 'transferencia') return false;
            final origem = (data['contaOrigemId'] ?? '').toString();
            final destino = (data['contaDestinoId'] ?? '').toString();
            return origem == widget.contaId || destino == widget.contaId;
          }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Text('Nenhuma movimentação nesta conta.',
                      style:
                          TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  Text(
                      'As transferências que envolvem esta conta aparecem aqui.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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
                      onEdit: () async {
                        await widget.onEdit(context, docs[i]);
                        if (mounted) _refresh();
                      },
                      onDelete: () => _excluirLancamento(docs[i]),
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
            const Text('Tem certeza que deseja excluir esta transferência?'),
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
    await doc.reference.delete();
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
                    padding: EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceLg,
                        80),
                    itemCount: docs.length,
                    itemBuilder: (context, i) => _LancamentoCard(
                      doc: docs[i],
                      tenantId: widget.tenantId,
                      onEdit: () async {
                        await widget.onEdit(context, docs[i]);
                        if (mounted) _refresh();
                      },
                      onDelete: () => _excluirLancamento(docs[i]),
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
    await doc.reference.delete();
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

  const _LancamentosTab(
      {required this.financeCol, required this.tenantId, required this.role});

  @override
  State<_LancamentosTab> createState() => _LancamentosTabState();
}

class _LancamentosTabState extends State<_LancamentosTab> {
  String _filtroTipo = 'todos';
  String _filtroCategoria = 'todas';
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = widget.financeCol.orderBy('createdAt', descending: true).get();
  }

  void _refresh() {
    setState(() {
      _future = widget.financeCol.orderBy('createdAt', descending: true).get();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_rounded,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Nenhum lançamento encontrado.',
                    style:
                        TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              ],
            ),
          );
        }

        // Filtros
        if (_filtroTipo != 'todos') {
          docs = docs.where((d) {
            final tipo = (d.data()['type'] ?? '').toString().toLowerCase();
            if (_filtroTipo == 'entrada')
              return tipo.contains('entrada') || tipo.contains('receita');
            return tipo.contains('saida') || tipo.contains('despesa');
          }).toList();
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

        return Column(
          children: [
            // Filtros — card premium
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceLg,
                  vertical: ThemeCleanPremium.spaceSm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceSm,
                    vertical: ThemeCleanPremium.spaceSm),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _filtroTipo,
                            isExpanded: true,
                            icon:
                                const Icon(Icons.filter_list_rounded, size: 20),
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
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          border: Border.all(color: Colors.grey.shade200),
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
                            onChanged: (v) =>
                                setState(() => _filtroCategoria = v ?? 'todas'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceLg),
              child: Text('${docs.length} lançamento(s)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700)),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 4,
                    ThemeCleanPremium.spaceLg, 100),
                itemCount: docs.length,
                itemBuilder: (context, i) => _LancamentoCard(
                  doc: docs[i],
                  tenantId: widget.tenantId,
                  onEdit: () => _editarLancamento(docs[i]),
                  onDelete: () => _excluirLancamento(docs[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _editarLancamento(DocumentSnapshot<Map<String, dynamic>> doc) {
    final parent = context.findAncestorStateOfType<_FinancePageState>();
    parent?._showLancamentoDialog(context, doc: doc);
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
    await doc.reference.delete();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lançamento excluído.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green));
  }
}

// ─── Card de Lançamento Individual ────────────────────────────────────────────
class _LancamentoCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final String tenantId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LancamentoCard(
      {required this.doc,
      required this.tenantId,
      required this.onEdit,
      required this.onDelete});

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

    final color = isTransfer
        ? _financeTransferencia
        : (isEntrada ? _financeEntradas : _financeSaidas);
    final titulo = isTransfer ? 'Transferência' : categoria;
    final subtitulo = isTransfer
        ? (origemNome.isNotEmpty && destinoNome.isNotEmpty
            ? '$origemNome → $destinoNome'
            : descricao)
        : descricao;

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          onTap: () => _showDetalhes(context, data, comprovanteUrl, dataStr,
              isEntrada, isTransfer, color, valor, titulo, subtitulo),
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
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
                      Text(titulo,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (subtitulo.isNotEmpty)
                        Text(subtitulo,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(dataStr,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                          if (comprovanteUrl.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.attach_file_rounded,
                                size: 14, color: Colors.grey.shade500),
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
                          onTap: () =>
                              _uploadComprovante(context, doc, tenantId),
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

  void _showDetalhes(
      BuildContext context,
      Map<String, dynamic> data,
      String comprovanteUrl,
      String dataStr,
      bool isEntrada,
      bool isTransfer,
      Color color,
      double valor,
      String titulo,
      String subtitulo) {
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
            Text('Data',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            Text(dataStr, style: const TextStyle(fontSize: 15)),
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

  Future<void> _uploadComprovante(BuildContext context,
      DocumentSnapshot<Map<String, dynamic>> doc, String tenantId) async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Anexar comprovante'),
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
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Comprovante anexado!',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    }
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
        text: isEdit ? (data?['valor'] ?? '').toString() : '');
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

    final categoriasList =
        await _getCategoriasDespesaForTenant(widget.tenantId);
    if (categoria.isNotEmpty && !categoriasList.contains(categoria))
      categoria = '';

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
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: dataInicio ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030));
                          if (d != null) {
                            dataInicio = d;
                            dataFim = d.add(const Duration(days: 365));
                            setDlgState(() {});
                          }
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(dataInicio != null
                            ? DateFormat('dd/MM/yyyy').format(dataInicio!)
                            : 'Data início'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: dataFim ??
                                  dataInicio?.add(const Duration(days: 365)) ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: dataInicio ?? DateTime(2020),
                              lastDate: DateTime(2030));
                          if (d != null) {
                            dataFim = d;
                            setDlgState(() {});
                          }
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(dataFim != null
                            ? DateFormat('dd/MM/yyyy').format(dataFim!)
                            : 'Data fim'),
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
                final valor =
                    double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;
                if (descCtrl.text.trim().isEmpty || valor <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Preencha descrição e valor.')));
                  return;
                }
                final payload = <String, dynamic>{
                  'descricao': descCtrl.text.trim(),
                  'valor': valor,
                  'categoria': categoria,
                  'diaVencimento': int.tryParse(diaCtrl.text) ?? 0,
                  'ativo': true,
                };
                if (dataInicio != null)
                  payload['dataInicio'] = Timestamp.fromDate(dataInicio!);
                if (dataFim != null)
                  payload['dataFim'] = Timestamp.fromDate(dataFim!);
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

    if (result == null) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (isEdit) {
      await doc!.reference.update(result);
    } else {
      await _col.add(result);
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

    await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('finance')
        .add({
      'type': 'saida',
      'amount': despesa['valor'] ?? 0,
      'categoria': despesa['categoria'] ?? despesa['descricao'] ?? '',
      'descricao': '${despesa['descricao'] ?? ''} (Despesa Fixa)',
      'createdAt': Timestamp.fromDate(now),
    });
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

  const _FinanceContasTab({required this.tenantId});

  @override
  State<_FinanceContasTab> createState() => _FinanceContasTabState();
}

class _FinanceContasTabState extends State<_FinanceContasTab> {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas');

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
                      'Contas para transferências (origem/destino)',
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
                    final nome = (d.data()['nome'] ?? '').toString();
                    final ativo = d.data()['ativo'] != false;
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
                        subtitle: ativo
                            ? null
                            : Text('Inativa',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
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
    final ctrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Nova conta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome da conta',
            hintText: 'Ex.: Caixa da Tesouraria',
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
      await col.add({'nome': nome, 'ativo': true});
      if (context.mounted) {
        onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conta adicionada.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
    }
  }

  Future<void> _showEditConta(
      BuildContext context,
      CollectionReference<Map<String, dynamic>> col,
      DocumentSnapshot<Map<String, dynamic>> doc,
      {VoidCallback? onSaved}) async {
    final nomeAtual = (doc.data()?['nome'] ?? '').toString();
    final ctrl = TextEditingController(text: nomeAtual);
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Editar conta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Nome', border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar'),
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary),
          ),
        ],
      ),
    );
    if (nome != null && nome.isNotEmpty && context.mounted) {
      await doc.reference.update({'nome': nome});
      if (context.mounted) {
        onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conta atualizada.',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green));
      }
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
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
            color: color.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6)),
      ],
      border: Border.all(color: color.withOpacity(0.15), width: 1),
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
            color: selected
                ? ThemeCleanPremium.primary.withOpacity(0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: ThemeCleanPremium.primary.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
                color: selected
                    ? ThemeCleanPremium.primary.withOpacity(0.3)
                    : const Color(0xFFE2E8F0)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
              color: ThemeCleanPremium.primary.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 6)),
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
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(
              minWidth: ThemeCleanPremium.minTouchTarget,
              minHeight: ThemeCleanPremium.minTouchTarget),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
double _parseValor(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0;
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
