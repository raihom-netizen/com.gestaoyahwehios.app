import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/foto_patrimonio_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        imageUrlFromMap,
        imageUrlsListFromMap,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:image_picker/image_picker.dart';

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

// ═══════════════════════════════════════════════════════════════════════════════
// PatrimonioPage — Módulo de Gestão de Patrimônio (Bens · Dashboard · Inventário)
// ═══════════════════════════════════════════════════════════════════════════════

class PatrimonioPage extends StatefulWidget {
  final String tenantId;
  final String role;

  /// Gestor liberou patrimônio para este membro (role membro).
  final bool? podeVerPatrimonio;
  final List<String>? permissions;

  /// Pré-preenche a busca do inventário (ex.: busca global).
  final String? initialSearchQuery;

  const PatrimonioPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.podeVerPatrimonio,
    this.permissions,
    this.initialSearchQuery,
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
  static const _categorias = [
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

  void _refreshPatrimonioTabs() {
    _bensTabKey.currentState?.refresh();
    _dashboardTabKey.currentState?.refresh();
    _inventarioTabKey.currentState?.refresh();
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _searchCtrl = TextEditingController();
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.trim().isNotEmpty) {
      final s = widget.initialSearchQuery!.trim();
      _searchCtrl.text = s;
      _q = s.toLowerCase();
    }
    FirebaseAuth.instance.currentUser?.getIdToken(true);
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
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PatrimonioFormPage(
          col: _col,
          doc: doc,
          categorias: _categorias,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nenhum item de patrimônio para exportar.')));
        return;
      }
      final branding = await loadReportPdfBranding(widget.tenantId);
      final pdf = pw.Document();
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
        'Total de bens: ${docs.length}',
        'Em manutenção: $emManut',
        'Precisa de reparo: $precisaReparo',
        'Valor total: ${_fmtMoney(valorTotal)}',
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
                  _statusLabel((m['status'] ?? '').toString()),
                  _fmtMoney(m['valor']),
                  (m['localizacao'] ?? '').toString(),
                  (m['responsavel'] ?? '').toString(),
                ];
              }).toList(),
              accent: branding.accent,
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted)
        await showPdfActions(context,
            bytes: bytes, filename: 'patrimonio_relatorio.pdf');
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                      'custo':
                          double.tryParse(custoCtrl.text.replaceAll(',', '.')),
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

  // ─── Detail bottom sheet ───────────────────────────────────────────────────

  void _showDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    final nome = (m['nome'] ?? 'Sem nome').toString();
    final categoria = (m['categoria'] ?? '').toString();
    final status = (m['status'] ?? '').toString();
    final cor = _catColor(categoria);
    final slots = _patrimonioCarouselSlotsFromData(m);
    final fotoUrls = slots.urls;
    final fotoPaths = slots.paths;

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
          builder: (ctx, scrollCtrl) {
            final dprD = MediaQuery.devicePixelRatioOf(ctx);
            final sheetW = MediaQuery.sizeOf(ctx).width;
            // Decode proporcional ao carrossel (220px altura) — evita decodificar largura total em 4K.
            final memDetailW = (sheetW * dprD).round().clamp(240, 960);
            final memDetailH = (220 * dprD).round().clamp(200, 720);
            return SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                  ThemeCleanPremium.spaceLg, 8, ThemeCleanPremium.spaceLg, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        .limit(5)
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
                              Navigator.pop(ctx);
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
                              Navigator.pop(ctx);
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
                              Navigator.pop(ctx);
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
          },
        ),
      ),
    );
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
              bottom: TabBar(
                controller: _tabCtrl,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                tabs: const [
                  Tab(text: 'Bens'),
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Inventário'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  onPressed: () => _exportPdfFromPage(context),
                  tooltip: 'Exportar relatório PDF',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(
                      ThemeCleanPremium.minTouchTarget,
                      ThemeCleanPremium.minTouchTarget,
                    ),
                  ),
                ),
                if (_canWrite)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => _openForm(),
                    tooltip: 'Novo bem',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text('Novo Bem',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd)),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Container(
                color: ThemeCleanPremium.primary,
                child: TabBar(
                  controller: _tabCtrl,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 14),
                  tabs: const [
                    Tab(text: 'Bens'),
                    Tab(text: 'Dashboard'),
                    Tab(text: 'Inventário'),
                  ],
                ),
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
                    categorias: _categorias,
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
                    onShowDetail: _showDetail,
                    onShowQrCode: _showQrCode,
                    onTransferir: _showTransferir,
                  ),
                  _DashboardTab(
                    key: _dashboardTabKey,
                    col: _col,
                    categorias: _categorias,
                    statusList: _statusList,
                    catColor: _catColor,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    fmtMoney: _fmtMoney,
                    tenantId: widget.tenantId,
                  ),
                  _InventarioTab(
                    key: _inventarioTabKey,
                    col: _col,
                    canWrite: _canWrite,
                    categorias: _categorias,
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
  /// Galeria (grade) como padrão; lista compacta opcional.
  bool _galleryView = true;

  @override
  void initState() {
    super.initState();
    _future = _loadBens(cacheFirst: true);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadBens(
      {required bool cacheFirst}) {
    return widget.col.orderBy('nome').get(
          GetOptions(
              source: cacheFirst ? Source.serverAndCache : Source.server),
        );
  }

  void refresh() {
    setState(() {
      _future = _loadBens(cacheFirst: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final filterCategoria = widget.filterCategoria;
    final filterStatus = widget.filterStatus;
    final canWrite = widget.canWrite;
    final categorias = widget.categorias;
    final statusList = widget.statusList;
    final searchController = widget.searchController;
    final catIcon = widget.catIcon;
    final catColor = widget.catColor;
    final statusLabel = widget.statusLabel;
    final statusColor = widget.statusColor;
    final fmtMoney = widget.fmtMoney;
    final onSearchChanged = widget.onSearchChanged;
    final onCategoriaChanged = widget.onCategoriaChanged;
    final onStatusChanged = widget.onStatusChanged;
    final onOpenForm = widget.onOpenForm;
    final onExcluir = widget.onExcluir;
    final onShowDetail = widget.onShowDetail;
    final onShowQrCode = widget.onShowQrCode;
    final onTransferir = widget.onTransferir;

    return Column(
      children: [
        // ── Barra de busca — Super Premium ──
        Padding(
          padding: EdgeInsets.fromLTRB(ThemeCleanPremium.spaceLg,
              ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceLg, 0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Nome, código, local, série...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: q.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  borderSide: const BorderSide(
                      color: ThemeCleanPremium.primaryLight, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),

        // ── Modo lista / galeria ──
        Padding(
          padding: EdgeInsets.fromLTRB(
              ThemeCleanPremium.spaceLg,
              ThemeCleanPremium.spaceSm,
              ThemeCleanPremium.spaceLg,
              0),
          child: Row(
            children: [
              Text(
                'Visualização',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Galeria',
                child: IconButton(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _galleryView = true),
                  icon: Icon(
                    Icons.grid_view_rounded,
                    color: _galleryView
                        ? ThemeCleanPremium.primary
                        : Colors.grey.shade400,
                  ),
                ),
              ),
              Tooltip(
                message: 'Lista',
                child: IconButton(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _galleryView = false),
                  icon: Icon(
                    Icons.view_list_rounded,
                    color: !_galleryView
                        ? ThemeCleanPremium.primary
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Filtros: Categoria ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipPremium(
                  label: 'Todos',
                  selected: filterCategoria.isEmpty,
                  onTap: () => onCategoriaChanged(''),
                ),
                ...categorias.map((c) => _FilterChipPremium(
                      label: c,
                      color: catColor(c),
                      selected: filterCategoria == c,
                      onTap: () =>
                          onCategoriaChanged(filterCategoria == c ? '' : c),
                    )),
              ],
            ),
          ),
        ),

        // ── Filtros: Status ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChipPremium(
                  label: 'Todos',
                  small: true,
                  selected: filterStatus.isEmpty,
                  onTap: () => onStatusChanged(''),
                ),
                ...statusList.map((s) => _FilterChipPremium(
                      label: s['label']!,
                      small: true,
                      color: statusColor(s['key']),
                      selected: filterStatus == s['key'],
                      onTap: () => onStatusChanged(
                          filterStatus == s['key'] ? '' : s['key']!),
                    )),
              ],
            ),
          ),
        ),

        // ── Lista com FutureBuilder ──
        Expanded(
          child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return ChurchPanelErrorBody(
                  title: 'Não foi possível carregar o patrimônio',
                  error: snap.error,
                  onRetry: refresh,
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const ChurchPanelLoadingBody();
              }

              final allDocs = snap.data?.docs ?? [];

              // Alertas de manutenção (calculado antes dos filtros)
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

              // Aplicar filtros
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
                        (d.data()['categoria'] ?? '').toString() ==
                        filterCategoria)
                    .toList();
              }
              if (filterStatus.isNotEmpty) {
                docs = docs
                    .where((d) =>
                        (d.data()['status'] ?? '').toString() == filterStatus)
                    .toList();
              }

              if (allDocs.isEmpty) {
                return Center(
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
                );
              }

              // Total do patrimônio filtrado
              double totalValor = 0;
              for (final d in docs) {
                final v = d.data()['valor'];
                if (v is num) totalValor += v.toDouble();
              }

              return Column(
                children: [
                  // Banner de manutenção
                  if (manutCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

                  if (reparoCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusSm),
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
                              border: Border.all(
                                  color: Colors.deepOrange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.handyman_rounded,
                                    color: Colors.deepOrange.shade800,
                                    size: 20),
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
                                    color: Colors.deepOrange.shade700,
                                    size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Resumo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          ThemeCleanPremium.primary.withOpacity(0.06),
                          ThemeCleanPremium.primaryLight.withOpacity(0.03),
                        ]),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_rounded,
                              size: 18,
                              color:
                                  ThemeCleanPremium.primary.withOpacity(0.6)),
                          const SizedBox(width: 8),
                          Text(
                              '${docs.length} ite${docs.length == 1 ? 'm' : 'ns'}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700)),
                          const Spacer(),
                          Text('Total: ${fmtMoney(totalValor)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: ThemeCleanPremium.primary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lista ou galeria
                  Expanded(
                    child: docs.isEmpty
                        ? Center(
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
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final crossCount = w >= 1100
                                  ? 4
                                  : w >= 700
                                      ? 3
                                      : 2;
                              if (!_galleryView) {
                                return ListView.builder(
                                  cacheExtent: 520,
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 88),
                                  itemCount: docs.length,
                                  itemBuilder: (context, i) => _PatrimonioCard(
                                    key: ValueKey('list_${docs[i].id}'),
                                    doc: docs[i],
                                    catIcon: catIcon,
                                    catColor: catColor,
                                    statusLabel: statusLabel,
                                    statusColor: statusColor,
                                    fmtMoney: fmtMoney,
                                    onTap: () => onShowDetail(docs[i]),
                                    onEdit: canWrite
                                        ? () => onOpenForm(docs[i])
                                        : null,
                                    onDelete: canWrite
                                        ? () => onExcluir(docs[i])
                                        : null,
                                    onQrCode: () => onShowQrCode(docs[i]),
                                    onTransferir: canWrite
                                        ? () => onTransferir(docs[i])
                                        : null,
                                  ),
                                );
                              }
                              return GridView.builder(
                                cacheExtent: 420,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 88),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: docs.length,
                                itemBuilder: (context, i) =>
                                    _PatrimonioGalleryTile(
                                  key: ValueKey('grid_${docs[i].id}'),
                                  doc: docs[i],
                                  catIcon: catIcon,
                                  catColor: catColor,
                                  statusLabel: statusLabel,
                                  statusColor: statusColor,
                                  fmtMoney: fmtMoney,
                                  onTap: () => onShowDetail(docs[i]),
                                  onEdit: canWrite
                                      ? () => onOpenForm(docs[i])
                                      : null,
                                  onDelete: canWrite
                                      ? () => onExcluir(docs[i])
                                      : null,
                                  onQrCode: () => onShowQrCode(docs[i]),
                                  onTransferir: canWrite
                                      ? () => onTransferir(docs[i])
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — _PatrimonioCard (card premium com foto, badges e popup)
// ═══════════════════════════════════════════════════════════════════════════════

class _PatrimonioCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
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
    final thumbUrl =
        slots.urls.isNotEmpty ? slots.urls.first : '';
    final thumbPath =
        slots.paths.isNotEmpty ? slots.paths.first : null;
    final dprList = MediaQuery.devicePixelRatioOf(context);
    const thumbSize = 76.0;
    final memListThumb = (thumbSize * dprList).round().clamp(160, 320);

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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
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
                                    fontWeight: FontWeight.w700, fontSize: 15),
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
                    switch (v) {
                      case 'edit':
                        onEdit?.call();
                      case 'delete':
                        onDelete?.call();
                      case 'qr':
                        onQrCode?.call();
                      case 'transfer':
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
    final thumbUrl = slots.urls.isNotEmpty ? slots.urls.first : '';
    final thumbPath = slots.paths.isNotEmpty ? slots.paths.first : null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const thumbH = 120.0;
    final memThumb = (thumbH * dpr).round().clamp(200, 480);

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
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
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
                            switch (v) {
                              case 'edit':
                                onEdit?.call();
                              case 'delete':
                                onDelete?.call();
                              case 'qr':
                                onQrCode?.call();
                              case 'transfer':
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
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.col.get();
  }

  void refresh() {
    setState(() {
      _future = widget.col.get();
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

        // ── Summary card builder ──
        Widget summaryCard({
          required IconData icon,
          required Color color,
          required String title,
          required String value,
        }) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
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
              ],
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
                        ),
                      ),
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.payments_rounded,
                          color: ThemeCleanPremium.success,
                          title: 'Valor Total',
                          value: fmtMoney(valorTotal),
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
                        ),
                      ),
                      SizedBox(
                        width: cardW,
                        child: summaryCard(
                          icon: Icons.trending_down_rounded,
                          color: const Color(0xFF7C3AED),
                          title: 'Depreciação Média',
                          value: '${avgDep.toStringAsFixed(1)}%',
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
    final branding = await loadReportPdfBranding(widget.tenantId);
    final pdf = pw.Document();

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
      'Total de bens: ${docs.length}',
      'Em manutenção: $emManut',
      'Precisa de reparo: $precisaReparo',
      'Valor total: ${widget.fmtMoney(valorTotal)}',
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
                widget.statusLabel((m['status'] ?? '').toString()),
                widget.fmtMoney(m['valor']),
                (m['localizacao'] ?? '').toString(),
                (m['responsavel'] ?? '').toString(),
              ];
            }).toList(),
            accent: branding.accent,
          ),
        ],
      ),
    );

    final bytes = Uint8List.fromList(await pdf.save());
    if (context.mounted)
      await showPdfActions(context,
          bytes: bytes, filename: 'patrimonio_relatorio.pdf');
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
    _future = widget.col.orderBy('nome').get();
  }

  void refresh() {
    setState(() {
      _future = widget.col.orderBy('nome').get();
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
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
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
        SizedBox(
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

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 6 — _PatrimonioFormPage (formulário com fotos, vida útil, manutenção)
// ═══════════════════════════════════════════════════════════════════════════════
class _PatrimonioFormPage extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final List<String> categorias;

  const _PatrimonioFormPage(
      {required this.col, this.doc, required this.categorias});

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
    _valor = TextEditingController(
        text: data['valor'] != null
            ? (data['valor'] is num
                ? (data['valor'] as num).toStringAsFixed(2)
                : data['valor'].toString())
            : '');
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
    var cat = (data['categoria'] ?? 'Som').toString();
    if (!widget.categorias.contains(cat)) {
      cat = widget.categorias.contains('Outro')
          ? 'Outro'
          : widget.categorias.first;
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
    for (final f in selecionadas) {
      final bytes = await f.readAsBytes();
      setState(() {
        _newImages.add(bytes);
        _newNames.add(f.name);
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
            (j) => ImageHelper.compressImage(
                  _newImages[j],
                  minWidth: 800,
                  minHeight: 600,
                  quality: 70,
                ),
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

        final results = await Future.wait(
          List.generate(nBatch, (j) {
            final slot = startSlot + j;
            final path =
                ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemId, slot);
            return MediaUploadService.uploadBytesDetailed(
              storagePath: path,
              bytes: compressed[j],
              contentType: 'image/jpeg',
              skipClientPrepare: true,
              onProgress: (p) {
                progresses[j] = p.clamp(0.0, 1.0);
                bumpUploadProgress();
              },
            );
          }),
        );
        for (final r in results) {
          allUrls.add(r.downloadUrl);
          allPaths.add(r.storagePath);
        }
        for (final r in results) {
          await CachedNetworkImage.evictFromCache(r.downloadUrl);
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

      final L = allUrls.length;
      if (mounted) {
        setState(() => _uploadProgress = 0.9);
      }
      await Future.wait([
        for (var s = L; s < _maxFotosPorItem; s++)
          FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
              tenantId: tenantId, itemDocId: itemId, slot: s),
      ]);
      await FirebaseStorageCleanupService.deleteGeneratedPatrimonioItemThumbnails(
          tenantId: tenantId, itemDocId: itemId);
      await FirebaseStorageCleanupService.deleteFlatLegacyPatrimonioDerivativesForItem(
          tenantId: tenantId, itemDocId: itemId);

      if (mounted) {
        setState(() => _uploadProgress = 0.97);
      }
      final valor = double.tryParse(_valor.text.replaceAll(',', '.'));
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.doc != null;
    final cor = _PatrimonioPageState._catColor(_categoria);
    final dprForm = MediaQuery.devicePixelRatioOf(context);
    final memPrev = (90 * dprForm).round().clamp(120, 1200);

    final allPreviews = <Widget>[];
    for (var i = 0; i < _existingUrls.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 90,
            height: 90,
            child: FotoPatrimonioWidget(
              key: ValueKey('form_prev_$idx${_existingUrls[idx]}'),
              storagePath: _pathForExistingPreview(idx),
              candidateUrls: _existingUrls[idx].isNotEmpty
                  ? [_existingUrls[idx]]
                  : <String>[],
              fit: BoxFit.cover,
              width: 90,
              height: 90,
              memCacheWidth: memPrev,
              memCacheHeight: memPrev,
              placeholder: Container(
                  color: cor.withOpacity(0.1),
                  child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cor))),
              errorWidget: Container(
                  color: cor.withOpacity(0.1),
                  child: Icon(Icons.photo_library_rounded,
                      color: cor.withOpacity(0.5), size: 32)),
            ),
          ),
        ),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => setState(() => _existingUrls.removeAt(idx)),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }
    for (var i = 0; i < _newImages.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_newImages[idx],
                width: 90, height: 90, fit: BoxFit.cover)),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => setState(() {
                      _newImages.removeAt(idx);
                      _newNames.removeAt(idx);
                    }),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
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
              // ── Fotos ──
              _SectionHeader(
                  title: 'Fotos do Bem',
                  icon: Icons.photo_library_rounded,
                  color: cor),
              const SizedBox(height: 10),
              _FormCard(children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ...allPreviews,
                  GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300)),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded,
                                    color: Colors.grey.shade400, size: 24),
                                const SizedBox(height: 2),
                                Text('Galeria',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade500))
                              ]))),
                  GestureDetector(
                      onTap: _pickCamera,
                      child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300)),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_alt_rounded,
                                    color: Colors.grey.shade400, size: 24),
                                const SizedBox(height: 2),
                                Text('Câmera',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade500))
                              ]))),
                ]),
                const SizedBox(height: 8),
                Text(
                  '$_fotoCountAtual/$_maxFotosPorItem fotos',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600),
                ),
              ]),
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
                    value: _categoria,
                    decoration: const InputDecoration(
                        labelText: 'Categoria *',
                        prefixIcon: Icon(Icons.category_rounded)),
                    items: widget.categorias
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Selecione a categoria' : null,
                    onChanged: (v) =>
                        setState(() => _categoria = v ?? _categoria)),
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Valor de compra (R\$) *',
                        prefixIcon: Icon(Icons.payments_rounded)),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Informe o valor de compra';
                      }
                      final n = double.tryParse(v.replaceAll(',', '.'));
                      if (n == null || n < 0) return 'Valor inválido';
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
  const _FilterChipPremium(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color,
      this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? ThemeCleanPremium.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? c : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: small ? 10 : 14, vertical: small ? 5 : 8),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? c : Colors.grey.shade300)),
            child: Text(label,
                style: TextStyle(
                    fontSize: small ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade700)),
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
