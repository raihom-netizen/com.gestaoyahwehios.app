import 'dart:async' show StreamSubscription, TimeoutException, Timer, unawaited;
import 'dart:typed_data';

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
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/ui/widgets/finance_comprovante_ui.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/core/gestao_yahweh_write_first_publish_service.dart';
import 'package:gestao_yahweh/core/yahweh_central_engine_service.dart';
import 'package:gestao_yahweh/ui/widgets/lazy_load_more_footer.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/church_module_query_probe.dart';
import 'package:gestao_yahweh/core/brasil_bancos.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/ui/pages/finance_receitas_recorrentes_tabs.dart';
import 'package:gestao_yahweh/services/despesas_fixas_geracao_service.dart';
import 'package:gestao_yahweh/ui/widgets/finance_resumo_charts_section.dart';
import 'package:gestao_yahweh/ui/widgets/finance_fixo_premium_dialogs.dart';
import 'package:gestao_yahweh/services/finance_audit_log_service.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/ui/pages/finance_bulk_assign_page.dart';
import 'package:gestao_yahweh/ui/pages/finance_smart_input_page.dart';
import 'package:gestao_yahweh/ui/pages/relatorios_page.dart'
    show RelatorioFinanceiroPage;
import 'package:gestao_yahweh/utils/finance_category_grouping.dart';
import 'package:gestao_yahweh/utils/finance_firestore_resilience.dart';
import 'package:gestao_yahweh/services/finance_despesas_categorias_tenant.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/services/panel_finance_accounts_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/finance_premium_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/finance_premium_lancamento_ui.dart';
import 'package:gestao_yahweh/ui/widgets/church_signatory_picker_sheet.dart';

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
  final branding = brasilBancoBrandingFor(
    codigo: (d['bancoCodigo'] ?? '').toString(),
    nome: _financeContaBancoNome(d),
  );
  if (branding != kBrasilBancoBrandingFallback) {
    return Color(branding.colorHex);
  }
  final banco = _financeContaBancoNome(d).toLowerCase();
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

Widget _financeBankMiniLogo({
  required String bancoCodigo,
  required String bancoNome,
  double size = 28,
  double fontSize = 11,
}) {
  final branding = brasilBancoBrandingFor(codigo: bancoCodigo, nome: bancoNome);
  final color = Color(branding.colorHex);
  final bg = color.withValues(alpha: 0.16);
  final initials = branding.initials.trim().isNotEmpty
      ? branding.initials.trim()
      : (bancoNome.trim().isEmpty ? 'BK' : bancoNome.trim().substring(0, 1).toUpperCase());
  final logoPath = (branding.miniLogoAssetPath ?? '').trim();
  final fallback = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      shape: BoxShape.circle,
      border: Border.all(color: color.withValues(alpha: 0.42)),
    ),
    alignment: Alignment.center,
    child: Text(
      initials,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.1,
        color: color,
      ),
    ),
  );
  if (logoPath.isEmpty) return fallback;
  return ClipOval(
    child: Image.asset(
      logoPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    ),
  );
}

Future<List<String>> _financeCategoriasReceitaTenant(String tenantId) async {
  try {
    final op = ChurchRepository.churchId(tenantId);
    if (op.isEmpty) return List<String>.from(_categoriasReceitaPadrao);
    final col = ChurchUiCollections.churchDoc(op)
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
    final list = nomes.where((n) => seen.add(n)).toList();
    return list.isEmpty ? List<String>.from(_categoriasReceitaPadrao) : list;
  } catch (_) {
    return List<String>.from(_categoriasReceitaPadrao);
  }
}

Future<List<({String id, String nome})>> _financeContasAtivasTenant(
    String tenantId) async {
  try {
    final op = ChurchRepository.churchId(tenantId);
    if (op.isEmpty) return const [];
    final snap = await ChurchUiCollections.churchDoc(op)
        .collection('contas')
        .orderBy('nome')
        .get();
    return snap.docs
        .where((d) => d.data()['ativo'] != false)
        .map((d) => (id: d.id, nome: _financeContaDisplayName(d.data())))
        .where((e) => e.nome.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

class _FinancePdfSignerSelection {
  final String leftName;
  final String rightName;
  final Uint8List? leftSignatureBytes;
  final Uint8List? rightSignatureBytes;
  final bool showDigitalSignatures;
  final PdfDigitalStampInput? leftDigitalStamp;
  final PdfDigitalStampInput? rightDigitalStamp;

  const _FinancePdfSignerSelection({
    required this.leftName,
    required this.rightName,
    required this.leftSignatureBytes,
    required this.rightSignatureBytes,
    required this.showDigitalSignatures,
    this.leftDigitalStamp,
    this.rightDigitalStamp,
  });
}

Future<Uint8List?> _financeTryLoadSignatureBytes(String rawUrl) async {
  final url = sanitizeImageUrl(rawUrl.trim());
  if (url.isEmpty) return null;
  final bytes = await ImageHelper.getBytesFromUrlOrNull(
    url,
    timeout: const Duration(seconds: 14),
  );
  if (bytes == null || bytes.length < 24) return null;
  return bytes;
}

Future<_FinancePdfSignerSelection?> _pickFinancePdfSigners(
  BuildContext context, {
  required String tenantId,
}) async {
  final signers = await ChurchSignatoryLoadService.loadEligible(
    seedTenantId: tenantId,
  );
  if (!context.mounted) return null;

  final picked = await showChurchDualSignatoryDialog(
    context,
    title: 'Assinaturas do PDF financeiro',
    signers: signers,
  );
  if (picked == null || !context.mounted) return null;

  Map<String, dynamic> churchData = {};
  String churchName = '';
  try {
    final snap = await ChurchRepository.churchDoc(tenantId).get();
    churchData = snap.data() ?? {};
    churchName = churchTaxIdChurchNameFromMap(churchData);
  } catch (_) {}

  PdfDigitalStampInput? leftStamp;
  PdfDigitalStampInput? rightStamp;
  if (picked.digital) {
    if (picked.left != null) {
      leftStamp = PdfDigitalStampInput.now(
        signerName: picked.left!.nome,
        signerCpfDigits: picked.left!.cpfDigits,
        churchName: churchName,
        churchData: churchData,
      );
    }
    if (picked.right != null) {
      rightStamp = PdfDigitalStampInput.now(
        signerName: picked.right!.nome,
        signerCpfDigits: picked.right!.cpfDigits,
        churchName: churchName,
        churchData: churchData,
      );
    }
  }

  return _FinancePdfSignerSelection(
    leftName: picked.left?.nome ?? 'Tesoureiro(a)',
    rightName: picked.right?.nome ?? 'Pastor Presidente',
    leftSignatureBytes: null,
    rightSignatureBytes: null,
    showDigitalSignatures: picked.digital,
    leftDigitalStamp: leftStamp,
    rightDigitalStamp: rightStamp,
  );
}

/// PDF Super Premium — lançamentos financeiros (lista completa ou filtrada).
Future<void> exportFinanceiroRelatorioPdf({
  required BuildContext context,
  required String tenantId,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  List<String> filterSummaryLines = const [],
  String filename = 'financeiro_relatorio.pdf',
  String leftSignerName = 'Tesoureiro(a)',
  String rightSignerName = 'Pastor Presidente',
  Uint8List? leftSignatureBytes,
  Uint8List? rightSignatureBytes,
  bool showDigitalSignatures = false,
  PdfDigitalStampInput? leftDigitalStamp,
  PdfDigitalStampInput? rightDigitalStamp,
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
          pw.SizedBox(height: 22),
          PdfSuperPremiumTheme.reportDualSignatureAttestation(
            accent: branding.accent,
            leftSignerName: leftSignerName,
            rightSignerName: rightSignerName,
            leftSignatureImageBytes: leftSignatureBytes,
            rightSignatureImageBytes: rightSignatureBytes,
            showDigitalSignatures: showDigitalSignatures,
            leftDigitalStamp: leftDigitalStamp,
            rightDigitalStamp: rightDigitalStamp,
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
  String leftSignerName = 'Tesoureiro(a)',
  String rightSignerName = 'Pastor Presidente',
  Uint8List? leftSignatureBytes,
  Uint8List? rightSignatureBytes,
  bool showDigitalSignatures = false,
  PdfDigitalStampInput? leftDigitalStamp,
  PdfDigitalStampInput? rightDigitalStamp,
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
          pw.SizedBox(height: 22),
          PdfSuperPremiumTheme.reportDualSignatureAttestation(
            accent: branding.accent,
            leftSignerName: leftSignerName,
            rightSignerName: rightSignerName,
            leftSignatureImageBytes: leftSignatureBytes,
            rightSignatureImageBytes: rightSignatureBytes,
            showDigitalSignatures: showDigitalSignatures,
            leftDigitalStamp: leftDigitalStamp,
            rightDigitalStamp: rightDigitalStamp,
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
      final list = await getCategoriasDespesaForTenant(widget.tenantId);
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
      await _ensureFinanceWriteReady();
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
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

  /// Voltar ao Painel no shell mobile (full screen).
  final VoidCallback? onShellBack;

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
    this.onShellBack,
  });

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  /// Mesmo critério que Eventos/Chat: doc operacional (cluster irmão) ganha sobre hint.
  String? _firestoreTenantId;
  bool _financeBootstrapDone = false;
  String get _tid {
    final hint = (_firestoreTenantId ?? '').trim().isNotEmpty
        ? _firestoreTenantId!.trim()
        : widget.tenantId.trim();
    return ChurchRepository.churchId(hint).isNotEmpty
        ? ChurchRepository.churchId(hint)
        : hint;
  }

  DocumentReference<Map<String, dynamic>> get _tenantRef =>
      ChurchUiCollections.churchDoc(_tid);

  CollectionReference<Map<String, dynamic>> get _financeCol =>
      ChurchUiCollections.financeiro(_tid);

  /// Incrementado após salvar/excluir lançamento — atualiza Resumo + Lançamentos.
  int _financeRevision = 0;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _financeRealtimeSubs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  Timer? _financeRealtimeDebounce;

  Future<void> _warmupBankBrandingAssets() async {
    if (!mounted) return;
    final paths = <String>{};
    for (final b in kBrasilBancosComuns) {
      final p =
          (brasilBancoBrandingFor(codigo: b.codigo, nome: b.nome).miniLogoAssetPath ?? '')
              .trim();
      if (p.isNotEmpty) paths.add(p);
    }
    for (final p in paths) {
      try {
        await precacheImage(AssetImage(p), context);
      } catch (_) {}
    }
  }

  void _notifyFinanceChanged() {
    if (!mounted) return;
    unawaited(ChurchFinanceRealtimeService.onFinanceMutation(_tid));
    setState(() => _financeRevision++);
  }

  void _prewarmFinanceCaches(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    unawaited(
      ChurchRepository.listCacheFirst(
        module: ChurchRepository.financeiro,
        churchIdHint: tid,
        limit: YahwehPerformanceV4.financeChartsSampleLimit,
      ),
    );
    unawaited(ChurchTenantResilientReads.contas(tid));
  }

  void _scheduleFinanceRealtimeRefresh() {
    _financeRealtimeDebounce?.cancel();
    _financeRealtimeDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _notifyFinanceChanged();
    });
  }

  void _startFinanceRealtimeSync() {
    for (final s in _financeRealtimeSubs) {
      unawaited(s.cancel());
    }
    _financeRealtimeSubs.clear();
    // Web: um único listener (limit 1) — actualiza extrato/gráficos sem F5.
    _financeRealtimeSubs.add(
      _financeCol.limit(1).watchSafe().listen((_) => _scheduleFinanceRealtimeRefresh()),
    );
    _financeRealtimeSubs.addAll([
      ChurchUiCollections.churchDoc(_tid)
          .collection('contas')
          .limit(1)
          .watchSafe()
          .listen((_) => _scheduleFinanceRealtimeRefresh()),
      ChurchUiCollections.churchDoc(_tid)
          .collection('despesas_fixas')
          .limit(1)
          .watchSafe()
          .listen((_) => _scheduleFinanceRealtimeRefresh()),
      ChurchUiCollections.churchDoc(_tid)
          .collection('receitas_recorrentes')
          .limit(1)
          .watchSafe()
          .listen((_) => _scheduleFinanceRealtimeRefresh()),
    ]);
  }

  Future<void> _bootstrapFirestoreTenant() async {
    if (!mounted) return;
    final churchId = ChurchRepository.churchId(widget.tenantId);
    if (churchId.isEmpty) {
      setState(() {
        _firestoreTenantId = null;
        _financeBootstrapDone = true;
      });
      return;
    }
    setState(() {
      _firestoreTenantId = churchId;
      _financeBootstrapDone = true;
    });
    _startFinanceRealtimeSync();
    unawaited(_warmFinanceData(churchId));
    unawaited(_resolveOperationalTenantInBackground());
  }

  Future<void> _warmFinanceData(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final results = await Future.wait([
        ChurchFinanceLoadService.loadLancamentos(
          seedTenantId: tid,
          limit: YahwehPerformanceV4.financeChartsSampleLimit,
        ),
        ChurchFinanceLoadService.loadContas(seedTenantId: tid),
      ]);
      if (mounted) {
        _notifyFinanceChanged();
      }
      unawaited(
        FinanceComprovantePublishService.reconcileStuckComprovantes(
          tenantId: tid,
          docs: results[0].docs,
        ),
      );
      ChurchModuleQueryProbe.logSuccess(
        module: 'Financeiro',
        churchId: ChurchFinanceLoadService.resolveChurchId(tid),
        path: FirebasePaths.finance(ChurchFinanceLoadService.resolveChurchId(tid)),
        totalDocs: results[0].docs.length,
      );
    } catch (e) {
      ChurchModuleQueryProbe.logError(
        module: 'Financeiro',
        churchId: ChurchFinanceLoadService.resolveChurchId(tid),
        path: FirebasePaths.finance(ChurchFinanceLoadService.resolveChurchId(tid)),
        error: '$e',
      );
    }
  }

  Future<void> _resolveOperationalTenantInBackground() async {
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      if (!mounted || tid.isEmpty) return;
      if (tid != _firestoreTenantId) {
        setState(() => _firestoreTenantId = tid);
        _notifyFinanceChanged();
      }
      unawaited(
        FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(tid),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('financeiro');
    unawaited(_ensureFinanceWriteReady().catchError((_) {}));
    final rawTab = widget.initialTabIndex ?? 0;
    final idx = rawTab < 0 ? 0 : (rawTab > 7 ? 7 : rawTab);
    _tabCtrl = TabController(length: 8, vsync: this, initialIndex: idx);
    unawaited(_bootstrapFirestoreTenant());
    _prewarmFinanceCaches(ChurchRepository.churchId(widget.tenantId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmupBankBrandingAssets());
    });
    final openId = widget.openLancamentoId?.trim();
    if (openId != null && openId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLancamento(openId));
    }
  }

  @override
  void didUpdateWidget(covariant FinancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      setState(() {
        _firestoreTenantId = null;
        _financeBootstrapDone = false;
      });
      unawaited(_bootstrapFirestoreTenant());
    }
  }

  Future<void> _openPendingLancamento(String id) async {
    if (!mounted) return;
    try {
      await _bootstrapFirestoreTenant();
      final doc = await _financeCol.doc(id).get();
      if (!doc.exists || !mounted) return;
      _tabCtrl.index = 1;
      final ok = await showFinanceLancamentoEditorForTenant(context,
          tenantId: _tid,
          existingDoc: doc,
          panelRole: widget.role);
      if (ok && mounted) _notifyFinanceChanged();
    } catch (_) {}
  }

  @override
  void dispose() {
    _financeRealtimeDebounce?.cancel();
    for (final s in _financeRealtimeSubs) {
      unawaited(s.cancel());
    }
    _financeRealtimeSubs.clear();
    _tabCtrl.dispose();
    super.dispose();
  }

  static const _financeTabs = <Widget>[
    Tab(text: 'Resumo'),
    Tab(text: 'Lançamentos'),
    Tab(text: 'Despesas Fixas'),
    Tab(text: 'Receitas Fixas'),
    Tab(text: 'Conciliação'),
    Tab(text: 'Categorias'),
    Tab(text: 'Contas'),
    Tab(text: 'Relatórios'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final canPop = Navigator.canPop(context);
    final showAppBar = !isMobile || canPop;
    final moduleEntry = kChurchShellNavEntries[ChurchShellIndices.financeiro];
    final moduleAccent = moduleEntry.accent;
    final shellChrome = widget.onShellBack != null && isMobile;

    if (!_financeBootstrapDone) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        appBar: showAppBar
            ? AppBar(
                leading: canPop
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.maybePop(context),
                        tooltip: 'Voltar')
                    : null,
                elevation: 0,
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                title: const Text('Financeiro'),
              )
            : null,
        body: const ChurchPanelLoadingBody(),
      );
    }

    if (_tid.trim().isEmpty) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        appBar: showAppBar
            ? AppBar(
                leading: canPop
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.maybePop(context),
                        tooltip: 'Voltar')
                    : null,
                elevation: 0,
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                title: const Text('Financeiro'),
              )
            : null,
        body: Padding(
          padding: ThemeCleanPremium.pagePadding(context),
          child: const ChurchPanelResilientLoadBanner(
            hasLocalData: false,
            isSyncing: false,
            errorTitle: 'Igreja não identificada',
            error: 'Não foi possível resolver o churchId da sessão atual.',
          ),
        ),
      );
    }

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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_finance',
        backgroundColor: moduleAccent,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 10,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text(
          'Lançamento Rápido',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        onPressed: () => unawaited(_showLancamentoDialog(context)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: DecoratedBox(
        decoration: churchModuleBodyGradient(moduleAccent),
        child: SafeArea(
        top: widget.onShellBack == null && !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shellChrome)
              ChurchModuleShellChrome(
                onBack: widget.onShellBack!,
                title: 'Financeiro',
                icon: moduleEntry.icon,
                accent: moduleAccent,
                subtitle: 'Receitas · despesas · contas',
                tabController: _tabCtrl,
                tabs: _financeTabs,
              ),
            Expanded(
              child: NestedScrollView(
          // Abas + visão por conta sobem com o scroll do conteúdo (web e mobile).
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              if (isMobile && !widget.embeddedInShell && !shellChrome)
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
              if (!shellChrome)
                SliverToBoxAdapter(
                  child: isMobile &&
                          widget.embeddedInShell &&
                          widget.onShellBack == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                moduleAccent,
                                Color.lerp(moduleAccent, Colors.white, 0.2)!,
                              ],
                            ),
                          ),
                          child: ChurchPanelPillTabBar(
                            controller: _tabCtrl,
                            accentColor: moduleAccent,
                            tabs: _financeTabs,
                          ),
                        )
                      : Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: ThemeCleanPremium.spaceLg,
                              vertical: ThemeCleanPremium.spaceSm),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.cardBackground,
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusLg),
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
                            border:
                                Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: TabBar(
                            controller: _tabCtrl,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            splashBorderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
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
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm),
                              border: Border.all(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.22),
                              ),
                            ),
                            dividerColor: Colors.transparent,
                            tabs: _financeTabs,
                          ),
                        ),
                ),
            ];
          },
          body: TabBarView(
            controller: _tabCtrl,
            children: [
              _ResumoTab(
                key: ValueKey('resumo_${_tid}_$_financeRevision'),
                financeCol: _financeCol,
                tenantId: _tid,
                role: widget.role,
                financeRevision: _financeRevision,
                onFinanceChanged: _notifyFinanceChanged,
              ),
              _LancamentosTab(
                key: ValueKey('lanc_${_tid}_$_financeRevision'),
                financeCol: _financeCol,
                tenantId: _tid,
                role: widget.role,
                financeRevision: _financeRevision,
                onFinanceChanged: _notifyFinanceChanged,
              ),
              _DespesasFixasTab(
                key: ValueKey('desp_fixas_$_tid'),
                tenantId: _tid,
                role: widget.role,
              ),
              FinanceReceitasFixasTab(
                key: ValueKey('rec_fixas_$_tid'),
                tenantId: _tid,
                role: widget.role,
              ),
              FinanceConciliacaoTab(
                tenantId: _tid,
                role: widget.role,
              ),
              _FinanceCategoriasTab(tenantId: _tid),
              _FinanceContasTab(
                tenantId: _tid,
                role: widget.role,
                onEditLancamento: (ctx, doc) =>
                    _showLancamentoDialog(ctx, doc: doc),
              ),
              RelatorioFinanceiroPage(
                tenantId: _tid,
                embeddedInFinanceModule: true,
                onEmbeddedBackToResumo: () {
                  if (_tabCtrl.index != 0) {
                    _tabCtrl.animateTo(0);
                  }
                },
              ),
            ],
          ),
        ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ─── Lançamento Rápido (Receita / Despesa / Transferência) ────────────────────
  Future<void> _showLancamentoDialog(BuildContext context,
      {DocumentSnapshot<Map<String, dynamic>>? doc,
      String? presetNovoTipo}) async {
    final tid = ChurchContextService.panelChurchId(_tid);
    if (tid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Igreja não vinculada. Saia e entre novamente no painel.',
            ),
          ),
        );
      }
      return;
    }
    try {
      final ok = await showFinanceLancamentoEditorForTenant(
        context,
        tenantId: tid,
        existingDoc: doc,
        panelRole: widget.role,
        presetNovoTipo: presetNovoTipo,
      );
      if (ok && mounted) _notifyFinanceChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatFirebaseErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    }
  }

  // ─── Exportar CSV ────────────────────────────────────────────────────────────
  Future<void> _exportarCSV(BuildContext context) async {
    final snap = await ChurchTenantResilientReads.financeRecentNetwork(
      _tid,
      limit: 2000,
    );
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
    final signers =
        await _pickFinancePdfSigners(context, tenantId: _tid);
    if (!mounted || signers == null) return;
    final snap = await ChurchTenantResilientReads.financeRecentNetwork(
      _tid,
      limit: 500,
    );
    if (!mounted) return;
    await exportFinanceiroRelatorioPdf(
      context: context,
      tenantId: _tid,
      docs: snap.docs,
      filename: 'financeiro_relatorio.pdf',
      leftSignerName: signers.leftName,
      rightSignerName: signers.rightName,
      leftSignatureBytes: signers.leftSignatureBytes,
      rightSignatureBytes: signers.rightSignatureBytes,
      showDigitalSignatures: signers.showDigitalSignatures,
      leftDigitalStamp: signers.leftDigitalStamp,
      rightDigitalStamp: signers.rightDigitalStamp,
    );
  }
}

String _financeDonationKindLabel(Map<String, dynamic> m) {
  final kindRaw = (m['donationKindLabel'] ?? m['donationKind'] ?? '')
      .toString()
      .toLowerCase()
      .trim();
  if (kindRaw.contains('ofert')) return 'Oferta';
  if (kindRaw.contains('diz') || kindRaw.contains('díz')) return 'Dízimo';
  final cat = (m['categoria'] ?? '').toString().toLowerCase();
  if (cat.contains('ofert')) return 'Oferta';
  if (cat.contains('diz') || cat.contains('díz')) return 'Dízimo';
  final desc = (m['descricao'] ?? '').toString().toLowerCase();
  if (desc.contains('oferta')) return 'Oferta';
  if (desc.contains('dizimo') || desc.contains('dízimo')) return 'Dízimo';
  return '';
}

bool _financeIsDonationLancamento(Map<String, dynamic> m) {
  return _financeDonationKindLabel(m).isNotEmpty;
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
    if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
    final tipo = financeInferTipo(data);
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
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> financeDocs;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> contasDocs;
  final Map<String, double> saldoAtualPorConta;

  const _FinanceContasResumoStrip({
    super.key,
    required this.tenantId,
    required this.role,
    required this.financeCol,
    required this.onFinanceChanged,
    required this.financeDocs,
    required this.contasDocs,
    this.saldoAtualPorConta = const {},
  });

  @override
  Widget build(BuildContext context) {
    final mesRef = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final mesLabel = DateFormat('MMMM yyyy', 'pt_BR').format(mesRef);

    final totais = _totaisReceitaDespesaPorContaNoMes(financeDocs, mesRef);
    final contasAtivas =
        contasDocs.where((c) => c.data()['ativo'] != false).toList();

    double gReceitas = 0, gDespesas = 0, gSaldoBancos = 0;
    for (final t in totais.values) {
      gReceitas += t.receitas;
      gDespesas += t.despesas;
    }
    if (saldoAtualPorConta.isNotEmpty) {
      gSaldoBancos =
          saldoAtualPorConta.values.fold(0.0, (a, b) => a + b);
    }
    final gSaldo = saldoAtualPorConta.isNotEmpty
        ? gSaldoBancos
        : gReceitas - gDespesas;
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
                                    saldoAtualPorConta.isNotEmpty
                                        ? 'Saldo bancos'
                                        : 'Saldo mês',
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
                    final saldoAtual = saldoAtualPorConta[id] ?? t.saldo;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FinancePremiumAccountCard(
                        nome: nome,
                        saldoAtual: saldoAtual,
                        receitasMes: t.receitas,
                        despesasMes: t.despesas,
                        bancoSubtitle: '$bancoNome · $tipoConta',
                        accent: contaAccent,
                        leading: _financeBankMiniLogo(
                          bancoCodigo:
                              (contaData['bancoCodigo'] ?? '').toString(),
                          bancoNome: bancoNome,
                          size: 30,
                          fontSize: 11,
                        ),
                        onTap: () => openExtrato(
                          contaId: id,
                          title: '$nome · $mesLabel',
                        ),
                        onTransfer: () async {
                          final ok = await showFinanceLancamentoEditorForTenant(
                            context,
                            tenantId: tenantId,
                            panelRole: role,
                            presetNovoTipo: 'transferencia',
                          );
                          if (ok) onFinanceChanged();
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
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
  late Future<List<dynamic>> _combinedFuture;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedFinanceDocs;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedContasDocs;
  String? _loadHint;
  bool _fetching = false;
  bool _showingStaleCache = false;
  Timer? _webLoadCap;
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

  bool _resumoHasLocalData(PanelFinanceAccountsSnapshot accountsCache) =>
      (_seedFinanceDocs?.isNotEmpty ?? false) ||
      (_seedContasDocs?.isNotEmpty ?? false) ||
      accountsCache.hasData;

  bool _resumoShouldShowStaleBanner({bool fromCache = false}) {
    if (!AppConnectivityService.instance.isOnline) {
      return fromCache ||
          (_seedFinanceDocs?.isNotEmpty ?? false) ||
          (_seedContasDocs?.isNotEmpty ?? false);
    }
    return false;
  }

  void _startResumoWebCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(PanelResilientLoad.webLoadingCap, () {
      if (!mounted || !_fetching) return;
      final hadLocal =
          _resumoHasLocalData(const PanelFinanceAccountsSnapshot());
      setState(() {
        _fetching = false;
        if (hadLocal) {
          _showingStaleCache = _resumoShouldShowStaleBanner(fromCache: true);
          _loadHint = null;
        } else {
          _loadHint ??=
              'Tempo esgotado ao carregar o resumo financeiro na Web.';
        }
      });
    });
  }

  Widget _buildResumoResilienceBanner({
    required Object? error,
    required PanelFinanceAccountsSnapshot accountsCache,
    VoidCallback? onRetry,
  }) {
    return ChurchPanelResilientLoadBanner(
      hasLocalData: _resumoHasLocalData(accountsCache),
      isSyncing: _fetching && _resumoHasLocalData(accountsCache),
      showStaleCache: _showingStaleCache && !_fetching,
      errorTitle: 'Não foi possível carregar o resumo financeiro',
      error: error,
      onRetry: onRetry ?? _refresh,
      staleMessage:
          'Modo offline — resumo com últimos dados guardados. Puxe para atualizar.',
      syncMessage:
          'Sincronizando financeiro… a mostrar dados guardados enquanto atualiza.',
    );
  }

  @override
  void initState() {
    super.initState();
    _reloadFutures();
  }

  @override
  void dispose() {
    _webLoadCap?.cancel();
    super.dispose();
  }

  Future<List<dynamic>> _loadFinanceBundle({required bool forceFresh}) async {
    final tid = ChurchRepository.churchId(widget.tenantId);
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final limit = YahwehPerformanceV4.financeChartsSampleLimit;
    final l = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: tid,
      limit: limit,
      forceRefresh: forceFresh,
      forceServer: forceFresh,
    );
    final c = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tid,
      forceRefresh: forceFresh,
      forceServer: forceFresh,
    );
    final s = await FinanceTenantSettings.load(tid);
    unawaited(
      FinanceComprovantePublishService.reconcileStuckComprovantes(
        tenantId: tid,
        docs: l.docs,
      ),
    );
    if (mounted) {
      final hadLocal = (_seedFinanceDocs?.isNotEmpty ?? false) ||
          (_seedContasDocs?.isNotEmpty ?? false);
      if (l.docs.isNotEmpty || c.docs.isNotEmpty) {
        _loadHint = null;
        _showingStaleCache = _resumoShouldShowStaleBanner(fromCache: l.fromCache);
      } else if (l.softError != null && l.softError!.trim().isNotEmpty) {
        final ui = PanelResilientLoad.afterFetch(
          hadLocalData: hadLocal,
          newItems: l.docs,
          fromCache: l.fromCache,
          softError: l.softError,
          forceFresh: forceFresh,
        );
        if (!hadLocal) _loadHint = ui.loadError;
        _showingStaleCache = ui.showingStaleCache &&
            !AppConnectivityService.instance.isOnline;
      } else {
        _loadHint = null;
        _showingStaleCache = false;
      }
    }
    return [l.snapshot, c.snapshot, s];
  }

  void _seedFinanceCaches(int limit) {
    final churchId = ChurchRepository.churchId(widget.tenantId);
    _seedFinanceDocs =
        ChurchFinanceLoadService.peekLancamentosRamAny(churchId) ??
            ChurchFinanceLoadService.peekLancamentosRam(churchId, limit: limit) ??
            const [];
    _seedContasDocs =
        ChurchFinanceLoadService.peekContasRam(churchId) ?? const [];
  }

  void _reloadFutures({bool forceFresh = false}) {
    final limit = YahwehPerformanceV4.financeChartsSampleLimit;

    if (!forceFresh) {
      _seedFinanceCaches(limit);
    } else {
      _seedFinanceDocs ??= const [];
      _seedContasDocs ??= const [];
    }

    final hadLocal = (_seedFinanceDocs?.isNotEmpty ?? false) ||
        (_seedContasDocs?.isNotEmpty ?? false);
    _fetching = true;
    if (!forceFresh && hadLocal) {
      _showingStaleCache = _resumoShouldShowStaleBanner(fromCache: true);
    }
    if (forceFresh) {
      _loadHint = null;
      _showingStaleCache = false;
    }
    _startResumoWebCap();

    final instantBundle = <dynamic>[
      MergedFirestoreQuerySnapshot(_seedFinanceDocs!),
      MergedFirestoreQuerySnapshot(_seedContasDocs!),
      const FinanceTenantSettings(),
    ];
    _combinedFuture = Future.value(instantBundle);

    unawaited(_loadFinanceBundle(forceFresh: forceFresh).then((fresh) {
      if (!mounted) return;
      _webLoadCap?.cancel();
      setState(() {
        final fs = fresh[0] as QuerySnapshot<Map<String, dynamic>>;
        final cs = fresh[1] as QuerySnapshot<Map<String, dynamic>>;
        _seedFinanceDocs = fs.docs;
        _seedContasDocs = cs.docs;
        _combinedFuture = Future.value(fresh);
        _fetching = false;
        _showingStaleCache = false;
        _loadHint = null;
      });
    }).catchError((e) {
      if (!mounted) return;
      _webLoadCap?.cancel();
      final hadLocalData = (_seedFinanceDocs?.isNotEmpty ?? false) ||
          (_seedContasDocs?.isNotEmpty ?? false);
      final ui = PanelResilientLoad.afterError(
        hadLocalData: hadLocalData,
        error: e,
      );
      setState(() {
        _fetching = ui.fetching;
        _showingStaleCache = ui.showingStaleCache &&
            !AppConnectivityService.instance.isOnline;
        if (!hadLocalData) _loadHint = ui.loadError;
      });
    }));

    _future = _combinedFuture.then(
      (v) => v[0] as QuerySnapshot<Map<String, dynamic>>,
    );
    _futureContas = _combinedFuture.then(
      (v) => v[1] as QuerySnapshot<Map<String, dynamic>>,
    );
    _futureSettings = _combinedFuture.then(
      (v) => v[2] as FinanceTenantSettings,
    );
  }

  @override
  void didUpdateWidget(covariant _ResumoTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      setState(() => _reloadFutures());
      return;
    }
    if (oldWidget.financeRevision != widget.financeRevision) {
      setState(() => _reloadFutures(forceFresh: true));
    }
  }

  Future<void> _refresh() async {
    setState(() => _reloadFutures(forceFresh: true));
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
    Widget resumoBody(PanelFinanceAccountsSnapshot accountsCache) {
      return FutureBuilder<List<dynamic>>(
      future: _combinedFuture,
      builder: (context, snap) {
        final loadError = snap.hasError ? snap.error : _loadHint;
        final hasLocal = _resumoHasLocalData(accountsCache) ||
            (snap.data != null &&
                snap.data!.isNotEmpty &&
                (((snap.data![0] as QuerySnapshot<Map<String, dynamic>>)
                            .docs
                            .isNotEmpty) ||
                    (snap.data!.length > 1 &&
                        (snap.data![1] as QuerySnapshot<Map<String, dynamic>>)
                            .docs
                            .isNotEmpty)));
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !hasLocal) {
          return const ChurchPanelLoadingBody();
        }
        if (!hasLocal && loadError != null) {
          return _buildResumoResilienceBanner(
            error: loadError,
            accountsCache: accountsCache,
          );
        }
        final showResilienceBanner =
            loadError != null || _fetching || _showingStaleCache;
        final financeSnap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final contasSnap = snap.data != null && snap.data!.length > 1
            ? snap.data![1] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final settings = snap.data != null && snap.data!.length > 2
            ? snap.data![2] as FinanceTenantSettings
            : const FinanceTenantSettings();
        final allDocs = financeSnap?.docs ?? _seedFinanceDocs ?? [];
        final docs = allDocs.where((d) {
          final dt = financeLancamentoDate(d.data());
          return _inRange(dt);
        }).toList();
        final contasDocs = contasSnap?.docs.isNotEmpty == true
            ? contasSnap!.docs
            : (_seedContasDocs ?? contasSnap?.docs ?? []);
        double totalReceitas = 0, totalDespesas = 0;
        final now = DateTime.now();

        final receitasMerger = FinanceCategoryMerger();
        final despesasMerger = FinanceCategoryMerger();
        final receitasPorCat = <String, double>{};
        final despesasPorCat = <String, double>{};
        for (final d in docs) {
          final data = d.data();
          final tipo = financeInferTipo(data);
          if (tipo == 'transferencia') continue;
          if (!financeLancamentoEfetivadoParaSaldo(data)) continue;
          final valor = _parseValor(data['amount'] ?? data['valor']);
          final cat = (data['categoria'] ?? 'Outros').toString().trim();
          final isEntrada = financeIsEntrada(data);

          if (isEntrada) {
            totalReceitas += valor;
            receitasMerger.addAmount(receitasPorCat, cat, valor,
                emptyLabel: 'Outros');
          } else {
            totalDespesas += valor;
            despesasMerger.addAmount(despesasPorCat, cat, valor,
                emptyLabel: 'Outros');
          }

        }

        final saldo = totalReceitas - totalDespesas;

        double aReceberPendente = 0, aPagarPendente = 0;
        for (final d in docs) {
          final data = d.data();
          final tipo = financeInferTipo(data);
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
        final saldoAtualPorConta = allDocs.isNotEmpty
            ? saldoPorConta
            : (accountsCache.hasData
                ? accountsCache.saldoPorConta
                : saldoPorConta);

        final saldoTotalContas = saldoAtualPorConta.values
            .fold(0.0, (a, b) => a + b);
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
          var gasto = 0.0;
          for (final de in despesasPorCat.entries) {
            if (FinanceCategoryMerger.sameCategoryGroup(
              de.key,
              e.key,
              emptyLabel: 'Outros',
            )) {
              gasto += de.value;
            }
          }
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
              if (showResilienceBanner)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                  child: _buildResumoResilienceBanner(
                    error: loadError,
                    accountsCache: accountsCache,
                  ),
                ),
              _FinanceContasResumoStrip(
                key: ValueKey(
                    'fin_strip_${widget.tenantId}_${widget.financeRevision}_'
                    '${accountsCache.updatedAt?.millisecondsSinceEpoch ?? 0}'),
                tenantId: widget.tenantId,
                role: widget.role,
                financeCol: widget.financeCol,
                onFinanceChanged: widget.onFinanceChanged,
                financeDocs: allDocs,
                contasDocs: contasDocs,
                saldoAtualPorConta: saldoAtualPorConta,
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
              FinanceResumoChartsSection(
                allLancamentos: allDocs,
                receitasPorCat: receitasPorCat,
                despesasPorCat: despesasPorCat,
                totalReceitas: totalReceitas,
                totalDespesas: totalDespesas,
                chartYear: now.year,
              ),
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
                      final saldoConta = saldoAtualPorConta[id] ?? 0.0;
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

    if (kIsWeb) {
      return FutureBuilder<PanelFinanceAccountsSnapshot>(
        future: PanelFinanceAccountsSnapshotService.readOnce(widget.tenantId),
        builder: (context, accountsSnap) {
          final accountsCache =
              accountsSnap.data ?? const PanelFinanceAccountsSnapshot();
          return resumoBody(accountsCache);
        },
      );
    }
    return StreamBuilder<PanelFinanceAccountsSnapshot>(
      stream: ChurchFinanceRealtimeService.watchAccountBalances(widget.tenantId),
      builder: (context, accountsSnap) {
        final accountsCache =
            accountsSnap.data ?? const PanelFinanceAccountsSnapshot();
        return resumoBody(accountsCache);
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

/// Filtros do extrato — chips premium coloridos (mobile-first).
Widget _financeExtratoPremiumChip({
  required String label,
  required IconData icon,
  required Color accent,
  required bool selected,
  required VoidCallback onTap,
}) {
  return FinancePremiumFilterChip(
    label: label,
    icon: icon,
    accent: accent,
    selected: selected,
    onTap: onTap,
  );
}

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
  int _fetchLimit = YahwehPerformanceV4.defaultPageSize;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedDocs;
  bool _fetching = false;
  /// Mês do extrato (sempre mês calendário).
  late DateTime _mesRefM;
  /// todos | entrada | saida | transferencia
  String _filtroMovimento = 'todos';
  /// Filtro adicional: dízimo vs oferta (receitas de doação / MP).
  String _filtroDoacao = 'todos';
  /// Só com extrato geral (`contaId` null); null = todas as contas.
  String? _filtroContaExtratoGeral;

  void _seedMovimentacoesFromRam() {
    final churchId = ChurchRepository.churchId(widget.tenantId);
    _seedDocs = ChurchFinanceLoadService.peekLancamentosRam(
          churchId,
          limit: _fetchLimit,
        ) ??
        const [];
  }

  void _reloadMovimentacoesFuture() {
    _fetching = true;
    _future = ChurchTenantResilientReads.financeRecent(
      widget.tenantId,
      limit: _fetchLimit,
    ).timeout(PanelResilientLoad.queryCap).then((snap) {
      if (mounted && snap.docs.isNotEmpty) {
        setState(() {
          _seedDocs = snap.docs;
          _fetching = false;
        });
      } else if (mounted) {
        setState(() => _fetching = false);
      }
      return snap;
    }).catchError((e) {
      if (mounted) {
        final ui = PanelResilientLoad.afterError(
          hadLocalData: (_seedDocs?.isNotEmpty ?? false),
          error: e,
        );
        setState(() => _fetching = ui.fetching);
      }
      throw e;
    });
  }

  @override
  void initState() {
    super.initState();
    final em = widget.extratoMes;
    if (em != null) {
      _mesRefM = DateTime(em.year, em.month, 1);
    } else {
      final n = DateTime.now();
      _mesRefM = DateTime(n.year, n.month, 1);
    }
    _seedMovimentacoesFromRam();
    _reloadMovimentacoesFuture();
  }

  void _loadMoreLancamentos() {
    setState(() {
      _fetchLimit += YahwehPerformanceV4.defaultPageSize;
      _reloadMovimentacoesFuture();
    });
  }

  void _refresh() {
    setState(_reloadMovimentacoesFuture);
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = ChurchRepository.churchId(widget.tenantId.trim());
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
          final loadError = snap.hasError ? snap.error : null;
          final rawDocs = snap.data?.docs ?? _seedDocs ?? [];
          final hasLocal = rawDocs.isNotEmpty;
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData &&
              !hasLocal) {
            return const ChurchPanelLoadingBody();
          }
          if (!hasLocal && loadError != null) {
            return ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: _fetching,
              errorTitle: 'Não foi possível carregar os lançamentos',
              error: loadError,
              onRetry: _refresh,
            );
          }
          final inicio = DateTime(_mesRefM.year, _mesRefM.month, 1);
          final fim = DateTime(_mesRefM.year, _mesRefM.month + 1, 0, 23, 59, 59);
          var docs = rawDocs;
          docs = docs.where((d) {
            final data = d.data();
            final t = _financeLancamentoInstant(data);
            if (t.isBefore(inicio) || t.isAfter(fim)) {
              return false;
            }
            final fix = widget.contaId;
            if (fix != null && fix.isNotEmpty) {
              if (!_financeLancamentoEnvolveConta(data, fix)) {
                return false;
              }
            } else {
              final fc = _filtroContaExtratoGeral;
              if (fc != null &&
                  fc.isNotEmpty &&
                  !_financeLancamentoEnvolveConta(data, fc)) {
                return false;
              }
            }
            if (_filtroMovimento != 'todos') {
              final typ = (data['type'] ?? '').toString().toLowerCase();
              if (_filtroMovimento == 'transferencia' && typ != 'transferencia') {
                return false;
              }
              if (_filtroMovimento == 'entrada' &&
                  !typ.contains('entrada') &&
                  !typ.contains('receita')) {
                return false;
              }
              if (_filtroMovimento == 'saida' &&
                  !typ.contains('saida') &&
                  !typ.contains('despesa') &&
                  !typ.contains('saída')) {
                return false;
              }
            }
            if (_filtroDoacao != 'todos') {
              if (!_financeIsDonationLancamento(data)) return false;
              final lbl = _financeDonationKindLabel(data);
              if (_filtroDoacao == 'dizimo' && lbl != 'Dízimo') return false;
              if (_filtroDoacao == 'oferta' && lbl != 'Oferta') return false;
            }
            return true;
          }).toList();

          final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
          final mesStr =
              DateFormat("MMMM 'de' y", 'pt_BR').format(_mesRefM);
          final allMaps = rawDocs.map((e) => e.data()).toList();
          String? ctaId = widget.contaId;
          double? saldoIni, recMes, desMes, saldoFim;
          if (ctaId != null && ctaId.isNotEmpty) {
            final fimAnt =
                DateTime(_mesRefM.year, _mesRefM.month, 0, 23, 59, 59);
            final sSaldoInicio = financeSaldoPorContaAteInclusive(
              contaIdsAtivas: {ctaId},
              lancamentos: allMaps,
              ateInclusive: fimAnt,
            )[ctaId] ??
                0.0;
            saldoIni = sSaldoInicio;
            final totM = _totaisReceitaDespesaPorContaNoMes(
                rawDocs, _mesRefM);
            final rM = totM[ctaId]?.receitas ?? 0.0;
            final dM = totM[ctaId]?.despesas ?? 0.0;
            recMes = rM;
            desMes = dM;
            saldoFim = sSaldoInicio + rM - dM;
          }

          return Column(
            children: [
              if (loadError != null || _fetching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ChurchPanelResilientLoadBanner(
                    hasLocalData: hasLocal,
                    isSyncing: _fetching && hasLocal,
                    errorTitle: 'Não foi possível carregar os lançamentos',
                    error: loadError,
                    onRetry: _refresh,
                  ),
                ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                            onPressed: () {
                              setState(() {
                                _mesRefM = DateTime(
                                    _mesRefM.year, _mesRefM.month - 1, 1);
                              });
                            },
                            icon: const Icon(Icons.chevron_left_rounded)),
                        Expanded(
                          child: Center(
                            child: Text(
                              mesStr[0].toUpperCase() + mesStr.substring(1),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                            onPressed: () {
                              setState(() {
                                _mesRefM = DateTime(
                                    _mesRefM.year, _mesRefM.month + 1, 1);
                              });
                            },
                            icon: const Icon(Icons.chevron_right_rounded)),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _financeExtratoPremiumChip(
                          label: 'Todas',
                          icon: Icons.receipt_long_rounded,
                          accent: ThemeCleanPremium.primary,
                          selected: _filtroMovimento == 'todos',
                          onTap: () => setState(() => _filtroMovimento = 'todos'),
                        ),
                        _financeExtratoPremiumChip(
                          label: 'Receitas',
                          icon: Icons.trending_up_rounded,
                          accent: const Color(0xFF16A34A),
                          selected: _filtroMovimento == 'entrada',
                          onTap: () => setState(() => _filtroMovimento = 'entrada'),
                        ),
                        _financeExtratoPremiumChip(
                          label: 'Despesas',
                          icon: Icons.trending_down_rounded,
                          accent: const Color(0xFFDC2626),
                          selected: _filtroMovimento == 'saida',
                          onTap: () => setState(() => _filtroMovimento = 'saida'),
                        ),
                        _financeExtratoPremiumChip(
                          label: 'Transfer.',
                          icon: Icons.swap_horiz_rounded,
                          accent: const Color(0xFF7C3AED),
                          selected: _filtroMovimento == 'transferencia',
                          onTap: () => setState(() => _filtroMovimento = 'transferencia'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Doações (dízimo / oferta)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _financeExtratoPremiumChip(
                                label: 'Todas',
                                icon: Icons.filter_list_rounded,
                                accent: const Color(0xFF0D9488),
                                selected: _filtroDoacao == 'todos',
                                onTap: () => setState(() => _filtroDoacao = 'todos'),
                              ),
                              _financeExtratoPremiumChip(
                                label: 'Dízimo',
                                icon: Icons.church_rounded,
                                accent: const Color(0xFF2563EB),
                                selected: _filtroDoacao == 'dizimo',
                                onTap: () => setState(() => _filtroDoacao = 'dizimo'),
                              ),
                              _financeExtratoPremiumChip(
                                label: 'Oferta',
                                icon: Icons.volunteer_activism_rounded,
                                accent: const Color(0xFF9333EA),
                                selected: _filtroDoacao == 'oferta',
                                onTap: () => setState(() => _filtroDoacao = 'oferta'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.contaId == null || widget.contaId!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          future: ChurchUiCollections.churchDoc(tenantId)
                              .collection('contas')
                              .orderBy('nome')
                              .get(),
                          builder: (ctx, cs) {
                            if (!cs.hasData) {
                              return const SizedBox(height: 2);
                            }
                            final cdocs = cs.data!.docs
                                .where((c) => c.data()['ativo'] != false)
                                .toList();
                            return DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: cdocs.any((c) => c.id == _filtroContaExtratoGeral)
                                  ? _filtroContaExtratoGeral
                                  : null,
                              hint: const Text('Todas as contas (extrato geral)'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Todas as contas',
                                      overflow: TextOverflow.ellipsis),
                                ),
                                ...cdocs.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                        _financeContaDisplayName(c.data()),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filtroContaExtratoGeral = v),
                            );
                          },
                        ),
                      ),
                    if (ctaId != null && ctaId.isNotEmpty && saldoIni != null) ...[
                      const SizedBox(height: 6),
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: ChurchUiCollections.churchDoc(tenantId)
                            .collection('contas')
                            .doc(ctaId)
                            .get(),
                        builder: (c, s) {
                          final accent = s.hasData
                              ? _financeContaBancoColor(s.data!.data() ?? const {})
                              : ThemeCleanPremium.primary;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [accent, Color.lerp(accent, const Color(0xFF0F172A), 0.4)!],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Resumo do mês',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                _linhaResumoExtrato(
                                    'Saldo no início do mês', saldoIni!, nf),
                                _linhaResumoExtrato(
                                    'Receitas (mês)', recMes ?? 0, nf),
                                _linhaResumoExtrato('Despesas (mês)', desMes ?? 0, nf,
                                    neg: true),
                                const Divider(color: Colors.white30, height: 14),
                                _linhaResumoExtrato('Saldo ao fim (estimado)',
                                    saldoFim ?? 0, nf,
                                    strong: true),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          '${docs.length} movimentação(ões) no mês e filtros',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          )),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                    await _future;
                  },
                  child: docs.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(32, 48, 32, 80),
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                                'Nenhum lançamento com estes filtros e mês selecionado.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            Text(
                              'Ajuste o mês, o tipo (receita/despesa) ou a conta. '
                              'Receitas, despesas e transferências vinculadas aparecem aqui.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        )
                      : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                        ThemeCleanPremium.spaceLg,
                        ThemeCleanPremium.spaceSm,
                        ThemeCleanPremium.spaceLg,
                        80),
                    itemCount: docs.length +
                        ((snap.data?.docs.length ?? 0) >= _fetchLimit ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= docs.length) {
                        return LazyLoadMoreFooter(
                          label: 'Carregar mais lançamentos',
                          onLoadMore: _loadMoreLancamentos,
                        );
                      }
                      return _LancamentoCard(
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
                          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
                              force: true);
                          await docs[i].reference.update({
                            'aprovacaoPendente': false,
                            'aprovadoPorUid':
                                firebaseDefaultAuth.currentUser?.uid ?? '',
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
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedDocs;
  bool _fetching = false;

  void _seedFromRam() {
    final churchId = ChurchRepository.churchId(widget.tenantId);
    _seedDocs = ChurchFinanceLoadService.peekLancamentosRam(
          churchId,
          limit: 500,
        ) ??
        const [];
  }

  void _reloadFuture() {
    _fetching = true;
    _future = ChurchTenantResilientReads.financeRecentNetwork(
      widget.tenantId,
      limit: 500,
    ).timeout(PanelResilientLoad.queryCap).then((snap) {
      if (mounted && snap.docs.isNotEmpty) {
        setState(() {
          _seedDocs = snap.docs;
          _fetching = false;
        });
      } else if (mounted) {
        setState(() => _fetching = false);
      }
      return snap;
    }).catchError((e) {
      if (mounted) {
        final ui = PanelResilientLoad.afterError(
          hadLocalData: (_seedDocs?.isNotEmpty ?? false),
          error: e,
        );
        setState(() => _fetching = ui.fetching);
      }
      throw e;
    });
  }

  @override
  void initState() {
    super.initState();
    _seedFromRam();
    _reloadFuture();
  }

  void _refresh() {
    setState(_reloadFuture);
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
          final loadError = snap.hasError ? snap.error : null;
          final rawDocs = snap.data?.docs ?? _seedDocs ?? [];
          final hasLocal = rawDocs.isNotEmpty;
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData &&
              !hasLocal) {
            return const ChurchPanelLoadingBody();
          }
          if (!hasLocal && loadError != null) {
            return ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: _fetching,
              errorTitle: 'Não foi possível carregar os lançamentos',
              error: loadError,
              onRetry: _refresh,
            );
          }
          var docs = rawDocs;
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
              if (loadError != null || _fetching)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    ThemeCleanPremium.spaceLg,
                    ThemeCleanPremium.spaceSm,
                    ThemeCleanPremium.spaceLg,
                    0,
                  ),
                  child: ChurchPanelResilientLoadBanner(
                    hasLocalData: hasLocal,
                    isSyncing: _fetching && hasLocal,
                    errorTitle: 'Não foi possível carregar os lançamentos',
                    error: loadError,
                    onRetry: _refresh,
                  ),
                ),
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
                            await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
                                force: true);
                            await doc.reference.update({
                              'aprovacaoPendente': false,
                              'aprovadoPorUid':
                                  firebaseDefaultAuth.currentUser?.uid ?? '',
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
  final int financeRevision;
  final VoidCallback? onFinanceChanged;

  const _LancamentosTab({
    super.key,
    required this.financeCol,
    required this.tenantId,
    required this.role,
    this.financeRevision = 0,
    this.onFinanceChanged,
  });

  @override
  State<_LancamentosTab> createState() => _LancamentosTabState();
}

class _LancamentosTabState extends State<_LancamentosTab> {
  String _filtroTipo = 'todos';
  /// todos | dizimo | oferta_missionaria
  String _filtroDoacaoKind = 'todos';
  String _filtroCategoria = 'todas';
  /// todos | pendente_aprovacao | nao_conciliados | a_pagar | pagos | a_receber | recebidos | futuras_despesas | futuras_receitas
  String _filtroExtra = 'todos';
  /// `__geral__` ou id da conta em `contas`.
  String _filtroContaId = '__geral__';
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  late Future<QuerySnapshot<Map<String, dynamic>>> _futureContas;
  late Future<List<dynamic>> _combinedFuture;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedFinanceDocs;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedContasDocs;
  String? _loadHint;
  bool _fetching = false;
  bool _showingStaleCache = false;
  Timer? _webLoadCap;
  int _financeFetchLimit = YahwehPerformanceV4.financeListInitialLimit;

  bool get _lancamentosHasLocalData =>
      (_seedFinanceDocs?.isNotEmpty ?? false) ||
      (_seedContasDocs?.isNotEmpty ?? false);

  void _startLancamentosWebCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(PanelResilientLoad.webLoadingCap, () {
      if (!mounted || !_fetching) return;
      setState(() {
        _fetching = false;
        if (_lancamentosHasLocalData) {
          _showingStaleCache = true;
          _loadHint = null;
        } else {
          _loadHint ??=
              'Tempo esgotado ao carregar lançamentos na Web.';
        }
      });
    });
  }

  Widget _buildLancamentosResilienceBanner({Object? error}) {
    return ChurchPanelResilientLoadBanner(
      hasLocalData: _lancamentosHasLocalData,
      isSyncing: _fetching && _lancamentosHasLocalData,
      showStaleCache: _showingStaleCache && !_fetching,
      errorTitle: 'Não foi possível carregar os lançamentos',
      error: error,
      onRetry: _refresh,
      staleMessage:
          'Modo offline — lançamentos com últimos dados guardados. Puxe para atualizar.',
      syncMessage:
          'Sincronizando lançamentos… a mostrar dados guardados enquanto atualiza.',
    );
  }

  Future<List<dynamic>> _loadLancamentosBundle({required bool forceFresh}) async {
    final tid = ChurchRepository.churchId(widget.tenantId);
    final l = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: tid,
      limit: _financeFetchLimit,
      forceRefresh: forceFresh,
      forceServer: forceFresh,
    );
    final c = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tid,
      forceRefresh: forceFresh,
      forceServer: forceFresh,
    );
    if (mounted) {
      final hadLocal = _lancamentosHasLocalData;
      if (l.docs.isNotEmpty) {
        _loadHint = null;
      } else if (l.softError != null) {
        final ui = PanelResilientLoad.afterFetch(
          hadLocalData: hadLocal,
          newItems: l.docs,
          fromCache: false,
          softError: l.softError,
          forceFresh: forceFresh,
        );
        if (!hadLocal) _loadHint = ui.loadError;
        _showingStaleCache = ui.showingStaleCache;
      }
    }
    return [l.snapshot, c.snapshot];
  }

  void _seedLancamentosCaches() {
    final churchId = ChurchRepository.churchId(widget.tenantId);
    _seedFinanceDocs =
        ChurchFinanceLoadService.peekLancamentosRam(
              churchId,
              limit: _financeFetchLimit,
            ) ??
            const [];
    _seedContasDocs =
        ChurchFinanceLoadService.peekContasRam(churchId) ?? const [];
  }

  void _reloadFutures({bool forceFresh = false}) {
    if (!forceFresh) {
      _seedLancamentosCaches();
    } else {
      _seedFinanceDocs ??= const [];
      _seedContasDocs ??= const [];
    }

    final hadLocal = _lancamentosHasLocalData;
    _fetching = true;
    if (!forceFresh && hadLocal) _showingStaleCache = true;
    if (forceFresh) _loadHint = null;
    _startLancamentosWebCap();

    final instantBundle = <dynamic>[
      MergedFirestoreQuerySnapshot(_seedFinanceDocs!),
      MergedFirestoreQuerySnapshot(_seedContasDocs!),
    ];
    _combinedFuture = Future.value(instantBundle);

    unawaited(_loadLancamentosBundle(forceFresh: forceFresh)
        .timeout(PanelResilientLoad.queryCap)
        .then((fresh) {
      if (!mounted) return;
      _webLoadCap?.cancel();
      setState(() {
        final fs = fresh[0] as QuerySnapshot<Map<String, dynamic>>;
        final cs = fresh[1] as QuerySnapshot<Map<String, dynamic>>;
        _seedFinanceDocs = fs.docs;
        _seedContasDocs = cs.docs;
        _combinedFuture = Future.value(fresh);
        _fetching = false;
        _showingStaleCache = false;
        _loadHint = null;
      });
    }).catchError((e) {
      if (!mounted) return;
      _webLoadCap?.cancel();
      final ui = PanelResilientLoad.afterError(
        hadLocalData: _lancamentosHasLocalData,
        error: e,
      );
      setState(() {
        _fetching = ui.fetching;
        _showingStaleCache = ui.showingStaleCache;
        if (!_lancamentosHasLocalData) _loadHint = ui.loadError;
      });
    }));

    _future = _combinedFuture.then(
      (v) => v[0] as QuerySnapshot<Map<String, dynamic>>,
    );
    _futureContas = _combinedFuture.then(
      (v) => v[1] as QuerySnapshot<Map<String, dynamic>>,
    );
  }

  @override
  void dispose() {
    _webLoadCap?.cancel();
    super.dispose();
  }

  void _loadMoreFinanceLancamentos() {
    setState(() {
      _financeFetchLimit += YahwehPerformanceV4.financeListPageStep;
      _reloadFutures(forceFresh: true);
    });
  }

  @override
  void initState() {
    super.initState();
    _reloadFutures();
  }

  @override
  void didUpdateWidget(covariant _LancamentosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.financeCol.path != widget.financeCol.path) {
      setState(() => _reloadFutures());
      return;
    }
    if (oldWidget.financeRevision != widget.financeRevision) {
      setState(() => _reloadFutures(forceFresh: true));
    }
  }

  void _refresh() {
    setState(() => _reloadFutures(forceFresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _combinedFuture,
      builder: (context, snap) {
        final loadError = snap.hasError ? snap.error : _loadHint;
        final hasLocal = _lancamentosHasLocalData ||
            (snap.data != null &&
                snap.data!.isNotEmpty &&
                ((snap.data![0] as QuerySnapshot<Map<String, dynamic>>)
                        .docs
                        .isNotEmpty ||
                    (snap.data!.length > 1 &&
                        (snap.data![1] as QuerySnapshot<Map<String, dynamic>>)
                            .docs
                            .isNotEmpty)));
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !hasLocal) {
          return const ChurchPanelLoadingBody();
        }
        if (!hasLocal && loadError != null) {
          return _buildLancamentosResilienceBanner(error: loadError);
        }
        final showResilienceBanner =
            loadError != null || _fetching || _showingStaleCache;
        final financeSnap = snap.data != null && snap.data!.isNotEmpty
            ? snap.data![0] as QuerySnapshot<Map<String, dynamic>>
            : null;
        final contasSnap = snap.data != null && snap.data!.length > 1
            ? snap.data![1] as QuerySnapshot<Map<String, dynamic>>
            : null;
        var docs = financeSnap?.docs ?? _seedFinanceDocs ?? [];
        final allLancsSnapshot = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
        final contasAtivasDocs = (contasSnap?.docs ?? _seedContasDocs ?? [])
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
        if (_filtroDoacaoKind != 'todos') {
          docs = docs.where((d) {
            final data = d.data();
            if (!_financeIsDonationLancamento(data)) return false;
            final kind = _financeDonationKindLabel(data).toLowerCase();
            if (_filtroDoacaoKind == 'dizimo') return kind.contains('díz') || kind.contains('diz');
            return kind.contains('oferta');
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
        final filtroVazio = allLancsSnapshot.isNotEmpty && docs.isEmpty;
        double aReceberAbertoFiltro = 0, aPagarAbertoFiltro = 0;
        if (filtroVazio) {
          for (final d in allLancsSnapshot) {
            final data = d.data();
            final tipo = (data['type'] ?? '').toString().toLowerCase();
            if (tipo == 'transferencia') continue;
            final valor = _parseValor(data['amount'] ?? data['valor']);
            if (financeLancamentoPendenteRecebimento(data)) {
              aReceberAbertoFiltro += valor;
            }
            if (financeLancamentoPendentePagamento(data)) {
              aPagarAbertoFiltro += valor;
            }
          }
        }

        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _future;
          },
          child: CustomScrollView(
            primary: true,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (showResilienceBanner)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ThemeCleanPremium.spaceLg,
                      ThemeCleanPremium.spaceSm,
                      ThemeCleanPremium.spaceLg,
                      0,
                    ),
                    child: _buildLancamentosResilienceBanner(error: loadError),
                  ),
                ),
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
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                                    value: _filtroDoacaoKind,
                                    isExpanded: true,
                                    icon: const Icon(
                                        Icons.volunteer_activism_rounded,
                                        size: 20),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'todos',
                                          child: Text('Todas doações')),
                                      DropdownMenuItem(
                                          value: 'dizimo', child: Text('Dízimo')),
                                      DropdownMenuItem(
                                          value: 'oferta_missionaria',
                                          child: Text('Oferta Missionária')),
                                    ],
                                    onChanged: (v) => setState(
                                        () => _filtroDoacaoKind = v ?? 'todos'),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tipo de movimento',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FinancePremiumFilterChip(
                                label: 'Todos',
                                icon: Icons.receipt_long_rounded,
                                accent: ThemeCleanPremium.primary,
                                selected: _filtroTipo == 'todos',
                                onTap: () => setState(() => _filtroTipo = 'todos'),
                                compact: true,
                              ),
                              const SizedBox(width: 8),
                              FinancePremiumFilterChip(
                                label: 'Receitas',
                                icon: Icons.trending_up_rounded,
                                accent: const Color(0xFF16A34A),
                                selected: _filtroTipo == 'entrada',
                                onTap: () => setState(() => _filtroTipo = 'entrada'),
                                compact: true,
                              ),
                              const SizedBox(width: 8),
                              FinancePremiumFilterChip(
                                label: 'Despesas',
                                icon: Icons.trending_down_rounded,
                                accent: const Color(0xFFDC2626),
                                selected: _filtroTipo == 'saida',
                                onTap: () => setState(() => _filtroTipo = 'saida'),
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
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
                        const SizedBox(height: 12),
                        Text(
                          'Situação',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FinancePremiumExtraStatusFilters(
                          selected: _filtroExtra,
                          onChanged: (v) => setState(() => _filtroExtra = v),
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
                  padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                      ThemeCleanPremium.spaceLg, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute<bool>(
                              fullscreenDialog: true,
                              builder: (_) => FinanceSmartInputPage(
                                tenantId: widget.tenantId,
                                panelRole: widget.role,
                              ),
                            ),
                          );
                          if (ok == true) {
                            _refresh();
                            widget.onFinanceChanged?.call();
                          }
                        },
                        icon: const Icon(Icons.content_paste_go_rounded,
                            size: 18),
                        label: const Text('Importar / colar extrato'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FinanceBulkAssignPage(
                                tenantId: widget.tenantId,
                                role: widget.role,
                              ),
                            ),
                          );
                          _refresh();
                          widget.onFinanceChanged?.call();
                        },
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Vincular em massa'),
                      ),
                    ],
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
              if (filtroVazio)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 8,
                        ThemeCleanPremium.spaceLg, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (aReceberAbertoFiltro > 0.009 || aPagarAbertoFiltro > 0.009) ...[
                          Text(
                            'Lançamentos em aberto (visão geral)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajuste os filtros abaixo ou toque em «Limpar filtros» para ver a lista completa.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, c) {
                              final wA = _TotalizadorCard(
                                label: 'A receber',
                                valor: aReceberAbertoFiltro,
                                icon: Icons.schedule_send_rounded,
                                color: const Color(0xFF0891B2),
                                semanticsLabel:
                                    'A receber em aberto, ${aReceberAbertoFiltro.toStringAsFixed(2)} reais',
                              );
                              final wP = _TotalizadorCard(
                                label: 'A pagar',
                                valor: aPagarAbertoFiltro,
                                icon: Icons.pending_actions_rounded,
                                color: const Color(0xFFEA580C),
                                semanticsLabel:
                                    'A pagar em aberto, ${aPagarAbertoFiltro.toStringAsFixed(2)} reais',
                              );
                              if (c.maxWidth < 520) {
                                return Column(
                                  children: [
                                    wA,
                                    const SizedBox(height: 10),
                                    wP,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: wA),
                                  const SizedBox(width: 12),
                                  Expanded(child: wP),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                        Icon(Icons.filter_alt_off_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum lançamento com estes filtros.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Troque o extra (pendente, a pagar, conciliado, etc.), a conta ou a categoria, ou mostre tudo de novo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.35),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _filtroTipo = 'todos';
                                _filtroCategoria = 'todas';
                                _filtroContaId = '__geral__';
                                _filtroDoacaoKind = 'todos';
                                _filtroExtra = 'todos';
                              });
                            },
                            icon: const Icon(Icons.clear_all_rounded, size: 20),
                            label: const Text('Limpar filtros'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
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
                          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
                              force: true);
                          await doc.reference.update({
                            'aprovacaoPendente': false,
                            'aprovadoPorUid':
                                firebaseDefaultAuth.currentUser?.uid ?? '',
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
              if ((financeSnap?.docs.length ?? 0) >= _financeFetchLimit)
                SliverToBoxAdapter(
                  child: LazyLoadMoreFooter(
                    label: 'Carregar mais lançamentos',
                    onLoadMore: _loadMoreFinanceLancamentos,
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
    final isDonation = !isTransfer && isEntrada && _financeIsDonationLancamento(data);
    final donationLabel = _financeDonationKindLabel(data);
    final valor = _parseValor(data['amount'] ?? data['valor']);
    final categoria =
        (data['categoria'] ?? data['title'] ?? 'Sem categoria').toString();
    final descricao = (data['descricao'] ?? '').toString();
    final donorNm = (data['donorName'] ?? '').toString().trim();
    final origemNome = (data['contaOrigemNome'] ?? '').toString();
    final destinoNome = (data['contaDestinoNome'] ?? '').toString();
    final dt = _parseDate(data['createdAt'] ?? data['date']);
    final dataStr =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final hasComprovanteAnexo =
        FinanceComprovanteAttachService.hasComprovanteReady(data);
    final comprovanteEnviando =
        FinanceComprovanteAttachService.isComprovanteUploading(data);
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
    final titulo = isTransfer
        ? 'Transferência'
        : (isDonation ? donationLabel : categoria);
    final subtitulo = isTransfer
        ? (origemNome.isNotEmpty && destinoNome.isNotEmpty
            ? '$origemNome → $destinoNome'
            : descricao)
        : (isDonation
            ? (donorNm.isNotEmpty
                ? donorNm
                : (descricao.isNotEmpty ? descricao : categoria))
            : descricao);

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
          onTap: () async {
            final compUrl =
                await FinanceComprovantePublishService.resolveComprovanteUrl(
                    data);
            if (!context.mounted) return;
            showFinanceLancamentoDetailsBottomSheet(context,
                data: data,
                comprovanteUrl: compUrl,
                dataStr: dataStr,
                isEntrada: isEntrada,
                isTransfer: isTransfer,
                color: color,
                valor: valor,
                titulo: titulo,
                subtitulo: subtitulo);
          },
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
                        color:
                            pendenteRecorrencia ? Colors.amber.shade100 : null,
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
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          if (vinculoLinha != null && !isTransfer)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: FinancePremiumVinculoPill(
                                label: vinculoLinha,
                                isMembro: vinculoLinha.startsWith('Membro'),
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
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isTransfer
                          ? 'R\$ ${valor.toStringAsFixed(2)}'
                          : '${isEntrada ? '+' : '-'} R\$ ${valor.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(dataStr,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    if (pendenteRecorrencia)
                      const FinancePremiumStatusPill(
                        label: 'Conciliar',
                        icon: Icons.sync_problem_rounded,
                        colors: [Color(0xFFD97706), Color(0xFFFBBF24)],
                      ),
                    if (hasComprovanteAnexo)
                      FinancePremiumStatusPill(
                        label: 'Comprovante',
                        icon: Icons.receipt_long_rounded,
                        colors: [
                          ThemeCleanPremium.success,
                          ThemeCleanPremium.success.withValues(alpha: 0.7),
                        ],
                      ),
                    if (pendenteAprovacao)
                      const FinancePremiumStatusPill(
                        label: 'Aprovar',
                        icon: Icons.gavel_rounded,
                        colors: [Color(0xFFEA580C), Color(0xFFFB923C)],
                      ),
                    if (!isTransfer && !conciliadoOk)
                      const FinancePremiumStatusPill(
                        label: 'Não conciliado',
                        icon: Icons.receipt_long_outlined,
                        colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                      ),
                    if (!isTransfer &&
                        isEntrada &&
                        data['recebimentoConfirmado'] == false)
                      const FinancePremiumStatusPill(
                        label: 'Pendente',
                        icon: Icons.schedule_rounded,
                        colors: [Color(0xFFD97706), Color(0xFFFBBF24)],
                      ),
                    if (!isTransfer &&
                        !isEntrada &&
                        data['pagamentoConfirmado'] == false)
                      const FinancePremiumStatusPill(
                        label: 'A pagar',
                        icon: Icons.schedule_rounded,
                        colors: [Color(0xFFDC2626), Color(0xFFF87171)],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (podeAprovar)
                        FinancePremiumIconAction(
                          icon: Icons.verified_rounded,
                          color: const Color(0xFF059669),
                          onTap: onApprove,
                          tooltip: 'Aprovar despesa',
                        ),
                      FinancePremiumIconAction(
                        icon: Icons.edit_rounded,
                        color: ThemeCleanPremium.primary,
                        onTap: onEdit,
                        tooltip: 'Editar',
                      ),
                      FinancePremiumIconAction(
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFDC2626),
                        onTap: onDelete,
                        tooltip: 'Excluir',
                      ),
                      if (hasComprovanteAnexo)
                        FinancePremiumIconAction(
                          icon: Icons.visibility_rounded,
                          color: const Color(0xFF0D9488),
                          onTap: () => FinanceComprovanteAttachService
                              .viewFromDoc(context, data),
                          tooltip: 'Ver comprovante',
                        )
                      else if (comprovanteEnviando)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        FinancePremiumIconAction(
                          icon: Icons.visibility_rounded,
                          color: Colors.grey.shade400,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Este lançamento ainda não tem comprovante.',
                                ),
                              ),
                            );
                          },
                          tooltip: 'Sem comprovante',
                        ),
                      FinancePremiumIconAction(
                        icon: hasComprovanteAnexo || comprovanteEnviando
                            ? Icons.sync_rounded
                            : Icons.photo_camera_rounded,
                        color: const Color(0xFF7C3AED),
                        tooltip: hasComprovanteAnexo || comprovanteEnviando
                            ? 'Trocar comprovante'
                            : 'Anexar comprovante',
                        onTap: comprovanteEnviando
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Comprovante ainda sincronizando…',
                                    ),
                                  ),
                                );
                              }
                            : () => uploadFinanceComprovanteForLancamento(
                                  context,
                                  tenantId: tenantId,
                                  doc: doc,
                                ),
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

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — Despesas Fixas
// ═══════════════════════════════════════════════════════════════════════════════
class _DespesasFixasTab extends StatefulWidget {
  final String tenantId;
  final String role;

  const _DespesasFixasTab({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  State<_DespesasFixasTab> createState() => _DespesasFixasTabState();
}

class _DespesasFixasTabState extends State<_DespesasFixasTab> {
  CollectionReference<Map<String, dynamic>> get _col =>
                ChurchUiCollections.churchDoc(widget.tenantId)
          .collection('despesas_fixas');

  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _cachedDocs;
  bool _fetching = false;

  void _reloadFuture() {
    _fetching = true;
    _future = ChurchTenantResilientReads.despesasFixas(widget.tenantId)
        .timeout(PanelResilientLoad.queryCap)
        .then((snap) {
      if (mounted) {
        setState(() {
          if (snap.docs.isNotEmpty) _cachedDocs = snap.docs;
          _fetching = false;
        });
      }
      return snap;
    }).catchError((e) {
      if (mounted) {
        final ui = PanelResilientLoad.afterError(
          hadLocalData: (_cachedDocs?.isNotEmpty ?? false),
          error: e,
        );
        setState(() => _fetching = ui.fetching);
      }
      throw e;
    });
  }

  @override
  void initState() {
    super.initState();
    _reloadFuture();
  }

  @override
  void didUpdateWidget(covariant _DespesasFixasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      setState(_reloadFuture);
    }
  }

  void _refresh() {
    setState(_reloadFuture);
  }

  Future<void> _gerarPendentes() async {
    try {
      final n = await gerarDespesasFixasPendentes(widget.tenantId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Nada novo a gerar (já existem ou fora do período).'
                : '$n despesa(s) projetada(s) no caixa.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final loadError = snap.hasError ? snap.error : null;
        final docs = snap.data?.docs ?? _cachedDocs ?? [];
        final hasLocal = docs.isNotEmpty;
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !hasLocal) {
          return const ChurchPanelLoadingBody();
        }
        if (!hasLocal && loadError != null) {
          return ChurchPanelResilientLoadBanner(
            hasLocalData: false,
            isSyncing: _fetching,
            errorTitle: 'Não foi possível carregar as despesas fixas',
            error: loadError,
            onRetry: _refresh,
          );
        }

        return Column(
          children: [
            if (loadError != null || _fetching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ChurchPanelResilientLoadBanner(
                  hasLocalData: hasLocal,
                  isSyncing: _fetching && hasLocal,
                  errorTitle: 'Não foi possível carregar as despesas fixas',
                  error: loadError,
                  onRetry: _refresh,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Despesas mensais recorrentes (${docs.length}) — lançamentos pendentes até confirmar pagamento.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _gerarPendentes,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Gerar no caixa'),
                  ),
                  const SizedBox(width: 4),
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
        await getCategoriasDespesaForTenant(widget.tenantId);
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
    await _ensureFinanceWriteReady();
    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
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
    final op = ChurchRepository.churchId(widget.tenantId.trim());
    await         ChurchUiCollections.financeiro(op)
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
    final ref = ChurchUiCollections.churchDoc(tenantId);
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
            padrao: kCategoriasDespesaPadrao,
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
      stream: widget.collection.orderBy('nome').watchSafe(),
      builder: (context, snap) {
        final loadError = snap.hasError ? snap.error : null;
        final docsRaw = snap.data?.docs ?? [];
        final hasLocal = docsRaw.isNotEmpty;
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
        if (!hasLocal && loadError != null) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: snap.connectionState == ConnectionState.waiting,
              errorTitle: 'Não foi possível carregar as categorias',
              error: loadError,
              onRetry: () => setState(() => _categoriasStreamRetry++),
            ),
          );
        }
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
      ChurchUiCollections.contas(widget.tenantId);

  CollectionReference<Map<String, dynamic>> get _financeCol =>
                ChurchUiCollections.financeiro(widget.tenantId);

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
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedContasDocs;
  String? _loadHint;
  bool _fetching = false;
  bool _showingStaleCache = false;
  Timer? _webLoadCap;

  bool get _contasHasLocalData => (_seedContasDocs?.isNotEmpty ?? false);

  void _startContasWebCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(PanelResilientLoad.webLoadingCap, () {
      if (!mounted || !_fetching) return;
      setState(() {
        _fetching = false;
        if (_contasHasLocalData) {
          _showingStaleCache = true;
          _loadHint = null;
        } else {
          _loadHint ??= 'Tempo esgotado ao carregar contas na Web.';
        }
      });
    });
  }

  Widget _buildContasResilienceBanner({Object? error}) {
    return ChurchPanelResilientLoadBanner(
      hasLocalData: _contasHasLocalData,
      isSyncing: _fetching && _contasHasLocalData,
      showStaleCache: _showingStaleCache && !_fetching,
      errorTitle: 'Não foi possível carregar as contas',
      error: error,
      onRetry: _refresh,
      staleMessage:
          'Modo offline — contas com últimos dados guardados. Puxe para atualizar.',
      syncMessage:
          'Sincronizando contas… a mostrar dados guardados enquanto atualiza.',
    );
  }

  void _seedContasCache() {
    final churchId = ChurchRepository.churchId(widget.tenantId);
    _seedContasDocs =
        ChurchFinanceLoadService.peekContasRam(churchId) ?? const [];
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadContasBundle({
    required bool forceFresh,
  }) async {
    final tid = ChurchRepository.churchId(widget.tenantId);
    final result = await ChurchFinanceLoadService.loadContas(
      seedTenantId: tid,
      forceRefresh: forceFresh,
      forceServer: forceFresh,
    ).timeout(PanelResilientLoad.queryCap);
    if (mounted) {
      final hadLocal = _contasHasLocalData;
      if (result.docs.isNotEmpty) {
        _loadHint = null;
      } else if (result.softError != null) {
        final ui = PanelResilientLoad.afterFetch(
          hadLocalData: hadLocal,
          newItems: result.docs,
          fromCache: false,
          softError: result.softError,
          forceFresh: forceFresh,
        );
        if (!hadLocal) _loadHint = ui.loadError;
        _showingStaleCache = ui.showingStaleCache;
      }
    }
    return result.snapshot;
  }

  void _reloadFuture({bool forceFresh = false}) {
    if (!forceFresh) {
      _seedContasCache();
    } else {
      _seedContasDocs ??= const [];
    }

    final hadLocal = _contasHasLocalData;
    _fetching = true;
    if (!forceFresh && hadLocal) _showingStaleCache = true;
    if (forceFresh) _loadHint = null;
    _startContasWebCap();

    _future = Future.value(MergedFirestoreQuerySnapshot(_seedContasDocs!));

    unawaited(
      _loadContasBundle(forceFresh: forceFresh).then((fresh) {
        if (!mounted) return;
        _webLoadCap?.cancel();
        setState(() {
          _seedContasDocs = fresh.docs;
          _future = Future.value(fresh);
          _fetching = false;
          _showingStaleCache = false;
          _loadHint = null;
        });
      }).catchError((e) {
        if (!mounted) return;
        _webLoadCap?.cancel();
        final ui = PanelResilientLoad.afterError(
          hadLocalData: _contasHasLocalData,
          error: e,
        );
        setState(() {
          _fetching = ui.fetching;
          _showingStaleCache = ui.showingStaleCache;
          if (!_contasHasLocalData) _loadHint = ui.loadError;
        });
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _reloadFuture();
  }

  @override
  void dispose() {
    _webLoadCap?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FinanceContasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      setState(() => _reloadFuture());
    }
  }

  void _refresh() {
    setState(() => _reloadFuture(forceFresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final loadError = snap.hasError ? snap.error : _loadHint;
        final hasLocal = _contasHasLocalData ||
            (snap.data?.docs.isNotEmpty ?? false);
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !hasLocal) {
          return const ChurchPanelLoadingBody();
        }
        if (!hasLocal && loadError != null) {
          return _buildContasResilienceBanner(error: loadError);
        }
        final showResilienceBanner =
            loadError != null || _fetching || _showingStaleCache;
        final docs = snap.data?.docs ?? _seedContasDocs ?? [];
        return Column(
          children: [
            if (showResilienceBanner)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ThemeCleanPremium.spaceLg,
                  ThemeCleanPremium.spaceSm,
                  ThemeCleanPremium.spaceLg,
                  0,
                ),
                child: _buildContasResilienceBanner(error: loadError),
              ),
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
                            color: _financeContaBancoColor(data)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                          ),
                          child: Icon(Icons.account_balance_rounded,
                              color: _financeContaBancoColor(data), size: 22),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(nome,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (data['contaPrincipal'] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: const Text('Principal',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                  side: BorderSide(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.35)),
                                ),
                              ),
                          ],
                        ),
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

    var contaPrincipal = d?['contaPrincipal'] == true;

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
                                child: Row(
                                  children: [
                                    _financeBankMiniLogo(
                                      bancoCodigo: b.codigo,
                                      bancoNome: b.nome,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        b.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
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
                    FinancePremiumContaTipoToggle(
                      selected: tipoConta,
                      onChanged: (v) => setDlg(() => tipoConta = v),
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Conta principal'),
                      subtitle: Text(
                        'Uma conta principal por igreja. Use para padrão em atalhos e novos lançamentos.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      value: contaPrincipal,
                      onChanged: (v) => setDlg(() => contaPrincipal = v),
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
      'bancoBrandSlug':
          brasilBancoBrandingFor(codigo: bancoSel.codigo, nome: bancoSel.nome).slug,
      'agencia': agenciaCtrl.text.trim(),
      'numeroConta': contaCtrl.text.trim(),
      'tipoConta': tipoConta,
      'observacao': obsCtrl.text.trim(),
      'ativo': d?['ativo'] ?? true,
      'contaPrincipal': contaPrincipal,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    late final DocumentReference<Map<String, dynamic>> savedRef;
    if (existing == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      savedRef = await col.add(payload);
    } else {
      savedRef = existing.reference;
      await savedRef.set(payload, SetOptions(merge: true));
    }

    if (contaPrincipal) {
      final snap = await col.get();
      final batch = firebaseDefaultFirestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'contaPrincipal': doc.id == savedRef.id});
      }
      await batch.commit();
    }

    if (!context.mounted) return;
    onSaved?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          existing == null ? 'Conta cadastrada.' : 'Conta atualizada.',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green));
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
  /// Acessibilidade: leitores de ecrã (e.g. VoiceOver) — resumo com valor.
  final String? semanticsLabel;

  const _TotalizadorCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
    this.onTap,
    this.semanticsLabel,
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
    Widget w;
    if (onTap == null) {
      w = Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          decoration: decoration,
          child: child);
    } else {
      w = Material(
          color: Colors.transparent,
          child: InkWell(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
              onTap: onTap,
              child: Container(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                  decoration: decoration,
                  child: child)));
    }
    if (semanticsLabel == null || semanticsLabel!.trim().isEmpty) {
      return w;
    }
    return Semantics(
      label: semanticsLabel!.trim(),
      container: true,
      child: w,
    );
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

/// Lista fornecedores ativos para o dropdown do lançamento.
Future<List<({String id, String nome})>> _fornecedoresParaFinanceDropdown(
    String tenantId) async {
  try {
    final op = ChurchRepository.churchId(tenantId);
    final snap = await ChurchUiCollections.fornecedores(op)
        .orderBy('nome')
        .limit(500)
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

/// Membros ativos — cache `_panel_cache/members_directory` (rápido; evita scan 3000).
Future<List<({String id, String nome})>> _membrosParaFinanceDropdown(
    String tenantId) async {
  try {
    final op = ChurchRepository.churchId(tenantId);
    var snap = await MembersDirectorySnapshotService.readOnce(op);
    if (!snap.hasEntries) {
      snap = await MembersDirectorySnapshotService.warmFromCallableIfStale(op);
    }
    final out = <({String id, String nome})>[];
    for (final e in snap.entries) {
      final st = e.status.toLowerCase();
      if (st == 'inativo' ||
          st == 'recusado' ||
          st == 'bloqueado' ||
          st == 'cancelado') {
        continue;
      }
      final n = e.displayName.trim();
      if (n.isEmpty) continue;
      out.add((id: e.memberDocId, nome: n));
    }
    if (out.isNotEmpty) {
      out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      return out;
    }
    // Fallback leve se cache ainda não existir.
    final legacy = await ChurchUiCollections.membros(op)
        .limit(YahwehPerformanceV4.defaultPageSize * 5)
        .get();
    for (final d in legacy.docs) {
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

/// Texto único para cartão / extrato (fornecedor, membro ou doador MP).
String? financeLancamentoVinculoLabel(Map<String, dynamic> data) {
  final fn = (data['fornecedorNome'] ?? '').toString().trim();
  final mnCadastro = (data['membroNome'] ?? '').toString().trim();
  final donor = (data['donorName'] ?? '').toString().trim();
  final origem = (data['origem'] ?? '').toString().toLowerCase();
  final fromMp =
      origem.contains('mercado_pago') || (data['mpPaymentId'] ?? '').toString().isNotEmpty;

  if (fn.isEmpty && mnCadastro.isEmpty && donor.isEmpty) return null;
  if (fn.isNotEmpty && (mnCadastro.isNotEmpty || donor.isNotEmpty)) {
    final m = mnCadastro.isNotEmpty ? mnCadastro : donor;
    return 'Fornecedor · $fn · Membro · $m';
  }
  if (fn.isNotEmpty) return 'Fornecedor · $fn';
  if (mnCadastro.isNotEmpty) return 'Membro · $mnCadastro';
  if (donor.isNotEmpty && fromMp) return 'Doador · $donor';
  return null;
}

/// Editor de lançamento (mesmo fluxo do módulo financeiro) — reutilizável no painel.
/// Retorna `true` se gravou com sucesso.
Future<void> _ensureFinanceWriteReady({BuildContext? context}) async {
  final ok = await YahwehModuleMediaGate.prepareForPublishUpload(
    context: context,
    module: YahwehMediaModule.financeiro,
    logLabel: 'finance_write',
    withPhotos: true,
  );
  if (!ok) {
    throw StateError('Firebase indisponível para operações financeiras.');
  }
}

bool _financeTreatSilentSuccess(
  BuildContext context,
  Object e, {
  required String tenantId,
  String message = 'Salvo — sincroniza em background.',
}) {
  if (!YahwehCentralEngineService.isOfflineQueuedSuccess(e)) return false;
  if (context.mounted) {
    showFinanceSaveSnackBar(context, message: message);
  }
  YahwehCentralEngineService.scheduleBackgroundSync(reason: 'finance_ui');
  unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
  return true;
}

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
  final effectiveTenantId =
      ChurchContextService.panelChurchId(ChurchRepository.churchId(tenantId));
  if (effectiveTenantId.isEmpty) return false;

  unawaited(_ensureFinanceWriteReady().catchError((_) {}));

  final op = effectiveTenantId;
  final financeCol = ChurchUiCollections.financeiro(op);

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

  List<String> catsReceita;
  List<String> catsDespesa;
  List<({String id, String nome})> contas;
  List<({String id, String nome})> fornecedoresOpts;
  List<({String id, String nome})> membrosOpts;
  FinanceTenantSettings settings;
  try {
    catsReceita = await _financeCategoriasReceitaTenant(effectiveTenantId);
    catsDespesa = await getCategoriasDespesaForTenant(effectiveTenantId);
    contas = await _financeContasAtivasTenant(effectiveTenantId);
    fornecedoresOpts =
        await _fornecedoresParaFinanceDropdown(effectiveTenantId);
    membrosOpts = await _membrosParaFinanceDropdown(effectiveTenantId);
    settings = await FinanceTenantSettings.load(effectiveTenantId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
    return false;
  }

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

  final membroIdRaw = isEdit
      ? (data?['membroId'] ?? data?['memberId'] ?? '').toString().trim()
      : '';
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
  if (membroId != null && membroNome.isEmpty && isEdit && data != null) {
    final dn = (data['donorName'] ?? '').toString().trim();
    if (dn.isNotEmpty) membroNome = dn;
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
  FinanceComprovanteAttachment? comprovanteAnexo;
  final comprovanteExistente =
      isEdit && FinanceComprovanteAttachService.hasComprovanteInDoc(data ?? {});
  String nomeConta(String? id) {
    if (id == null) return '';
    for (final c in contas) {
      if (c.id == id) return c.nome;
    }
    return '';
  }

  final dataCtrl = TextEditingController(text: formatBrDateDdMmYyyy(dataSel));

  final result = await Navigator.of(context, rootNavigator: true)
      .push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        final isTransfer = t == 'transferencia';
        final cats = t == 'entrada'
            ? catsReceita
            : (t == 'saida' ? catsDespesa : <String>[]);
        if (cat.isNotEmpty && cats.isNotEmpty && !cats.contains(cat)) cat = '';
        final contaFieldId = t == 'entrada' ? cdId : coId;
        final pageAccent = FinancePremiumLancamentoUi.accentForTipo(t);
        final pageGradient = FinancePremiumLancamentoUi.gradientForTipo(t);
        final pagePad = ThemeCleanPremium.pagePadding(ctx);

        void onTipoChanged(String v) {
          setDlgState(() {
            final prev = t;
            t = v;
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
          });
        }

        Future<void> pickDataLancamento() async {
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
        }

        void submitLancamento() {
          final valor = parseBrCurrencyInput(valorCtrl.text);
          final parsedData = parseBrDateDdMmYyyy(dataCtrl.text.trim());
          if (parsedData == null) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Informe a data (DD/MM/AAAA).')),
            );
            return;
          }
          dataSelLocal = parsedData;
          if (valor <= 0) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Informe um valor válido.')),
            );
            return;
          }
          if (!isTransfer && cat.isEmpty) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Selecione uma categoria.')),
            );
            return;
          }
          if (!isTransfer && contas.isNotEmpty) {
            if (t == 'entrada' && cdId == null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('Selecione a conta ou caixa da receita.')),
              );
              return;
            }
            if (t == 'saida' && coId == null) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('Selecione a conta ou caixa da despesa.')),
              );
              return;
            }
          }
          if (isTransfer &&
              (coId == null || cdId == null || coId == cdId)) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                  content:
                      Text('Selecione contas de origem e destino diferentes.')),
            );
            return;
          }
          final map = <String, dynamic>{
            'type': t,
            'amount': valor,
            'descricao': descCtrl.text.trim(),
            'createdAt': Timestamp.fromDate(dataSelLocal),
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
            if (lockFornecedor && fid != null && fid.isNotEmpty) {
              map['fornecedorId'] = fid;
              map['fornecedorNome'] = fornecedorNome;
            } else if (!lockFornecedor) {
              if (vinculoTipo == 'fornecedor' &&
                  fid != null &&
                  fid.isNotEmpty) {
                map['fornecedorId'] = fid;
                map['fornecedorNome'] = fornecedorNome;
              }
              if (vinculoTipo == 'membro' && mid != null && mid.isNotEmpty) {
                map['membroId'] = mid;
                map['membroNome'] = membroNome;
              }
            }
            if (t == 'entrada') {
              map['recebimentoConfirmado'] = recebimentoConfirmado;
            } else {
              map['pagamentoConfirmado'] = pagamentoConfirmado;
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
                AppPermissions.despesaFinanceiraExigeSegundaAprovacao(panelRole);
            map['aprovacaoPendente'] = need;
          }
          ThemeCleanPremium.hapticAction();
          Navigator.pop(ctx, map);
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF0F4FF),
          appBar: financePremiumLancamentoAppBar(
            title: isEdit ? 'Editar lançamento' : 'Novo lançamento',
            onBack: () => Navigator.pop(ctx),
            gradientColors: pageGradient,
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: pagePad.copyWith(top: 14, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                FinancePremiumTipoToggle(
                  selected: t,
                  onChanged: onTipoChanged,
                ),
                const SizedBox(height: 18),
                FinancePremiumAmountField(
                  controller: valorCtrl,
                  isReceita: t == 'entrada',
                ),
                const SizedBox(height: 16),
                FinancePremiumFieldTile(
                  label: 'Data do lançamento',
                  value: formatBrDateDdMmYyyy(dataSelLocal),
                  icon: Icons.calendar_today_rounded,
                  accent: pageAccent,
                  onTap: pickDataLancamento,
                ),
                const SizedBox(height: 18),
                if (!isTransfer)
                  FinancePremiumSectionCard(
                    title: 'Classificação',
                    icon: Icons.category_rounded,
                    accent: pageAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  DropdownButtonFormField<String>(
                    value: cat.isNotEmpty ? cat : null,
                    decoration: financePremiumDropdownDecoration(
                      label: 'Categoria',
                      prefixIcon: Icons.category_rounded,
                      accent: pageAccent,
                    ),
                    items: cats
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDlgState(() => cat = v ?? ''),
                  ),
                  const SizedBox(height: 12),
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
                      FinancePremiumVinculoToggle(
                        selected: vinculoTipo,
                        onChanged: (v) => setDlgState(() {
                          vinculoTipo = v;
                          if (vinculoTipo != 'fornecedor') {
                            fornecedorId = null;
                            fornecedorNome = '';
                          }
                          if (vinculoTipo != 'membro') {
                            membroId = null;
                            membroNome = '';
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (vinculoTipo == 'fornecedor')
                        FinanceFixoTitularCard(
                          vinculoTipo: 'fornecedor',
                          tituloPlaceholder: 'Fornecedor / prestador',
                          nomeExibicao: fornecedorNome,
                          onTap: () async {
                            final picked = await showFinancePremiumFornecedorPicker(
                              ctx,
                              tenantId: effectiveTenantId,
                            );
                            if (picked == null) return;
                            setDlgState(() {
                              fornecedorId = picked.$1;
                              fornecedorNome = picked.$2;
                            });
                          },
                        ),
                      if (vinculoTipo == 'membro')
                        FinanceFixoTitularCard(
                          vinculoTipo: 'membro',
                          tituloPlaceholder: 'Membro',
                          nomeExibicao: membroNome,
                          onTap: () async {
                            final picked = await showFinancePremiumMemberPicker(
                              ctx,
                              tenantId: effectiveTenantId,
                            );
                            if (picked == null) return;
                            setDlgState(() {
                              membroId = picked.$1;
                              membroNome = picked.$2;
                            });
                          },
                        ),
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
                    FinancePremiumSituacaoToggle(
                      confirmed: recebimentoConfirmado,
                      isReceita: true,
                      onChanged: (v) =>
                          setDlgState(() => recebimentoConfirmado = v),
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
                    FinancePremiumSituacaoToggle(
                      confirmed: pagamentoConfirmado,
                      isReceita: false,
                      onChanged: (v) =>
                          setDlgState(() => pagamentoConfirmado = v),
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
                    ),
                  ),
                if (isTransfer)
                  FinancePremiumSectionCard(
                    title: 'Transferência entre contas',
                    icon: Icons.swap_horiz_rounded,
                    accent: pageAccent,
                    child: FinancePremiumTransferAccountsSection(
                      contas: contas,
                      origemId: coId,
                      destinoId: cdId,
                      accent: pageAccent,
                      onOrigemChanged: (v) => setDlgState(() => coId = v),
                      onDestinoChanged: (v) => setDlgState(() => cdId = v),
                    ),
                  ),
                const SizedBox(height: 16),
                FinancePremiumSectionCard(
                  title: isTransfer ? 'Anotações' : 'Descrição',
                  icon: Icons.notes_rounded,
                  accent: pageAccent,
                  child: TextField(
                  controller: descCtrl,
                  decoration: financePremiumDropdownDecoration(
                    label: isTransfer
                        ? 'Anotações (opcional)'
                        : 'Descrição (opcional)',
                    prefixIcon: Icons.notes_rounded,
                    accent: pageAccent,
                  ),
                  maxLines: 2,
                ),
                ),
                if (!isTransfer) ...[
                  const SizedBox(height: 16),
                  FinancePremiumSectionCard(
                    title: 'Informações adicionais',
                    icon: Icons.more_horiz_rounded,
                    accent: pageAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  TextField(
                    controller: centroCustoCtrl,
                    decoration: financePremiumDropdownDecoration(
                      label: 'Centro de custo / projeto (opcional)',
                      prefixIcon: Icons.hub_rounded,
                      accent: pageAccent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: extratoRefCtrl,
                    decoration: financePremiumDropdownDecoration(
                      label: 'Ref. extrato / ID bancário (opcional)',
                      prefixIcon: Icons.tag_rounded,
                      accent: pageAccent,
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
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FinancePremiumSectionCard(
                  title: 'Comprovante',
                  icon: Icons.receipt_long_rounded,
                  accent: pageAccent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked =
                        await FinanceComprovanteAttachService.showPickSheet(
                      ctx,
                      title: comprovanteAnexo != null || comprovanteExistente
                          ? 'Trocar comprovante'
                          : 'Anexar comprovante',
                    );
                    if (picked == null) return;
                    comprovanteAnexo = picked;
                    setDlgState(() {});
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${picked.fileName} selecionado — toque «Salvar» para enviar.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: Icon(
                      comprovanteAnexo != null || comprovanteExistente
                          ? Icons.check_circle_rounded
                          : Icons.add_photo_alternate_rounded,
                      size: 20),
                  label: Text(
                    comprovanteAnexo != null
                        ? 'Pronto para enviar ao salvar'
                        : (comprovanteExistente
                            ? 'Comprovante já gravado'
                            : 'Anexar comprovante'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: comprovanteAnexo != null || comprovanteExistente
                        ? ThemeCleanPremium.success
                        : null,
                  ),
                ),
                if (comprovanteAnexo != null)
                  TextButton.icon(
                    onPressed: () => setDlgState(() {
                      comprovanteAnexo = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Remover novo anexo'),
                    style: TextButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.error),
                  ),
                if (isEdit &&
                    comprovanteExistente &&
                    comprovanteAnexo == null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      FinanceComprovanteAttachService.displayNameFromDoc(
                          data ?? {}),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            FinanceComprovanteAttachService.viewFromDoc(
                          ctx,
                          data ?? {},
                        ),
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        label: const Text('Ver comprovante'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked =
                              await FinanceComprovanteAttachService
                                  .showPickSheet(
                            ctx,
                            title: 'Trocar comprovante',
                          );
                          if (picked == null) return;
                          comprovanteAnexo = picked;
                          setDlgState(() {});
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Trocar comprovante'),
                      ),
                    ],
                  ),
                ],
                    ],
                  ),
                ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: pagePad.copyWith(top: 8, bottom: 12),
                  child: FinancePremiumFormFooterActions(
                    onCancel: () => Navigator.pop(ctx),
                    onSave: submitLancamento,
                    saveLabel:
                        isEdit ? 'Salvar alterações' : 'Adicionar lançamento',
                    saveIcon:
                        isEdit ? Icons.save_rounded : Icons.check_rounded,
                    accent: pageAccent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
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
    if (comprovanteAnexo != null &&
        !AppConnectivityService.instance.isOnline) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Sem ligação à internet. Conecte-se para enviar o comprovante.',
            ),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
      return false;
    }

    await _ensureFinanceWriteReady(context: context);

    Future<void> persistComprovante({
      required DocumentReference<Map<String, dynamic>> docRef,
      required Map<String, dynamic> refData,
      required Uint8List bytes,
      required String mime,
      String? fileName,
      String? prevPath,
      String? prevUrl,
    }) async {
      if (!context.mounted) return;
      final refDate =
          FinanceComprovantePublishService.referenceDateFromMap(refData);
      await FinanceComprovanteUi.runWithProgress(
        context,
        label: 'Enviando comprovante…',
        action: (onProgress) => FinanceComprovantePublishService
            .uploadComprovanteNow(
          tenantId: tenantId,
          docRef: docRef,
          rawBytes: bytes,
          mimeType: mime,
          fileName: fileName,
          referenceDate: refDate,
          previousStoragePath: prevPath,
          previousDownloadUrl: prevUrl,
          onProgress: onProgress,
        ),
      );
    }

    if (isEdit) {
      final novoComp = comprovanteAnexo;
      Uint8List? pendingBytes;
      String? pendingMime;
      String? pendingFileName;
      if (novoComp != null) {
        final prepared =
            await FinanceComprovanteAttachService.prepareUploadBytes(novoComp);
        pendingBytes = prepared.bytes;
        pendingMime = prepared.mimeType;
        pendingFileName = novoComp.fileName;
        result.remove('comprovanteUrl');
        result.remove('comprovanteLink');
      } else if (FinanceComprovanteAttachService.hasComprovanteInDoc(data ?? {})) {
        result['comprovanteUrl'] = data?['comprovanteUrl'];
        result['comprovanteLink'] =
            data?['comprovanteLink'] ?? data?['comprovanteUrl'];
        result['comprovanteStoragePath'] = data?['comprovanteStoragePath'];
        result['comprovanteMimeType'] = data?['comprovanteMimeType'];
        result['comprovanteFileName'] = data?['comprovanteFileName'];
        result['hasComprovante'] = data?['hasComprovante'] ?? true;
      }
      final patch = Map<String, dynamic>.from(result);
      if (pendingBytes != null) {
        patch[FinanceComprovantePublishService.comprovanteUploadStateField] =
            EntityPublishStatus.uploading;
      }
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
      await FinanceComprovantePublishService.saveLancamentoFirst(
        financeCol: financeCol,
        payload: patch,
        isEdit: true,
        existingRef: existingDoc.reference,
        hasNewComprovante: pendingBytes != null,
        previousPayloadForSaldo: data,
      );
      if (pendingBytes != null && pendingMime != null) {
        if (kIsWeb && AppConnectivityService.instance.isOnline) {
          await persistComprovante(
            docRef: existingDoc.reference,
            refData: {...?data, ...patch},
            bytes: pendingBytes,
            mime: pendingMime,
            fileName: pendingFileName,
            prevPath: (data?['comprovanteStoragePath'] ?? '').toString(),
            prevUrl: (data?['comprovanteUrl'] ?? '').toString(),
          );
          if (context.mounted) {
            showFinanceSaveSnackBar(
              context,
              message: 'Lançamento e comprovante atualizados!',
            );
          }
        } else {
          await GestaoYahwehWriteFirstPublishService.queueFinanceComprovanteAfterSave(
            churchId: ChurchRepository.churchId(tenantId),
            docRef: existingDoc.reference,
            bytes: pendingBytes,
            mimeType: pendingMime,
            fileName: pendingFileName,
            referenceDate: FinanceComprovantePublishService.referenceDateFromMap(
              {...?data, ...patch},
            ),
            previousStoragePath:
                (data?['comprovanteStoragePath'] ?? '').toString(),
            previousDownloadUrl: (data?['comprovanteUrl'] ?? '').toString(),
          );
          if (context.mounted) {
            showFinanceSaveSnackBar(
              context,
              message:
                  'Lançamento salvo — comprovante sincroniza em background.',
            );
          }
        }
      } else if (context.mounted) {
        showFinanceSaveSnackBar(
          context,
          message: 'Lançamento atualizado!',
        );
      }
    } else {
      final novoCompAdd = comprovanteAnexo;
      Uint8List? pendingAddBytes;
      String? pendingAddMime;
      String? pendingAddFileName;
      if (novoCompAdd != null) {
        final prepared =
            await FinanceComprovanteAttachService.prepareUploadBytes(
                novoCompAdd);
        pendingAddBytes = prepared.bytes;
        pendingAddMime = prepared.mimeType;
        pendingAddFileName = novoCompAdd.fileName;
      }

      final preRef = financeCol.doc();

      await FinanceComprovantePublishService.saveLancamentoFirst(
        financeCol: financeCol,
        payload: result,
        isEdit: false,
        preGeneratedRef: preRef,
        hasNewComprovante: pendingAddBytes != null,
      );

      if (pendingAddBytes != null && pendingAddMime != null) {
        if (kIsWeb && AppConnectivityService.instance.isOnline) {
          await persistComprovante(
            docRef: preRef,
            refData: result,
            bytes: pendingAddBytes,
            mime: pendingAddMime,
            fileName: pendingAddFileName,
          );
          if (context.mounted) {
            showFinanceSaveSnackBar(
              context,
              message: 'Lançamento e comprovante salvos!',
            );
          }
        } else {
          await GestaoYahwehWriteFirstPublishService.queueFinanceComprovanteAfterSave(
            churchId: ChurchRepository.churchId(tenantId),
            docRef: preRef,
            bytes: pendingAddBytes,
            mimeType: pendingAddMime,
            fileName: pendingAddFileName,
            referenceDate:
                FinanceComprovantePublishService.referenceDateFromMap(result),
          );
          if (context.mounted) {
            showFinanceSaveSnackBar(
              context,
              message: pendingAddBytes != null
                  ? 'Lançamento salvo — comprovante sincroniza em background.'
                  : 'Lançamento salvo!',
            );
          }
        }
      } else if (context.mounted) {
        showFinanceSaveSnackBar(
          context,
          message: 'Lançamento salvo!',
        );
      }
    }
    unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
    return true;
  } catch (e) {
    if (_financeTreatSilentSuccess(context, e, tenantId: tenantId)) {
      return true;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
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
  final docData = doc.data() ?? {};
  final jaTem = FinanceComprovanteAttachService.hasComprovanteInDoc(docData);

  final picked = await FinanceComprovanteAttachService.showPickSheet(
    context,
    title: jaTem ? 'Trocar comprovante' : 'Anexar comprovante',
  );
  if (picked == null) return;

  if (!context.mounted) return;

  try {
    await _ensureFinanceWriteReady(context: context);
    final prepared =
        await FinanceComprovanteAttachService.prepareUploadBytes(picked);
    final data = doc.data() ?? {};
    final refDate =
        FinanceComprovantePublishService.referenceDateFromMap(data);
    if (!context.mounted) return;

    await FinanceComprovanteUi.runWithProgress(
      context,
      label: jaTem ? 'Atualizando comprovante…' : 'Enviando comprovante…',
      action: (onProgress) => FinanceComprovantePublishService.uploadComprovanteNow(
        tenantId: tenantId,
        docRef: doc.reference,
        rawBytes: prepared.bytes,
        mimeType: prepared.mimeType,
        fileName: picked.fileName,
        referenceDate: refDate,
        previousStoragePath: (data['comprovanteStoragePath'] ?? '').toString(),
        previousDownloadUrl: (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
            .toString(),
        onProgress: onProgress,
      ),
    );

    if (!context.mounted) return;
    final pathHint = FinanceComprovantePublishService.comprovantePathFor(
      tenantId: tenantId,
      lancamentoId: doc.id,
      referenceDate: refDate,
      ext: FinanceComprovanteAttachService.extensionForMime(prepared.mimeType),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            jaTem
                ? 'Comprovante atualizado!\n$pathHint'
                : 'Comprovante anexado!\n$pathHint',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4)));
    unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
  } catch (e) {
    if (YahwehCentralEngineService.isOfflineQueuedSuccess(e)) {
      final prepared =
          await FinanceComprovanteAttachService.prepareUploadBytes(picked);
      final data = doc.data() ?? {};
      await YahwehCentralEngineService.queueFinanceComprovante(
        churchId: ChurchRepository.churchId(tenantId),
        docRef: doc.reference,
        bytes: prepared.bytes,
        mimeType: prepared.mimeType,
        fileName: picked.fileName,
        referenceDate:
            FinanceComprovantePublishService.referenceDateFromMap(data),
        previousStoragePath: (data['comprovanteStoragePath'] ?? '').toString(),
        previousDownloadUrl:
            (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
                .toString(),
      );
      if (context.mounted) {
        showFinanceSaveSnackBar(
          context,
          message: jaTem
              ? 'Comprovante guardado — sincroniza em background.'
              : 'Comprovante anexado — sincroniza em background.',
        );
      }
      unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
      return;
    }
    await YahwehModuleMediaGate.recoverNoAppAfterPublishError(e);
    await FinanceComprovantePublishService.markComprovanteUploadFailed(
      docRef: doc.reference,
      error: e,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
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
          if (comprovanteUrl.isNotEmpty ||
              FinanceComprovanteAttachService.hasComprovanteInDoc(data)) ...[
            const SizedBox(height: 16),
            Text('Comprovante',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            if (FinanceComprovanteAttachService.mimeFromDoc(data)
                .contains('pdf'))
              OutlinedButton.icon(
                onPressed: () => FinanceComprovanteAttachService.viewFromDoc(
                  ctx,
                  data,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(FinanceComprovanteAttachService.displayNameFromDoc(
                    data)),
              )
            else if (comprovanteUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SafeNetworkImage(
                    imageUrl: comprovanteUrl,
                    height: 200,
                    fit: BoxFit.cover,
                    errorWidget: const Text('Erro ao carregar imagem')),
              )
            else
              OutlinedButton.icon(
                onPressed: () => FinanceComprovanteAttachService.viewFromDoc(
                  ctx,
                  data,
                ),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver comprovante'),
              ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
Widget _linhaResumoExtrato(
  String label,
  double v,
  NumberFormat nf, {
  bool neg = false,
  bool strong = false,
}) {
  final c = (neg && v > 0) ? const Color(0xFFFECACA) : Colors.white;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1.5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color: c,
              fontSize: strong ? 14 : 12.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
            )),
        Text(
          nf.format(v),
          style: TextStyle(
            color: c,
            fontSize: strong ? 16 : 13.5,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

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
