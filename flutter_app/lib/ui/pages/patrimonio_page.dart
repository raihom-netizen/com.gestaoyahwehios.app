import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/foto_patrimonio_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        imageUrlFromMap,
        imageUrlsListFromMap,
        isValidImageUrl,
        ResilientNetworkImage,
        sanitizeImageUrl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Extrai URLs de fotos do patrimônio — lista + campos simples + strings dinâmicas do Firestore.
/// Unifica duplicatas e normaliza URLs do Storage (incl. host *.firebasestorage.app).
List<String> _fotoUrlsFromData(Map<String, dynamic> m) {
  final out = <String>[];
  bool looksLikeStoragePath(String s) {
    if (s.isEmpty) return false;
    final low = s.toLowerCase();
    if (low.startsWith('http://') || low.startsWith('https://')) return false;
    if (low.startsWith('data:')) return false;
    return s.contains('/') || low.startsWith('gs://');
  }

  void push(String raw) {
    final s = sanitizeImageUrl(raw);
    if (!isValidImageUrl(s) && !looksLikeStoragePath(s)) return;
    if (!out.contains(s)) out.add(s);
  }

  // Mesma prioridade de outros módulos (logo, membros): nenhum campo legado fica de fora.
  final primary = imageUrlFromMap(m);
  if (primary.isNotEmpty) push(primary);

  for (final u in imageUrlsListFromMap(m)) {
    push(u);
  }
  for (final k in [
    'imageUrl',
    'defaultImageUrl',
    'fotoUrl',
    'photoUrl',
    'url',
    'downloadURL',
    'downloadUrl',
    'storagePath',
    'fullPath',
    'fotoPath',
    'imagePath',
    'path',
    'foto_storage_path',
  ]) {
    push(m[k]?.toString() ?? '');
  }
  final raw = m['fotoUrls'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        for (final k in [
          'url',
          'imageUrl',
          'downloadURL',
          'downloadUrl',
          'fotoUrl',
          'photoUrl',
          'fullPath',
          'storagePath',
          'path',
        ]) {
          final v = e[k];
          if (v != null) push(v.toString());
        }
      } else {
        push(e is String ? e : e?.toString() ?? '');
      }
    }
  }
  for (final k in ['imageStoragePath', 'fotoPath', 'storagePath']) {
    push(m[k]?.toString() ?? '');
  }
  final storagePaths = m['fotoStoragePaths'];
  if (storagePaths is List) {
    for (final e in storagePaths) {
      push(e?.toString() ?? '');
    }
  }
  for (final k in ['imageVariants', 'fotoVariants']) {
    final variants = m[k];
    if (variants is Map) {
      for (final v in variants.values) {
        if (v is Map) {
          push((v['url'] ?? v['downloadUrl'] ?? v['storagePath'] ?? '')
              .toString());
        } else {
          push(v?.toString() ?? '');
        }
      }
    }
  }
  return out;
}

/// Carrossel e miniaturas: [fotoUrls] ordenados + fallback (imageUrl…), **sem** duplicar
/// slides por lista de paths maior que URLs reais (ex.: 1 foto + 5 paths → 1 slide).
/// Alinha [fotoStoragePaths] ao comprimento das URLs quando possível.
({List<String> urls, List<String?> paths}) _patrimonioCarouselSlotsFromData(
    Map<String, dynamic> m) {
  bool looksLikeStoragePath(String s) {
    if (s.isEmpty) return false;
    final low = s.toLowerCase();
    if (low.startsWith('http://') || low.startsWith('https://')) return false;
    if (low.startsWith('data:')) return false;
    return s.contains('/') || low.startsWith('gs://');
  }

  void pushUrl(List<String> out, String raw) {
    final s = sanitizeImageUrl(raw);
    if (!isValidImageUrl(s) && !looksLikeStoragePath(s)) return;
    if (!out.contains(s)) out.add(s);
  }

  final urls = <String>[];
  final rawList = m['fotoUrls'];
  if (rawList is List) {
    for (final e in rawList) {
      if (e is Map) {
        for (final k in [
          'url',
          'imageUrl',
          'downloadURL',
          'downloadUrl',
          'fotoUrl',
          'photoUrl',
          'fullPath',
          'storagePath',
          'path',
        ]) {
          final v = e[k];
          if (v != null) pushUrl(urls, v.toString());
        }
      } else {
        pushUrl(urls, e is String ? e : e?.toString() ?? '');
      }
    }
  }

  if (urls.isEmpty) {
    final fb = sanitizeImageUrl(
      (m['defaultImageUrl'] ??
              m['imageUrl'] ??
              m['fotoUrl'] ??
              m['photoUrl'] ??
              imageUrlFromMap(m))
          .toString(),
    );
    if (isValidImageUrl(fb) || looksLikeStoragePath(fb)) {
      if (fb.isNotEmpty) urls.add(fb);
    }
  }

  /// Se a lista gravada veio vazia/inválida mas existe mídia nos mesmos campos do formulário/PDF.
  if (urls.isEmpty) {
    final flat = <String>[];
    void pushFlat(String raw) {
      final s = sanitizeImageUrl(raw);
      if (!isValidImageUrl(s) && !looksLikeStoragePath(s)) return;
      if (!flat.contains(s)) flat.add(s);
    }

    final primary = imageUrlFromMap(m);
    if (primary.isNotEmpty) pushFlat(primary);
    for (final k in [
      'imageUrl',
      'defaultImageUrl',
      'fotoUrl',
      'photoUrl',
      'url',
      'downloadURL',
      'downloadUrl',
    ]) {
      pushFlat(m[k]?.toString() ?? '');
    }
    if (rawList is List) {
      for (final e in rawList) {
        if (e is String || e is num) pushFlat(e.toString());
      }
    }
    urls.addAll(flat);
  }

  final pathRaw = m['fotoStoragePaths'];
  var paths = <String?>[];
  if (pathRaw is List) {
    for (final e in pathRaw) {
      final t = e?.toString().trim();
      paths.add(t != null && t.isNotEmpty ? t : null);
    }
  }

  if (urls.isEmpty && paths.isEmpty) {
    return (urls: <String>[], paths: <String?>[]);
  }

  /// Não criar 5 páginas só porque [fotoStoragePaths] tem 5 entradas e só há 1 URL válida.
  if (urls.isNotEmpty) {
    if (paths.length > urls.length) {
      paths = paths.sublist(0, urls.length);
    }
  }

  final maxN = urls.isNotEmpty ? urls.length : paths.length;
  if (maxN == 0) {
    return (urls: <String>[], paths: <String?>[]);
  }

  final outUrls = <String>[];
  final outPaths = <String?>[];
  for (var i = 0; i < maxN; i++) {
    final u = i < urls.length ? urls[i] : '';
    final p = i < paths.length ? paths[i] : null;
    final pu = sanitizeImageUrl(u);
    final hasUrl = isValidImageUrl(pu) || looksLikeStoragePath(pu);
    final hasPath = p != null && p.isNotEmpty;
    if (!hasUrl && !hasPath) continue;
    outUrls.add(hasUrl ? pu : '');
    outPaths.add(hasPath ? p : null);
  }
  return (urls: outUrls, paths: outPaths);
}

/// Miniatura na lista/galeria: prefere o primeiro slot com URL http(s) (evita `getDownloadURL` só com path).
({String url, String? path}) _patrimonioThumbFromSlots(
  List<String> urls,
  List<String?> paths,
) {
  if (urls.isEmpty) return (url: '', path: null);
  for (var i = 0; i < urls.length; i++) {
    final pu = sanitizeImageUrl(urls[i]);
    if (pu.isEmpty) continue;
    if (isValidImageUrl(pu) &&
        (pu.startsWith('https://') || pu.startsWith('http://'))) {
      final p = i < paths.length ? paths[i] : null;
      return (url: pu, path: p);
    }
  }
  final u0 = sanitizeImageUrl(urls.first);
  final p0 = paths.isNotEmpty ? paths.first : null;
  return (url: u0, path: p0);
}

DateTime? _dataAquisicaoFromPatrimonioMap(Map<String, dynamic> m) {
  final da = m['dataAquisicao'];
  if (da is Timestamp) return da.toDate();
  if (da is DateTime) return da;
  return null;
}

/// PDF Super Premium — patrimônio (tabela completa + linhas opcionais de filtros).
Future<void> _exportPatrimonioRelatorioPdf({
  required BuildContext context,
  required String tenantId,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required String Function(String?) statusLabel,
  required String Function(dynamic) fmtMoney,
  List<String> filterSummaryLines = const [],
  String filename = 'patrimonio_relatorio.pdf',
}) async {
  final branding = await loadReportPdfBranding(tenantId);
  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  double valorTotal = 0;
  int emManut = 0;
  int precisaReparo = 0;
  for (final d in docs) {
    final v = d.data()['valor'];
    if (v is num) valorTotal += v.toDouble();
    final st = (d.data()['status'] ?? '').toString();
    if (st == 'em_manutencao') emManut++;
    if (st == 'precisa_reparo') precisaReparo++;
  }
  final extraPat = <String>[
    ...filterSummaryLines,
    if (filterSummaryLines.isNotEmpty) '---',
    'Total de bens (filtro): ${docs.length}',
    'Em manutenção: $emManut',
    'Precisa de reparo: $precisaReparo',
    'Valor total: ${fmtMoney(valorTotal)}',
  ];
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: PdfSuperPremiumTheme.header(
          'Relatório de Patrimônio',
          branding: branding,
          extraLines: extraPat,
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: branding.churchName,
      ),
      build: (ctx) => [
        PdfSuperPremiumTheme.fromTextArray(
          headers: const [
            'Nome',
            'Categoria',
            'Status',
            'Valor',
            'Localização',
            'Responsável'
          ],
          data: docs.map((d) {
            final m = d.data();
            return [
              (m['nome'] ?? '').toString(),
              (m['categoria'] ?? '').toString(),
              statusLabel((m['status'] ?? '').toString()),
              fmtMoney(m['valor']),
              (m['localizacao'] ?? '').toString(),
              (m['responsavel'] ?? '').toString(),
            ];
          }).toList(),
          accent: branding.accent,
          columnWidths: PdfSuperPremiumTheme.columnWidthsPatrimonioListaSimples,
        ),
      ],
    ),
  );
  final bytes = Uint8List.fromList(await pdf.save());
  if (context.mounted) {
    await showPdfActions(context, bytes: bytes, filename: filename);
  }
}

/// PDF ultra premium — sessão de inventário (bens conferidos + assinatura pastoral).
Future<void> _exportPatrimonioInventarioSessaoPdf({
  required BuildContext context,
  required String tenantId,
  required Map<String, dynamic> data,
  required String Function(String?) statusLabel,
}) async {
  final branding = await loadReportPdfBranding(tenantId);
  final pdf = await PdfSuperPremiumTheme.newPdfDocument();
  final titulo = (data['titulo'] ?? 'Inventário').toString();
  final por = (data['criadoPorNome'] ?? '').toString();
  final ts = data['finalizadoEm'];
  var dtStr = '';
  if (ts is Timestamp) {
    dtStr = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(ts.toDate());
  }
  final total = data['totalBens'];
  final conf = data['conferidos'];
  final pend = data['pendentes'];
  final pct = data['percentualConferido'];
  final extraPat = <String>[
    'Documento: $titulo',
    'Sessão finalizada em: $dtStr',
    'Responsável pela conferência: $por',
    'Conferidos: $conf / $total · Pendentes: $pend · Percentual: ${pct is num ? pct.toStringAsFixed(1) : ''}%',
  ];
  final rawItens = data['itens'];
  final rows = <List<String>>[];
  if (rawItens is List) {
    for (final e in rawItens) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(
            e.map((k, v) => MapEntry(k.toString(), v)));
        rows.add([
          (m['nome'] ?? '').toString(),
          (m['categoria'] ?? '').toString(),
          (m['conferidoNestaSessao'] == true) ? 'Sim' : 'Não',
          (m['localizacao'] ?? '').toString(),
          statusLabel((m['status'] ?? '').toString()),
        ]);
      }
    }
  }
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: PdfSuperPremiumTheme.pageMargin,
      header: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: PdfSuperPremiumTheme.header(
          'Relatório de inventário (sessão)',
          branding: branding,
          extraLines: extraPat,
        ),
      ),
      footer: (ctx) => PdfSuperPremiumTheme.footer(
        ctx,
        churchName: branding.churchName,
      ),
      build: (ctx) => [
        if (rows.isNotEmpty)
          PdfSuperPremiumTheme.fromTextArray(
            headers: const [
              'Nome',
              'Categoria',
              'Conf. nesta sessão',
              'Localização',
              'Status',
            ],
            data: rows,
            accent: branding.accent,
            columnWidths: {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(1.15),
              2: const pw.FlexColumnWidth(1.35),
              3: const pw.FlexColumnWidth(1.85),
              4: const pw.FlexColumnWidth(1.25),
            },
          )
        else
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Este registo foi criado antes do relatório detalhado por bem. '
              'Mostram-se apenas os totais no cabeçalho.',
              style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
            ),
          ),
        pw.SizedBox(height: 28),
        pw.Text(
          'Validação pastoral',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: branding.accent,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Assinatura do pastor responsável',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 36),
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.8)),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Nome legível e carimbo (opcional)',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Data: _______________',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    ),
  );
  final bytes = Uint8List.fromList(await pdf.save());
  final safeName =
      titulo.replaceAll(RegExp(r'[^\w\-\s]'), '_').trim().replaceAll(' ', '_');
  if (context.mounted) {
    await showPdfActions(
      context,
      bytes: bytes,
      filename:
          'inventario_sessao_${safeName.isEmpty ? 'relatorio' : safeName}.pdf',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PatrimonioPage — Módulo de Gestão de Patrimônio (Bens · Dashboard · Relatórios · Inventário)
// ═══════════════════════════════════════════════════════════════════════════════

/// Abas do cabeçalho — alto contraste sobre fundo primário (segmentos tipo “pill”).
class PatrimonioModuleTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;

  const PatrimonioModuleTabBar({super.key, required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ChurchPanelPillTabBar(
      controller: controller,
      tabs: const [
        Tab(text: 'Bens'),
        Tab(text: 'Dashboard'),
        Tab(text: 'Relatórios'),
        Tab(text: 'Inventário'),
      ],
    );
  }
}

class PatrimonioPage extends StatefulWidget {
  final String tenantId;
  final String role;

  /// Gestor liberou patrimônio para este membro (role membro).
  final bool? podeVerPatrimonio;
  final List<String>? permissions;

  /// Pré-preenche a busca do inventário (ex.: busca global).
  final String? initialSearchQuery;

  /// Dentro de [IgrejaCleanShell]: evita [SafeArea] superior extra entre o cartão do módulo e as abas.
  final bool embeddedInShell;

  const PatrimonioPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.podeVerPatrimonio,
    this.permissions,
    this.initialSearchQuery,
    this.embeddedInShell = false,
  });

  @override
  State<PatrimonioPage> createState() => _PatrimonioPageState();
}

class _PatrimonioPageState extends State<PatrimonioPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final TextEditingController _searchCtrl;

  String _q = '';
  String _filterCategoria = '';
  String _filterStatus = '';

  bool get _canWrite {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('patrimonio');

  /// Categorias principais do inventário (ERP) + legado para dados antigos.
  /// Extras por igreja: `igrejas/{id}/config/patrimonio` → `categoriasExtras`.
  static const List<String> _categoriasBase = [
    'Som',
    'Móveis',
    'Instrumentos',
    'Imóveis',
    'Veículo',
    'Eletrônico',
    'Equipamento',
    'Outro',
    // Legado (mantém seleção ao editar docs antigos)
    'Móvel',
    'Imóvel',
    'Instrumento Musical',
    'Som e Mídia',
  ];

  /// Base + extras do Firestore, sem duplicar por nome (ignora maiúsculas), em ordem alfabética.
  static List<String> _mergeAndSortCategorias(Iterable<String> base,
      [dynamic categoriasExtras]) {
    final map = <String, String>{};
    for (final b in base) {
      final t = b.trim();
      if (t.isEmpty) continue;
      map[t.toLowerCase()] = t;
    }
    if (categoriasExtras is List) {
      for (final e in categoriasExtras) {
        final s = e.toString().trim();
        if (s.isEmpty) continue;
        final k = s.toLowerCase();
        if (!map.containsKey(k)) map[k] = s;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  static const _statusList = [
    {'key': 'novo', 'label': 'Novo'},
    {'key': 'bom', 'label': 'Bom'},
    {'key': 'precisa_reparo', 'label': 'Precisa de Reparo'},
    {'key': 'em_manutencao', 'label': 'Em manutenção'},
    {'key': 'danificado', 'label': 'Danificado'},
    {'key': 'obsoleto', 'label': 'Obsoleto'},
  ];

  final GlobalKey<_BensTabState> _bensTabKey = GlobalKey<_BensTabState>();
  final GlobalKey<_DashboardTabState> _dashboardTabKey =
      GlobalKey<_DashboardTabState>();
  final GlobalKey<_InventarioTabState> _inventarioTabKey =
      GlobalKey<_InventarioTabState>();

  /// Base + extras (`config/patrimonio`), ordenadas alfabeticamente.
  late List<String> _categoriasEfetivas;

  void _refreshPatrimonioTabs() {
    _bensTabKey.currentState?.refresh();
    _dashboardTabKey.currentState?.refresh();
    _inventarioTabKey.currentState?.refresh();
  }

  @override
  void initState() {
    super.initState();
    _categoriasEfetivas = _mergeAndSortCategorias(_categoriasBase);
    _tabCtrl = TabController(length: 4, vsync: this);
    _searchCtrl = TextEditingController();
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      final s = widget.initialSearchQuery!.trim();
      _searchCtrl.text = s;
      _q = s.toLowerCase();
    }
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    unawaited(_loadCategoriasExtras());
  }

  Future<void> _loadCategoriasExtras() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('config')
          .doc('patrimonio')
          .get();
      final extra = snap.data()?['categoriasExtras'];
      if (!mounted) return;
      setState(() {
        _categoriasEfetivas = _mergeAndSortCategorias(_categoriasBase, extra);
      });
    } catch (_) {
      /* mantém lista local */
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static IconData _catIcon(String cat) {
    switch (cat) {
      case 'Som':
      case 'Som e Mídia':
        return Icons.speaker_group_rounded;
      case 'Móveis':
      case 'Móvel':
        return Icons.chair_rounded;
      case 'Instrumentos':
      case 'Instrumento Musical':
        return Icons.piano_rounded;
      case 'Imóveis':
      case 'Imóvel':
        return Icons.apartment_rounded;
      case 'Equipamento':
        return Icons.build_rounded;
      case 'Veículo':
        return Icons.directions_car_rounded;
      case 'Eletrônico':
        return Icons.devices_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }

  static Color _catColor(String cat) {
    switch (cat) {
      case 'Som':
      case 'Som e Mídia':
        return const Color(0xFFEA580C);
      case 'Móveis':
      case 'Móvel':
        return const Color(0xFFD97706);
      case 'Instrumentos':
      case 'Instrumento Musical':
        return const Color(0xFFDB2777);
      case 'Imóveis':
      case 'Imóvel':
        return const Color(0xFF16A34A);
      case 'Equipamento':
        return const Color(0xFF2563EB);
      case 'Veículo':
        return const Color(0xFF7C3AED);
      case 'Eletrônico':
        return const Color(0xFF0891B2);
      default:
        return Colors.grey.shade600;
    }
  }

  String _statusLabel(String? key) {
    if (key == null || key.isEmpty) return '—';
    for (final s in _statusList) {
      if (s['key'] == key) return s['label']!;
    }
    return key;
  }

  Color _statusColor(String? key) {
    switch (key) {
      case 'novo':
        return const Color(0xFF0891B2);
      case 'bom':
        return ThemeCleanPremium.success;
      case 'precisa_reparo':
        return Colors.deepOrange.shade700;
      case 'em_manutencao':
        return Colors.orange.shade700;
      case 'danificado':
        return ThemeCleanPremium.error;
      case 'obsoleto':
        return Colors.grey.shade600;
      default:
        return Colors.grey;
    }
  }

  String _fmtMoney(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null) return '—';
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    DateTime? d;
    if (v is Timestamp) d = v.toDate();
    if (v is DateTime) d = v;
    if (d == null) return v.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  // ─── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (!_canWrite) return;
    await _loadCategoriasExtras();
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PatrimonioFormPage(
          col: _col,
          doc: doc,
          categorias: List<String>.from(_categoriasEfetivas),
          onCategoriasChanged: _loadCategoriasExtras,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
      unawaited(_loadCategoriasExtras());
      _refreshPatrimonioTabs();
    }
  }

  Future<void> _excluir(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_canWrite) return;
    final nome = (doc.data()?['nome'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_forever_rounded,
                color: ThemeCleanPremium.error, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Excluir patrimônio'),
        ]),
        content:
            Text('Deseja excluir "$nome"?\nEsta ação não poderá ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final data = doc.data();
      if (data != null) {
        final urls = _fotoUrlsFromData(data);
        urls.addAll(FirebaseStorageCleanupService.urlsFromVariantMap(
            data['imageVariants']));
        urls.addAll(FirebaseStorageCleanupService.urlsFromVariantMap(
            data['fotoVariants']));
        await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(urls);
      }
      await _col.doc(doc.id).delete();
      if (!mounted) return;
      _refreshPatrimonioTabs();
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Patrimônio excluído.'));
    }
  }

  // ─── QR Code ───────────────────────────────────────────────────────────────

  void _showQrCode(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final serie = (m['numeroSerie'] ?? doc.id).toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_rounded,
                color: ThemeCleanPremium.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(nome,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: QrImageView(
                  data: 'PATRIMONIO|${widget.tenantId}|${doc.id}|$serie',
                  version: QrVersions.auto,
                  size: 200,
                  gapless: true,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Nº Série: $serie',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  // ─── Transferir ────────────────────────────────────────────────────────────

  Future<void> _exportPdfFromPage(BuildContext context) async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snap = await _col.orderBy('nome').get();
      final docs = snap.docs;
      if (docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum item de patrimônio para exportar.')));
        }
        return;
      }
      if (!mounted) return;
      await _exportPatrimonioRelatorioPdf(
        context: context,
        tenantId: widget.tenantId,
        docs: docs,
        statusLabel: _statusLabel,
        fmtMoney: _fmtMoney,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao gerar PDF. Tente novamente.'),
            action: SnackBarAction(
                label: 'Tentar de novo',
                onPressed: () => _exportPdfFromPage(context)),
          ),
        );
      }
    }
  }

  void _showTransferir(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!_canWrite) return;
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final respCtrl =
        TextEditingController(text: (m['responsavel'] ?? '').toString());
    final localCtrl =
        TextEditingController(text: (m['localizacao'] ?? '').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primaryLight.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                color: ThemeCleanPremium.primaryLight, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transferir bem'),
                Text(nome,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: respCtrl,
              decoration: const InputDecoration(
                labelText: 'Novo responsável',
                prefixIcon: Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: localCtrl,
              decoration: const InputDecoration(
                labelText: 'Nova localização',
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final antigoResp = (m['responsavel'] ?? '').toString();
              final novoResp = respCtrl.text.trim();
              final novoLocal = localCtrl.text.trim();
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              final userName =
                  FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário';

              await _col.doc(doc.id).update({
                'responsavel': novoResp,
                'localizacao': novoLocal,
                'atualizadoEm': FieldValue.serverTimestamp(),
              });
              await _col.doc(doc.id).collection('transferencias').add({
                'de': antigoResp,
                'para': novoResp,
                'localizacao': novoLocal,
                'data': FieldValue.serverTimestamp(),
                'criadoPorUid': uid,
                'criadoPorNome': userName,
              });

              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  ThemeCleanPremium.successSnackBar(
                      'Bem transferido com sucesso!'),
                );
              }
            },
            child: const Text('Transferir'),
          ),
        ],
      ),
    );
  }

  // ─── Depreciação ─────────────────────────────────────────────────────────

  Widget _buildDepreciacao(Map<String, dynamic> m, Color cor) {
    final valor = (m['valor'] is num) ? (m['valor'] as num).toDouble() : 0.0;
    final vidaUtil =
        (m['vidaUtil'] is num) ? (m['vidaUtil'] as num).toInt() : 0;
    if (valor <= 0 || vidaUtil <= 0) return const SizedBox.shrink();
    DateTime? aquisicao;
    try {
      aquisicao = (m['dataAquisicao'] as Timestamp).toDate();
    } catch (_) {}
    if (aquisicao == null) return const SizedBox.shrink();

    final anosUsados = DateTime.now().difference(aquisicao).inDays / 365.25;
    final depreciacaoAnual = valor / vidaUtil;
    final depreciacaoTotal = (depreciacaoAnual * anosUsados).clamp(0.0, valor);
    final valorAtual = (valor - depreciacaoTotal).clamp(0.0, valor);
    final percentVidaUtil =
        ((vidaUtil - anosUsados) / vidaUtil * 100).clamp(0.0, 100.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16, top: 8),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: cor.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.trending_down_rounded, size: 16, color: cor),
          const SizedBox(width: 8),
          Text('Depreciação',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: cor)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: Column(children: [
            Text('Valor Atual',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            Text(_fmtMoney(valorAtual),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: cor)),
          ])),
          Container(width: 1, height: 32, color: Colors.grey.shade300),
          Expanded(
              child: Column(children: [
            Text('Vida Útil Restante',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            Text('${percentVidaUtil.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color:
                        percentVidaUtil < 20 ? ThemeCleanPremium.error : cor)),
          ])),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: percentVidaUtil / 100,
              backgroundColor: Colors.grey.shade200,
              color: percentVidaUtil < 20 ? ThemeCleanPremium.error : cor,
              minHeight: 6),
        ),
        const SizedBox(height: 6),
        Text(
            'Depreciação: ${_fmtMoney(depreciacaoTotal)} (${anosUsados.toStringAsFixed(1)} anos de $vidaUtil)',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]),
    );
  }

  // ─── Registrar Manutenção ──────────────────────────────────────────────────

  void _addManutencao(DocumentSnapshot<Map<String, dynamic>> doc) {
    final descCtrl = TextEditingController();
    final custoCtrl = TextEditingController();
    final prestCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Registrar Manutenção',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade700)),
              const SizedBox(height: 16),
              TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Descrição *',
                      prefixIcon: Icon(Icons.description_rounded))),
              const SizedBox(height: 12),
              TextField(
                  controller: custoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrCurrencyInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Custo (R\$)',
                      prefixIcon: Icon(Icons.payments_rounded))),
              const SizedBox(height: 12),
              TextField(
                  controller: prestCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Prestador / Técnico',
                      prefixIcon: Icon(Icons.engineering_rounded))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                  onPressed: () async {
                    if (descCtrl.text.trim().isEmpty) return;
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final userName =
                        FirebaseAuth.instance.currentUser?.displayName ??
                            'Usuário';
                    await doc.reference.collection('manutencoes').add({
                      'descricao': descCtrl.text.trim(),
                      'custo': parseBrCurrencyInput(custoCtrl.text),
                      'prestador': prestCtrl.text.trim(),
                      'data': FieldValue.serverTimestamp(),
                      'criadoPorUid': uid,
                      'criadoPorNome': userName,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          ThemeCleanPremium.successSnackBar(
                              'Manutenção registrada!'));
                  },
                  child: const Text('Salvar'),
                )),
              ]),
            ])),
      ),
    );
  }

  // ─── Detalhe completo: folha inferior (fotos, histórico, editar/excluir) ─

  Widget _patrimonioDetailScrollContent(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    ScrollController? scrollController,
    BuildContext? sheetContext,
    required BuildContext layoutContext,
    bool showDragHandle = true,
  }) {
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final categoria = (m['categoria'] ?? '').toString();
    final status = (m['status'] ?? '').toString();
    final cor = _catColor(categoria);
    final slots = _patrimonioCarouselSlotsFromData(m);
    final fotoUrls = slots.urls;
    final fotoPaths = slots.paths;

    final dprD = MediaQuery.devicePixelRatioOf(layoutContext);
    final sheetW = MediaQuery.sizeOf(layoutContext).width;
    // Decode proporcional ao carrossel (220px altura) — evita decodificar largura total em 4K.
    final memDetailW = (sheetW * dprD).round().clamp(240, 960);
    final memDetailH = (220 * dprD).round().clamp(200, 720);
    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
          ThemeCleanPremium.spaceLg, 8, ThemeCleanPremium.spaceLg, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDragHandle)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
                  // Foto em destaque — SafeNetworkImage + refresh token (web/desktop/mobile)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: fotoUrls.isNotEmpty
                        ? _PatrimonioPhotoCarousel(
                            key: ValueKey('pat_detail_carousel_${doc.id}'),
                            urls: fotoUrls,
                            storagePaths: fotoPaths,
                            cor: cor,
                            categoria: categoria,
                            memCacheWidth: memDetailW,
                            memCacheHeight: memDetailH,
                          )
                        : Container(
                            height: 220,
                            color: cor.withOpacity(0.08),
                            child: Center(
                                child: Icon(_catIcon(categoria),
                                    size: 56, color: cor.withOpacity(0.5))),
                          ),
                  ),
                  // Header — Super Premium
                  Container(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                          ),
                          child:
                              Icon(_catIcon(categoria), color: cor, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nome,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E293B),
                                      letterSpacing: -0.2)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 6, children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: cor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  child: Text(categoria,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: cor)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: _statusColor(status)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm)),
                                  child: Text(_statusLabel(status),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _statusColor(status))),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (m['valor'] != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: cor.withOpacity(0.15)),
                      ),
                      child: Column(
                        children: [
                          Text('Valor do bem',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Text(_fmtMoney(m['valor']),
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: cor)),
                        ],
                      ),
                    ),
                  _DetailItem(
                      icon: Icons.description_outlined,
                      label: 'Descrição',
                      value: (m['descricao'] ?? '').toString()),
                  _DetailItem(
                      icon: Icons.calendar_today_rounded,
                      label: 'Data de aquisição',
                      value: _fmtDate(m['dataAquisicao'])),
                  _DetailItem(
                      icon: Icons.location_on_outlined,
                      label: 'Localização',
                      value: (m['localizacao'] ?? '').toString()),
                  _DetailItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Responsável',
                      value: (m['responsavel'] ?? '').toString()),
                  _DetailItem(
                      icon: Icons.qr_code_rounded,
                      label: 'Número de série',
                      value: (m['numeroSerie'] ?? '').toString()),
                  if (_fmtDate(m['proximaManutencao']).isNotEmpty)
                    _DetailItem(
                        icon: Icons.build_circle_outlined,
                        label: 'Próxima manutenção',
                        value: _fmtDate(m['proximaManutencao'])),
                  _DetailItem(
                      icon: Icons.notes_rounded,
                      label: 'Observações',
                      value: (m['observacoes'] ?? '').toString()),

                  // ── Depreciação ──
                  if (m['valor'] != null &&
                      m['vidaUtil'] != null &&
                      m['dataAquisicao'] != null)
                    _buildDepreciacao(m, cor),

                  // ── Histórico de Manutenções ──
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.build_rounded,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text('Manutenções',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange.shade700)),
                    const Spacer(),
                    if (_canWrite)
                      TextButton.icon(
                        onPressed: () => _addManutencao(doc),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Registrar',
                            style: TextStyle(fontSize: 12)),
                      ),
                  ]),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: doc.reference
                        .collection('manutencoes')
                        .orderBy('data', descending: true)
                        .limit(12)
                        .snapshots(),
                    builder: (context, mSnap) {
                      final mDocs = mSnap.data?.docs ?? [];
                      if (mDocs.isEmpty)
                        return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Nenhuma manutenção registrada.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500)));
                      return Column(
                          children: mDocs.map((md) {
                        final mm = md.data();
                        final desc = (mm['descricao'] ?? '').toString();
                        final custo = mm['custo'];
                        final prest = (mm['prestador'] ?? '').toString();
                        final dt = _fmtDate(mm['data']);
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.15))),
                          child: Row(children: [
                            Container(
                                width: 4,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade400,
                                    borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(desc,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12)),
                                  if (prest.isNotEmpty)
                                    Text('Prestador: $prest',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600)),
                                  Row(children: [
                                    if (dt.isNotEmpty)
                                      Text(dt,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500)),
                                    if (custo != null) ...[
                                      const SizedBox(width: 8),
                                      Text(_fmtMoney(custo),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.orange.shade800))
                                    ],
                                  ]),
                                ])),
                          ]),
                        );
                      }).toList());
                    },
                  ),

                  // ── Histórico de Transferências ──
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.swap_horiz_rounded,
                        size: 16, color: const Color(0xFF7C3AED)),
                    const SizedBox(width: 8),
                    const Text('Transferências',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF7C3AED))),
                  ]),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: doc.reference
                        .collection('transferencias')
                        .orderBy('data', descending: true)
                        .limit(5)
                        .snapshots(),
                    builder: (context, tSnap) {
                      final tDocs = tSnap.data?.docs ?? [];
                      if (tDocs.isEmpty)
                        return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Nenhuma transferência registrada.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500)));
                      return Column(
                          children: tDocs.map((td) {
                        final tm = td.data();
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF7C3AED)
                                      .withOpacity(0.15))),
                          child: Row(children: [
                            const Icon(Icons.arrow_forward_rounded,
                                size: 16, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: RichText(
                                    text: TextSpan(
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87),
                                        children: [
                                  TextSpan(
                                      text: (tm['de'] ?? '?').toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const TextSpan(text: ' → '),
                                  TextSpan(
                                      text: (tm['para'] ?? '?').toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ]))),
                            Text(_fmtDate(tm['data']),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade500)),
                          ]),
                        );
                      }).toList());
                    },
                  ),

                  const SizedBox(height: 24),
                  if (_canWrite)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (sheetContext != null) {
                                Navigator.pop(sheetContext);
                              }
                              _openForm(doc: doc);
                            },
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Editar'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (sheetContext != null) {
                                Navigator.pop(sheetContext);
                              }
                              _showQrCode(doc);
                            },
                            icon: const Icon(Icons.qr_code_rounded, size: 18),
                            label: const Text('QR Code'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (sheetContext != null) {
                                Navigator.pop(sheetContext);
                              }
                              _excluir(doc);
                            },
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: ThemeCleanPremium.error),
                            label: const Text('Excluir',
                                style:
                                    TextStyle(color: ThemeCleanPremium.error)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: ThemeCleanPremium.error),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
  }

  void _showDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusMd)),
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (ctx, scrollCtrl) => _patrimonioDetailScrollContent(
            doc,
            scrollController: scrollCtrl,
            sheetContext: ctx,
            layoutContext: ctx,
            showDragHandle: true,
          ),
        ),
      ),
    );
  }

  void _onBemTapped(DocumentSnapshot<Map<String, dynamic>> doc) {
    _showDetail(doc);
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final canPop = Navigator.canPop(context);
    final showAppBar = !isMobile || canPop;

    if (!AppPermissions.canViewPatrimonio(
      widget.role,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
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
                        tooltip: 'Voltar',
                      )
                    : null,
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                title: const Text('Patrimônio'),
              ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Acesso restrito ao módulo de patrimônio.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              elevation: 0,
              title: const Text('Patrimônio',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              bottom: PatrimonioModuleTabBar(controller: _tabCtrl),
              actions: [
                IconButton(
                  icon: Icon(Icons.picture_as_pdf_rounded,
                      color: ThemeCleanPremium.primary),
                  onPressed: () => _exportPdfFromPage(context),
                  tooltip: 'Exportar relatório PDF',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: ThemeCleanPremium.primary,
                    elevation: 2,
                    shadowColor: Colors.black26,
                    minimumSize: const Size(
                      ThemeCleanPremium.minTouchTarget,
                      ThemeCleanPremium.minTouchTarget,
                    ),
                  ),
                ),
                if (_canWrite)
                  IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded,
                        color: ThemeCleanPremium.primary),
                    onPressed: () => _openForm(),
                    tooltip: 'Novo bem',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ThemeCleanPremium.primary,
                      elevation: 2,
                      shadowColor: Colors.black26,
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _canWrite
          ? Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg),
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary,
                    ThemeCleanPremium.primaryLight,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  ...ThemeCleanPremium.softUiCardShadow,
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_rounded, size: 24),
                label: const Text('Novo Bem',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                hoverElevation: 0,
                focusElevation: 0,
                highlightElevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg)),
              ),
            )
          : null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          children: [
            if (isMobile)
              Container(
                color: ThemeCleanPremium.primary,
                child: PatrimonioModuleTabBar(controller: _tabCtrl),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _BensTab(
                    key: _bensTabKey,
                    col: _col,
                    q: _q,
                    filterCategoria: _filterCategoria,
                    filterStatus: _filterStatus,
                    canWrite: _canWrite,
                    categorias: _categoriasEfetivas,
                    statusList: _statusList,
                    searchController: _searchCtrl,
                    catIcon: _catIcon,
                    catColor: _catColor,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    fmtMoney: _fmtMoney,
                    fmtDate: _fmtDate,
                    onSearchChanged: (v) =>
                        setState(() => _q = v.trim().toLowerCase()),
                    onCategoriaChanged: (v) =>
                        setState(() => _filterCategoria = v),
                    onStatusChanged: (v) => setState(() => _filterStatus = v),
                    onOpenForm: (doc) => _openForm(doc: doc),
                    onExcluir: _excluir,
                    onShowDetail: _onBemTapped,
                    onShowQrCode: _showQrCode,
                    onTransferir: _showTransferir,
                  ),
                  _DashboardTab(
                    key: _dashboardTabKey,
                    col: _col,
                    categorias: _categoriasEfetivas,
                    statusList: _statusList,
                    catColor: _catColor,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    fmtMoney: _fmtMoney,
                    tenantId: widget.tenantId,
                    onBemSelected: (doc) {
                      if (_canWrite) {
                        _openForm(doc: doc);
                      } else {
                        _onBemTapped(doc);
                      }
                    },
                  ),
                  _RelatoriosPatrimonioTab(
                    col: _col,
                    categorias: _categoriasEfetivas,
                    statusLabel: _statusLabel,
                    fmtMoney: _fmtMoney,
                    fmtDate: _fmtDate,
                    tenantId: widget.tenantId,
                  ),
                  _InventarioTab(
                    key: _inventarioTabKey,
                    col: _col,
                    canWrite: _canWrite,
                    categorias: _categoriasEfetivas,
                    statusList: _statusList,
                    catIcon: _catIcon,
                    catColor: _catColor,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    fmtMoney: _fmtMoney,
                    fmtDate: _fmtDate,
                    tenantId: widget.tenantId,
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

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — _BensTab (lista de bens com busca, filtros e alertas)
// ═══════════════════════════════════════════════════════════════════════════════

class _BensTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final String q;
  final String filterCategoria;
  final String filterStatus;
  final bool canWrite;
  final List<String> categorias;
  final List<Map<String, String>> statusList;
  final TextEditingController searchController;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final String Function(dynamic) fmtMoney;
  final String Function(dynamic) fmtDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoriaChanged;
  final ValueChanged<String> onStatusChanged;
  final void Function(DocumentSnapshot<Map<String, dynamic>>?) onOpenForm;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onExcluir;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onShowDetail;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onShowQrCode;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onTransferir;

  const _BensTab({
    super.key,
    required this.col,
    required this.q,
    required this.filterCategoria,
    required this.filterStatus,
    required this.canWrite,
    required this.categorias,
    required this.statusList,
    required this.searchController,
    required this.catIcon,
    required this.catColor,
    required this.statusLabel,
    required this.statusColor,
    required this.fmtMoney,
    required this.fmtDate,
    required this.onSearchChanged,
    required this.onCategoriaChanged,
    required this.onStatusChanged,
    required this.onOpenForm,
    required this.onExcluir,
    required this.onShowDetail,
    required this.onShowQrCode,
    required this.onTransferir,
  });

  @override
  State<_BensTab> createState() => _BensTabState();
}

class _BensTabState extends State<_BensTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  /// Lista compacta por padrão; galeria em grade se o utilizador alternar.
  bool _galleryView = false;

  /// `nome` — ordem alfabética; `aquisicao` / `conferencia` — mais recente primeiro (sem data por último).
  String _sortMode = 'nome';

  static IconData _statusChipIcon(String key) {
    switch (key) {
      case 'novo':
        return Icons.auto_awesome_rounded;
      case 'bom':
        return Icons.verified_rounded;
      case 'precisa_reparo':
        return Icons.handyman_rounded;
      case 'em_manutencao':
        return Icons.build_circle_rounded;
      case 'danificado':
        return Icons.warning_amber_rounded;
      case 'obsoleto':
        return Icons.inventory_2_outlined;
      default:
        return Icons.label_outline_rounded;
    }
  }

  void _applyPatrimonioSort(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    int nameCmp(QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b) {
      return (a.data()['nome'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b.data()['nome'] ?? '').toString().toLowerCase());
    }

    docs.sort((a, b) {
      switch (_sortMode) {
        case 'aquisicao':
          final da = ts(a.data()['dataAquisicao']);
          final db = ts(b.data()['dataAquisicao']);
          if (da == null && db == null) return nameCmp(a, b);
          if (da == null) return 1;
          if (db == null) return -1;
          final c = db.compareTo(da);
          return c != 0 ? c : nameCmp(a, b);
        case 'conferencia':
          final da = ts(a.data()['ultimaConferencia']);
          final db = ts(b.data()['ultimaConferencia']);
          if (da == null && db == null) return nameCmp(a, b);
          if (da == null) return 1;
          if (db == null) return -1;
          final c = db.compareTo(da);
          return c != 0 ? c : nameCmp(a, b);
        default:
          return nameCmp(a, b);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _future = _loadBensFirstPaint();
  }

  /// Cache local primeiro (lista aparece rápido); depois atualiza do servidor em segundo plano.
  Future<QuerySnapshot<Map<String, dynamic>>> _loadBensFirstPaint() async {
    try {
      final cached = await widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        unawaited(_refreshBensFromServer());
        return cached;
      }
    } catch (_) {}
    return widget.col
        .orderBy('nome')
        .get(const GetOptions(source: Source.server));
  }

  Future<void> _refreshBensFromServer() async {
    try {
      final server = await widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() => _future = Future.value(server));
    } catch (_) {}
  }

  void refresh() {
    setState(() {
      _future = widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));
    });
  }

  /// Busca + filtros como slivers: rolagem única evita scroll “travado” (web / shell / mobile).
  List<Widget> _bensTabHeaderSlivers() {
    final q = widget.q;
    final filterCategoria = widget.filterCategoria;
    final filterStatus = widget.filterStatus;
    final categorias = widget.categorias;
    final statusList = widget.statusList;
    final searchController = widget.searchController;
    final catColor = widget.catColor;
    final statusColor = widget.statusColor;
    final catIcon = widget.catIcon;

    final filterSectionLabelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.85,
      color: ThemeCleanPremium.onSurfaceVariant,
    );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
              ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFE8EEF4)),
            ),
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Nome, código, local, série...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.75),
                    ),
                    suffixIcon: q.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              searchController.clear();
                              widget.onSearchChanged('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusSm),
                      borderSide: const BorderSide(
                          color: ThemeCleanPremium.primaryLight, width: 2),
                    ),
                    filled: true,
                    fillColor: ThemeCleanPremium.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  onChanged: widget.onSearchChanged,
                ),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Visualização',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<bool>(
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                          selectedBackgroundColor: ThemeCleanPremium.primary,
                          selectedForegroundColor: Colors.white,
                          foregroundColor: ThemeCleanPremium.onSurface,
                          backgroundColor: Colors.white,
                          shadowColor:
                              ThemeCleanPremium.primary.withValues(alpha: 0.22),
                          elevation: 1,
                        ),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Lista',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            icon: Icon(Icons.view_list_rounded, size: 18),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Galeria',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            icon: Icon(Icons.grid_view_rounded, size: 18),
                          ),
                        ],
                        selected: {_galleryView},
                        onSelectionChanged: (next) {
                          if (next.isEmpty) return;
                          setState(() => _galleryView = next.first);
                        },
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
          padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
              ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 0),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Color(0xFFF8FAFC),
                ],
              ),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFE8EEF4)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('CATEGORIA', style: filterSectionLabelStyle),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: ListView(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _FilterChipPremium(
                        label: 'Todos',
                        icon: Icons.layers_rounded,
                        selected: filterCategoria.isEmpty,
                        onTap: () => widget.onCategoriaChanged(''),
                      ),
                      ...categorias.map((c) => _FilterChipPremium(
                            label: c,
                            icon: catIcon(c),
                            color: catColor(c),
                            selected: filterCategoria == c,
                            onTap: () => widget.onCategoriaChanged(
                                filterCategoria == c ? '' : c),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('ESTADO OU CONDIÇÃO', style: filterSectionLabelStyle),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: ListView(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _FilterChipPremium(
                        label: 'Todos',
                        icon: Icons.filter_list_rounded,
                        small: true,
                        selected: filterStatus.isEmpty,
                        onTap: () => widget.onStatusChanged(''),
                      ),
                      ...statusList.map((s) => _FilterChipPremium(
                            label: s['label']!,
                            icon: _statusChipIcon(s['key']!),
                            small: true,
                            color: statusColor(s['key']),
                            selected: filterStatus == s['key'],
                            onTap: () => widget.onStatusChanged(
                                filterStatus == s['key'] ? '' : s['key']!),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('ORDENAR POR', style: filterSectionLabelStyle),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _FilterChipPremium(
                        label: 'Nome (A–Z)',
                        icon: Icons.sort_by_alpha_rounded,
                        small: true,
                        color: ThemeCleanPremium.primary,
                        selected: _sortMode == 'nome',
                        onTap: () => setState(() => _sortMode = 'nome'),
                      ),
                      _FilterChipPremium(
                        label: 'Data de aquisição',
                        icon: Icons.calendar_month_rounded,
                        small: true,
                        color: ThemeCleanPremium.primary,
                        selected: _sortMode == 'aquisicao',
                        onTap: () => setState(() => _sortMode = 'aquisicao'),
                      ),
                      _FilterChipPremium(
                        label: 'Última conferência',
                        icon: Icons.fact_check_rounded,
                        small: true,
                        color: ThemeCleanPremium.primary,
                        selected: _sortMode == 'conferencia',
                        onTap: () =>
                            setState(() => _sortMode = 'conferencia'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final filterCategoria = widget.filterCategoria;
    final filterStatus = widget.filterStatus;
    final canWrite = widget.canWrite;
    final catIcon = widget.catIcon;
    final catColor = widget.catColor;
    final statusLabel = widget.statusLabel;
    final statusColor = widget.statusColor;
    final fmtMoney = widget.fmtMoney;
    final onStatusChanged = widget.onStatusChanged;
    final onOpenForm = widget.onOpenForm;
    final onExcluir = widget.onExcluir;
    final onShowDetail = widget.onShowDetail;
    final onShowQrCode = widget.onShowQrCode;
    final onTransferir = widget.onTransferir;

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return CustomScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ..._bensTabHeaderSlivers(),
              SliverFillRemaining(
                hasScrollBody: false,
                child: ChurchPanelErrorBody(
                  title: 'Não foi possível carregar o patrimônio',
                  error: snap.error,
                  onRetry: refresh,
                ),
              ),
            ],
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return CustomScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ..._bensTabHeaderSlivers(),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: ChurchPanelLoadingBody(),
              ),
            ],
          );
        }

        final allDocs = snap.data?.docs ?? [];

        final now = DateTime.now();
        final soon = now.add(const Duration(days: 7));
        int manutCount = 0;
        int reparoCount = 0;
        for (final d in allDocs) {
          final pm = d.data()['proximaManutencao'];
          DateTime? pDate;
          if (pm is Timestamp) pDate = pm.toDate();
          if (pm is DateTime) pDate = pm;
          if (pDate != null && pDate.isBefore(soon)) manutCount++;
          if ((d.data()['status'] ?? '').toString() == 'precisa_reparo') {
            reparoCount++;
          }
        }

        var docs = List.of(allDocs);
        if (q.isNotEmpty) {
          docs = docs.where((d) {
            final m = d.data();
            final codigo =
                '${m['codigoPatrimonio'] ?? m['codigo_patrimonio'] ?? ''}'
                    .toLowerCase();
            final all =
                '${m['nome']}${m['descricao']}${m['responsavel']}${m['categoria']}${m['localizacao']}${m['numeroSerie']}$codigo'
                    .toLowerCase();
            return all.contains(q);
          }).toList();
        }
        if (filterCategoria.isNotEmpty) {
          docs = docs
              .where((d) =>
                  (d.data()['categoria'] ?? '').toString() == filterCategoria)
              .toList();
        }
        if (filterStatus.isNotEmpty) {
          docs = docs
              .where(
                  (d) => (d.data()['status'] ?? '').toString() == filterStatus)
              .toList();
        }
        _applyPatrimonioSort(docs);

        if (allDocs.isEmpty) {
          return CustomScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ..._bensTabHeaderSlivers(),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Nenhum patrimônio cadastrado',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500)),
                      const SizedBox(height: 6),
                      Text('Cadastre bens usando o botão abaixo',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        double totalValor = 0;
        for (final d in docs) {
          final v = d.data()['valor'];
          if (v is num) totalValor += v.toDouble();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final crossCount =
                w >= 1100 ? 4 : w >= 700 ? 3 : 2;

            final contentSlivers = <Widget>[
              ..._bensTabHeaderSlivers(),
              if (manutCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                        ThemeCleanPremium.spaceLg, ThemeCleanPremium.spaceSm),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade800, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$manutCount ${manutCount == 1 ? 'bem precisa' : 'bens precisam'} de manutenção',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.amber.shade700, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              if (reparoCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                        ThemeCleanPremium.spaceLg, ThemeCleanPremium.spaceSm),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusSm),
                        onTap: () => onStatusChanged(
                          filterStatus == 'precisa_reparo'
                              ? ''
                              : 'precisa_reparo',
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.shade50,
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                            border:
                                Border.all(color: Colors.deepOrange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.handyman_rounded,
                                  color: Colors.deepOrange.shade800, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$reparoCount ${reparoCount == 1 ? 'item' : 'itens'} marcados como “Precisa de Reparo”'
                                  '${filterStatus == 'precisa_reparo' ? ' (filtro ativo)' : ' — toque para filtrar'}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepOrange.shade900),
                                ),
                              ),
                              Icon(Icons.touch_app_rounded,
                                  color: Colors.deepOrange.shade700, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceLg),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: ThemeCleanPremium.spaceMd,
                        vertical: ThemeCleanPremium.spaceSm),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ThemeCleanPremium.primary.withValues(alpha: 0.07),
                          ThemeCleanPremium.primaryLight.withValues(alpha: 0.04),
                          Colors.white,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      border: Border.all(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                      ),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                          ),
                          child: Icon(Icons.inventory_2_rounded,
                              size: 20,
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.9)),
                        ),
                        const SizedBox(width: 12),
                        Text(
                            '${docs.length} ite${docs.length == 1 ? 'm' : 'ns'}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.1,
                                color: ThemeCleanPremium.onSurface)),
                        const Spacer(),
                        Text('Total: ${fmtMoney(totalValor)}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: ThemeCleanPremium.primary)),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ];

            if (docs.isEmpty) {
              contentSlivers.add(
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Nenhum resultado para os filtros',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ),
              );
            } else if (!_galleryView) {
              contentSlivers.add(
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                      ThemeCleanPremium.spaceLg, 88),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PatrimonioCard(
                          key: ValueKey('list_${docs[i].id}'),
                          doc: docs[i],
                          selected: false,
                          catIcon: catIcon,
                          catColor: catColor,
                          statusLabel: statusLabel,
                          statusColor: statusColor,
                          fmtMoney: fmtMoney,
                          onTap: () => onShowDetail(docs[i]),
                          onEdit:
                              canWrite ? () => onOpenForm(docs[i]) : null,
                          onDelete:
                              canWrite ? () => onExcluir(docs[i]) : null,
                          onQrCode: () => onShowQrCode(docs[i]),
                          onTransferir:
                              canWrite ? () => onTransferir(docs[i]) : null,
                        ),
                      ),
                      childCount: docs.length,
                    ),
                  ),
                ),
              );
            } else {
              contentSlivers.add(
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg, 0,
                      ThemeCleanPremium.spaceLg, 88),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _PatrimonioGalleryTile(
                        key: ValueKey('grid_${docs[i].id}'),
                        doc: docs[i],
                        selected: false,
                        catIcon: catIcon,
                        catColor: catColor,
                        statusLabel: statusLabel,
                        statusColor: statusColor,
                        fmtMoney: fmtMoney,
                        onTap: () => onShowDetail(docs[i]),
                        onEdit: canWrite ? () => onOpenForm(docs[i]) : null,
                        onDelete: canWrite ? () => onExcluir(docs[i]) : null,
                        onQrCode: () => onShowQrCode(docs[i]),
                        onTransferir:
                            canWrite ? () => onTransferir(docs[i]) : null,
                      ),
                      childCount: docs.length,
                    ),
                  ),
                ),
              );
            }

            return CustomScrollView(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 650,
              slivers: contentSlivers,
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — _PatrimonioCard (card premium com foto, badges e popup)
// ═══════════════════════════════════════════════════════════════════════════════

class _PatrimonioCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final String Function(dynamic) fmtMoney;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onQrCode;
  final VoidCallback? onTransferir;

  const _PatrimonioCard({
    super.key,
    required this.doc,
    this.selected = false,
    required this.catIcon,
    required this.catColor,
    required this.statusLabel,
    required this.statusColor,
    required this.fmtMoney,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onQrCode,
    this.onTransferir,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final categoria = (m['categoria'] ?? '').toString();
    final status = (m['status'] ?? 'bom').toString();
    final valor = m['valor'];
    final local = (m['localizacao'] ?? '').toString();
    final resp = (m['responsavel'] ?? '').toString();
    final cor = catColor(categoria);
    final stColor = statusColor(status);
    final slots = _patrimonioCarouselSlotsFromData(m);
    final hasPhoto = slots.urls.isNotEmpty;
    final thumb = _patrimonioThumbFromSlots(slots.urls, slots.paths);
    final thumbUrl = thumb.url;
    final thumbPath = thumb.path;
    final dprList = MediaQuery.devicePixelRatioOf(context);
    const thumbSize = 76.0;
    // Lista do inventário: decode menor = scroll mais rápido (foto principal continua no detalhe).
    final memListThumb = (thumbSize * dprList).round().clamp(120, 240);

    // Alerta de manutenção próxima / vencida
    final proxManut = m['proximaManutencao'];
    DateTime? proxDate;
    if (proxManut is Timestamp) proxDate = proxManut.toDate();
    if (proxManut is DateTime) proxDate = proxManut;
    final needsMaint = proxDate != null &&
        proxDate.isBefore(DateTime.now().add(const Duration(days: 7)));

    Widget photoLoadingPlaceholder() => Container(
          width: thumbSize,
          height: thumbSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor.withOpacity(0.15), cor.withOpacity(0.05)],
            ),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: cor.withOpacity(0.7),
            ),
          ),
        );

    Widget photoPlaceholder() => Container(
          width: thumbSize,
          height: thumbSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor.withOpacity(0.15), cor.withOpacity(0.05)],
            ),
          ),
          child: Center(child: Icon(catIcon(categoria), color: cor, size: 28)),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                ...ThemeCleanPremium.softUiCardShadow,
              ]
            : ThemeCleanPremium.softUiCardShadow,
        border: Border.all(
          color: selected
              ? ThemeCleanPremium.primary.withValues(alpha: 0.65)
              : const Color(0xFFF1F5F9),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
            child: Row(
              children: [
                // Foto ou ícone
                SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: hasPhoto
                          ? FotoPatrimonioWidget(
                              key: ValueKey('pat_thumb_${doc.id}'),
                              storagePath: thumbPath,
                              candidateUrls: thumbUrl.isNotEmpty
                                  ? [thumbUrl]
                                  : <String>[],
                              fit: BoxFit.cover,
                              width: thumbSize,
                              height: thumbSize,
                              memCacheWidth: memListThumb,
                              memCacheHeight: memListThumb,
                              placeholder: photoLoadingPlaceholder(),
                              errorWidget: photoPlaceholder(),
                            )
                          : photoPlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Conteúdo central
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nome + alerta manutenção
                      Row(
                        children: [
                          Expanded(
                            child: Text(nome,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (needsMaint)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Tooltip(
                                message: 'Manutenção pendente',
                                child: Icon(Icons.warning_amber_rounded,
                                    size: 18, color: Colors.amber.shade700),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Badges: categoria + status
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(categoria,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cor)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: stColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(statusLabel(status),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: stColor)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Valor
                      if (valor != null)
                        Text(fmtMoney(valor),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: ThemeCleanPremium.primary)),

                      // Localização e responsável
                      if (local.isNotEmpty || resp.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              if (local.isNotEmpty) ...[
                                Icon(Icons.location_on_outlined,
                                    size: 12, color: Colors.grey.shade500),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(local,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                              if (local.isNotEmpty && resp.isNotEmpty)
                                const SizedBox(width: 10),
                              if (resp.isNotEmpty) ...[
                                Icon(Icons.person_outline_rounded,
                                    size: 12, color: Colors.grey.shade500),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(resp,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Popup menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: Colors.grey.shade400, size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (v) {
                    if (v == 'edit') {
                      onEdit?.call();
                    } else if (v == 'delete') {
                      onDelete?.call();
                    } else if (v == 'qr') {
                      onQrCode?.call();
                    } else if (v == 'transfer') {
                      onTransferir?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ]),
                      ),
                    const PopupMenuItem(
                      value: 'qr',
                      child: Row(children: [
                        Icon(Icons.qr_code_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('QR Code'),
                      ]),
                    ),
                    if (onTransferir != null)
                      const PopupMenuItem(
                        value: 'transfer',
                        child: Row(children: [
                          Icon(Icons.swap_horiz_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Transferir'),
                        ]),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.red.shade400),
                          const SizedBox(width: 8),
                          Text('Excluir',
                              style: TextStyle(color: Colors.red.shade400)),
                        ]),
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

/// Card em grade (galeria) — mesmo comportamento do card em lista, layout vertical.
class _PatrimonioGalleryTile extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final String Function(dynamic) fmtMoney;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onQrCode;
  final VoidCallback? onTransferir;

  const _PatrimonioGalleryTile({
    super.key,
    required this.doc,
    this.selected = false,
    required this.catIcon,
    required this.catColor,
    required this.statusLabel,
    required this.statusColor,
    required this.fmtMoney,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onQrCode,
    this.onTransferir,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final categoria = (m['categoria'] ?? '').toString();
    final status = (m['status'] ?? 'bom').toString();
    final valor = m['valor'];
    final cor = catColor(categoria);
    final stColor = statusColor(status);
    final slots = _patrimonioCarouselSlotsFromData(m);
    final hasPhoto = slots.urls.isNotEmpty;
    final thumb = _patrimonioThumbFromSlots(slots.urls, slots.paths);
    final thumbUrl = thumb.url;
    final thumbPath = thumb.path;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const thumbH = 120.0;
    /// Miniaturas do grid: decode ~300px (memória leve na lista/galeria).
    const kGridMemPx = 300;
    final memThumb = (kGridMemPx * dpr).round().clamp(240, 900);

    Widget photoLoading() => Container(
          height: thumbH,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor.withOpacity(0.15), cor.withOpacity(0.05)],
            ),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: cor.withOpacity(0.7),
            ),
          ),
        );

    Widget photoPh() => Container(
          height: thumbH,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cor.withOpacity(0.15), cor.withOpacity(0.05)],
            ),
          ),
          child: Center(child: Icon(catIcon(categoria), color: cor, size: 40)),
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    ...ThemeCleanPremium.softUiCardShadow,
                  ]
                : ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
              color: selected
                  ? ThemeCleanPremium.primary.withValues(alpha: 0.65)
                  : const Color(0xFFF1F5F9),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: thumbH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    hasPhoto
                        ? FotoPatrimonioWidget(
                            key: ValueKey('gal_${doc.id}'),
                            storagePath: thumbPath,
                            candidateUrls:
                                thumbUrl.isNotEmpty ? [thumbUrl] : <String>[],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: thumbH,
                            memCacheWidth: memThumb,
                            memCacheHeight: memThumb,
                            placeholder: photoLoading(),
                            errorWidget: photoPh(),
                          )
                        : photoPh(),
                    Positioned(
                      top: 6,
                      right: 4,
                      child: Material(
                        color: Colors.white.withOpacity(0.94),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          icon: Icon(Icons.more_vert_rounded,
                              color: Colors.grey.shade600, size: 20),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) {
                            if (v == 'edit') {
                              onEdit?.call();
                            } else if (v == 'delete') {
                              onDelete?.call();
                            } else if (v == 'qr') {
                              onQrCode?.call();
                            } else if (v == 'transfer') {
                              onTransferir?.call();
                            }
                          },
                          itemBuilder: (_) => [
                            if (onEdit != null)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Editar'),
                                ]),
                              ),
                            const PopupMenuItem(
                              value: 'qr',
                              child: Row(children: [
                                Icon(Icons.qr_code_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('QR Code'),
                              ]),
                            ),
                            if (onTransferir != null)
                              const PopupMenuItem(
                                value: 'transfer',
                                child: Row(children: [
                                  Icon(Icons.swap_horiz_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text('Transferir'),
                                ]),
                              ),
                            if (onDelete != null)
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 18, color: Colors.red.shade400),
                                  const SizedBox(width: 8),
                                  Text('Excluir',
                                      style: TextStyle(
                                          color: Colors.red.shade400)),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: cor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              categoria,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: cor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: stColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel(status),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: stColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (valor != null)
                        Text(
                          fmtMoney(valor),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: ThemeCleanPremium.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3B — _RelatoriosPatrimonioTab (filtros + exportação PDF Super Premium)
// ═══════════════════════════════════════════════════════════════════════════════

class _RelatoriosPatrimonioTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final List<String> categorias;
  final String Function(String?) statusLabel;
  final String Function(dynamic) fmtMoney;
  final String Function(dynamic) fmtDate;
  final String tenantId;

  const _RelatoriosPatrimonioTab({
    required this.col,
    required this.categorias,
    required this.statusLabel,
    required this.fmtMoney,
    required this.fmtDate,
    required this.tenantId,
  });

  @override
  State<_RelatoriosPatrimonioTab> createState() =>
      _RelatoriosPatrimonioTabState();
}

class _RelatoriosPatrimonioTabState extends State<_RelatoriosPatrimonioTab> {
  int _streamRetryToken = 0;
  String _filtroCategoria = '';
  int? _filtroAno;
  int? _filtroMes;
  DateTime? _aquisicaoInicio;
  DateTime? _aquisicaoFim;

  static const _mesesNomes = [
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

  String _fmtD(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) {
      final m = d.data();
      final cat = (m['categoria'] ?? 'Outro').toString();
      if (_filtroCategoria.isNotEmpty && cat != _filtroCategoria) {
        return false;
      }
      final aq = _dataAquisicaoFromPatrimonioMap(m);
      final hasRange = _aquisicaoInicio != null || _aquisicaoFim != null;
      if (hasRange) {
        if (aq == null) return false;
        final ad = DateTime(aq.year, aq.month, aq.day);
        if (_aquisicaoInicio != null) {
          final s = DateTime(
            _aquisicaoInicio!.year,
            _aquisicaoInicio!.month,
            _aquisicaoInicio!.day,
          );
          if (ad.isBefore(s)) return false;
        }
        if (_aquisicaoFim != null) {
          final e = DateTime(
            _aquisicaoFim!.year,
            _aquisicaoFim!.month,
            _aquisicaoFim!.day,
          );
          if (ad.isAfter(e)) return false;
        }
        return true;
      }
      if (_filtroAno != null) {
        if (aq == null) return false;
        if (aq.year != _filtroAno) return false;
      }
      if (_filtroMes != null) {
        if (aq == null) return false;
        if (aq.month != _filtroMes) return false;
      }
      return true;
    }).toList();
  }

  List<String> _filterSummaryLines() {
    final lines = <String>[];
    if (_filtroCategoria.isNotEmpty) {
      lines.add('Categoria: $_filtroCategoria');
    }
    if (_filtroAno != null) {
      lines.add('Ano (aquisição): $_filtroAno');
    }
    if (_filtroMes != null) {
      lines.add(
        'Mês (aquisição): ${_mesesNomes[_filtroMes! - 1]}',
      );
    }
    if (_aquisicaoInicio != null) {
      lines.add('Aquisição de: ${_fmtD(_aquisicaoInicio!)}');
    }
    if (_aquisicaoFim != null) {
      lines.add('Aquisição até: ${_fmtD(_aquisicaoFim!)}');
    }
    return lines;
  }

  Future<void> _exportFilteredPdf(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered,
  ) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum bem com os filtros atuais.')),
      );
      return;
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (!context.mounted) return;
    await _exportPatrimonioRelatorioPdf(
      context: context,
      tenantId: widget.tenantId,
      docs: filtered,
      statusLabel: widget.statusLabel,
      fmtMoney: widget.fmtMoney,
      filterSummaryLines: _filterSummaryLines(),
      filename: 'patrimonio_relatorio_filtrado.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final anos = List<int>.generate(now.year - 1999, (i) => 2000 + i);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(_streamRetryToken),
      stream: widget.col.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar o patrimônio',
            error: snap.error,
            onRetry: () => setState(() => _streamRetryToken++),
          );
        }
        if (!snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final all = snap.data!.docs;
        final filtered = _applyFilters(all);
        double soma = 0;
        for (final d in filtered) {
          final v = d.data()['valor'];
          if (v is num) soma += v.toDouble();
        }

        return SingleChildScrollView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
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
                            Icons.analytics_outlined,
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
                    const SizedBox(height: 14),
                    Text(
                      'Filtre por categoria, mês/ano ou período da data de aquisição. O PDF usa a mesma identidade visual (logo ampliada) do sistema.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: ThemeCleanPremium.spaceSm,
                runSpacing: ThemeCleanPremium.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _filtroCategoria.isEmpty ? null : _filtroCategoria,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ...widget.categorias.map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _filtroCategoria = v ?? ''),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int?>(
                      value: _filtroAno,
                      decoration: InputDecoration(
                        labelText: 'Ano',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...anos.map(
                          (y) => DropdownMenuItem<int?>(
                            value: y,
                            child: Text('$y'),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filtroAno = v),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int?>(
                      value: _filtroMes,
                      decoration: InputDecoration(
                        labelText: 'Mês',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos'),
                        ),
                        ...List.generate(
                          12,
                          (i) => DropdownMenuItem<int?>(
                            value: i + 1,
                            child: Text(_mesesNomes[i]),
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
                        initialDate: _aquisicaoInicio ?? now,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (d != null) setState(() => _aquisicaoInicio = d);
                    },
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(
                      _aquisicaoInicio != null
                          ? 'De: ${_fmtD(_aquisicaoInicio!)}'
                          : 'Aquisição de',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      side: BorderSide(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
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
                        initialDate: _aquisicaoFim ?? now,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (d != null) setState(() => _aquisicaoFim = d);
                    },
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      _aquisicaoFim != null
                          ? 'Até: ${_fmtD(_aquisicaoFim!)}'
                          : 'Aquisição até',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.primary,
                      side: BorderSide(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
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
                      _filtroCategoria = '';
                      _filtroAno = null;
                      _filtroMes = null;
                      _aquisicaoInicio = null;
                      _aquisicaoFim = null;
                    }),
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('Limpar filtros'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_rounded,
                        color: ThemeCleanPremium.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${filtered.length} bem(ns) · Valor filtrado: ${widget.fmtMoney(soma)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => _exportFilteredPdf(context, filtered),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text(
                    'Gerar PDF Super Premium (filtros atuais)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pré-visualização (primeiros 40)',
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
                      'Nenhum bem corresponde aos filtros.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                ...filtered.take(40).map((d) {
                  final m = d.data();
                  final nome = (m['nome'] ?? '—').toString();
                  final cat = (m['categoria'] ?? '').toString();
                  final st = widget.statusLabel((m['status'] ?? '').toString());
                  final aq = _dataAquisicaoFromPatrimonioMap(m);
                  final aqStr = aq != null ? widget.fmtDate(Timestamp.fromDate(aq)) : '—';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$cat · $st · Aquis.: $aqStr',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              widget.fmtMoney(m['valor']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ThemeCleanPremium.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Lista rápida do painel (KPI) — editar + exportar PDF
// ═══════════════════════════════════════════════════════════════════════════════

class _PatrimonioKpiListDialog extends StatelessWidget {
  final String title;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String tenantId;
  final String Function(String?) statusLabel;
  final String Function(dynamic) fmtMoney;
  final void Function(DocumentSnapshot<Map<String, dynamic>> doc) onBemSelected;
  final List<String> pdfFilterLines;
  final String pdfFilename;

  const _PatrimonioKpiListDialog({
    required this.title,
    required this.docs,
    required this.tenantId,
    required this.statusLabel,
    required this.fmtMoney,
    required this.onBemSelected,
    required this.pdfFilterLines,
    required this.pdfFilename,
  });

  Future<void> _export(BuildContext context) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item para exportar.')),
      );
      return;
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (!context.mounted) return;
    await _exportPatrimonioRelatorioPdf(
      context: context,
      tenantId: tenantId,
      docs: docs,
      statusLabel: statusLabel,
      fmtMoney: fmtMoney,
      filterSummaryLines: pdfFilterLines,
      filename: pdfFilename,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Exportar PDF',
                    onPressed: () => _export(context),
                    icon: Icon(Icons.picture_as_pdf_rounded,
                        color: ThemeCleanPremium.primary),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ThemeCleanPremium.primary,
                      elevation: 1,
                    ),
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
              child: Text(
                '${docs.length} item(ns) · toque para abrir o bem',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum bem nesta lista.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final m = d.data();
                        final nome = (m['nome'] ?? '—').toString();
                        final cat = (m['categoria'] ?? '').toString();
                        final st = statusLabel((m['status'] ?? '').toString());
                        return Material(
                          color: ThemeCleanPremium.cardBackground,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(ThemeCleanPremium.radiusSm),
                            onTap: () => onBemSelected(d),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm),
                                border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nome,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$cat · $st',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    fmtMoney(m['valor']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      color: Colors.grey.shade400),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: docs.isEmpty ? null : () => _export(context),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Exportar lista em PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — _DashboardTab (resumos, gráficos e exportação PDF)
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final List<String> categorias;
  final List<Map<String, String>> statusList;
  final Color Function(String) catColor;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final String Function(dynamic) fmtMoney;
  final String tenantId;
  final void Function(DocumentSnapshot<Map<String, dynamic>> doc) onBemSelected;

  const _DashboardTab({
    super.key,
    required this.col,
    required this.categorias,
    required this.statusList,
    required this.catColor,
    required this.statusLabel,
    required this.statusColor,
    required this.fmtMoney,
    required this.tenantId,
    required this.onBemSelected,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDashboardFirstPaint();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadDashboardFirstPaint() async {
    try {
      final cached =
          await widget.col.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        unawaited(_refreshDashboardFromServer());
        return cached;
      }
    } catch (_) {}
    return widget.col.get(const GetOptions(source: Source.server));
  }

  Future<void> _refreshDashboardFromServer() async {
    try {
      final server =
          await widget.col.get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() => _future = Future.value(server));
    } catch (_) {}
  }

  void refresh() {
    setState(() {
      _future = widget.col.get(const GetOptions(source: Source.server));
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusList = widget.statusList;
    final catColor = widget.catColor;
    final statusColor = widget.statusColor;
    final fmtMoney = widget.fmtMoney;

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os dados do painel',
            error: snap.error,
            onRetry: refresh,
          );
        }
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }

        final docs = snap.data!.docs;
        final total = docs.length;

        double valorTotal = 0;
        int emManutencao = 0;
        int precisaReparo = 0;
        double somaDepreciacao = 0;
        int countDepreciacao = 0;

        final catValues = <String, double>{};
        final statusCounts = <String, int>{};
        final now = DateTime.now();

        for (final d in docs) {
          final m = d.data();
          final valor = m['valor'];
          final v = valor is num ? valor.toDouble() : 0.0;
          valorTotal += v;

          final cat = (m['categoria'] ?? 'Outro').toString();
          catValues[cat] = (catValues[cat] ?? 0) + v;

          final st = (m['status'] ?? 'bom').toString();
          statusCounts[st] = (statusCounts[st] ?? 0) + 1;
          if (st == 'em_manutencao') emManutencao++;
          if (st == 'precisa_reparo') precisaReparo++;

          final da = m['dataAquisicao'];
          DateTime? acquired;
          if (da is Timestamp) acquired = da.toDate();
          if (da is DateTime) acquired = da;
          if (acquired != null && v > 0) {
            final years = now.difference(acquired).inDays / 365.25;
            somaDepreciacao += (years * 10).clamp(0, 100);
            countDepreciacao++;
          }
        }

        final avgDep =
            countDepreciacao > 0 ? (somaDepreciacao / countDepreciacao) : 0.0;

        final manutencaoDocs = docs.where((d) {
          final st = (d.data()['status'] ?? 'bom').toString();
          return st == 'em_manutencao' || st == 'precisa_reparo';
        }).toList();

        void openKpiList({
          required String title,
          required List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
          required List<String> pdfLines,
          required String pdfFilename,
        }) {
          showDialog<void>(
            context: context,
            builder: (ctx) => _PatrimonioKpiListDialog(
              title: title,
              docs: list,
              tenantId: widget.tenantId,
              statusLabel: widget.statusLabel,
              fmtMoney: widget.fmtMoney,
              onBemSelected: (doc) {
                Navigator.of(ctx).pop();
                widget.onBemSelected(doc);
              },
              pdfFilterLines: pdfLines,
              pdfFilename: pdfFilename,
            ),
          );
        }

        // ── Summary card builder ──
        Widget summaryCard({
          required IconData icon,
          required Color color,
          required String title,
          required String value,
          VoidCallback? onTap,
        }) {
          final inner = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 12),
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface)),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.touch_app_rounded, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'Ver lista e exportar',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );

          if (onTap == null) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: inner,
            );
          }
          return Material(
            color: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: inner,
              ),
            ),
          );
        }

        // ── PieChart sections ──
        final pieEntries = <PieChartSectionData>[];
        final activeCats = <String>[];
        catValues.forEach((cat, val) {
          if (val > 0) {
            activeCats.add(cat);
            final pct = valorTotal > 0 ? (val / valorTotal * 100) : 0.0;
            pieEntries.add(PieChartSectionData(
              value: val,
              title: '${pct.toStringAsFixed(0)}%',
              color: catColor(cat),
              radius: 52,
              titleStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ));
          }
        });

        // ── BarChart groups ──
        final barGroups = <BarChartGroupData>[];
        int maxCount = 0;
        for (int i = 0; i < statusList.length; i++) {
          final key = statusList[i]['key']!;
          final count = statusCounts[key] ?? 0;
          if (count > maxCount) maxCount = count;
          barGroups.add(BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: statusColor(key),
                width: 28,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ],
          ));
        }

        return SingleChildScrollView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 4 Summary cards ──
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 600;
                  final gap = ThemeCleanPremium.spaceSm;
                  final cardW = wide
                      ? (constraints.maxWidth - 3 * gap) / 4
                      : (constraints.maxWidth - gap) / 2;

                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.inventory_2_rounded,
                          color: ThemeCleanPremium.primary,
                          title: 'Total de Bens',
                          value: '$total',
                          onTap: () => openKpiList(
                            title: 'Todos os bens',
                            list: docs,
                            pdfLines: const [
                              'Origem: painel — Total de bens',
                            ],
                            pdfFilename: 'patrimonio_lista_total.pdf',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.payments_rounded,
                          color: ThemeCleanPremium.success,
                          title: 'Valor Total',
                          value: fmtMoney(valorTotal),
                          onTap: null,
                        ),
                      ),
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.build_circle_rounded,
                          color: Colors.orange.shade700,
                          title: 'Manutenção / Reparo',
                          value: precisaReparo > 0
                              ? '$emManutencao em manut. · $precisaReparo reparo'
                              : '$emManutencao',
                          onTap: () => openKpiList(
                            title: 'Manutenção e reparo',
                            list: manutencaoDocs,
                            pdfLines: const [
                              'Origem: painel — Manutenção / Reparo',
                              'Inclui: em manutenção e precisa de reparo',
                            ],
                            pdfFilename:
                                'patrimonio_lista_manutencao_reparo.pdf',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.trending_down_rounded,
                          color: const Color(0xFF7C3AED),
                          title: 'Depreciação Média',
                          value: '${avgDep.toStringAsFixed(1)}%',
                          onTap: null,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── PieChart: Distribuição por categoria ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Distribuição por Categoria',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface)),
                    const SizedBox(height: 4),
                    Text('Valor total por categoria',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 20),
                    if (pieEntries.isEmpty)
                      SizedBox(
                        height: 180,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pie_chart_outline_rounded,
                                  size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('Sem dados para exibir',
                                  style:
                                      TextStyle(color: Colors.grey.shade400)),
                            ],
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 220,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: PieChart(
                                PieChartData(
                                  sections: pieEntries,
                                  centerSpaceRadius: 36,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: activeCats.map((cat) {
                                    final val = catValues[cat] ?? 0;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: catColor(cat),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                                '$cat · ${fmtMoney(val)}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade700,
                                                    fontWeight:
                                                        FontWeight.w500),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── BarChart: Status dos bens ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status dos Bens',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface)),
                    const SizedBox(height: 4),
                    Text('Quantidade por condição',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: barGroups.isEmpty
                          ? Center(
                              child: Text('Sem dados',
                                  style:
                                      TextStyle(color: Colors.grey.shade400)),
                            )
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (maxCount + 2).toDouble(),
                                barTouchData: BarTouchData(enabled: true),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        final i = value.toInt();
                                        if (i >= 0 && i < statusList.length) {
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                              statusList[i]['label']!,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade600),
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      getTitlesWidget: (value, meta) {
                                        if (value == value.roundToDouble()) {
                                          return Text('${value.toInt()}',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500));
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 1,
                                  getDrawingHorizontalLine: (value) => FlLine(
                                    color: Colors.grey.shade200,
                                    strokeWidth: 1,
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: barGroups,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Linha: inventários finalizados por mês (últimos 6 meses) ──
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('igrejas')
                    .doc(widget.tenantId)
                    .collection('patrimonio_inventario_historico')
                    .orderBy('finalizadoEm', descending: true)
                    .limit(48)
                    .snapshots(),
                builder: (context, hSnap) {
                  final hList = hSnap.data?.docs ?? [];
                  final now = DateTime.now();
                  final monthKeys = <String>[];
                  for (var i = 5; i >= 0; i--) {
                    final d = DateTime(now.year, now.month - i, 1);
                    monthKeys.add(
                        '${d.year}-${d.month.toString().padLeft(2, '0')}');
                  }
                  final counts = <String, int>{
                    for (final k in monthKeys) k: 0,
                  };
                  for (final d in hList) {
                    final m = d.data();
                    final ts = m['finalizadoEm'];
                    if (ts is Timestamp) {
                      final t = ts.toDate();
                      final key =
                          '${t.year}-${t.month.toString().padLeft(2, '0')}';
                      if (counts.containsKey(key)) {
                        counts[key] = (counts[key] ?? 0) + 1;
                      }
                    }
                  }
                  final spots = <FlSpot>[];
                  var maxY = 1.0;
                  for (var i = 0; i < monthKeys.length; i++) {
                    final c = counts[monthKeys[i]] ?? 0;
                    final y = c.toDouble();
                    if (y > maxY) maxY = y;
                    spots.add(FlSpot(i.toDouble(), y));
                  }
                  final lineColor = const Color(0xFF0EA5E9);
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                      border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: lineColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.show_chart_rounded,
                                  color: lineColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Inventários no tempo',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Sessões finalizadas por mês (últimos 6 meses)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (spots.every((s) => s.y == 0))
                          SizedBox(
                            height: 140,
                            child: Center(
                              child: Text(
                                'Ainda não há inventários registrados.\nUse a aba Inventário e finalize uma conferência.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 200,
                            child: LineChart(
                              LineChartData(
                                minY: 0,
                                maxY: maxY + 1,
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: maxY > 5 ? 2 : 1,
                                  getDrawingHorizontalLine: (v) => FlLine(
                                    color: Colors.grey.shade200,
                                    strokeWidth: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  show: true,
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      getTitlesWidget: (value, meta) {
                                        final i = value.round();
                                        if (i < 0 || i >= monthKeys.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final parts = monthKeys[i].split('-');
                                        final mo = int.tryParse(parts[1]) ?? 1;
                                        const meses = [
                                          '',
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
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                            meses[mo],
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      getTitlesWidget: (value, meta) {
                                        if (value == value.roundToDouble() &&
                                            value >= 0) {
                                          return Text(
                                            '${value.toInt()}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade500,
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: spots,
                                    isCurved: true,
                                    curveSmoothness: 0.35,
                                    color: lineColor,
                                    barWidth: 3,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter: (s, p, b, i) =>
                                          FlDotCirclePainter(
                                        radius: 4,
                                        color: lineColor,
                                        strokeWidth: 2,
                                        strokeColor: Colors.white,
                                      ),
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          lineColor.withValues(alpha: 0.22),
                                          lineColor.withValues(alpha: 0.02),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems: (touched) {
                                      return [
                                        for (final t in touched)
                                          if (t.x.round() >= 0 &&
                                              t.x.round() < monthKeys.length)
                                            LineTooltipItem(
                                              '${monthKeys[t.x.round()]}\n'
                                              '${t.y.toInt()} sessão(ões)',
                                              const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                      ];
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Exportar PDF ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => _exportPdf(context, docs),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Exportar Relatório PDF',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportPdf(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!context.mounted) return;
    await _exportPatrimonioRelatorioPdf(
      context: context,
      tenantId: widget.tenantId,
      docs: docs,
      statusLabel: widget.statusLabel,
      fmtMoney: widget.fmtMoney,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — _InventarioTab (conferência periódica de bens)
// ═══════════════════════════════════════════════════════════════════════════════
class _InventarioTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final bool canWrite;
  final List<String> categorias;
  final List<Map<String, String>> statusList;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final String Function(dynamic) fmtMoney;
  final String Function(dynamic) fmtDate;
  final String tenantId;

  const _InventarioTab({
    super.key,
    required this.col,
    required this.canWrite,
    required this.categorias,
    required this.statusList,
    required this.catIcon,
    required this.catColor,
    required this.statusLabel,
    required this.statusColor,
    required this.fmtMoney,
    required this.fmtDate,
    required this.tenantId,
  });

  @override
  State<_InventarioTab> createState() => _InventarioTabState();
}

class _InventarioTabState extends State<_InventarioTab> {
  bool _conferindo = false;
  final Set<String> _conferidos = {};
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadInventarioFirstPaint();
  }

  Future<QuerySnapshot<Map<String, dynamic>>>
      _loadInventarioFirstPaint() async {
    try {
      final cached = await widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) {
        unawaited(_refreshInventarioFromServer());
        return cached;
      }
    } catch (_) {}
    return widget.col
        .orderBy('nome')
        .get(const GetOptions(source: Source.server));
  }

  Future<void> _refreshInventarioFromServer() async {
    try {
      final server = await widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() => _future = Future.value(server));
    } catch (_) {}
  }

  void refresh() {
    setState(() {
      _future = widget.col
          .orderBy('nome')
          .get(const GetOptions(source: Source.server));
    });
  }

  Future<void> _marcarConferido(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nome = FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário';
    await doc.reference.update({
      'ultimaConferencia': FieldValue.serverTimestamp(),
      'conferidoPor': nome,
      'conferidoPorUid': uid,
    });
    setState(() => _conferidos.add(doc.id));
  }

  Future<void> _iniciarConferencia() async {
    setState(() {
      _conferindo = true;
      _conferidos.clear();
    });
  }

  Future<void> _finalizarConferencia(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final total = docs.length;
    final conferidos = _conferidos.length;
    final pendentes = total - conferidos;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nome = FirebaseAuth.instance.currentUser?.displayName ?? 'Usuário';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Conferência Finalizada'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded,
              color: ThemeCleanPremium.success, size: 56),
          const SizedBox(height: 16),
          Text('$conferidos de $total bens conferidos',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (pendentes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$pendentes bens NÃO conferidos',
                  style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          Text(
            'Um registro será salvo no histórico de inventários.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ]),
        actions: [
          FilledButton(
            onPressed: () async {
              try {
                final agora = DateTime.now();
                final itens = <Map<String, dynamic>>[];
                for (final d in docs) {
                  final m = d.data();
                  itens.add({
                    'benId': d.id,
                    'nome': (m['nome'] ?? '').toString(),
                    'categoria': (m['categoria'] ?? '').toString(),
                    'localizacao': (m['localizacao'] ?? '').toString(),
                    'status': (m['status'] ?? '').toString(),
                    'conferidoNestaSessao': _conferidos.contains(d.id),
                  });
                }
                await FirebaseFirestore.instance
                    .collection('igrejas')
                    .doc(widget.tenantId)
                    .collection('patrimonio_inventario_historico')
                    .add({
                  'finalizadoEm': FieldValue.serverTimestamp(),
                  'totalBens': total,
                  'conferidos': conferidos,
                  'pendentes': pendentes,
                  'percentualConferido':
                      total > 0 ? (100.0 * conferidos / total) : 0.0,
                  'criadoPorUid': uid,
                  'criadoPorNome': nome,
                  'titulo':
                      'Inventário ${DateFormat('dd/MM/yyyy HH:mm').format(agora)}',
                  'itens': itens,
                  'anoRef': agora.year,
                  'mesRef': agora.month,
                  'diaRef': agora.day,
                });
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Não foi possível gravar o histórico. Verifique permissões.'),
                      backgroundColor: ThemeCleanPremium.error,
                    ),
                  );
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    setState(() {
      _conferindo = false;
      _conferidos.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar o inventário',
            error: snap.error,
            onRetry: refresh,
          );
        }
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Nenhum patrimônio cadastrado',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500)),
          ]));
        }

        final now = DateTime.now();
        int conferidosRecente = 0;
        int semConferencia = 0;
        for (final d in docs) {
          final uc = d.data()['ultimaConferencia'];
          if (uc == null) {
            semConferencia++;
            continue;
          }
          try {
            final dt = (uc as Timestamp).toDate();
            if (now.difference(dt).inDays <= 90) conferidosRecente++;
          } catch (_) {
            semConferencia++;
          }
        }

        return ListView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            _InventarioHistoricoSection(
              tenantId: widget.tenantId,
              categorias: widget.categorias,
              statusLabel: widget.statusLabel,
              catIcon: widget.catIcon,
              catColor: widget.catColor,
            ),
            const SizedBox(height: 16),
            // Summary cards
            Row(children: [
              Expanded(
                  child: _MiniSummary(
                      icon: Icons.inventory_2_rounded,
                      label: 'Total',
                      value: '${docs.length}',
                      color: ThemeCleanPremium.primary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _MiniSummary(
                      icon: Icons.check_circle_rounded,
                      label: 'Conferidos (90d)',
                      value: '$conferidosRecente',
                      color: ThemeCleanPremium.success)),
              const SizedBox(width: 10),
              Expanded(
                  child: _MiniSummary(
                      icon: Icons.warning_rounded,
                      label: 'Pendentes',
                      value: '$semConferencia',
                      color: Colors.orange.shade700)),
            ]),
            const SizedBox(height: 16),

            // Action button
            if (widget.canWrite && !_conferindo)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _iniciarConferencia,
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Iniciar Conferência',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  ),
                ),
              ),
            if (_conferindo) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.06),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  border: Border.all(
                      color: ThemeCleanPremium.primary.withOpacity(0.15)),
                ),
                child: Row(children: [
                  Icon(Icons.fact_check_rounded,
                      color: ThemeCleanPremium.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Conferência em andamento — ${_conferidos.length}/${docs.length}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ThemeCleanPremium.primary))),
                  TextButton(
                    onPressed: () => _finalizarConferencia(docs),
                    child: const Text('Finalizar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),

            // Items list
            for (final doc in docs)
              _ConferenciaItem(
                doc: doc,
                catIcon: widget.catIcon,
                catColor: widget.catColor,
                fmtDate: widget.fmtDate,
                conferindo: _conferindo,
                jaConferido: _conferidos.contains(doc.id),
                onConferir: () => _marcarConferido(doc),
              ),
          ],
        );
      },
    );
  }
}

/// Histórico de sessões de inventário + filtros + abertura do relatório premium.
class _InventarioHistoricoSection extends StatefulWidget {
  final String tenantId;
  final List<String> categorias;
  final String Function(String?) statusLabel;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;

  const _InventarioHistoricoSection({
    required this.tenantId,
    required this.categorias,
    required this.statusLabel,
    required this.catIcon,
    required this.catColor,
  });

  @override
  State<_InventarioHistoricoSection> createState() =>
      _InventarioHistoricoSectionState();
}

class _InventarioHistoricoSectionState extends State<_InventarioHistoricoSection> {
  int? _filtroAno;
  int? _filtroMes;
  int? _filtroDia;
  String _filtroCategoria = '';

  bool _docPassaFiltros(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m['finalizadoEm'];
    if (ts is! Timestamp) {
      return _filtroCategoria.isEmpty && _filtroAno == null &&
          _filtroMes == null &&
          _filtroDia == null;
    }
    final date = ts.toDate();
    if (_filtroAno != null && date.year != _filtroAno) return false;
    if (_filtroMes != null && date.month != _filtroMes) return false;
    if (_filtroDia != null && date.day != _filtroDia) return false;
    if (_filtroCategoria.isEmpty) return true;
    final itens = m['itens'];
    if (itens is! List) return false;
    for (final e in itens) {
      if (e is Map &&
          (e['categoria'] ?? '').toString() == _filtroCategoria) {
        return true;
      }
    }
    return false;
  }

  void _abrirPreview(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _InventarioHistoricoPreviewScaffold(
          tenantId: widget.tenantId,
          data: doc.data(),
          statusLabel: widget.statusLabel,
          catIcon: widget.catIcon,
          catColor: widget.catColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('patrimonio_inventario_historico')
          .orderBy('finalizadoEm', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, hSnap) {
        final allDocs = hSnap.data?.docs ?? [];
        final anos = <int>{};
        for (final d in allDocs) {
          final ts = d.data()['finalizadoEm'];
          if (ts is Timestamp) anos.add(ts.toDate().year);
        }
        final anosOrdenados = anos.toList()..sort((a, b) => b.compareTo(a));

        final hDocs = allDocs.where(_docPassaFiltros).toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF0F7FF)],
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.history_rounded,
                        color: ThemeCleanPremium.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Histórico de inventários',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          allDocs.isEmpty
                              ? 'Finalize uma conferência para registrar aqui.'
                              : '${hDocs.length} de ${allDocs.length} exibido(s) · toque para relatório',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (allDocs.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _InventarioFiltroChip(
                        label: 'Ano',
                        child: DropdownButton<int?>(
                          value: _filtroAno,
                          hint: const Text('Todos'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            for (final y in anosOrdenados)
                              DropdownMenuItem<int?>(
                                value: y,
                                child: Text('$y'),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _filtroAno = v;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _InventarioFiltroChip(
                        label: 'Mês',
                        child: DropdownButton<int?>(
                          value: _filtroMes,
                          hint: const Text('Todos'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem<int?>(
                                value: m,
                                child: Text(
                                  DateFormat.MMM('pt_BR')
                                      .format(DateTime(2024, m)),
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _filtroMes = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _InventarioFiltroChip(
                        label: 'Dia',
                        child: DropdownButton<int?>(
                          value: _filtroDia,
                          hint: const Text('Todos'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Todos'),
                            ),
                            for (var day = 1; day <= 31; day++)
                              DropdownMenuItem<int?>(
                                value: day,
                                child: Text('$day'),
                              ),
                          ],
                          onChanged: (v) => setState(() => _filtroDia = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _InventarioFiltroChip(
                        label: 'Categoria',
                        child: DropdownButton<String?>(
                          value: _filtroCategoria.isEmpty
                              ? null
                              : _filtroCategoria,
                          hint: const Text('Todas'),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todas'),
                            ),
                            for (final c in widget.categorias)
                              DropdownMenuItem<String?>(
                                value: c,
                                child: Text(
                                  c,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(
                            () => _filtroCategoria = v ?? '',
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _filtroAno = null;
                          _filtroMes = null;
                          _filtroDia = null;
                          _filtroCategoria = '';
                        }),
                        icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                        label: const Text('Limpar'),
                      ),
                    ],
                  ),
                ),
              ],
              if (hDocs.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...hDocs.map((d) {
                  final m = d.data();
                  final titulo = (m['titulo'] ?? 'Inventário').toString();
                  final conf = m['conferidos'];
                  final tot = m['totalBens'];
                  final pend = m['pendentes'];
                  final por = (m['criadoPorNome'] ?? '').toString();
                  final ts = m['finalizadoEm'];
                  var dt = '';
                  if (ts is Timestamp) {
                    dt = DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
                  }
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _abrirPreview(d),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.success
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.picture_as_pdf_outlined,
                                    size: 20,
                                    color: ThemeCleanPremium.success),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titulo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$conf / $tot conferidos'
                                      '${pend != null ? ' · $pend pendente(s)' : ''}'
                                      '${dt.isNotEmpty ? ' · $dt' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (por.isNotEmpty)
                                      Text(
                                        'Responsável: $por',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: ThemeCleanPremium.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Toque para relatório e exportar PDF',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.w600,
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
                }),
              ] else if (allDocs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Nenhum registo com os filtros atuais.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InventarioFiltroChip extends StatelessWidget {
  final String label;
  final Widget child;

  const _InventarioFiltroChip({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 6),
          child,
        ],
      ),
    );
  }
}

class _InventarioHistoricoPreviewScaffold extends StatelessWidget {
  final String tenantId;
  final Map<String, dynamic> data;
  final String Function(String?) statusLabel;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;

  const _InventarioHistoricoPreviewScaffold({
    required this.tenantId,
    required this.data,
    required this.statusLabel,
    required this.catIcon,
    required this.catColor,
  });

  Future<void> _export(BuildContext context) async {
    await _exportPatrimonioInventarioSessaoPdf(
      context: context,
      tenantId: tenantId,
      data: data,
      statusLabel: statusLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = (data['titulo'] ?? 'Inventário').toString();
    final por = (data['criadoPorNome'] ?? '').toString();
    final ts = data['finalizadoEm'];
    var dt = '';
    if (ts is Timestamp) {
      dt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(ts.toDate());
    }
    final total = data['totalBens'];
    final conf = data['conferidos'];
    final pend = data['pendentes'];
    final pct = data['percentualConferido'];
    final itens = data['itens'];
    final rows = <Map<String, dynamic>>[];
    if (itens is List) {
      for (final e in itens) {
        if (e is Map) {
          rows.add(Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Relatório da sessão'),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: () => _export(context),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _export(context),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text(
              'Exportar PDF (ultra premium)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ThemeCleanPremium.primary,
                  ThemeCleanPremium.primary.withValues(alpha: 0.82),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                if (dt.isNotEmpty)
                  Text(
                    dt,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PreviewStatChip(
                      label: 'Conferidos',
                      value: '$conf / $total',
                      icon: Icons.check_circle_rounded,
                    ),
                    _PreviewStatChip(
                      label: 'Pendentes',
                      value: '${pend ?? '—'}',
                      icon: Icons.pending_actions_rounded,
                    ),
                    if (pct is num)
                      _PreviewStatChip(
                        label: '%',
                        value: '${pct.toStringAsFixed(1)}%',
                        icon: Icons.percent_rounded,
                      ),
                  ],
                ),
                if (por.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Conferência registrada por $por',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            rows.isEmpty
                ? 'Detalhe por bem'
                : 'Bens (${rows.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                'Este registo é anterior ao relatório detalhado. Use o PDF para o resumo oficial.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            )
          else
            ...rows.map((m) {
              final cat = (m['categoria'] ?? '').toString();
              final cor = catColor(cat);
              final ok = m['conferidoNestaSessao'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ok
                        ? ThemeCleanPremium.success.withValues(alpha: 0.35)
                        : const Color(0xFFE2E8F0),
                    width: ok ? 1.4 : 1,
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(catIcon(cat), color: cor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (m['nome'] ?? '').toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat.isEmpty ? '—' : cat,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                ok ? Icons.verified_rounded : Icons.help_outline,
                                size: 16,
                                color: ok
                                    ? ThemeCleanPremium.success
                                    : Colors.orange.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ok
                                    ? 'Conferido nesta sessão'
                                    : 'Não conferido nesta sessão',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ok
                                      ? ThemeCleanPremium.success
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                          if ((m['localizacao'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Local: ${m['localizacao']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          Text(
                            'Status: ${statusLabel((m['status'] ?? '').toString())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
              ),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.draw_rounded,
                        color: ThemeCleanPremium.primary, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Validação pastoral',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Assinatura do pastor responsável',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nome legível · carimbo da igreja (opcional) · data',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
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

class _PreviewStatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _PreviewStatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniSummary extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MiniSummary(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _ConferenciaItem extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final IconData Function(String) catIcon;
  final Color Function(String) catColor;
  final String Function(dynamic) fmtDate;
  final bool conferindo, jaConferido;
  final VoidCallback onConferir;

  const _ConferenciaItem({
    required this.doc,
    required this.catIcon,
    required this.catColor,
    required this.fmtDate,
    required this.conferindo,
    required this.jaConferido,
    required this.onConferir,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final nome = (m['nome'] ?? '').toString();
    final cat = (m['categoria'] ?? '').toString();
    final cor = catColor(cat);
    final ucDate = fmtDate(m['ultimaConferencia']);
    final ucPor = (m['conferidoPor'] ?? '').toString();
    final local = (m['localizacao'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: jaConferido
            ? ThemeCleanPremium.success.withOpacity(0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: jaConferido
            ? Border.all(color: ThemeCleanPremium.success.withOpacity(0.3))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(catIcon(cat), color: cor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(nome,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                if (local.isNotEmpty)
                  Text(local,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (ucDate.isNotEmpty)
                  Text(
                      'Última: $ucDate${ucPor.isNotEmpty ? ' por $ucPor' : ''}',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade500))
                else
                  Text('Nunca conferido',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600)),
              ])),
          if (conferindo && !jaConferido)
            FilledButton.icon(
              onPressed: onConferir,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('OK', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.success,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(48, 36),
              ),
            )
          else if (jaConferido)
            const Icon(Icons.check_circle_rounded,
                color: ThemeCleanPremium.success, size: 24),
        ]),
      ),
    );
  }
}

class _PatrimonioPhotoCarousel extends StatefulWidget {
  final List<String> urls;
  final List<String?> storagePaths;
  final Color cor;
  final String categoria;
  final int memCacheWidth;
  final int memCacheHeight;

  const _PatrimonioPhotoCarousel({
    super.key,
    required this.urls,
    required this.storagePaths,
    required this.cor,
    required this.categoria,
    required this.memCacheWidth,
    required this.memCacheHeight,
  });

  @override
  State<_PatrimonioPhotoCarousel> createState() =>
      _PatrimonioPhotoCarouselState();
}

class _PatrimonioPhotoCarouselState extends State<_PatrimonioPhotoCarousel> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= widget.urls.length) return;
    await _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _openFullscreenZoom() {
    if (widget.urls.isEmpty) return;
    final i =
        (_controller.page ?? 0).round().clamp(0, widget.urls.length - 1);
    unawaited(_PatrimonioFullscreenGallery.open(
      context,
      urls: widget.urls,
      storagePaths: widget.storagePaths,
      initialIndex: i,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pageView = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, i) {
          final raw = widget.urls[i];
          final path =
              i < widget.storagePaths.length ? widget.storagePaths[i] : null;
          return FotoPatrimonioWidget(
            key: ValueKey('pat_photo_${raw}_${path}_$i'),
            storagePath: path,
            candidateUrls: raw.isNotEmpty ? [raw] : <String>[],
            fit: BoxFit.cover,
            width: double.infinity,
            height: 220,
            memCacheWidth: widget.memCacheWidth,
            memCacheHeight: widget.memCacheHeight,
            placeholder: Container(
              color: widget.cor.withOpacity(0.08),
              alignment: Alignment.center,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: widget.cor.withOpacity(0.45),
                ),
              ),
            ),
            errorWidget: Container(
              color: widget.cor.withOpacity(0.08),
              child: Center(
                child: Icon(
                  _PatrimonioPageState._catIcon(widget.categoria),
                  size: 56,
                  color: widget.cor.withOpacity(0.5),
                ),
              ),
            ),
          );
        },
      ),
    );

    return Column(
      children: [
        Tooltip(
          message: 'Toque para ampliar com zoom',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openFullscreenZoom,
            child: SizedBox(
              height: 220,
              child: widget.urls.length > 1
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        pageView,
                        Positioned(
                          left: 2,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            elevation: 1,
                            child: IconButton(
                              tooltip: 'Foto anterior',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              icon: Icon(Icons.chevron_left_rounded,
                                  color: widget.cor, size: 28),
                              onPressed: () {
                                final i = _controller.page?.round() ?? 0;
                                _goToPage(i - 1);
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            elevation: 1,
                            child: IconButton(
                              tooltip: 'Próxima foto',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              icon: Icon(Icons.chevron_right_rounded,
                                  color: widget.cor, size: 28),
                              onPressed: () {
                                final i = _controller.page?.round() ?? 0;
                                _goToPage(i + 1);
                              },
                            ),
                          ),
                        ),
                      ],
                    )
                  : pageView,
            ),
          ),
        ),
        if (widget.urls.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SmoothPageIndicator(
              controller: _controller,
              count: widget.urls.length,
              effect: WormEffect(
                dotWidth: 8,
                dotHeight: 8,
                dotColor: Colors.grey.shade300,
                activeDotColor: widget.cor,
              ),
              onDotClicked: _goToPage,
            ),
          ),
      ],
    );
  }
}

/// Zoom em tela cheia: miniatura rápida por baixo + mesma URL em alta definição por cima (pinch).
class _PatrimonioFullscreenGallery extends StatefulWidget {
  final List<String> urls;
  final List<String?> storagePaths;
  final int initialIndex;

  const _PatrimonioFullscreenGallery({
    required this.urls,
    required this.storagePaths,
    required this.initialIndex,
  });

  static Future<void> open(
    BuildContext context, {
    required List<String> urls,
    required List<String?> storagePaths,
    required int initialIndex,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _PatrimonioFullscreenGallery(
          urls: urls,
          storagePaths: storagePaths,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<_PatrimonioFullscreenGallery> createState() =>
      _PatrimonioFullscreenGalleryState();
}

class _PatrimonioFullscreenGalleryState extends State<_PatrimonioFullscreenGallery> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    final n = widget.urls.length;
    _current = n <= 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    if (widget.urls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Fotos'),
        ),
        body: const Center(
          child: Text('Nenhuma imagem',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            pageController: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            builder: (context, index) {
              final raw = widget.urls[index];
              final path = index < widget.storagePaths.length
                  ? widget.storagePaths[index]
                  : null;
              final sz = MediaQuery.sizeOf(context);
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final h = sz.height * 0.88;
              final previewW = (sz.width * dpr).round().clamp(240, 960);
              final previewH = (h * dpr).round().clamp(240, 960);
              if (raw.isEmpty) {
                return PhotoViewGalleryPageOptions.customChild(
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white54, size: 64),
                  ),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.contained,
                  initialScale: PhotoViewComputedScale.contained,
                );
              }
              return PhotoViewGalleryPageOptions.customChild(
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    FotoPatrimonioWidget(
                      storagePath: path,
                      candidateUrls: [raw],
                      width: sz.width,
                      height: h,
                      memCacheWidth: previewW,
                      memCacheHeight: previewH,
                      fit: BoxFit.contain,
                      placeholder: const ColoredBox(color: Colors.black),
                      errorWidget: const SizedBox.shrink(),
                    ),
                    ResilientNetworkImage(
                      imageUrl: raw,
                      fit: BoxFit.contain,
                      width: sz.width,
                      height: h,
                      memCacheWidth: 4096,
                      memCacheHeight: 4096,
                      placeholder: const SizedBox.shrink(),
                      errorWidget: const SizedBox.shrink(),
                    ),
                  ],
                ),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3.5,
                initialScale: PhotoViewComputedScale.contained,
              );
            },
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
          Positioned(
            top: padding.top + 4,
            left: 12,
            child: Material(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  '${_current + 1} / ${widget.urls.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 4,
            right: 4,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6 — _PatrimonioFormPage (formulário com fotos, vida útil, manutenção)
// ═══════════════════════════════════════════════════════════════════════════════
class _PatrimonioFormPage extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final List<String> categorias;
  final Future<void> Function()? onCategoriasChanged;

  const _PatrimonioFormPage({
    required this.col,
    this.doc,
    required this.categorias,
    this.onCategoriasChanged,
  });

  @override
  State<_PatrimonioFormPage> createState() => _PatrimonioFormPageState();
}

class _PatrimonioFormPageState extends State<_PatrimonioFormPage> {
  static const int _maxFotosPorItem = 5;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nome,
      _desc,
      _valor,
      _local,
      _resp,
      _serie,
      _obs,
      _vidaUtil,
      _codigo;
  late String _categoria, _status;
  DateTime? _dataAquisicao, _proximaManutencao;
  final List<String> _existingUrls = [];
  final List<Uint8List> _newImages = [];
  final List<String> _newNames = [];
  late List<String> _categoriasOpcoes;
  bool _saving = false;
  double _uploadProgress = 0;

  static const _statusOptions = [
    {'key': 'novo', 'label': 'Novo', 'icon': Icons.fiber_new_rounded},
    {'key': 'bom', 'label': 'Bom', 'icon': Icons.check_circle_outline_rounded},
    {
      'key': 'precisa_reparo',
      'label': 'Precisa de Reparo',
      'icon': Icons.handyman_outlined
    },
    {
      'key': 'em_manutencao',
      'label': 'Em manutenção',
      'icon': Icons.build_circle_outlined
    },
    {
      'key': 'danificado',
      'label': 'Danificado',
      'icon': Icons.warning_amber_rounded
    },
    {'key': 'obsoleto', 'label': 'Obsoleto', 'icon': Icons.cancel_outlined},
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    _nome = TextEditingController(text: (data['nome'] ?? '').toString());
    _desc = TextEditingController(text: (data['descricao'] ?? '').toString());
    final vn = data['valor'];
    double? vd;
    if (vn is num) {
      vd = vn.toDouble();
    } else if (vn != null) {
      vd = parseBrCurrencyInput(vn.toString());
    }
    _valor = TextEditingController(
        text: vd != null && vd > 0 ? formatBrCurrencyInitial(vd) : '');
    _local =
        TextEditingController(text: (data['localizacao'] ?? '').toString());
    _resp = TextEditingController(text: (data['responsavel'] ?? '').toString());
    _serie =
        TextEditingController(text: (data['numeroSerie'] ?? '').toString());
    _obs = TextEditingController(text: (data['observacoes'] ?? '').toString());
    _vidaUtil =
        TextEditingController(text: (data['vidaUtil'] ?? '').toString());
    _codigo = TextEditingController(
        text: (data['codigoPatrimonio'] ?? data['codigo_patrimonio'] ?? '')
            .toString());
    _categoriasOpcoes = List<String>.from(widget.categorias);
    var cat = (data['categoria'] ?? 'Som').toString();
    if (!_categoriasOpcoes.contains(cat)) {
      cat = _categoriasOpcoes.contains('Outro')
          ? 'Outro'
          : (_categoriasOpcoes.isNotEmpty ? _categoriasOpcoes.first : 'Outro');
    }
    _categoria = cat;
    _status = (data['status'] ??
            (widget.doc == null ? 'novo' : 'bom'))
        .toString();
    if (data['dataAquisicao'] is Timestamp)
      _dataAquisicao = (data['dataAquisicao'] as Timestamp).toDate();
    if (data['proximaManutencao'] is Timestamp)
      _proximaManutencao = (data['proximaManutencao'] as Timestamp).toDate();
    final urls = _fotoUrlsFromData(data);
    _existingUrls.addAll(
        urls.length > _maxFotosPorItem ? urls.sublist(0, _maxFotosPorItem) : urls);
  }

  @override
  void dispose() {
    _nome.dispose();
    _desc.dispose();
    _valor.dispose();
    _local.dispose();
    _resp.dispose();
    _serie.dispose();
    _obs.dispose();
    _vidaUtil.dispose();
    _codigo.dispose();
    super.dispose();
  }

  int get _fotoCountAtual => _existingUrls.length + _newImages.length;
  bool get _atingiuLimiteFotos => _fotoCountAtual >= _maxFotosPorItem;

  /// Alinha [fotoStoragePaths] por índice às fotos existentes (preview no formulário).
  String? _pathForExistingPreview(int idx) {
    final data = widget.doc?.data();
    if (data == null) return null;
    final raw = data['fotoStoragePaths'];
    if (raw is! List || idx >= raw.length) return null;
    final t = raw[idx]?.toString().trim();
    return t != null && t.isNotEmpty ? t : null;
  }

  void _showLimiteFotosSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Limite de $_maxFotosPorItem fotos por item (inventário digital)')),
    );
  }

  Future<void> _cadastrarNovaCategoria() async {
    if (_saving) return;
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: const Text('Nova categoria'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome da categoria',
              hintText: 'Ex.: Ferramentas',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final nomeDigitado = ctrl.text.trim();
      if (nomeDigitado.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o nome da categoria.')),
        );
        return;
      }
      for (final c in _categoriasOpcoes) {
        if (c.toLowerCase() == nomeDigitado.toLowerCase()) {
          setState(() => _categoria = c);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('A categoria "$c" já está na lista.')),
          );
          return;
        }
      }
      final tenantId = widget.col.parent!.id;
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('config')
          .doc('patrimonio')
          .set(
        {
          'categoriasExtras': FieldValue.arrayUnion([nomeDigitado]),
          'atualizadoEm': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() {
        _categoriasOpcoes = {..._categoriasOpcoes, nomeDigitado}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _categoria = nomeDigitado;
      });
      final f = widget.onCategoriasChanged;
      if (f != null) await f();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Categoria cadastrada.'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar categoria: $e')),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _pickImages() async {
    if (_atingiuLimiteFotos) {
      _showLimiteFotosSnack();
      return;
    }
    final files =
        await MediaHandlerService.instance.pickAndProcessMultipleImages();
    final vagas = _maxFotosPorItem - _fotoCountAtual;
    if (files.length > vagas) {
      _showLimiteFotosSnack();
    }
    final selecionadas = files.take(vagas).toList();
    final novosBytes = <Uint8List>[];
    final novosNomes = <String>[];
    for (final f in selecionadas) {
      novosBytes.add(await f.readAsBytes());
      novosNomes.add(f.name);
    }
    if (novosBytes.isNotEmpty && mounted) {
      setState(() {
        _newImages.addAll(novosBytes);
        _newNames.addAll(novosNomes);
      });
    }
  }

  Future<void> _pickCamera() async {
    if (_atingiuLimiteFotos) {
      _showLimiteFotosSnack();
      return;
    }
    final file = await MediaHandlerService.instance
        .pickAndProcessImage(source: ImageSource.camera);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _newImages.add(bytes);
        _newNames.add(file.name);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dataAquisicao == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe a data de aquisição (campo obrigatório).')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _uploadProgress = 0;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
      final tenantId = widget.col.parent!.id;
      final DocumentReference<Map<String, dynamic>> itemRef =
          widget.doc != null ? widget.col.doc(widget.doc!.id) : widget.col.doc();
      final itemId = itemRef.id;

      final allUrls = List<String>.from(_existingUrls);
      final prev = widget.doc?.data();
      final prevPathByUrl = <String, String>{};
      if (prev != null) {
        final pUrls = _fotoUrlsFromData(prev);
        final rawP = prev['fotoStoragePaths'];
        if (rawP is List) {
          for (var i = 0; i < pUrls.length && i < rawP.length; i++) {
            final ku = sanitizeImageUrl(pUrls[i]);
            if (ku.isNotEmpty) {
              prevPathByUrl[ku] = rawP[i].toString().trim();
            }
          }
        }
      }

      final allPaths = <String>[];
      for (var i = 0; i < allUrls.length; i++) {
        final u = sanitizeImageUrl(allUrls[i]);
        final p = prevPathByUrl[u];
        if (p != null && p.isNotEmpty) {
          allPaths.add(p);
        } else {
          allPaths.add(
              ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemId, i));
        }
      }

      final startSlot = allUrls.length;
      final vagas = (_maxFotosPorItem - startSlot).clamp(0, _maxFotosPorItem);
      final nBatch = _newImages.length < vagas ? _newImages.length : vagas;
      if (nBatch > 0) {
        await Future.wait(
          List.generate(
            nBatch,
            (j) => FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
                  tenantId: tenantId,
                  itemDocId: itemId,
                  slot: startSlot + j,
                ),
          ),
        );
        final compressed = await Future.wait(
          List.generate(
            nBatch,
            (j) => ImageHelper.compressPatrimonioPhotoForUpload(_newImages[j]),
          ),
        );
        final progresses = List<double>.filled(nBatch, 0);
        void bumpUploadProgress() {
          if (!mounted || nBatch <= 0) {
            return;
          }
          final sum = progresses.fold<double>(0, (a, b) => a + b) / nBatch;
          setState(() => _uploadProgress = sum.clamp(0.0, 1.0));
        }

        const uploadConcurrency = 6;
        final results = <MediaUploadResult>[];
        for (var batchStart = 0;
            batchStart < nBatch;
            batchStart += uploadConcurrency) {
          final batchEnd = math.min(batchStart + uploadConcurrency, nBatch);
          final chunk = await Future.wait(
            List.generate(batchEnd - batchStart, (k) {
              final j = batchStart + k;
              final slot = startSlot + j;
              final path =
                  ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemId, slot);
              return MediaUploadService.uploadBytesDetailed(
                storagePath: path,
                bytes: compressed[j],
                contentType: 'image/webp',
                skipClientPrepare: true,
                onProgress: (p) {
                  progresses[j] = p.clamp(0.0, 1.0);
                  bumpUploadProgress();
                },
              );
            }),
          );
          results.addAll(chunk);
        }
        for (final r in results) {
          allUrls.add(r.downloadUrl);
          allPaths.add(r.storagePath);
        }
        if (results.isNotEmpty) {
          await Future.wait([
            for (final r in results)
              CachedNetworkImage.evictFromCache(r.downloadUrl),
          ]);
        }
      }

      if (widget.doc != null && prev != null) {
        final oldList = _fotoUrlsFromData(prev)
            .map((e) => sanitizeImageUrl(e))
            .where((e) => e.isNotEmpty)
            .toList();
        final oldSet = oldList.toSet();
        final newSet = allUrls
            .map((e) => sanitizeImageUrl(e))
            .where((e) => e.isNotEmpty)
            .toSet();
        await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
            oldSet.difference(newSet));
        final oldFirst = oldList.isEmpty ? '' : oldList.first;
        final newFirst = allUrls.isEmpty ? '' : sanitizeImageUrl(allUrls.first);
        if (oldFirst.isNotEmpty && oldFirst != newFirst) {
          await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
            FirebaseStorageCleanupService.urlsFromVariantMap(
                prev['imageVariants']),
          );
          await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
            FirebaseStorageCleanupService.urlsFromVariantMap(
                prev['fotoVariants']),
          );
        }
      }

      final occupiedSlots = allUrls.length;
      if (mounted) {
        setState(() => _uploadProgress = 0.92);
      }
      final valor = parseBrCurrencyInput(_valor.text);
      final vidaUtil = int.tryParse(_vidaUtil.text);
      final payload = <String, dynamic>{
        'nome': _nome.text.trim(),
        'descricao': _desc.text.trim(),
        'categoria': _categoria,
        'codigoPatrimonio': _codigo.text.trim(),
        'valor': valor,
        'vidaUtil': vidaUtil,
        'dataAquisicao':
            _dataAquisicao != null ? Timestamp.fromDate(_dataAquisicao!) : null,
        'proximaManutencao': _proximaManutencao != null
            ? Timestamp.fromDate(_proximaManutencao!)
            : null,
        'localizacao': _local.text.trim(),
        'responsavel': _resp.text.trim(),
        'numeroSerie': _serie.text.trim(),
        'status': _status,
        'observacoes': _obs.text.trim(),
        'fotoUrls': allUrls,
        if (allPaths.isNotEmpty) 'fotoStoragePaths': allPaths,
        if (allUrls.isNotEmpty) 'imageUrl': allUrls.first,
        if (allUrls.isNotEmpty) 'defaultImageUrl': allUrls.first,
        if (allPaths.isNotEmpty) 'imageStoragePath': allPaths.first,
        'atualizadoEm': FieldValue.serverTimestamp(),
      };
      if (widget.doc != null) {
        payload['imageVariants'] = FieldValue.delete();
        payload['fotoVariants'] = FieldValue.delete();
      }
      if (widget.doc == null) {
        payload['criadoEm'] = FieldValue.serverTimestamp();
        await itemRef.set(payload);
      } else {
        await itemRef.set(payload, SetOptions(merge: true));
      }
      FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
        tenantId: tenantId,
        itemDocId: itemId,
      );
      unawaited(() async {
        try {
          await Future.wait([
            for (var s = occupiedSlots; s < _maxFotosPorItem; s++)
              FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
                tenantId: tenantId,
                itemDocId: itemId,
                slot: s,
              ),
          ]);
        } catch (_) {}
      }());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(widget.doc == null
              ? 'Bem cadastrado!'
              : 'Patrimônio atualizado!'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Color _statusColorFromKey(String key) {
    switch (key) {
      case 'novo':
        return const Color(0xFF0891B2);
      case 'bom':
        return ThemeCleanPremium.success;
      case 'precisa_reparo':
        return Colors.deepOrange.shade700;
      case 'em_manutencao':
        return Colors.orange.shade700;
      case 'danificado':
        return ThemeCleanPremium.error;
      case 'obsoleto':
        return Colors.grey.shade600;
      default:
        return Colors.grey;
    }
  }

  static String _formatBytesPat(int n) {
    if (n < 1000) return '$n bytes';
    if (n < 1024 * 1024) {
      return '${(n / 1024).toStringAsFixed(1)} KB';
    }
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Lista estilo “Arquivos” (miniatura + nome + tamanho) — até [_maxFotosPorItem] fotos, leve na RAM.
  Widget _buildFotosArquivosSection(Color cor) {
    final dprForm = MediaQuery.devicePixelRatioOf(context);
    final memThumb = (52 * dprForm).round().clamp(88, 280);

    Widget rowTile({
      required Widget thumb,
      required String title,
      required String subtitle,
      required VoidCallback onRemove,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            thumb,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remover',
              onPressed: onRemove,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      );
    }

    final linhas = <Widget>[];
    for (var i = 0; i < _existingUrls.length; i++) {
      final idx = i;
      linhas.add(
        rowTile(
          thumb: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: FotoPatrimonioWidget(
                key: ValueKey('pat_row_ex_$idx${_existingUrls[idx]}'),
                storagePath: _pathForExistingPreview(idx),
                candidateUrls: _existingUrls[idx].isNotEmpty
                    ? [_existingUrls[idx]]
                    : <String>[],
                fit: BoxFit.cover,
                width: 52,
                height: 52,
                memCacheWidth: memThumb,
                memCacheHeight: memThumb,
                placeholder: Container(
                  color: cor.withValues(alpha: 0.12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cor,
                      ),
                    ),
                  ),
                ),
                errorWidget: Container(
                  color: cor.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: cor.withValues(alpha: 0.5),
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          title: 'Foto ${i + 1}',
          subtitle: 'image/jpeg · inventário',
          onRemove: () => setState(() => _existingUrls.removeAt(idx)),
        ),
      );
    }
    for (var i = 0; i < _newImages.length; i++) {
      final idx = i;
      final nome =
          idx < _newNames.length && _newNames[idx].isNotEmpty
              ? _newNames[idx]
              : 'Nova imagem ${i + 1}';
      linhas.add(
        rowTile(
          thumb: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Image.memory(
                _newImages[idx],
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          title: nome,
          subtitle:
              '${_formatBytesPat(_newImages[idx].length)} · aguardando envio',
          onRemove: () => setState(() {
            _newImages.removeAt(idx);
            _newNames.removeAt(idx);
          }),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Fotos do Bem',
          icon: Icons.photo_library_rounded,
          color: cor,
        ),
        const SizedBox(height: 10),
        _FormCard(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 420;
                  final btn = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: _atingiuLimiteFotos ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 20),
                        label: const Text('Galeria'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _atingiuLimiteFotos ? null : _pickCamera,
                        icon: const Icon(Icons.photo_camera_outlined, size: 20),
                        label: const Text('Câmera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeCleanPremium.primary,
                          side: BorderSide(
                            color:
                                ThemeCleanPremium.primary.withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            color: ThemeCleanPremium.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Arquivos ($_fotoCountAtual/$_maxFotosPorItem)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Até $_maxFotosPorItem fotos por bem. Envio em WebP comprimido para abrir rápido na lista.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (narrow)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  _atingiuLimiteFotos ? null : _pickImages,
                              icon: const Icon(Icons.add_photo_alternate_outlined,
                                  size: 20),
                              label: const Text('Galeria'),
                              style: FilledButton.styleFrom(
                                backgroundColor: ThemeCleanPremium.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _atingiuLimiteFotos ? null : _pickCamera,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Câmera'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ThemeCleanPremium.primary,
                                side: BorderSide(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.55),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: btn,
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (linhas.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        size: 42, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      'Nenhum arquivo anexado',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Use Galeria ou Câmera acima.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...linhas,
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.doc != null;
    final cor = _PatrimonioPageState._catColor(_categoria);

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _saving ? null : () => Navigator.maybePop(context),
        ),
        title: Text(isEditing ? 'Editar Patrimônio' : 'Novo Patrimônio'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, color: Colors.white),
            label: Text(_saving ? 'Salvando...' : 'Salvar',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  label: const Text('Voltar'),
                  style: TextButton.styleFrom(
                    foregroundColor: ThemeCleanPremium.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildFotosArquivosSection(cor),
              const SizedBox(height: 20),

              // ── Identificação ──
              _SectionHeader(
                  title: 'Identificação',
                  icon: Icons.badge_rounded,
                  color: cor),
              const SizedBox(height: 10),
              _FormCard(children: [
                TextFormField(
                    controller: _nome,
                    decoration: const InputDecoration(
                        labelText: 'Nome do bem *',
                        prefixIcon: Icon(Icons.label_rounded)),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Obrigatório' : null),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                    value: _categoriasOpcoes.contains(_categoria)
                        ? _categoria
                        : (_categoriasOpcoes.isNotEmpty
                            ? _categoriasOpcoes.first
                            : null),
                    decoration: const InputDecoration(
                        labelText: 'Categoria *',
                        prefixIcon: Icon(Icons.category_rounded)),
                    items: _categoriasOpcoes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Selecione a categoria' : null,
                    onChanged: (v) =>
                        setState(() => _categoria = v ?? _categoria)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _cadastrarNovaCategoria,
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    label: const Text('Cadastrar categoria'),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _codigo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Código de patrimônio',
                        hintText: 'Opcional — útil em buscas e etiquetas',
                        prefixIcon: Icon(Icons.tag_rounded)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _desc,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Descrição',
                        prefixIcon: Icon(Icons.description_rounded),
                        alignLabelWithHint: true)),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _serie,
                    decoration: const InputDecoration(
                        labelText: 'Número de série',
                        prefixIcon: Icon(Icons.qr_code_rounded))),
              ]),
              const SizedBox(height: 20),

              // ── Financeiro + Depreciação ──
              _SectionHeader(
                  title: 'Financeiro & Depreciação',
                  icon: Icons.attach_money_rounded,
                  color: ThemeCleanPremium.success),
              const SizedBox(height: 10),
              _FormCard(children: [
                TextFormField(
                    controller: _valor,
                    keyboardType: TextInputType.number,
                    inputFormatters: [BrCurrencyInputFormatter()],
                    decoration: const InputDecoration(
                        labelText: 'Valor de compra (R\$) *',
                        prefixIcon: Icon(Icons.payments_rounded)),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Informe o valor de compra';
                      }
                      final n = parseBrCurrencyInput(v);
                      if (n < 0) return 'Valor inválido';
                      return null;
                    }),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _vidaUtil,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Vida útil (anos)',
                        prefixIcon: Icon(Icons.timelapse_rounded),
                        hintText: 'Ex: 5, 10, 15')),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: _dataAquisicao ?? DateTime.now(),
                        firstDate: DateTime(1950),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() => _dataAquisicao = d);
                  },
                  child: AbsorbPointer(
                      child: TextFormField(
                    decoration: const InputDecoration(
                        labelText: 'Data de aquisição *',
                        prefixIcon: Icon(Icons.calendar_month_rounded),
                        hintText: 'Toque para escolher',
                      ),
                    controller: TextEditingController(
                        text: _dataAquisicao != null
                            ? DateFormat('dd/MM/yyyy').format(_dataAquisicao!)
                            : ''),
                  )),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Localização ──
              _SectionHeader(
                  title: 'Localização e Responsável',
                  icon: Icons.location_on_rounded,
                  color: const Color(0xFF7C3AED)),
              const SizedBox(height: 10),
              _FormCard(children: [
                TextFormField(
                    controller: _local,
                    decoration: const InputDecoration(
                        labelText: 'Localização',
                        prefixIcon: Icon(Icons.place_rounded))),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _resp,
                    decoration: const InputDecoration(
                        labelText: 'Responsável',
                        prefixIcon: Icon(Icons.person_rounded))),
              ]),
              const SizedBox(height: 20),

              // ── Manutenção ──
              _SectionHeader(
                  title: 'Manutenção Programada',
                  icon: Icons.build_rounded,
                  color: Colors.orange.shade700),
              const SizedBox(height: 10),
              _FormCard(children: [
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: _proximaManutencao ??
                            DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 5)));
                    if (d != null) setState(() => _proximaManutencao = d);
                  },
                  child: AbsorbPointer(
                      child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Próxima manutenção',
                      prefixIcon: const Icon(Icons.event_rounded),
                      suffixIcon: _proximaManutencao != null
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () =>
                                  setState(() => _proximaManutencao = null))
                          : null,
                    ),
                    controller: TextEditingController(
                        text: _proximaManutencao != null
                            ? DateFormat('dd/MM/yyyy')
                                .format(_proximaManutencao!)
                            : ''),
                  )),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Status ──
              _SectionHeader(
                  title: 'Status',
                  icon: Icons.flag_rounded,
                  color: Colors.orange.shade700),
              const SizedBox(height: 10),
              _FormCard(children: [
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _statusOptions.map((s) {
                      final selected = _status == s['key'];
                      final c = _statusColorFromKey(s['key'] as String);
                      return ChoiceChip(
                        avatar: Icon(s['icon'] as IconData,
                            size: 18, color: selected ? Colors.white : c),
                        label: Text(s['label'] as String,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : c)),
                        selected: selected,
                        selectedColor: c,
                        backgroundColor: c.withOpacity(0.08),
                        onSelected: (_) =>
                            setState(() => _status = s['key'] as String),
                        side: BorderSide.none,
                      );
                    }).toList()),
              ]),
              const SizedBox(height: 20),

              // ── Observações ──
              _SectionHeader(
                  title: 'Observações',
                  icon: Icons.notes_rounded,
                  color: Colors.grey.shade600),
              const SizedBox(height: 10),
              _FormCard(children: [
                TextFormField(
                    controller: _obs,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Observações', alignLabelWithHint: true)),
              ]),
              const SizedBox(height: 24),

              // Botão salvar
              if (_saving && _uploadProgress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _uploadProgress.clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload: ${(_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded),
                    label: Text(
                        _saving
                            ? 'Salvando...'
                            : (isEditing
                                ? 'Atualizar Patrimônio'
                                : 'Cadastrar Patrimônio'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    style: FilledButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm))),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares reutilizáveis
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader(
      {required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18)),
      const SizedBox(width: 10),
      Text(title,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: color)),
    ]);
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;
  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _FilterChipPremium extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final bool small;
  final IconData? icon;
  const _FilterChipPremium(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color,
      this.small = false,
      this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeCleanPremium.primary;
    final radius = BorderRadius.circular(22);
    final iconColor = selected
        ? Colors.white
        : Color.lerp(c, ThemeCleanPremium.onSurfaceVariant, 0.35)!;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: selected
                  ? LinearGradient(
                      colors: [c, Color.lerp(c, Colors.white, 0.12)!],
                    )
                  : null,
              color: selected ? null : Colors.white,
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : const Color(0xFFE8EDF5),
                width: 1.1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: c.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: small ? 12 : 16,
              vertical: small ? 7 : 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: small ? 15.5 : 17,
                    color: iconColor,
                  ),
                  SizedBox(width: small ? 5 : 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 11.5 : 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.15,
                    color: selected
                        ? Colors.white
                        : ThemeCleanPremium.onSurfaceVariant,
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

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _DetailItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14)),
        ])),
      ]),
    );
  }
}
