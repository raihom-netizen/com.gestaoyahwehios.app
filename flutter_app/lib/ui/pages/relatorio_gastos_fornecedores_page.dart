import 'dart:async';

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_reports_engine_fetcher.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

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
  bool _showingStaleCache = false;
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

  bool _dataNoPeriodo(Map<String, dynamic> m) {
    final dt = financeLancamentoDate(m);
    if (dt == null) return false;
    final p = _periodoAtual();
    final inicioDay = DateTime(p.inicio.year, p.inicio.month, p.inicio.day);
    final fimEnd = DateTime(p.fim.year, p.fim.month, p.fim.day, 23, 59, 59, 999);
    return !dt.isBefore(inicioDay) && !dt.isAfter(fimEnd);
  }

  Future<void> _load() async {
    final hadLocal = _despesas.isNotEmpty || _receitas.isNotEmpty;
    setState(() {
      _loading = !hadLocal;
      if (!hadLocal) {
        _err = null;
        _despesas.clear();
        _receitas.clear();
        _totalDespesas = 0;
        _totalReceitas = 0;
        _amostraDocs = 0;
      }
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final p = _periodoAtual();
      final rows = await YahwehReportsEngineFetcher.fetchFinanceRowsForPeriod(
        churchIdHint: widget.tenantId,
        inicio: p.inicio,
        fim: p.fim,
        limit: YahwehReportsEngineFetcher.kFinanceReportLimit,
      ).timeout(PanelResilientLoad.queryCap);
      final nextDespesas = <String, double>{};
      final nextReceitas = <String, double>{};
      var totalDespesas = 0.0;
      var totalReceitas = 0.0;
      _amostraDocs = rows.length;
      for (final m in rows) {
        final fid = (m['fornecedorId'] ?? '').toString().trim();
        if (fid.isEmpty) continue;
        final nome =
            (m['fornecedorNome'] ?? 'Fornecedor / prestador').toString().trim();
        final tipo = (m['tipo'] ?? '').toString().toLowerCase();
        final v = financeParseValorBr(m['valor'] ?? m['amount']);
        if (tipo == 'saida' || tipo.contains('despesa')) {
          nextDespesas[nome] = (nextDespesas[nome] ?? 0) + v;
          totalDespesas += v;
        } else if (tipo == 'entrada' || tipo.contains('receita')) {
          nextReceitas[nome] = (nextReceitas[nome] ?? 0) + v;
          totalReceitas += v;
        }
      }
      if (mounted) {
        setState(() {
          _despesas
            ..clear()
            ..addAll(nextDespesas);
          _receitas
            ..clear()
            ..addAll(nextReceitas);
          _totalDespesas = totalDespesas;
          _totalReceitas = totalReceitas;
          _err = null;
          _showingStaleCache = false;
        });
      }
    } catch (e) {
      final ui = PanelResilientLoad.afterError(
        hadLocalData: hadLocal,
        error: e,
      );
      if (mounted) {
        setState(() {
          _err = ui.loadError;
          _showingStaleCache = ui.showingStaleCache;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    bool showDigital,
    PdfDigitalStampInput? leftDigitalStamp,
    PdfDigitalStampInput? rightDigitalStamp,
  })?> _pickPdfSigners() async {
    final op = ChurchRepository.churchId(widget.tenantId.trim());
    List<Map<String, dynamic>> raw = const [];
    try {
      final dir = await MembersDirectorySnapshotService.readOnce(op);
      if (dir.hasEntries) {
        raw = dir.entries
            .map((e) => {...e.toMemberDataMap(), 'id': e.memberDocId})
            .toList();
      } else {
        final snap = await ChurchTenantResilientReads.membrosRecent(op, limit: 800);
        raw = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      }
    } catch (_) {}
    final opts = raw
        .map((m) {
          return (
            id: (m['id'] ?? '').toString(),
            nome: (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
                .toString()
                .trim(),
            cargo: (m['CARGO'] ?? m['FUNCAO'] ?? m['cargo'] ?? '')
                .toString()
                .trim(),
            cpf: (m['CPF'] ?? m['cpf'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\D'), ''),
            assinatura:
                (m['assinaturaUrl'] ?? m['assinatura_url'] ?? '').toString().trim(),
          );
        })
        .where((e) => e.nome.isNotEmpty && e.id.isNotEmpty)
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
          bool showDigital,
          PdfDigitalStampInput? leftDigitalStamp,
          PdfDigitalStampInput? rightDigitalStamp,
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
                  title: const Text('Selo de assinatura digital'),
                  subtitle: const Text(
                    'Certificado digital compacto (igreja + assinante).',
                  ),
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
                ({String id, String nome, String cargo, String cpf, String assinatura})?
                    pick(String? id) {
                  if (id == null || id.isEmpty) return null;
                  for (final e in opts) {
                    if (e.id == id) return e;
                  }
                  return null;
                }

                final left = pick(leftId);
                final right = pick(rightId);
                Map<String, dynamic> churchData = {};
                try {
                  churchData =
                      (await ChurchRepository.churchDoc(op).get()).data() ?? {};
                } catch (_) {}
                final churchName = churchTaxIdChurchNameFromMap(churchData);

                PdfDigitalStampInput? leftStamp;
                PdfDigitalStampInput? rightStamp;
                if (showDigital) {
                  if (left != null) {
                    leftStamp = PdfDigitalStampInput.now(
                      signerName: left.nome,
                      signerCpfDigits:
                          left.cpf.length == 11 ? left.cpf : null,
                      churchName: churchName,
                      churchData: churchData,
                    );
                  }
                  if (right != null) {
                    rightStamp = PdfDigitalStampInput.now(
                      signerName: right.nome,
                      signerCpfDigits:
                          right.cpf.length == 11 ? right.cpf : null,
                      churchName: churchName,
                      churchData: churchData,
                    );
                  }
                }
                if (!ctx.mounted) return;
                Navigator.pop(
                  ctx,
                  (
                    leftName: left?.nome ?? 'Responsável financeiro',
                    rightName: right?.nome ?? 'Responsável pastoral',
                    leftSig: null,
                    rightSig: null,
                    showDigital: showDigital,
                    leftDigitalStamp: leftStamp,
                    rightDigitalStamp: rightStamp,
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
              leftDigitalStamp: signerCfg.leftDigitalStamp,
              rightDigitalStamp: signerCfg.rightDigitalStamp,
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
      body: _loading && _despesas.isEmpty && _receitas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _err != null && _despesas.isEmpty && _receitas.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: ChurchPanelResilientLoadBanner(
                    hasLocalData: false,
                    isSyncing: false,
                    errorTitle:
                        'Não foi possível carregar o relatório de fornecedores',
                    error: _err,
                    onRetry: _load,
                  ),
                )
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: ChurchPanelResilientLoadBanner(
                          hasLocalData:
                              _despesas.isNotEmpty || _receitas.isNotEmpty,
                          isSyncing: _loading,
                          showStaleCache:
                              _showingStaleCache && !_loading,
                          errorTitle:
                              'Não foi possível carregar o relatório de fornecedores',
                          error: _err,
                          onRetry: _load,
                        ),
                      ),
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
