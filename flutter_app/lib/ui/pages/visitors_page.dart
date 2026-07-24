import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/church_visitantes_load_service.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';
import 'package:fl_chart/fl_chart.dart';

/// Abre WhatsApp (app ou web) com o número informado.
Future<void> launchWhatsAppContact(
  String rawPhone, {
  String? prefilledMessage,
}) async {
  final d = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return;
  await ChurchMemberContactChat.launchWhatsAppDigits(
    d,
    message: prefilledMessage ?? ChurchMemberContactChat.faleComigoDraft(),
  );
}

class VisitorsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Dentro de [IgrejaCleanShell]: remove título duplicado e ajusta [SafeArea].
  final bool embeddedInShell;
  const VisitorsPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<VisitorsPage> createState() => _VisitorsPageState();
}

/// Aba principal: Do Dia (cadastros de hoje, em aberto) | Histórico (consultas)
enum _TabVisitante { doDia, historico }

/// Filtro in-place ao tocar nos cartões do painel (mesma base dos totais).
enum _VisitorKpiDrill {
  none,
  esteMes,
  novosSemana,
  acompanhamento,
  convertidos,
}

bool _visitorMatchesKpiDrill(_VisitorData v, _VisitorKpiDrill drill) {
  if (drill == _VisitorKpiDrill.none) return true;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month);
  final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
  switch (drill) {
    case _VisitorKpiDrill.none:
      return true;
    case _VisitorKpiDrill.esteMes:
      final d = v.createdAt;
      return d != null && d.isAfter(startOfMonth);
    case _VisitorKpiDrill.novosSemana:
      final d = v.createdAt;
      return d != null && d.isAfter(startOfWeek) && v.status == 'Novo';
    case _VisitorKpiDrill.acompanhamento:
      return v.status == 'Em acompanhamento';
    case _VisitorKpiDrill.convertidos:
      return v.status == 'Convertido';
  }
}

String _kpiDrillTitle(_VisitorKpiDrill d) {
  switch (d) {
    case _VisitorKpiDrill.none:
      return '';
    case _VisitorKpiDrill.esteMes:
      return 'Cadastros deste mês';
    case _VisitorKpiDrill.novosSemana:
      return 'Novos na semana (status Novo)';
    case _VisitorKpiDrill.acompanhamento:
      return 'Em acompanhamento';
    case _VisitorKpiDrill.convertidos:
      return 'Convertidos';
  }
}

const List<String> _kMesesAbrPt = [
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

String _mesAbrPt(int month) =>
    month >= 1 && month <= 12 ? _kMesesAbrPt[month - 1] : '$month';

/// Quem pode gerir visitantes (cadastro, edição, exclusão de fichas — não confundir com [AppPermissions.canConvertVisitorToMember]).
bool churchVisitorManagementRole(String role) {
  final s = ChurchRolePermissions.snapshotFor(role);
  if (s.manageVisitors) return true;
  final r = ChurchRolePermissions.normalize(role);
  return r == ChurchRoleKeys.membro || r == ChurchRoleKeys.visitante;
}

/// Abre a ficha completa do visitante (editar, follow-up, excluir) sem trocar o módulo do shell.
Future<void> openChurchVisitorFichaFromDashboard(
  BuildContext context, {
  required String tenantId,
  required String role,
  required String visitorDocId,
}) async {
  final op = ChurchRepository.churchId(tenantId.trim());
  if (kIsWeb) {
    await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
  }
  final snap = await FirestoreWebGuard.runWithWebRecovery(
    () => ChurchUiCollections.visitantes(op).doc(visitorDocId).get(),
    maxAttempts: 4,
  );
  if (!context.mounted) return;
  if (!snap.exists || snap.data() == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visitante não encontrado.')),
    );
    return;
  }
  final visitor = _VisitorData(id: snap.id, data: snap.data()!);
  final membersRef =       ChurchUiCollections.membros(op);
  final canManage = churchVisitorManagementRole(role);
  final isMobile = ThemeCleanPremium.isMobile(context);
  if (isMobile) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _VisitorDetailsPage(
          tenantId: tenantId,
          visitor: visitor,
          canManage: canManage,
          canConvertVisitor: AppPermissions.canConvertVisitorToMember(role),
          membersRef: membersRef,
        ),
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: _VisitorDetailsPage(
            tenantId: tenantId,
            visitor: visitor,
            canManage: canManage,
            canConvertVisitor: AppPermissions.canConvertVisitorToMember(role),
            membersRef: membersRef,
            isDialog: true,
          ),
        ),
      ),
    );
  }
}

/// Cores premium do módulo Visitantes (laranja / âmbar).
abstract final class _VisitorsPremiumTheme {
  _VisitorsPremiumTheme._();

  static const orange = Color(0xFFF97316);
  static const amber = Color(0xFFFBBF24);
  static const deepOrange = Color(0xFFEA580C);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF97316), Color(0xFFFBBF24), Color(0xFFFB923C)],
  );

  static Color statusAccent(String status) {
    switch (status) {
      case 'Novo':
        return const Color(0xFF3B82F6);
      case 'Em acompanhamento':
        return deepOrange;
      case 'Convertido':
        return const Color(0xFF16A34A);
      case 'Desistente':
        return const Color(0xFF94A3B8);
      default:
        return orange;
    }
  }
}

class _VisitorsPageState extends State<VisitorsPage> {
  _TabVisitante _tab = _TabVisitante.doDia;
  String _searchNome = '';
  Timer? _searchDebounce;

  void _scheduleSearchNome(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final next = raw.trim().toLowerCase();
      if (next == _searchNome) return;
      setState(() => _searchNome = next);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _webLoadCap?.cancel();
    super.dispose();
  }
  DateTime? _filtroData;
  int? _filtroDia;
  int? _filtroMes;
  int? _filtroAno;
  late Future<QuerySnapshot<Map<String, dynamic>>> _visitantesFuture;
  Timer? _webLoadCap;
  int _visitantesLoadGen = 0;
  bool _visitantesLoadPending = true;

  /// Doc operacional (slug/alias) — resolve em background sem bloquear a lista.
  String _effectiveTenantId = '';

  /// Painel: lista filtrada ao tocar em Este mês / Novos / Acompanhamento / Convertidos.
  _VisitorKpiDrill _kpiDrill = _VisitorKpiDrill.none;

  /// Relatório: ano civil + mês opcional para totais e gráfico.
  int _reportYear = DateTime.now().year;
  int? _reportMonth;
  bool _reportExpanded = false;

  /// Seleção múltipla — excluir individual, selecionados ou todos.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _bulkDeleting = false;

  bool get _canManage => churchVisitorManagementRole(widget.role);

  String get _tid => _effectiveTenantId.isNotEmpty
      ? _effectiveTenantId
      : ChurchRepository.churchId(widget.tenantId);

  String get _churchId => ChurchRepository.churchId(_tid);

  CollectionReference<Map<String, dynamic>> get _visitantesRef =>
      ChurchUiCollections.visitantes(_churchId);

  CollectionReference<Map<String, dynamic>> get _membersRef =>
      ChurchUiCollections.membros(_churchId);

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisitantes({
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final tid = _tid.trim();
    if (tid.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }
    final result = await ChurchVisitantesLoadService.load(
      seedTenantId: _churchId,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
      fullList: forceRefresh || forceServer,
    );
    if (result.docs.isNotEmpty) {
      ChurchVisitantesLoadService.putRam(result.churchId, result.docs);
      unawaited(ChurchVisitantesLoadService.persistAfterLoad(result));
    }
    return result.snapshot;
  }

  QuerySnapshot<Map<String, dynamic>>? _peekInstantVisitantesSnap() {
    final cid = _churchId.trim();
    if (cid.isEmpty) return null;

    final moduleDocs = YahwehModuleCaches.visitantes.docs;
    if (moduleDocs.isNotEmpty) {
      final docs = moduleDocs
          .where((d) => d.id != ChurchVisitantesLoadService.kSchemaDocId)
          .toList();
      if (docs.isNotEmpty) {
        return MergedFirestoreQuerySnapshot(docs);
      }
    }

    final ram = ChurchVisitantesLoadService.peekRam(cid);
    if (ram != null) {
      return MergedFirestoreQuerySnapshot(ram);
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(
      ChurchVisitantesLoadService.cacheKey(
        cid,
        ChurchVisitantesLoadService.kDefaultLimit,
      ),
    );
    if (mem != null && mem.docs.isNotEmpty) {
      final docs = mem.docs
          .where((d) => d.id != ChurchVisitantesLoadService.kSchemaDocId)
          .toList();
      if (docs.isNotEmpty) return MergedFirestoreQuerySnapshot(docs);
    }
    return null;
  }

  void _startWebLoadingCap() {
    if (!kIsWeb) return;
    _webLoadCap?.cancel();
    _webLoadCap = Timer(const Duration(seconds: 14), () {
      if (!mounted || !_visitantesLoadPending) return;
      final fallback = _peekInstantVisitantesSnap();
      setState(() {
        _visitantesLoadPending = false;
        _visitantesFuture = Future.value(
          fallback ?? const MergedFirestoreQuerySnapshot([]),
        );
      });
      _scheduleVisitantesRetry();
    });
  }

  void _scheduleVisitantesRetry() {
    final gen = ++_visitantesLoadGen;
    for (final delay in const [2, 6, 14]) {
      Future<void>.delayed(Duration(seconds: delay), () async {
        if (!mounted || gen != _visitantesLoadGen) return;
        await _refreshVisitantesBackground(forceRefresh: delay >= 6);
      });
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadVisitantesWithCap({
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    try {
      final snap = await _loadVisitantes(
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      return snap;
    } catch (e) {
      final fallback = _peekInstantVisitantesSnap();
      if (fallback != null) return fallback;
      return const MergedFirestoreQuerySnapshot([]);
    } finally {
      if (mounted) {
        _webLoadCap?.cancel();
        _visitantesLoadPending = false;
      }
    }
  }

  Future<void> _refreshVisitantesBackground({bool forceRefresh = false}) async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await _loadVisitantesWithCap(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _visitantesFuture = Future.value(snap));
    } catch (_) {}
  }

  void _refresh() {
    _visitantesLoadGen++;
    _visitantesLoadPending = true;
    _startWebLoadingCap();
    setState(() {
      _visitantesFuture = _loadVisitantesWithCap(
        forceRefresh: true,
        forceServer: !kIsWeb,
      );
    });
  }

  Future<void> _tryIndexedDbCacheFirst() async {
    if (_peekInstantVisitantesSnap() != null) return;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final cacheSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchUiCollections.visitantes(_churchId)
            .limit(ChurchVisitantesLoadService.kDefaultLimit)
            .get(const GetOptions(source: Source.cache)),
        maxAttempts: 3,
      ).timeout(const Duration(seconds: 3));
      final docs = cacheSnap.docs
          .where((d) => d.id != ChurchVisitantesLoadService.kSchemaDocId)
          .toList();
      if (docs.isEmpty || !mounted || !_visitantesLoadPending) return;
      setState(() {
        _visitantesFuture = Future.value(MergedFirestoreQuerySnapshot(docs));
        _visitantesLoadPending = false;
      });
      _webLoadCap?.cancel();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _effectiveTenantId = ChurchRepository.churchId(widget.tenantId).trim();
    unawaited(YahwehModuleCaches.visitantes.warmUp(_churchId));
    final instant = _peekInstantVisitantesSnap();
    if (instant != null) {
      _visitantesFuture = Future.value(instant);
      _visitantesLoadPending = false;
      unawaited(_refreshVisitantesBackground());
    } else {
      _visitantesFuture = _loadVisitantesWithCap();
      unawaited(_tryIndexedDbCacheFirst());
      unawaited(YahwehModuleCaches.visitantes.ensureLoaded(_churchId));
    }
    _startWebLoadingCap();
  }

  @override
  void didUpdateWidget(covariant VisitorsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _visitantesLoadGen++;
      _effectiveTenantId = ChurchRepository.churchId(widget.tenantId).trim();
      unawaited(YahwehModuleCaches.visitantes.warmUp(_churchId));
      _visitantesLoadPending = true;
      final instant = _peekInstantVisitantesSnap();
      if (instant != null) {
        _visitantesFuture = Future.value(instant);
        _visitantesLoadPending = false;
        unawaited(_refreshVisitantesBackground());
      } else {
        _visitantesFuture = _loadVisitantesWithCap();
        unawaited(_tryIndexedDbCacheFirst());
        unawaited(YahwehModuleCaches.visitantes.ensureLoaded(_churchId));
      }
      _startWebLoadingCap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final tt = Theme.of(context).textTheme;

    final showAppBar = !isMobile || Navigator.canPop(context);
    return Scaffold(
      appBar: !showAppBar
          ? null
          : AppBar(
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              title: Text(_selectionMode
                  ? '${_selectedIds.length} selecionado(s)'
                  : 'Visitantes / Primeiro Contato'),
              actions: [
                if (_canManage && _selectionMode) ...[
                  TextButton(
                    onPressed: _bulkDeleting ? null : _exitSelectionMode,
                    child: const Text('Cancelar'),
                  ),
                ] else if (_canManage) ...[
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: ThemeCleanPremium.primary),
                    tooltip: 'Mais opções',
                    onSelected: (v) {
                      if (v == 'select') {
                        setState(() => _selectionMode = true);
                      } else if (v == 'delete_all') {
                        _confirmDeleteAll(context);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'select',
                        child: Row(
                          children: [
                            Icon(Icons.checklist_rounded, size: 20),
                            SizedBox(width: 10),
                            Text('Selecionar vários'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_rounded,
                                size: 20, color: ThemeCleanPremium.error),
                            SizedBox(width: 10),
                            Text('Excluir todos',
                                style: TextStyle(color: ThemeCleanPremium.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (!_selectionMode)
                  IconButton(
                    icon: Icon(Icons.refresh_rounded,
                        color: ThemeCleanPremium.primary),
                    onPressed: _refresh,
                    tooltip: 'Atualizar',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ThemeCleanPremium.primary,
                      elevation: 1,
                      shadowColor: Colors.black26,
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _canManage && !_selectionMode
          ? Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg),
                gradient: _VisitorsPremiumTheme.heroGradient,
                boxShadow: [
                  BoxShadow(
                    color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.42),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  ...ThemeCleanPremium.softUiCardShadow,
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () => _openVisitorForm(context),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Novo Visitante',
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
        child: ResilientPanelQueryFutureBuilder(
          future: _visitantesFuture,
          errorTitle: 'Não foi possível carregar os visitantes',
          onRetry: _refresh,
          builder: (context, snap, {required bool showingStaleCache}) {
            final allDocs = snap.docs.where((d) => d.id != '_schema').toList();
            final allVisitors = allDocs
                .map((d) => _VisitorData(id: d.id, data: d.data()))
                .toList();

            final filtered = _filteredVisitors(allVisitors);

            return RefreshIndicator(
              color: _VisitorsPremiumTheme.orange,
              onRefresh: () async => _refresh(),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: ThemeCleanPremium.pagePadding(context),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (showingStaleCache) ...[
                          const ChurchPanelOfflineStaleBanner(
                            message:
                                'Exibindo últimos visitantes guardados — puxe para atualizar.',
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                        ],
                        if (_kpiDrill == _VisitorKpiDrill.none) ...[
                          _VisitorsHeroHeader(
                            totalCount: allVisitors.length,
                            novosHoje: allVisitors.where((v) {
                              final d = v.createdAt;
                              if (d == null) return true;
                              final now = DateTime.now();
                              return d.year == now.year &&
                                  d.month == now.month &&
                                  d.day == now.day;
                            }).length,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          if (isMobile && !widget.embeddedInShell) ...[
                            Text(
                              'Visitantes',
                              style: tt.headlineMedium?.copyWith(
                                color: ThemeCleanPremium.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceLg),
                          ],
                          _SummaryCards(
                            visitors: allVisitors,
                            isMobile: isMobile,
                            selectedDrill: _kpiDrill,
                            onDrillTap: (d) {
                              setState(() {
                                _kpiDrill = d;
                                _selectionMode = false;
                                _selectedIds.clear();
                              });
                            },
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          _buildTabBar(context),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          if (_tab == _TabVisitante.historico) ...[
                            _buildFiltrosHistorico(context, tt),
                            const SizedBox(height: ThemeCleanPremium.spaceSm),
                          ] else ...[
                            _buildSearchField(tt),
                            const SizedBox(height: ThemeCleanPremium.spaceSm),
                          ],
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          _VisitorsListHeader(
                            tab: _tab,
                            count: filtered.length,
                            totalHoje: allVisitors.where((v) {
                              final d = v.createdAt;
                              if (d == null) return true;
                              final now = DateTime.now();
                              return d.year == now.year &&
                                  d.month == now.month &&
                                  d.day == now.day;
                            }).length,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                        ] else ...[
                          _KpiDrillHeader(
                            drill: _kpiDrill,
                            count: filtered.length,
                            onClose: () => setState(() {
                              _kpiDrill = _VisitorKpiDrill.none;
                              _selectionMode = false;
                              _selectedIds.clear();
                            }),
                            onSelectAll: _canManage
                                ? () {
                                    setState(() => _selectionMode = true);
                                    unawaited(_selectAllVisible());
                                  }
                                : null,
                            onEnterSelection: _canManage
                                ? () => setState(() => _selectionMode = true)
                                : null,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          _buildSearchField(tt),
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                        ],
                      ]),
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ThemeCleanPremium.isNarrow(context)
                              ? ThemeCleanPremium.spaceSm
                              : ThemeCleanPremium.spaceLg,
                          vertical: ThemeCleanPremium.spaceLg,
                        ),
                        child: _buildEmptyState(tt),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ThemeCleanPremium.isNarrow(context)
                            ? ThemeCleanPremium.spaceSm
                            : ThemeCleanPremium.spaceLg,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final v = filtered[i];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: i == filtered.length - 1
                                    ? 8
                                    : ThemeCleanPremium.spaceSm,
                              ),
                              child: _VisitorModernRow(
                                visitor: v,
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(v.id),
                                canManage: _canManage,
                                onSelectionChanged: _selectionMode
                                    ? (sel) => setState(() {
                                          if (sel) {
                                            _selectedIds.add(v.id);
                                          } else {
                                            _selectedIds.remove(v.id);
                                          }
                                        })
                                    : null,
                                onTap: () {
                                  if (_selectionMode) {
                                    setState(() {
                                      if (_selectedIds.contains(v.id)) {
                                        _selectedIds.remove(v.id);
                                      } else {
                                        _selectedIds.add(v.id);
                                      }
                                    });
                                  } else {
                                    _openVisitorDetails(context, v);
                                  }
                                },
                                onEdit: () =>
                                    _openVisitorForm(context, visitor: v),
                                onDelete: () => _confirmDelete(context, v),
                              ),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                  if (_kpiDrill == _VisitorKpiDrill.none)
                  SliverPadding(
                    padding: ThemeCleanPremium.pagePadding(context),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: ThemeCleanPremium.spaceLg),
                        _VisitorsReportPanel(
                          visitors: allVisitors,
                          year: _reportYear,
                          month: _reportMonth,
                          expanded: _reportExpanded,
                          onToggleExpanded: () => setState(
                              () => _reportExpanded = !_reportExpanded),
                          onYearChanged: (y) => setState(() {
                            _reportYear = y;
                          }),
                          onMonthChanged: (m) =>
                              setState(() => _reportMonth = m),
                        ),
                        const SizedBox(height: 80),
                      ]),
                    ),
                  )
                  else
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _canManage && _selectionMode
          ? _buildSelectionBar()
          : null,
    );
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Widget _buildSelectionBar() {
    return Material(
      elevation: 12,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              TextButton(
                onPressed: _bulkDeleting
                    ? null
                    : () => setState(() => _selectedIds.clear()),
                child: const Text('Limpar'),
              ),
              Expanded(
                child: Text(
                  '${_selectedIds.length} selecionado(s)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _bulkDeleting ? null : _selectAllVisible,
                child: const Text('Selecionar todos'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _bulkDeleting || _selectedIds.isEmpty
                    ? null
                    : () => _confirmDeleteSelected(context),
                icon: _bulkDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Excluir'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAllVisible() async {
    final snap = await _visitantesFuture;
    if (!mounted) return;
    final all = snap.docs
        .where((d) => d.id != '_schema')
        .map((d) => _VisitorData(id: d.id, data: d.data()))
        .toList();
    final filtered = _filteredVisitors(all);
    setState(() {
      _selectedIds.addAll(filtered.map((v) => v.id));
    });
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    final n = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Excluir selecionados?'),
        content: Text(
          'Deseja excluir $n visitante(s)? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _runBulkDelete(_selectedIds.toList());
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final snap = await _visitantesFuture;
    final ids = snap.docs
        .where((d) => d.id != '_schema')
        .map((d) => d.id)
        .toList();
    if (ids.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum visitante para excluir.')),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Excluir TODOS os visitantes?'),
        content: Text(
          'Serão apagados ${ids.length} cadastro(s) de visitantes. '
          'Esta ação é irreversível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir todos'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _runBulkDelete(ids);
  }

  Future<void> _runBulkDelete(List<String> ids) async {
    setState(() => _bulkDeleting = true);
    try {
      final n = await ChurchVisitantesLoadService.deleteVisitors(
        seedTenantId: widget.tenantId,
        docIds: ids,
      );
      if (!mounted) return;
      _exitSelectionMode();
      _refreshVisitantesBackground();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? 'Visitante excluído' : '$n visitantes excluídos',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(
          color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.12),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _VisitorTabChip(
              selected: _tab == _TabVisitante.doDia,
              icon: Icons.wb_sunny_rounded,
              label: 'Do Dia',
              gradient: _VisitorsPremiumTheme.heroGradient,
              onTap: () => setState(() => _tab = _TabVisitante.doDia),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _VisitorTabChip(
              selected: _tab == _TabVisitante.historico,
              icon: Icons.history_rounded,
              label: 'Histórico',
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
              ),
              onTap: () => setState(() => _tab = _TabVisitante.historico),
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _mesesAbr = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  static String _mesAbr(int month) => month >= 1 && month <= 12 ? _mesesAbr[month - 1] : '$month';

  Widget _buildFiltrosHistorico(BuildContext context, TextTheme tt) {
    final now = DateTime.now();
    return Wrap(
      spacing: ThemeCleanPremium.spaceXs,
      runSpacing: ThemeCleanPremium.spaceXs,
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            onChanged: _scheduleSearchNome,
            decoration: InputDecoration(
              hintText: 'Buscar por nome',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _filtroData ?? now, firstDate: DateTime(2020), lastDate: now);
            if (d != null) setState(() { _filtroData = d; });
          },
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: Text(_filtroData != null ? '${_filtroData!.day.toString().padLeft(2,'0')}/${_filtroData!.month.toString().padLeft(2,'0')}/${_filtroData!.year}' : 'Data'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroDia,
          decoration: InputDecoration(
            labelText: 'Dia',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(31, (i) => DropdownMenuItem<int?>(value: i + 1, child: Text('${i + 1}')))],
          onChanged: (v) => setState(() => _filtroDia = v),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroMes,
          decoration: InputDecoration(
            labelText: 'Mês',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(12, (i) => DropdownMenuItem<int?>(value: i + 1, child: Text(_mesAbr(i + 1))))],
          onChanged: (v) => setState(() => _filtroMes = v),
        ),
        DropdownButtonFormField<int?>(
          value: _filtroAno,
          decoration: InputDecoration(
            labelText: 'Ano',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          ),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos')), ...List.generate(now.year - 2019, (i) => DropdownMenuItem<int?>(value: 2020 + i, child: Text('${2020 + i}')))],
          onChanged: (v) => setState(() => _filtroAno = v),
        ),
        if (_filtroData != null || _filtroDia != null || _filtroMes != null || _filtroAno != null)
          TextButton.icon(
            onPressed: () => setState(() { _filtroData = null; _filtroDia = null; _filtroMes = null; _filtroAno = null; }),
            icon: const Icon(Icons.clear_rounded, size: 18),
            label: const Text('Limpar'),
          ),
      ],
    );
  }

  Widget _buildSearchField(TextTheme tt) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: TextField(
        onChanged: _scheduleSearchNome,
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou telefone…',
          prefixIcon: const Icon(Icons.search_rounded, color: ThemeCleanPremium.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            borderSide: const BorderSide(color: ThemeCleanPremium.primaryLight, width: 2),
          ),
          filled: true,
          fillColor: ThemeCleanPremium.cardBackground,
        ),
      ),
    );
  }

  Widget _buildEmptyState(TextTheme tt) {
    final hasFilters = _searchNome.isNotEmpty || _filtroData != null || _filtroDia != null || _filtroMes != null || _filtroAno != null;
    final hasKpi = _kpiDrill != _VisitorKpiDrill.none;
    String title;
    if (hasKpi) {
      title = 'Nenhum visitante neste indicador';
    } else if (hasFilters) {
      title = 'Nenhum visitante encontrado';
    } else {
      title = _tab == _TabVisitante.doDia
          ? 'Nenhum visitante hoje'
          : 'Nenhum visitante no histórico';
    }
    String subtitle;
    if (hasKpi) {
      subtitle = 'Toque no cabeçalho azul para voltar ao painel completo.';
    } else if (hasFilters) {
      subtitle = 'Tente outro filtro';
    } else {
      subtitle = _tab == _TabVisitante.doDia
          ? 'Cadastros do culto aparecem aqui'
          : 'Adicione o primeiro visitante com o botão +';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _VisitorsPremiumTheme.orange.withValues(alpha: 0.14),
                    _VisitorsPremiumTheme.amber.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.handshake_rounded,
                size: 56,
                color: _VisitorsPremiumTheme.deepOrange.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(
                color: ThemeCleanPremium.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
            ),
            if (_canManage && !hasFilters && !hasKpi) ...[
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              FilledButton.icon(
                onPressed: () => _openVisitorForm(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _VisitorsPremiumTheme.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Cadastrar primeiro visitante'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_VisitorData> _applyFilters(List<_VisitorData> all) {
    var result = all;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    if (_tab == _TabVisitante.doDia) {
      // Sem data (Timestamp ainda a sincronizar) → mostra no dia para não “sumir”.
      result = result.where((v) {
        final d = v.createdAt;
        if (d == null) return true;
        return !d.isBefore(startOfToday) && d.isBefore(endOfToday);
      }).toList();
    } else {
      result = result.where((v) {
        final d = v.createdAt;
        return d != null && d.isBefore(startOfToday);
      }).toList();
    }

    if (_searchNome.isNotEmpty) {
      result = result.where((v) {
        final name = (v.data['nome'] ?? '').toString().toLowerCase();
        final phone = (v.data['telefone'] ?? '').toString().toLowerCase();
        return name.contains(_searchNome) || phone.contains(_searchNome);
      }).toList();
    }

    if (_tab == _TabVisitante.historico) {
      if (_filtroData != null) {
        final s = DateTime(_filtroData!.year, _filtroData!.month, _filtroData!.day);
        final e = s.add(const Duration(days: 1));
        result = result.where((v) {
          final d = v.createdAt;
          return d != null && !d.isBefore(s) && d.isBefore(e);
        }).toList();
      }
      if (_filtroDia != null) {
        result = result.where((v) => (v.createdAt?.day ?? 0) == _filtroDia).toList();
      }
      if (_filtroMes != null) {
        result = result.where((v) => (v.createdAt?.month ?? 0) == _filtroMes).toList();
      }
      if (_filtroAno != null) {
        result = result.where((v) => (v.createdAt?.year ?? 0) == _filtroAno).toList();
      }
    }

    return result;
  }

  /// Lista principal: com filtro KPI (cartões) ignora aba Dia/Histórico — alinhado aos totais.
  List<_VisitorData> _filteredVisitors(List<_VisitorData> all) {
    if (_kpiDrill != _VisitorKpiDrill.none) {
      var result =
          all.where((v) => _visitorMatchesKpiDrill(v, _kpiDrill)).toList();
      if (_searchNome.isNotEmpty) {
        result = result.where((v) {
          final name = (v.data['nome'] ?? '').toString().toLowerCase();
          final phone = (v.data['telefone'] ?? '').toString().toLowerCase();
          return name.contains(_searchNome) || phone.contains(_searchNome);
        }).toList();
      }
      return result;
    }
    return _applyFilters(all);
  }

  // ─── Cadastro / Edição ──────────────────────────────────────────────────────
  void _openVisitorForm(BuildContext context, {_VisitorData? visitor}) {
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: ThemeCleanPremium.isMobile(context),
        builder: (_) => _VisitorFormPage(
          churchId: _churchId,
          visitor: visitor,
        ),
      ),
    )
        .then((saved) {
      if (!mounted || saved != true) return;
      // saveVisitor já inseriu no RAM — pinta na hora; sync em background.
      final instant = _peekInstantVisitantesSnap();
      if (instant != null) {
        setState(() {
          _visitantesLoadPending = false;
          _visitantesFuture = Future.value(instant);
        });
      }
      unawaited(_refreshVisitantesBackground(forceRefresh: true));
    });
  }

  // ─── Detalhes ───────────────────────────────────────────────────────────────
  void _openVisitorDetails(BuildContext context, _VisitorData visitor) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _VisitorDetailsPage(
            tenantId: widget.tenantId,
            visitor: visitor,
            canManage: _canManage,
            canConvertVisitor: AppPermissions.canConvertVisitorToMember(widget.role),
            membersRef: _membersRef,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: _VisitorDetailsPage(
              tenantId: widget.tenantId,
              visitor: visitor,
              canManage: _canManage,
              canConvertVisitor: AppPermissions.canConvertVisitorToMember(widget.role),
              membersRef: _membersRef,
              isDialog: true,
            ),
          ),
        ),
      );
    }
  }

  // ─── Excluir ────────────────────────────────────────────────────────────────
  Future<void> _confirmDelete(BuildContext context, _VisitorData visitor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Excluir visitante?'),
        content: Text('Deseja excluir "${visitor.nome}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ChurchVisitantesLoadService.deleteVisitors(
          seedTenantId: widget.tenantId,
          docIds: [visitor.id],
        );
        if (context.mounted) {
          _refreshVisitantesBackground();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Visitante excluído',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir: $e'),
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorData {
  final String id;
  final Map<String, dynamic> data;

  _VisitorData({required this.id, required this.data});

  String get nome => (data['nome'] ?? '').toString();
  String get telefone => (data['telefone'] ?? '').toString();
  String get email => (data['email'] ?? '').toString();
  String get status => (data['status'] ?? 'Novo').toString();
  String get comoConheceu => (data['comoConheceu'] ?? '').toString();
  String get observacoes => (data['observacoes'] ?? '').toString();
  int get followupCount => (data['followupCount'] ?? 0) as int;

  DateTime? get createdAt =>
      ChurchVisitantesLoadService.parseVisitorInstant(data['createdAt']) ??
      ChurchVisitantesLoadService.parseVisitorInstant(data['updatedAt']);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Summary Cards
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// Hero + tabs premium
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorsHeroHeader extends StatelessWidget {
  const _VisitorsHeroHeader({
    required this.totalCount,
    required this.novosHoje,
  });

  final int totalCount;
  final int novosHoje;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: _VisitorsPremiumTheme.heroGradient,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: ThemeCleanPremium.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Primeiro Contato',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Acompanhe visitantes, follow-ups e conversões',
                  style: tt.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalCount',
                style: tt.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                novosHoje > 0 ? '+$novosHoje hoje' : 'total',
                style: tt.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisitorsListHeader extends StatelessWidget {
  const _VisitorsListHeader({
    required this.tab,
    required this.count,
    required this.totalHoje,
  });

  final _TabVisitante tab;
  final int count;
  final int totalHoje;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDia = tab == _TabVisitante.doDia;
    final title = isDia ? 'Visitantes de hoje' : 'Histórico';
    final qtyLabel = isDia
        ? (totalHoje == 1 ? '1 no dia' : '$totalHoje no dia')
        : (count == 1 ? '1 visitante' : '$count visitantes');

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isDia
                    ? 'Nomes cadastrados neste dia'
                    : 'Registros anteriores',
                style: tt.bodySmall?.copyWith(
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: isDia ? _VisitorsPremiumTheme.heroGradient : null,
            color: isDia ? null : ThemeCleanPremium.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isDia
                ? [
                    BoxShadow(
                      color:
                          _VisitorsPremiumTheme.orange.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            qtyLabel,
            style: tt.labelLarge?.copyWith(
              color: isDia ? Colors.white : ThemeCleanPremium.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _VisitorModernRow extends StatelessWidget {
  const _VisitorModernRow({
    required this.visitor,
    required this.selectionMode,
    required this.selected,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onSelectionChanged,
  });

  final _VisitorData visitor;
  final bool selectionMode;
  final bool selected;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = _VisitorsPremiumTheme.statusAccent(visitor.status);
    final nome = visitor.nome.trim().isEmpty ? 'Sem nome' : visitor.nome.trim();
    final initial = nome.isNotEmpty ? nome[0].toUpperCase() : '?';
    final phone = visitor.telefone.trim();
    final narrow = ThemeCleanPremium.isNarrow(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            border: Border.all(
              color: selected
                  ? _VisitorsPremiumTheme.orange
                  : accent.withValues(alpha: 0.28),
              width: selected ? 1.8 : 1,
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (selectionMode) ...[
                      Checkbox(
                        value: selected,
                        activeColor: _VisitorsPremiumTheme.orange,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onChanged: onSelectionChanged == null
                            ? null
                            : (v) => onSelectionChanged!(v ?? false),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: accent.withValues(alpha: 0.18),
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  visitor.status,
                                  style: tt.labelSmall?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (phone.isNotEmpty)
                                Text(
                                  brPhoneMaskLive(phone),
                                  style: tt.labelSmall?.copyWith(
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              else
                                Text(
                                  _VisitorCard._formatDate(visitor.createdAt),
                                  style: tt.labelSmall?.copyWith(
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!selectionMode && canManage && !narrow) ...[
                      IconButton(
                        tooltip: 'Editar',
                        onPressed: onEdit,
                        icon: Icon(Icons.edit_rounded,
                            color: ThemeCleanPremium.primary),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: ThemeCleanPremium.error),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                    ],
                    if (phone.isNotEmpty && !selectionMode)
                      IconButton(
                        tooltip: 'WhatsApp',
                        onPressed: () => launchWhatsAppContact(phone),
                        icon: const WhatsappBrandIcon(
                            size: 22, color: Color(0xFF25D366)),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                      ),
                  ],
                ),
                if (!selectionMode && canManage && narrow) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Editar'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          foregroundColor: ThemeCleanPremium.primary,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Excluir'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          foregroundColor: ThemeCleanPremium.error,
                          side: const BorderSide(color: ThemeCleanPremium.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitorTabChip extends StatelessWidget {
  const _VisitorTabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: selected ? gradient : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
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
// Summary Cards
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryCards extends StatelessWidget {
  final List<_VisitorData> visitors;
  final bool isMobile;
  final _VisitorKpiDrill selectedDrill;
  final void Function(_VisitorKpiDrill drill) onDrillTap;

  const _SummaryCards({
    required this.visitors,
    required this.isMobile,
    required this.selectedDrill,
    required this.onDrillTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));

    final thisMonth = visitors.where((v) {
      final d = v.createdAt;
      return d != null && d.isAfter(startOfMonth);
    }).length;

    final thisWeekNew = visitors.where((v) {
      final d = v.createdAt;
      return d != null && d.isAfter(startOfWeek) && v.status == 'Novo';
    }).length;

    final accompanying =
        visitors.where((v) => v.status == 'Em acompanhamento').length;
    final converted = visitors.where((v) => v.status == 'Convertido').length;

    final cards = <(_SummaryCardData, _VisitorKpiDrill)>[
      (
        _SummaryCardData('Este Mês', '$thisMonth', Icons.calendar_month_rounded,
            const Color(0xFF3B82F6)),
        _VisitorKpiDrill.esteMes
      ),
      (
        _SummaryCardData('Novos (Semana)', '$thisWeekNew',
            Icons.fiber_new_rounded, const Color(0xFF8B5CF6)),
        _VisitorKpiDrill.novosSemana
      ),
      (
        _SummaryCardData('Acompanhamento', '$accompanying',
            Icons.support_agent_rounded, const Color(0xFFF59E0B)),
        _VisitorKpiDrill.acompanhamento
      ),
      (
        _SummaryCardData('Convertidos', '$converted', Icons.verified_rounded,
            const Color(0xFF16A34A)),
        _VisitorKpiDrill.convertidos
      ),
    ];

    if (isMobile) {
      return SizedBox(
        height: 122,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: ThemeCleanPremium.spaceSm),
          itemBuilder: (_, i) => SizedBox(
            width: 164,
            child: _buildCard(context, cards[i].$1, cards[i].$2),
          ),
        ),
      );
    }

    return Wrap(
      spacing: ThemeCleanPremium.spaceMd,
      runSpacing: ThemeCleanPremium.spaceMd,
      children: cards
          .map((e) => SizedBox(
                width: 200,
                child: _buildCard(context, e.$1, e.$2),
              ))
          .toList(),
    );
  }

  Widget _buildCard(
      BuildContext context, _SummaryCardData c, _VisitorKpiDrill drill) {
    final selected = selectedDrill == drill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onDrillTap(drill),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.color.withValues(alpha: selected ? 0.22 : 0.12),
                ThemeCleanPremium.cardBackground,
              ],
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(
              color: selected
                  ? c.color.withValues(alpha: 0.65)
                  : c.color.withValues(alpha: 0.18),
              width: selected ? 2.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.color.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                    ...ThemeCleanPremium.softUiCardShadow,
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: c.color.withValues(alpha: 0.38)),
                    ),
                    child: Icon(c.icon, color: c.color, size: 22),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.touch_app_rounded,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Text(
                c.value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurface,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                c.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeCleanPremium.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCardData(this.label, this.value, this.icon, this.color);
}

/// Cabeçalho do filtro ao tocar num cartão KPI — Retornar + seleção em massa.
class _KpiDrillHeader extends StatelessWidget {
  final _VisitorKpiDrill drill;
  final int count;
  final VoidCallback onClose;
  final VoidCallback? onSelectAll;
  final VoidCallback? onEnterSelection;

  const _KpiDrillHeader({
    required this.drill,
    required this.count,
    required this.onClose,
    this.onSelectAll,
    this.onEnterSelection,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF0F172A), 0.22)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.white.withValues(alpha: 0.14),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onClose,
                  tooltip: 'Retornar',
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kpiDrillTitle(drill),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$count ${count == 1 ? "visitante" : "visitantes"} · linhas modernas com editar e excluir',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text(
                'Retornar',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
          if (onSelectAll != null || onEnterSelection != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onEnterSelection != null)
                  OutlinedButton.icon(
                    onPressed: onEnterSelection,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: const Text('Selecionar'),
                  ),
                if (onSelectAll != null)
                  OutlinedButton.icon(
                    onPressed: onSelectAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.select_all_rounded, size: 18),
                    label: const Text('Selecionar todos'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Relatório por ano/mês e gráfico de barras (cadastros por mês).
class _VisitorsReportPanel extends StatelessWidget {
  final List<_VisitorData> visitors;
  final int year;
  final int? month;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<int?> onMonthChanged;

  const _VisitorsReportPanel({
    required this.visitors,
    required this.year,
    required this.month,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final years = List<int>.generate(now.year - 2019, (i) => 2020 + i);
    final monthCounts = List<int>.filled(12, 0);
    for (final v in visitors) {
      final d = v.createdAt;
      if (d == null) continue;
      if (d.year != year) continue;
      monthCounts[d.month - 1]++;
    }
    final totalYear = monthCounts.fold<int>(0, (a, b) => a + b);
    final int totalPeriod = (month != null && month! >= 1 && month! <= 12)
        ? monthCounts[month! - 1]
        : totalYear;

    final maxY = monthCounts.fold<int>(1, (a, b) => a > b ? a : b);
    final maxChart = (maxY * 1.2).ceil().clamp(1, 99999).toDouble();

    const meses = ['J','F','M','A','M','J','J','A','S','O','N','D'];

    return Material(
      color: ThemeCleanPremium.cardBackground,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.insights_rounded,
                        color: ThemeCleanPremium.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Relatório & evolução',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        Text(
                          'Por ano e mês · gráfico de cadastros',
                          style: tt.bodySmall?.copyWith(
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      value: year,
                      decoration: InputDecoration(
                        labelText: 'Ano',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                        ),
                      ),
                      items: years
                          .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                          .toList(),
                      onChanged: (y) {
                        if (y != null) onYearChanged(y);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int?>(
                      value: month,
                      decoration: InputDecoration(
                        labelText: 'Mês',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('Todos')),
                        ...List.generate(
                          12,
                          (i) => DropdownMenuItem<int?>(
                            value: i + 1,
                            child: Text(_mesAbrPt(i + 1)),
                          ),
                        ),
                      ],
                      onChanged: onMonthChanged,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Total no período: ',
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$totalPeriod',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                  Text(
                    month != null
                        ? ' (${_mesAbrPt(month!)}/$year)'
                        : ' ($year)',
                    style: tt.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Container(
                height: 200,
                padding: const EdgeInsets.only(
                    right: 8, top: 8, left: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxChart,
                    barTouchData: BarTouchData(enabled: true),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxChart > 5 ? maxChart / 5 : 1,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFFE2E8F0),
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= 12) {
                              return const SizedBox.shrink();
                            }
                            final highlight = month != null && month == i + 1;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                meses[i],
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: highlight
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: highlight
                                      ? ThemeCleanPremium.primary
                                      : Colors.grey.shade600,
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
                          getTitlesWidget: (v, meta) => Text(
                            v.toInt().toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < 12; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: monthCounts[i].toDouble(),
                              color: month != null && month == i + 1
                                  ? ThemeCleanPremium.primary
                                  : Color.lerp(
                                      ThemeCleanPremium.primary,
                                      const Color(0xFF94A3B8),
                                      0.45,
                                    )!,
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Card
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorCard extends StatelessWidget {
  final _VisitorData visitor;
  final String tenantId;
  final bool canManage;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VisitorCard({
    required this.visitor,
    required this.tenantId,
    required this.canManage,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final badge = _statusBadge(visitor.status);
    final dateStr = _formatDate(visitor.createdAt);
    final accent = _VisitorsPremiumTheme.statusAccent(visitor.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  accent.withValues(alpha: 0.08),
                  ThemeCleanPremium.cardBackground,
                ],
                stops: const [0.0, 0.35],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                    child: Row(
                      children: [
                        if (selectionMode) ...[
                          Checkbox(
                            value: selected,
                            activeColor: _VisitorsPremiumTheme.orange,
                            onChanged: onSelectionChanged == null
                                ? null
                                : (v) => onSelectionChanged!(v ?? false),
                          ),
                          const SizedBox(width: 4),
                        ],
                        _avatar(visitor.nome, accent),
                        const SizedBox(width: ThemeCleanPremium.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      visitor.nome,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: ThemeCleanPremium.spaceXs),
                                  badge,
                                ],
                              ),
                      const SizedBox(height: 4),
                      if (visitor.telefone.isNotEmpty)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_outlined, size: 14, color: ThemeCleanPremium.onSurfaceVariant),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    visitor.telefone.isEmpty
                                        ? ''
                                        : brPhoneMaskLive(visitor.telefone),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                            Material(
                              color: const Color(0xFF25D366),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () => launchWhatsAppContact(visitor.telefone),
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      WhatsappBrandIcon(size: 14, color: Colors.white),
                                      SizedBox(width: 5),
                                      Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (visitor.email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined, size: 14, color: ThemeCleanPremium.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                visitor.email,
                                style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: tt.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11),
                          ),
                          if (visitor.followupCount > 0) ...[
                            const SizedBox(width: ThemeCleanPremium.spaceSm),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primaryLight.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.forum_outlined, size: 12, color: ThemeCleanPremium.primaryLight),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${visitor.followupCount}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primaryLight),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (canManage && !selectionMode)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: ThemeCleanPremium.onSurfaceVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Editar')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: ThemeCleanPremium.error), SizedBox(width: 8), Text('Excluir', style: TextStyle(color: ThemeCleanPremium.error))])),
                    ],
                  ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String name, Color accent) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.45),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
    );
  }

  static Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Novo':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E40AF);
        break;
      case 'Em acompanhamento':
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFC2410C);
        break;
      case 'Convertido':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'Desistente':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Form — tela premium com voltar (Web / Android / iOS)
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorFormPage extends StatefulWidget {
  final String churchId;
  final _VisitorData? visitor;

  const _VisitorFormPage({
    required this.churchId,
    this.visitor,
  });

  @override
  State<_VisitorFormPage> createState() => _VisitorFormPageState();
}

class _VisitorFormPageState extends State<_VisitorFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _obsCtrl;
  String _comoConheceu = 'Convite';
  bool _saving = false;

  static const _origens = [
    'Convite',
    'Redes Sociais',
    'Passou na frente',
    'Outro',
  ];

  bool get _isEdit => widget.visitor != null;

  String get _pathLabel =>
      FirebasePaths.visitantes(widget.churchId.trim());

  @override
  void initState() {
    super.initState();
    final v = widget.visitor;
    _nomeCtrl = TextEditingController(text: v?.nome ?? '');
    _telCtrl = TextEditingController(
      text: v != null && v.telefone.trim().isNotEmpty
          ? brPhoneMaskLive(v.telefone)
          : '',
    );
    _emailCtrl = TextEditingController(text: v?.email ?? '');
    _obsCtrl = TextEditingController(text: v?.observacoes ?? '');
    if (v != null && _origens.contains(v.comoConheceu)) {
      _comoConheceu = v.comoConheceu;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _VisitorsPremiumTheme.orange),
      filled: true,
      fillColor: const Color(0xFFFFF7ED),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: BorderSide(
          color: _VisitorsPremiumTheme.orange.withValues(alpha: 0.18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        borderSide: const BorderSide(
          color: _VisitorsPremiumTheme.orange,
          width: 1.6,
        ),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: ThemeCleanPremium.spaceMd,
        vertical: maxLines > 1 ? ThemeCleanPremium.spaceMd : 14,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final churchId = widget.churchId.trim();
    if (churchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Igreja não identificada.')),
        );
      }
      setState(() => _saving = false);
      return;
    }

    final telMasked = brPhoneMaskLive(_telCtrl.text);
    final payload = <String, dynamic>{
      'nome': _nomeCtrl.text.trim(),
      'telefone': telMasked,
      'email': _emailCtrl.text.trim(),
      'comoConheceu': _comoConheceu,
      'observacoes': _obsCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await ChurchVisitantesLoadService.saveVisitor(
        churchId: churchId,
        payload: payload,
        existingDocId: _isEdit ? widget.visitor!.id : null,
      ).timeout(
        kIsWeb ? const Duration(seconds: 12) : const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Tempo esgotado ao salvar. Verifique a conexão e tente de novo.',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            _isEdit ? 'Visitante atualizado.' : 'Visitante cadastrado.',
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        final friendly = FirestoreWebGuard.isInternalAssertionError(e)
            ? 'Firestore instável na web. Aguarde 2 segundos e toque em Cadastrar novamente.'
            : (e is TimeoutException
                ? e.message
                : 'Erro ao salvar: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendly ?? 'Erro ao salvar.'),
            backgroundColor: ThemeCleanPremium.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isMobile = ThemeCleanPremium.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          style: IconButton.styleFrom(
            minimumSize: const Size(
              ThemeCleanPremium.minTouchTarget,
              ThemeCleanPremium.minTouchTarget,
            ),
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: _VisitorsPremiumTheme.heroGradient,
            boxShadow: [
              BoxShadow(
                color: Color(0x33F97316),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
        ),
        title: Text(
          _isEdit ? 'Editar visitante' : 'Novo visitante',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 560),
            child: SingleChildScrollView(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
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
                                  gradient: _VisitorsPremiumTheme.heroGradient,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: ThemeCleanPremium.spaceMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Primeiro contato',
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Registo em $_pathLabel',
                                      style: tt.bodySmall?.copyWith(
                                        color: ThemeCleanPremium.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          TextFormField(
                            controller: _nomeCtrl,
                            decoration: _fieldDecoration(
                              label: 'Nome *',
                              icon: Icons.person_outline_rounded,
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Informe o nome'
                                : null,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          TextFormField(
                            controller: _telCtrl,
                            decoration: _fieldDecoration(
                              label: 'Telefone / WhatsApp',
                              icon: Icons.phone_outlined,
                            ).copyWith(
                              hintText: '62 9.9170-5247',
                            ),
                            keyboardType: TextInputType.phone,
                            inputFormatters: const [
                              BrPhoneInputFormatter(),
                            ],
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: _fieldDecoration(
                              label: 'E-mail',
                              icon: Icons.email_outlined,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          DropdownButtonFormField<String>(
                            value: _comoConheceu,
                            decoration: _fieldDecoration(
                              label: 'Como conheceu a igreja',
                              icon: Icons.info_outline_rounded,
                            ),
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            items: _origens
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(o),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _comoConheceu = v);
                                    }
                                  },
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          TextFormField(
                            controller: _obsCtrl,
                            decoration: _fieldDecoration(
                              label: 'Observações',
                              icon: Icons.note_alt_outlined,
                              maxLines: 3,
                            ),
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        gradient: _VisitorsPremiumTheme.heroGradient,
                        boxShadow: [
                          BoxShadow(
                            color: _VisitorsPremiumTheme.orange
                                .withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: ThemeCleanPremium.minTouchTarget + 4,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusLg,
                              ),
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                            _isEdit
                                ? 'Salvar alterações'
                                : 'Cadastrar visitante',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
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
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Visitor Details Page (Full page mobile / Dialog desktop)
// ═══════════════════════════════════════════════════════════════════════════════

class _VisitorDetailsPage extends StatefulWidget {
  final String tenantId;
  final _VisitorData visitor;
  final bool canManage;
  /// Secretariado, gestor, pastor, tesoureiro, ADM — não o papel [membro].
  final bool canConvertVisitor;
  final CollectionReference<Map<String, dynamic>> membersRef;
  final bool isDialog;

  const _VisitorDetailsPage({
    required this.tenantId,
    required this.visitor,
    required this.canManage,
    required this.canConvertVisitor,
    required this.membersRef,
    this.isDialog = false,
  });

  @override
  State<_VisitorDetailsPage> createState() => _VisitorDetailsPageState();
}

class _VisitorDetailsPageState extends State<_VisitorDetailsPage> {
  late DocumentReference<Map<String, dynamic>> _visitorDoc;
  late CollectionReference<Map<String, dynamic>> _followupsRef;
  late Future<QuerySnapshot<Map<String, dynamic>>> _followupsFuture;

  Future<QuerySnapshot<Map<String, dynamic>>> _loadFollowups() async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    return FirestoreWebGuard.runWithWebRecovery(
      () => _followupsRef.orderBy('data', descending: true).get(),
      maxAttempts: 4,
    );
  }

  Future<void> _patchVisitorDoc(Map<String, dynamic> data) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => runFirestorePublishWithRecovery(
        () => _visitorDoc.update(data),
        maxAttempts: 4,
      ),
      maxAttempts: 4,
    );
  }

  @override
  void initState() {
    super.initState();
    _visitorDoc = ChurchUiCollections.visitantes(
      ChurchRepository.churchId(widget.tenantId),
    ).doc(widget.visitor.id);
    _followupsRef = _visitorDoc.collection('followups');
    _followupsFuture = _loadFollowups();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isMobile = ThemeCleanPremium.isMobile(context);

    final content = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _visitorDoc.watchSafe(),
      builder: (context, vSnap) {
        if (vSnap.hasError) {
          return Center(child: Text('Erro: ${vSnap.error}'));
        }
        if (vSnap.connectionState == ConnectionState.waiting && !vSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final vData = vSnap.data?.data();
        if (vData == null) {
          return const Center(child: Text('Visitante não encontrado'));
        }

        final current = _VisitorData(id: widget.visitor.id, data: vData);

        return SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoHeader(context, current, tt),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              if (widget.canManage) ...[
                _buildActionButtons(context, current),
                const SizedBox(height: ThemeCleanPremium.spaceLg),
              ],
              Text('Timeline de Follow-up', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildFollowupTimeline(context, tt),
            ],
          ),
        );
      },
    );

    if (widget.isDialog) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Scaffold(
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    ThemeCleanPremium.primary,
                    ThemeCleanPremium.primary.withValues(alpha: 0.88),
                    ThemeCleanPremium.primaryLight,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
            title: Text(widget.visitor.nome),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
              constraints: const BoxConstraints(minWidth: ThemeCleanPremium.minTouchTarget, minHeight: ThemeCleanPremium.minTouchTarget),
            ),
          ),
          body: content,
        ),
      );
    }

    return Scaffold(
      appBar: isMobile
          ? null
          : AppBar(title: Text(widget.visitor.nome)),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Padding(
                padding: const EdgeInsets.fromLTRB(ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceSm, ThemeCleanPremium.spaceSm, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                      constraints: const BoxConstraints(minWidth: ThemeCleanPremium.minTouchTarget, minHeight: ThemeCleanPremium.minTouchTarget),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceXs),
                    Expanded(
                      child: Text(
                        widget.visitor.nome,
                        style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => _addFollowup(context),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Follow-up'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildInfoHeader(BuildContext context, _VisitorData v, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.cardBackground,
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
            ThemeCleanPremium.cardBackground,
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
        ),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: ThemeCleanPremium.primaryLight.withValues(alpha: 0.14),
                child: Text(
                  v.nome.isNotEmpty ? v.nome[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ThemeCleanPremium.primary),
                ),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.nome, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    _VisitorCard._statusBadge(v.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          _infoRow(Icons.phone_outlined, 'Telefone', v.telefone.isEmpty ? '—' : brPhoneMaskLive(v.telefone)),
          _infoRow(Icons.email_outlined, 'E-mail', v.email.isEmpty ? '—' : v.email),
          _infoRow(Icons.info_outline_rounded, 'Como conheceu', v.comoConheceu.isEmpty ? '—' : v.comoConheceu),
          _infoRow(Icons.calendar_today_outlined, 'Primeiro contato', _VisitorCard._formatDate(v.createdAt)),
          if (v.observacoes.isNotEmpty)
            _infoRow(Icons.note_alt_outlined, 'Observações', v.observacoes),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ThemeCleanPremium.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurface))),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, _VisitorData v) {
    Widget waBtn() => Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF128C7E), Color(0xFF25D366)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              onTap: () => launchWhatsAppContact(v.telefone),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceMd,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const WhatsappBrandIcon(size: 20, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      'WhatsApp',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget outlinePremium({
      required VoidCallback onPressed,
      required IconData icon,
      required String label,
    }) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          gradient: LinearGradient(
            colors: [
              ThemeCleanPremium.primary.withValues(alpha: 0.08),
              ThemeCleanPremium.primary.withValues(alpha: 0.02),
            ],
          ),
          border: Border.all(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeCleanPremium.spaceMd,
                vertical: 14,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget convertBtn() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ThemeCleanPremium.success,
                ThemeCleanPremium.success.withValues(alpha: 0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.success.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              onTap: () => _convertToMember(context, v),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceMd,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Converter para Membro',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.telefone.isNotEmpty) ...[
          waBtn(),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
        ],
        outlinePremium(
          onPressed: () => _changeStatus(context, v),
          icon: Icons.swap_horiz_rounded,
          label: 'Alterar Status',
        ),
        if (widget.canConvertVisitor && v.status != 'Convertido') ...[
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          convertBtn(),
        ],
      ],
    );
  }

  Widget _buildFollowupTimeline(BuildContext context, TextTheme tt) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _followupsFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Erro ao carregar follow-ups: ${snap.error}', style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() { _followupsFuture = _loadFollowups(); }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.surfaceVariant,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            child: Column(
              children: [
                Icon(Icons.forum_outlined, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: ThemeCleanPremium.spaceSm),
                Text('Nenhum follow-up registrado', style: tt.bodyMedium?.copyWith(color: ThemeCleanPremium.onSurfaceVariant)),
              ],
            ),
          );
        }

        return Column(
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final isLast = i == docs.length - 1;
            return _FollowupTimelineItem(data: d, isLast: isLast);
          }),
        );
      },
    );
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  Future<void> _changeStatus(BuildContext context, _VisitorData v) async {
    const statuses = ['Novo', 'Em acompanhamento', 'Convertido', 'Desistente'];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary,
                      ThemeCleanPremium.primaryLight,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(ThemeCleanPremium.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: Colors.white.withValues(alpha: 0.95), size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Alterar Status',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Column(
                  children: statuses.map((s) {
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      onTap: () => Navigator.pop(ctx, s),
                      leading: _VisitorCard._statusBadge(s),
                      trailing: s == v.status
                          ? const Icon(Icons.check_rounded, color: ThemeCleanPremium.primary)
                          : null,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != v.status && context.mounted) {
      await _patchVisitorDoc({
        'status': picked,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _convertToMember(BuildContext context, _VisitorData v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        contentPadding: EdgeInsets.zero,
        titlePadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ThemeCleanPremium.success,
                ThemeCleanPremium.success.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ThemeCleanPremium.radiusLg),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Converter para Membro',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            'Deseja converter "${v.nome}" em membro da igreja?',
            style: Theme.of(ctx).textTheme.bodyLarge,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Converter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await widget.membersRef.add({
        'nome': v.nome,
        'telefone': v.telefone,
        'email': v.email,
        'status': 'ativo',
        'origemVisitante': true,
        'visitanteId': v.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _patchVisitorDoc({
        'status': 'Convertido',
        'convertedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visitante convertido para membro com sucesso!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  Future<void> _addFollowup(BuildContext context) async {
    final tipoCtrl = ValueNotifier<String>('Ligação');
    final notasCtrl = TextEditingController();
    final responsavelCtrl = TextEditingController();
    const tipos = ['Ligação', 'WhatsApp', 'Visita', 'Outro'];

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(ThemeCleanPremium.radiusLg)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('Novo Follow-up', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              ValueListenableBuilder<String>(
                valueListenable: tipoCtrl,
                builder: (_, tipo, __) => DropdownButtonFormField<String>(
                  value: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo de contato', prefixIcon: Icon(Icons.category_outlined)),
                  items: tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) { if (v != null) tipoCtrl.value = v; },
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: responsavelCtrl,
                decoration: const InputDecoration(labelText: 'Responsável', prefixIcon: Icon(Icons.person_outline_rounded)),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              TextFormField(
                controller: notasCtrl,
                decoration: const InputDecoration(labelText: 'Notas', prefixIcon: Icon(Icons.note_alt_outlined)),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              SizedBox(
                height: ThemeCleanPremium.minTouchTarget,
                child: FilledButton.icon(
                  onPressed: () async {
                    await _followupsRef.add({
                      'tipo': tipoCtrl.value,
                      'notas': notasCtrl.text.trim(),
                      'responsavel': responsavelCtrl.text.trim(),
                      'data': FieldValue.serverTimestamp(),
                    });
                    await _patchVisitorDoc({
                      'followupCount': FieldValue.increment(1),
                      'ultimoFollowupAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Registrar Follow-up'),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
            ],
          ),
        ),
      ),
    );

    tipoCtrl.dispose();
    notasCtrl.dispose();
    responsavelCtrl.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up registrado!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Follow-up Timeline Item
// ═══════════════════════════════════════════════════════════════════════════════

class _FollowupTimelineItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isLast;

  const _FollowupTimelineItem({required this.data, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final tipo = (data['tipo'] ?? '').toString();
    final notas = (data['notas'] ?? '').toString();
    final responsavel = (data['responsavel'] ?? '').toString();
    final ts = data['data'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
        : '—';

    final tipoIcon = _tipoIcon(tipo);
    final tipoColor = _tipoColor(tipo);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tipoColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: tipoColor.withOpacity(0.3), width: 3),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ThemeCleanPremium.spaceSm),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(tipoIcon, size: 16, color: tipoColor),
                      const SizedBox(width: 6),
                      Text(tipo, style: tt.labelLarge?.copyWith(color: tipoColor, fontSize: 13)),
                      const Spacer(),
                      Text(dateStr, style: tt.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                  if (notas.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(notas, style: tt.bodyMedium?.copyWith(color: ThemeCleanPremium.onSurface, height: 1.4)),
                  ],
                  if (responsavel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 12, color: ThemeCleanPremium.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(responsavel, style: tt.bodySmall?.copyWith(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'Ligação': return Icons.phone_rounded;
      case 'WhatsApp': return Icons.chat_rounded;
      case 'Visita': return Icons.home_rounded;
      default: return Icons.more_horiz_rounded;
    }
  }

  static Color _tipoColor(String tipo) {
    switch (tipo) {
      case 'Ligação': return const Color(0xFF3B82F6);
      case 'WhatsApp': return const Color(0xFF22C55E);
      case 'Visita': return const Color(0xFFF59E0B);
      default: return const Color(0xFF8B5CF6);
    }
  }
}
