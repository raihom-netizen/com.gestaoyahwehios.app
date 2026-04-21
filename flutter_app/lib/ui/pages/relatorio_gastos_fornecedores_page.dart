import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Período do relatório fornecedores/prestadores.
enum _PeriodoFornecedor { mes, ano, personalizado }

Widget _fornecedoresAppBarIconButton({
  required IconData icon,
  required String tooltip,
  required VoidCallback? onPressed,
}) {
  final enabled = onPressed != null;
  return Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Material(
      color: enabled
          ? Colors.white.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(11),
      child: IconButton(
        icon: Icon(icon, size: 23),
        color: Colors.white,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
        ),
      ),
    ),
  );
}

/// Relatório de movimentação vinculada a fornecedores/prestadores (despesas e receitas no caixa).
class RelatorioGastosFornecedoresPage extends StatefulWidget {
  final String tenantId;

  const RelatorioGastosFornecedoresPage({super.key, required this.tenantId});

  @override
  State<RelatorioGastosFornecedoresPage> createState() =>
      _RelatorioGastosFornecedoresPageState();
}

class _RelatorioGastosFornecedoresPageState
    extends State<RelatorioGastosFornecedoresPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  _PeriodoFornecedor _periodoMode = _PeriodoFornecedor.mes;
  late int _mes;
  late int _ano;
  DateTime? _customIni;
  DateTime? _customFim;

  bool _loading = true;
  String? _err;
  final Map<String, double> _despesas = {};
  final Map<String, double> _receitas = {};
  double _totalDespesas = 0;
  double _totalReceitas = 0;
  int _amostraDocs = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month;
    _ano = now.year;
    _customIni = DateTime(now.year, now.month, 1);
    _customFim = now;
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  ({DateTime inicio, DateTime fim}) _periodoAtual() {
    switch (_periodoMode) {
      case _PeriodoFornecedor.mes:
        final i = DateTime(_ano, _mes, 1);
        final f = DateTime(_ano, _mes + 1, 0, 23, 59, 59);
        return (inicio: i, fim: f);
      case _PeriodoFornecedor.ano:
        return (
          inicio: DateTime(_ano, 1, 1),
          fim: DateTime(_ano, 12, 31, 23, 59, 59),
        );
      case _PeriodoFornecedor.personalizado:
        final a = _customIni ?? DateTime.now();
        final b = _customFim ?? DateTime.now();
        return (
          inicio: DateTime(a.year, a.month, a.day),
          fim: DateTime(b.year, b.month, b.day, 23, 59, 59),
        );
    }
  }

  bool _dataNoPeriodo(Timestamp? ts) {
    if (ts == null) return false;
    final d = ts.toDate();
    final p = _periodoAtual();
    return !d.isBefore(p.inicio) && !d.isAfter(p.fim);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
      _despesas.clear();
      _receitas.clear();
      _totalDespesas = 0;
      _totalReceitas = 0;
      _amostraDocs = 0;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('finance')
          .orderBy('createdAt', descending: true)
          .limit(4000)
          .get();
      _amostraDocs = snap.docs.length;
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['createdAt'] as Timestamp?;
        if (!_dataNoPeriodo(ts)) continue;
        final fid = (m['fornecedorId'] ?? '').toString().trim();
        if (fid.isEmpty) continue;
        final nome =
            (m['fornecedorNome'] ?? 'Fornecedor / prestador').toString().trim();
        final tipo = (m['type'] ?? '').toString().toLowerCase();
        final valor = (m['amount'] ?? m['valor'] ?? 0);
        final v = valor is num ? valor.toDouble() : 0.0;
        if (tipo == 'saida' || tipo.contains('despesa')) {
          _despesas[nome] = (_despesas[nome] ?? 0) + v;
          _totalDespesas += v;
        } else if (tipo == 'entrada' || tipo.contains('receita')) {
          _receitas[nome] = (_receitas[nome] ?? 0) + v;
          _totalReceitas += v;
        }
      }
    } catch (e) {
      _err = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _tituloPeriodo() {
    final p = _periodoAtual();
    switch (_periodoMode) {
      case _PeriodoFornecedor.mes:
        return DateFormat("MMMM 'de' yyyy", 'pt_BR').format(p.inicio);
      case _PeriodoFornecedor.ano:
        return 'Ano ${p.inicio.year}';
      case _PeriodoFornecedor.personalizado:
        return '${DateFormat('dd/MM/yyyy').format(p.inicio)} - ${DateFormat('dd/MM/yyyy').format(p.fim)}';
    }
  }

  Future<({
    String leftName,
    String rightName,
    Uint8List? leftSig,
    Uint8List? rightSig,
    bool showDigital
  })?> _pickPdfSigners() async {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
        .get();
    final opts = snap.docs
        .map((d) {
          final m = d.data();
          return (
            id: d.id,
            nome: (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
                .toString()
                .trim(),
            cargo: (m['CARGO'] ?? m['FUNCAO'] ?? m['cargo'] ?? '')
                .toString()
                .trim(),
            assinatura:
                (m['assinaturaUrl'] ?? m['assinatura_url'] ?? '').toString().trim(),
          );
        })
        .where((e) => e.nome.isNotEmpty)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    if (!mounted) return null;
    String? leftId;
    String? rightId;
    var showDigital = false;
    return showDialog<
        ({
          String leftName,
          String rightName,
          Uint8List? leftSig,
          Uint8List? rightSig,
          bool showDigital
        })>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Assinaturas do PDF'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: leftId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assinante esquerdo',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('— Não definido —'),
                    ),
                    ...opts.map((e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.cargo.isEmpty ? e.nome : '${e.nome} — ${e.cargo}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) => setDlg(() => leftId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: rightId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assinante direito',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('— Não definido —'),
                    ),
                    ...opts.map((e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(
                            e.cargo.isEmpty ? e.nome : '${e.nome} — ${e.cargo}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) => setDlg(() => rightId = v),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: showDigital,
                  onChanged: (v) => setDlg(() => showDigital = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Carregar assinatura digital'),
                  subtitle:
                      const Text('Desative para assinatura manual no impresso.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                ({String id, String nome, String cargo, String assinatura})?
                    pick(String? id) {
                  if (id == null || id.isEmpty) return null;
                  for (final e in opts) {
                    if (e.id == id) return e;
                  }
                  return null;
                }

                final left = pick(leftId);
                final right = pick(rightId);
                Uint8List? leftSig;
                Uint8List? rightSig;
                if (showDigital) {
                  if (left != null && left.assinatura.isNotEmpty) {
                    leftSig = await ImageHelper.getBytesFromUrlOrNull(
                      sanitizeImageUrl(left.assinatura),
                      timeout: const Duration(seconds: 14),
                    );
                  }
                  if (right != null && right.assinatura.isNotEmpty) {
                    rightSig = await ImageHelper.getBytesFromUrlOrNull(
                      sanitizeImageUrl(right.assinatura),
                      timeout: const Duration(seconds: 14),
                    );
                  }
                }
                if (!ctx.mounted) return;
                Navigator.pop(
                  ctx,
                  (
                    leftName: left?.nome ?? 'Responsável financeiro',
                    rightName: right?.nome ?? 'Responsável pastoral',
                    leftSig: leftSig,
                    rightSig: rightSig,
                    showDigital: showDigital,
                  ),
                );
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final ctx = context;
    try {
      final signerCfg = await _pickPdfSigners();
      if (signerCfg == null) return;
      final branding = await loadReportPdfBranding(widget.tenantId);
      if (!ctx.mounted) return;
      final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      final linhasDesp = _despesas.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final linhasRec = _receitas.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (c) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: PdfSuperPremiumTheme.header(
              'Relatório - Fornecedores e prestadores',
              branding: branding,
              extraLines: [
                'Período: ${_tituloPeriodo()}',
                'Despesas (pagamentos): ${nf.format(_totalDespesas)}',
                'Receitas (créditos/estornos): ${nf.format(_totalReceitas)}',
              ],
            ),
          ),
          footer: (c) => PdfSuperPremiumTheme.footer(c, churchName: branding.churchName),
          build: (c) => [
            pw.Text(
              'Despesas por fornecedor/prestador',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
            pw.SizedBox(height: 6),
            PdfSuperPremiumTheme.fromTextArray(
              headers: const ['Fornecedor / prestador', 'Valor (R\$)'],
              data: linhasDesp
                  .map((e) => [e.key, e.value.toStringAsFixed(2)])
                  .toList(),
              accent: branding.accent,
              columnWidths: const {
                0: pw.FlexColumnWidth(3.6),
                1: pw.FixedColumnWidth(92),
              },
              cellAlignmentsExtra: const {
                1: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Receitas vinculadas (créditos)',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 6),
            PdfSuperPremiumTheme.fromTextArray(
              headers: const ['Fornecedor / prestador', 'Valor (R\$)'],
              data: linhasRec.isEmpty
                  ? [
                      ['-', '0,00'],
                    ]
                  : linhasRec
                      .map((e) => [e.key, e.value.toStringAsFixed(2)])
                      .toList(),
              accent: branding.accent,
              columnWidths: const {
                0: pw.FlexColumnWidth(3.6),
                1: pw.FixedColumnWidth(92),
              },
              cellAlignmentsExtra: const {
                1: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 20),
            PdfSuperPremiumTheme.reportDualSignatureAttestation(
              accent: branding.accent,
              leftTitle: 'Conferência financeira',
              rightTitle: 'Conferência pastoral',
              leftSignerName: signerCfg.leftName,
              rightSignerName: signerCfg.rightName,
              leftSignatureImageBytes: signerCfg.leftSig,
              rightSignatureImageBytes: signerCfg.rightSig,
              showDigitalSignatures: signerCfg.showDigital,
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (!ctx.mounted) return;
      await showPdfActions(ctx,
          bytes: bytes, filename: 'relatorio_fornecedores_prestadores.pdf');
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('Relatório fornecedores e prestadores;${_tituloPeriodo()}');
    buf.writeln('Tipo;Fornecedor;Valor');
    for (final e in _despesas.entries) {
      buf.writeln('Despesa;${_csvCell(e.key)};${e.value.toStringAsFixed(2)}');
    }
    for (final e in _receitas.entries) {
      buf.writeln('Receita;${_csvCell(e.key)};${e.value.toStringAsFixed(2)}');
    }
    final text = buf.toString();
    await Share.share(
      text,
      subject: 'Relatório fornecedores — ${widget.tenantId}',
    );
  }

  String _csvCell(String s) {
    if (s.contains(';') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _pickMesAno() async {
    final y = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ano'),
        content: SizedBox(
          width: 280,
          height: 200,
          child: YearPicker(
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
            selectedDate: DateTime(_ano),
            onChanged: (d) => Navigator.pop(ctx, d.year),
          ),
        ),
      ),
    );
    if (y != null && mounted) {
      setState(() => _ano = y);
      await _load();
    }
  }

  Future<void> _pickMes() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_ano, _mes),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && mounted) {
      setState(() {
        _ano = picked.year;
        _mes = picked.month;
      });
      await _load();
    }
  }

  Future<void> _pickIntervalo() async {
    final ini = await showDatePicker(
      context: context,
      initialDate: _customIni ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12),
      locale: const Locale('pt', 'BR'),
      helpText: 'Data inicial',
    );
    if (ini == null || !mounted) return;
    final fim = await showDatePicker(
      context: context,
      initialDate: _customFim ?? ini,
      firstDate: ini,
      lastDate: DateTime(2035, 12),
      locale: const Locale('pt', 'BR'),
      helpText: 'Data final',
    );
    if (fim != null && mounted) {
      setState(() {
        _customIni = ini;
        _customFim = fim;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Fornecedores e prestadores',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        ),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
        actions: [
          _fornecedoresAppBarIconButton(
            icon: Icons.picture_as_pdf_rounded,
            tooltip: 'Exportar PDF',
            onPressed: _loading || (_despesas.isEmpty && _receitas.isEmpty)
                ? null
                : _exportPdf,
          ),
          _fornecedoresAppBarIconButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Exportar CSV (texto)',
            onPressed: _loading || (_despesas.isEmpty && _receitas.isEmpty)
                ? null
                : _exportCsv,
          ),
          _fornecedoresAppBarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Atualizar',
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
          indicatorColor: ThemeCleanPremium.navSidebarAccent,
          indicatorWeight: 3.5,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Despesas', icon: Icon(Icons.trending_down_rounded, size: 20)),
            Tab(text: 'Receitas', icon: Icon(Icons.trending_up_rounded, size: 20)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? Center(child: Text(_err!, textAlign: TextAlign.center))
              : Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        ThemeCleanPremium.primary.withValues(alpha: 0.045),
                        ThemeCleanPremium.surfaceVariant,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildFiltroPeriodo(nf),
                      Expanded(
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: [
                            _buildAba(
                              tituloAba: 'Pagamentos a fornecedores/prestadores',
                              mapa: _despesas,
                              total: _totalDespesas,
                              cor: const Color(0xFFDC2626),
                              vazio:
                                  'Nenhuma despesa com fornecedor no período.\nVincule fornecedores nos lançamentos do Financeiro.',
                            ),
                            _buildAba(
                              tituloAba: 'Receitas / créditos vinculados',
                              mapa: _receitas,
                              total: _totalReceitas,
                              cor: const Color(0xFF2563EB),
                              vazio:
                                  'Nenhuma receita com fornecedor no período.\nUse receita com fornecedor para estornos ou devoluções.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFiltroPeriodo(NumberFormat nf) {
    final segStyle = SegmentedButton.styleFrom(
      selectedBackgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.16),
      selectedForegroundColor: ThemeCleanPremium.primary,
      foregroundColor: ThemeCleanPremium.onSurface,
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_PeriodoFornecedor>(
              style: segStyle,
              segments: const [
                ButtonSegment(
                  value: _PeriodoFornecedor.mes,
                  label: Text('Mês'),
                  icon: Icon(Icons.calendar_month_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _PeriodoFornecedor.ano,
                  label: Text('Ano'),
                  icon: Icon(Icons.date_range_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _PeriodoFornecedor.personalizado,
                  label: Text('Período'),
                  icon: Icon(Icons.edit_calendar_rounded, size: 18),
                ),
              ],
              selected: {_periodoMode},
              onSelectionChanged: (s) async {
                setState(() => _periodoMode = s.first);
                await _load();
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _tituloPeriodo(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (_periodoMode == _PeriodoFornecedor.mes)
                  TextButton.icon(
                    onPressed: _pickMes,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: const Text('Escolher mês'),
                    style: TextButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (_periodoMode == _PeriodoFornecedor.ano)
                  TextButton.icon(
                    onPressed: _pickMesAno,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: const Text('Escolher ano'),
                    style: TextButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (_periodoMode == _PeriodoFornecedor.personalizado)
                  TextButton.icon(
                    onPressed: _pickIntervalo,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: const Text('Datas'),
                    style: TextButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.insights_rounded,
                    size: 20,
                    color: ThemeCleanPremium.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Totais no período: despesas ${nf.format(_totalDespesas)} | '
                      'receitas ${nf.format(_totalReceitas)} | '
                      'líquido ${nf.format(_totalReceitas - _totalDespesas)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (kDebugMode || _amostraDocs >= 4000)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _amostraDocs >= 4000
                      ? 'Atenção: limite de 4000 lançamentos recentes na análise. Ajuste o período ou use o relatório financeiro completo.'
                      : 'Amostra: $_amostraDocs lançamentos lidos.',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAba({
    required String tituloAba,
    required Map<String, double> mapa,
    required double total,
    required Color cor,
    required String vazio,
  }) {
    if (mapa.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cor.withValues(alpha: 0.2),
                      cor.withValues(alpha: 0.06),
                    ],
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: cor.withValues(alpha: 0.25)),
                ),
                child: Icon(Icons.pie_chart_outline_rounded, size: 48, color: cor),
              ),
              const SizedBox(height: 18),
              Text(
                vazio,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: ThemeCleanPremium.pagePadding(context),
        children: [
          Text(
            tituloAba,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.2,
              color: cor,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.cardBackground,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFE8EEF4)),
            ),
            child: SizedBox(
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2.5,
                      centerSpaceRadius: 64,
                      centerSpaceColor: ThemeCleanPremium.surfaceVariant,
                      sections: _buildSections(mapa, total),
                    ),
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          nf.format(total),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cor,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _legendItems(mapa, total),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Detalhamento',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: Colors.grey.shade900,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...() {
            final sorted = mapa.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            return sorted.map((e) {
              final pct = total > 0 ? (e.value / total * 100) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.cardBackground,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(color: const Color(0xFFE8EEF4)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${pct.toStringAsFixed(1)}% do total desta aba',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        nf.format(e.value),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: cor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            });
          }(),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections(
    Map<String, double> mapa,
    double total,
  ) {
    final entries = mapa.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF7C3AED),
      const Color(0xFF059669),
      const Color(0xFFEA580C),
      const Color(0xFFDC2626),
      const Color(0xFF0891B2),
      const Color(0xFFCA8A04),
      const Color(0xFFBE185D),
    ];
    final list = <PieChartSectionData>[];
    var i = 0;
    final multiSlice = entries.length > 1;
    for (final e in entries.take(10)) {
      final pct = total > 0 ? (e.value / total * 100) : 0.0;
      final showPct = multiSlice && pct >= 5;
      list.add(
        PieChartSectionData(
          color: colors[i % colors.length],
          value: e.value,
          title: showPct ? '${pct.toStringAsFixed(0)}%' : '',
          showTitle: showPct,
          radius: 58,
          borderSide: const BorderSide(color: Colors.white, width: 2.5),
          titleStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      );
      i++;
    }
    return list;
  }

  List<Widget> _legendItems(Map<String, double> mapa, double total) {
    final entries = mapa.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF7C3AED),
      const Color(0xFF059669),
      const Color(0xFFEA580C),
      const Color(0xFFDC2626),
      const Color(0xFF0891B2),
      const Color(0xFFCA8A04),
      const Color(0xFFBE185D),
    ];
    var i = 0;
    return entries.take(10).map((e) {
      final c = colors[i % colors.length];
      i++;
      final pct = total > 0 ? (e.value / total * 100) : 0.0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: 0.45),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                '${e.key} (${pct.toStringAsFixed(0)}%)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
