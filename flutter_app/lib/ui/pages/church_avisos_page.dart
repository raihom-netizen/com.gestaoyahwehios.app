import 'dart:async' show Completer, unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/services/church_instant_upload_pipeline.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/aviso_publish_ui.dart';
import 'package:gestao_yahweh/ui/widgets/church_avisos_carousel.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart'
    show showYahwehOriginalImageZoom;
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_social_post_bar.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show
        formatFirebaseErrorForUser,
        formatUploadErrorForUser,
        kFeedPublishQueuedUserMessage;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Módulo Avisos — publicação para toda a igreja (índice shell 7).
class ChurchAvisosPage extends StatefulWidget {
  const ChurchAvisosPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions = const [],
    this.embeddedInShell = false,
  });

  final String tenantId;
  final String role;
  final List<String> permissions;
  final bool embeddedInShell;

  @override
  State<ChurchAvisosPage> createState() => _ChurchAvisosPageState();
}

/// Filtros da lista de avisos (só lista — sem grid).
enum _AvisoListFilter {
  todos,
  permanentes,
  comVencimento,
  comFoto,
  estaSemana,
  esteMes,
}

class _ChurchAvisosPageState extends State<ChurchAvisosPage> {
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _loading = false;
  List<ChurchAvisoItem> _items = const [];
  String? _loadError;
  bool _showingStaleCache = false;
  _AvisoListFilter _filtro = _AvisoListFilter.todos;
  final TextEditingController _searchCtrl = TextEditingController();
  /// Assunto = título (campo dedicado no formulário).
  final TextEditingController _assuntoCtrl = TextEditingController();
  DateTime? _filterDate;
  /// Recentes primeiro (padrão WisdomApp).
  bool _sortDateAsc = false;

  bool get _canManage =>
      ChurchAvisosService.canManage(widget.role, permissions: widget.permissions);

  bool _canDeleteAviso(ChurchAvisoItem item) =>
      AppPermissions.canDeleteMuralFeedRecord(
        widget.role,
        currentUid: firebaseDefaultAuth.currentUser?.uid ?? '',
        data: item.rawData,
        permissions: widget.permissions,
      );

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _assuntoCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    final ram = ChurchAvisosLoadService.peekRam(
      widget.tenantId,
      limit: ChurchAvisosLoadService.kModuleListLimit,
    );
    if (ram != null && ram.isNotEmpty) {
      _items = ChurchAvisosLoadService.sortItemsByDate(
        ram,
        ascending: _sortDateAsc,
      );
    }
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _assuntoCtrl.dispose();
    super.dispose();
  }

  List<ChurchAvisoItem> get _visibleItems {
    var list = ChurchAvisosLoadService.sortItemsByDate(
      _items,
      ascending: _sortDateAsc,
    );
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (a) =>
                a.title.toLowerCase().contains(q) ||
                a.body.toLowerCase().contains(q),
          )
          .toList();
    }
    final assunto = _assuntoCtrl.text.trim().toLowerCase();
    if (assunto.isNotEmpty) {
      list = list
          .where((a) => a.title.toLowerCase().contains(assunto))
          .toList();
    }
    if (_filterDate != null) {
      final d = _filterDate!;
      list = list.where((a) {
        final c = a.createdAt;
        if (c == null) return false;
        return c.year == d.year && c.month == d.month && c.day == d.day;
      }).toList();
    }
    final now = DateTime.now();
    switch (_filtro) {
      case _AvisoListFilter.permanentes:
        list = list.where((a) => a.permanent).toList();
      case _AvisoListFilter.comVencimento:
        list = list.where((a) => !a.permanent && a.expiresAt != null).toList();
      case _AvisoListFilter.comFoto:
        list = list.where((a) => a.hasImages).toList();
      case _AvisoListFilter.estaSemana:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
        list = list.where((a) {
          final c = a.createdAt;
          return c != null && !c.isBefore(start);
        }).toList();
      case _AvisoListFilter.esteMes:
        list = list.where((a) {
          final c = a.createdAt;
          return c != null && c.year == now.year && c.month == now.month;
        }).toList();
      case _AvisoListFilter.todos:
        break;
    }
    return list;
  }

  void _removeLocalIds(Set<String> ids) {
    if (ids.isEmpty) return;
    setState(() {
      _items = _items.where((i) => !ids.contains(i.id)).toList();
      _selected.removeWhere(ids.contains);
    });
  }

  Future<void> _reload({bool forceRefresh = false}) async {
    if (!mounted) return;
    final hadLocal = _items.isNotEmpty;
    setState(() {
      _loading = _items.isEmpty;
      if (!hadLocal) _loadError = null;
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      // Uma camada de recovery — o load service já tem timeout próprio.
      final list = await ChurchAvisosLoadService.loadActive(
        churchIdHint: widget.tenantId,
        limit: ChurchAvisosLoadService.kModuleListLimit,
        forceRefresh: forceRefresh,
        forceServer: forceRefresh,
      );
      if (!mounted) return;
      final ui = PanelResilientLoad.afterFetch(
        hadLocalData: hadLocal,
        newItems: list,
        fromCache: false,
      );
      setState(() {
        if (list.isNotEmpty || !hadLocal) {
          _items = ChurchAvisosLoadService.sortItemsByDate(
            list,
            ascending: _sortDateAsc,
          );
        }
        _loading = false;
        _showingStaleCache = ui.showingStaleCache;
        _loadError = ui.loadError;
      });
    } catch (e) {
      if (!mounted) return;
      final ui = PanelResilientLoad.afterError(
        hadLocalData: hadLocal,
        error: e,
      );
      setState(() {
        _loading = false;
        _showingStaleCache = ui.showingStaleCache;
        _loadError = ui.loadError ?? e.toString();
      });
    }
  }

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Data do aviso',
      confirmText: 'Filtrar',
    );
    if (!mounted || picked == null) return;
    setState(() => _filterDate = picked);
  }

  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChurchAvisoEditorSheet(
        tenantId: widget.tenantId,
        role: widget.role,
        permissions: widget.permissions,
      ),
    );
    if (created == true) {
      await _reload(forceRefresh: true);
    } else if (created is Map &&
        (created['ok'] == true || created['ok'] == 'true')) {
      final pending = created['awaitPublish'];
      if (pending is Future) {
        try {
          await pending;
        } catch (_) {}
      }
      await _reload(forceRefresh: true);
    }
  }

  Future<void> _openEditSheet(ChurchAvisoItem item) async {
    final updated = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChurchAvisoEditorSheet(
        tenantId: widget.tenantId,
        role: widget.role,
        permissions: widget.permissions,
        initialItem: item,
      ),
    );
    if (updated == true) {
      await _reload(forceRefresh: true);
    } else if (updated is Map &&
        (updated['ok'] == true || updated['ok'] == 'true')) {
      final pending = updated['awaitPublish'];
      if (pending is Future) {
        try {
          await pending;
        } catch (_) {}
      }
      await _reload(forceRefresh: true);
    }
  }

  Future<void> _confirmDeleteOne(ChurchAvisoItem item) async {
    if (!_canDeleteAviso(item)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Sem permissão para excluir este aviso.',
          ),
        );
      }
      return;
    }
    final ok = await _showDeleteConfirmDialog(count: 1);
    if (ok != true) return;
    _removeLocalIds({item.id});
    try {
      await ChurchAvisosService.deleteOne(
        churchIdHint: widget.tenantId,
        docId: item.id,
        data: item.toStorageCleanupPayload(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Aviso excluído.'),
        );
        await _reload(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatFirebaseErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
        await _reload(forceRefresh: true);
      }
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _showDeleteConfirmDialog(count: count);
    if (ok != true) return;
    final ids = Set<String>.from(_selected);
    final dataById = <String, Map<String, dynamic>>{
      for (final item in _items.where((i) => ids.contains(i.id)))
        item.id: item.toStorageCleanupPayload(),
    };
    setState(() {
      _loading = true;
      _selectionMode = false;
      _selected.clear();
    });
    _removeLocalIds(ids);
    try {
      final n = await ChurchAvisosService.deleteMany(
        churchIdHint: widget.tenantId,
        docIds: ids,
        dataById: dataById,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('$n aviso(s) excluído(s).'),
        );
        await _reload(forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatFirebaseErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
        await _reload(forceRefresh: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showDeleteConfirmDialog({required int count}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Confirmar exclusão')),
          ],
        ),
        content: Text(
          count == 1
              ? 'Este aviso será removido do painel, do site público e do armazenamento. Deseja continuar?'
              : 'Serão excluídos $count avisos do painel, do site e do armazenamento. Confirma?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, excluir'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar aviso (texto)…',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _assuntoCtrl,
                decoration: InputDecoration(
                  hintText: 'Assunto / título…',
                  prefixIcon: const Icon(Icons.topic_outlined, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _filterDate != null
                  ? const Color(0xFF0EA5E9)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickFilterDate,
                onLongPress: () => setState(() => _filterDate = null),
                child: SizedBox(
                  height: 48,
                  width: 48,
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: _filterDate != null
                        ? Colors.white
                        : const Color(0xFF334155),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_filterDate != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Data: ${dateFmt.format(_filterDate!)}'),
              onDeleted: () => setState(() => _filterDate = null),
              deleteIconColor: Colors.white,
              backgroundColor: const Color(0xFF0284C7),
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Todos', _AvisoListFilter.todos),
              const SizedBox(width: 8),
              _filterChip('Permanentes', _AvisoListFilter.permanentes),
              const SizedBox(width: 8),
              _filterChip('Com vencimento', _AvisoListFilter.comVencimento),
              const SizedBox(width: 8),
              _filterChip('Com foto', _AvisoListFilter.comFoto),
              const SizedBox(width: 8),
              _filterChip('Esta semana', _AvisoListFilter.estaSemana),
              const SizedBox(width: 8),
              _filterChip('Este mês', _AvisoListFilter.esteMes),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_sortDateAsc ? 'Data ↑' : 'Data ↓'),
                selected: true,
                onSelected: (_) => setState(() => _sortDateAsc = !_sortDateAsc),
                showCheckmark: false,
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.2,
                ),
                backgroundColor: YahwehWisdomVisualKit.navyMid,
                selectedColor: YahwehWisdomVisualKit.navyMid,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                avatar: Icon(
                  _sortDateAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _AvisoListFilter value) {
    final sel = _filtro == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filtro = value),
      showCheckmark: true,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: sel ? Colors.white : const Color(0xFF1E293B),
        fontWeight: FontWeight.w800,
        fontSize: 12.2,
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      selectedColor: YahwehWisdomVisualKit.tealAccent,
      side: BorderSide(
        color: sel ? YahwehWisdomVisualKit.navyMid : const Color(0xFFD5DEE8),
      ),
      shadowColor: YahwehWisdomVisualKit.tealAccent.withValues(alpha: 0.22),
      elevation: sel ? 1.5 : 0,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _openAvisoViewer(ChurchAvisoItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AvisoViewerSheet(
        item: item,
        tenantId: widget.tenantId,
        dateLabel: _formatDate(item.createdAt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final visible = _visibleItems;

    final body = DecoratedBox(
      decoration: YahwehWisdomVisualKit.moduleBodyGradient(
        YahwehWisdomVisualKit.tealAccent,
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_showingStaleCache && _items.isNotEmpty)
                      const ChurchPanelOfflineStaleBanner(
                        message: 'Mostrando avisos em cache — sincronizando…',
                      ),
                    if (_loadError != null && _items.isEmpty)
                      ChurchPanelErrorBody(
                        title: 'Não foi possível carregar os avisos.',
                        error: _loadError,
                        onRetry: _reload,
                      ),
                    if (_loadError == null || _items.isNotEmpty) ...[
                      ChurchAvisosCarousel(
                        churchIdHint: widget.tenantId,
                        compact: true,
                        churchSlug: () {
                          final d = ChurchContextService.currentChurchData ??
                              const {};
                          return (d['slug'] ?? d['publicSlug'] ?? '')
                              .toString()
                              .trim();
                        }(),
                        churchName: () {
                          final d = ChurchContextService.currentChurchData ??
                              const {};
                          return (d['nome'] ??
                                  d['name'] ??
                                  d['nomeIgreja'] ??
                                  '')
                              .toString()
                              .trim();
                        }(),
                      ),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      _AvisosHeroHeader(
                        total: visible.length,
                        fetching: _loading,
                        onRefresh: _reload,
                      ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: YahwehWisdomVisualKit.wisdomSectionCard(
                          borderTint: YahwehWisdomVisualKit.tealAccent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.view_list_rounded,
                              color: YahwehWisdomVisualKit.navyMid,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Lista de avisos — filtre por data, assunto ou tipo.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      _buildFilterBar(),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      if (_canManage) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _openCreateSheet,
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: const Text('Novo aviso'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: YahwehWisdomVisualKit.navyMid,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  minimumSize: const Size(48, 48),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: _selectionMode
                                  ? 'Cancelar seleção'
                                  : 'Selecionar',
                              style: IconButton.styleFrom(
                                backgroundColor: _selectionMode
                                    ? const Color(0xFFFEE2E2)
                                    : const Color(0xFFDBEAFE),
                                foregroundColor: _selectionMode
                                    ? const Color(0xFFB91C1C)
                                    : YahwehWisdomVisualKit.navyMid,
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: () => setState(() {
                                _selectionMode = !_selectionMode;
                                if (!_selectionMode) _selected.clear();
                              }),
                              icon: Icon(
                                _selectionMode
                                    ? Icons.close_rounded
                                    : Icons.checklist_rounded,
                              ),
                            ),
                          ],
                        ),
                        if (_selectionMode) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: visible.isEmpty
                                    ? null
                                    : () => setState(() {
                                          if (_selected.length ==
                                              visible.length) {
                                            _selected.clear();
                                          } else {
                                            _selected
                                              ..clear()
                                              ..addAll(visible.map((e) => e.id));
                                          }
                                        }),
                                child: Text(
                                  _selected.length == visible.length
                                      ? 'Desmarcar todos'
                                      : 'Selecionar todos',
                                ),
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _selected.isEmpty || _loading
                                    ? null
                                    : _confirmDeleteSelected,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  minimumSize: const Size(48, 48),
                                ),
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.delete_outline_rounded,
                                        size: 18),
                                label: Text('Excluir (${_selected.length})'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: ThemeCleanPremium.spaceSm),
                      ],
                      if (_loading && _items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            _items.isEmpty
                                ? (_canManage
                                    ? 'Nenhum aviso publicado. Toque em «Novo aviso».'
                                    : 'Nenhum aviso no momento.')
                                : 'Nenhum aviso neste filtro.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
              if (visible.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    0,
                    padding.right,
                    padding.bottom + 24,
                  ),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final card = _AvisoListCard(
                        item: item,
                        tenantId: widget.tenantId,
                        dateLabel: _formatDate(item.createdAt),
                        canManage: _canManage,
                        canDelete: _canDeleteAviso(item),
                        selectionMode: _selectionMode,
                        selected: _selected.contains(item.id),
                        onToggleSelect: () => setState(() {
                          if (_selected.contains(item.id)) {
                            _selected.remove(item.id);
                          } else {
                            _selected.add(item.id);
                          }
                        }),
                        onView: () => _openAvisoViewer(item),
                        onEdit: () => _openEditSheet(item),
                        onDelete: () => _confirmDeleteOne(item),
                      );
                      return _AvisoStaggeredAppear(
                        key: ValueKey('list_${item.id}'),
                        index: index,
                        child: card,
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.embeddedInShell) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: body,
    );
  }
}

class _AvisoTone {
  const _AvisoTone({
    required this.primary,
    required this.secondary,
    required this.soft,
  });

  final Color primary;
  final Color secondary;
  final Color soft;
}

class _AvisosHeroHeader extends StatelessWidget {
  const _AvisosHeroHeader({
    required this.total,
    required this.fetching,
    required this.onRefresh,
  });

  final int total;
  final bool fetching;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F766E),
            Color(0xFF1E3A8A),
            Color(0xFF7C3AED),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Painel de Avisos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$total aviso(s) ativo(s) · lista Wisdom',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (fetching)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          else
            Material(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              child: IconButton(
                tooltip: 'Atualizar',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvisoStaggeredAppear extends StatefulWidget {
  const _AvisoStaggeredAppear({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<_AvisoStaggeredAppear> createState() => _AvisoStaggeredAppearState();
}

class _AvisoStaggeredAppearState extends State<_AvisoStaggeredAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    final delayMs = (widget.index * 35).clamp(0, 280);
    Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) || (media?.accessibleNavigation ?? false);
    if (reduceMotion) return widget.child;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

_AvisoTone _resolveAvisoTone(ChurchAvisoItem item) {
  if (item.permanent) {
    return const _AvisoTone(
      primary: Color(0xFF059669),
      secondary: Color(0xFF10B981),
      soft: Color(0xFFD1FAE5),
    );
  }

  final expiresSoon =
      item.expiresAt != null && item.expiresAt!.difference(DateTime.now()).inDays <= 3;
  if (expiresSoon) {
    return const _AvisoTone(
      primary: Color(0xFFEA580C),
      secondary: Color(0xFFF59E0B),
      soft: Color(0xFFFFEDD5),
    );
  }

  if (item.hasImages) {
    return const _AvisoTone(
      primary: Color(0xFF7C3AED),
      secondary: Color(0xFF8B5CF6),
      soft: Color(0xFFEDE9FE),
    );
  }

  return const _AvisoTone(
    primary: Color(0xFF0284C7),
    secondary: Color(0xFF0EA5E9),
    soft: Color(0xFFE0F2FE),
  );
}

class _AvisoGridCard extends StatefulWidget {
  const _AvisoGridCard({
    required this.item,
    required this.dateLabel,
    required this.canManage,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final ChurchAvisoItem item;
  final String dateLabel;
  final bool canManage;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_AvisoGridCard> createState() => _AvisoGridCardState();
}

class _AvisoGridCardState extends State<_AvisoGridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tone = _resolveAvisoTone(widget.item);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        scale: _hover && !widget.selectionMode ? 1.015 : 1,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.selectionMode ? widget.onToggleSelect : widget.onView,
            onLongPress:
                widget.canManage && !widget.selectionMode ? widget.onDelete : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    tone.secondary.withValues(alpha: 0.15),
                    tone.primary.withValues(alpha: 0.08),
                    Colors.white,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: widget.selected
                      ? tone.primary
                      : const Color(0xFFE2E8F0),
                  width: widget.selected ? 2 : 1,
                ),
                boxShadow: _hover
                    ? [
                        ...ThemeCleanPremium.softUiCardShadow,
                        BoxShadow(
                          color: tone.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.item.hasImages)
                          ColoredBox(
                            color: tone.soft,
                            child: SafeNetworkImage(
                              imageUrl: (widget.item.mediaRefs().isNotEmpty
                                      ? widget.item.mediaRefs().first
                                      : widget.item.imageUrls.first),
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              memCacheWidth: 720,
                            ),
                          )
                        else
                          Container(
                            color: tone.soft,
                            child: Icon(
                              Icons.campaign_outlined,
                              size: 40,
                              color: tone.primary,
                            ),
                          ),
                        if (widget.selectionMode)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.92),
                              shape: const CircleBorder(),
                              child: Checkbox(
                                value: widget.selected,
                                onChanged: (_) => widget.onToggleSelect(),
                              ),
                            ),
                          ),
                        if (widget.canManage && !widget.selectionMode)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.94),
                                  ),
                                  tooltip: 'Ver completo',
                                  onPressed: widget.onView,
                                  icon: Icon(
                                    Icons.visibility_rounded,
                                    color: tone.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.94),
                                  ),
                                  tooltip: 'Editar',
                                  onPressed: widget.onEdit,
                                  icon: Icon(
                                    Icons.edit_rounded,
                                    color: tone.secondary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.94),
                                  ),
                                  tooltip: 'Excluir',
                                  onPressed: widget.onDelete,
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade400,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title.isEmpty ? 'Aviso' : widget.item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.item.permanent
                                ? 'Permanente'
                                : 'Vence ${_formatExpiry(widget.item.expiresAt)}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: tone.primary,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                Icons.photo_library_rounded,
                                size: 14,
                                color: tone.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(widget.item.mediaRefs().isNotEmpty ? widget.item.mediaRefs().length : widget.item.imageUrls.length)} foto(s)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: tone.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Publicado ${widget.dateLabel}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
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
      ),
    );
  }

  static String _formatExpiry(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

class _AvisoListCard extends StatefulWidget {
  const _AvisoListCard({
    required this.item,
    required this.tenantId,
    required this.dateLabel,
    required this.canManage,
    required this.canDelete,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final ChurchAvisoItem item;
  final String tenantId;
  final String dateLabel;
  final bool canManage;
  final bool canDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_AvisoListCard> createState() => _AvisoListCardState();
}

class _AvisoListCardState extends State<_AvisoListCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tone = _resolveAvisoTone(widget.item);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        scale: _hover && !widget.selectionMode ? 1.01 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                tone.secondary.withValues(alpha: 0.13),
                tone.primary.withValues(alpha: 0.09),
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: widget.selected ? tone.primary : const Color(0xFFE2E8F0),
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: _hover
                ? [
                    ...ThemeCleanPremium.softUiCardShadow,
                    BoxShadow(
                      color: tone.primary.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.selectionMode ? widget.onToggleSelect : widget.onView,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: ColoredBox(
                        color: tone.soft,
                        child: widget.item.hasImages
                            ? SafeNetworkImage(
                                imageUrl: (widget.item.mediaRefs().isNotEmpty
                                        ? widget.item.mediaRefs().first
                                        : widget.item.imageUrls.first),
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                memCacheWidth: 900,
                              )
                            : Center(
                                child: Icon(
                                  Icons.campaign_rounded,
                                  color: tone.primary,
                                  size: 44,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.title.isEmpty
                                  ? 'Aviso'
                                  : widget.item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                height: 1.25,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (widget.item.body.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.item.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _miniTag(
                                  icon: Icons.calendar_month_rounded,
                                  text: widget.dateLabel,
                                  color: tone.primary,
                                ),
                                _miniTag(
                                  icon: Icons.photo_library_outlined,
                                  text:
                                      '${(widget.item.mediaRefs().isNotEmpty ? widget.item.mediaRefs().length : widget.item.imageUrls.length)} foto(s)',
                                  color: tone.secondary,
                                ),
                                _miniTag(
                                  icon: widget.item.permanent
                                      ? Icons.all_inclusive_rounded
                                      : Icons.timer_outlined,
                                  text: widget.item.permanent
                                      ? 'Permanente'
                                      : 'Com validade',
                                  color: tone.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        children: [
                          if (widget.selectionMode)
                            Checkbox(
                              value: widget.selected,
                              onChanged: (_) => widget.onToggleSelect(),
                            )
                          else ...[
                            IconButton.filledTonal(
                              tooltip: 'Ver completo',
                              style: IconButton.styleFrom(
                                backgroundColor: tone.soft,
                                minimumSize: const Size(44, 44),
                              ),
                              onPressed: widget.onView,
                              icon: Icon(
                                Icons.visibility_rounded,
                                color: tone.primary,
                              ),
                            ),
                            if (widget.canManage)
                              IconButton.filledTonal(
                                tooltip: 'Editar',
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      tone.secondary.withValues(alpha: 0.18),
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: widget.onEdit,
                                icon: Icon(
                                  Icons.edit_rounded,
                                  color: tone.secondary,
                                ),
                              ),
                            if (widget.canDelete)
                              IconButton.filledTonal(
                                tooltip: 'Excluir',
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFFEE2E2),
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: widget.onDelete,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  if (!widget.selectionMode)
                    Builder(
                      builder: (context) {
                        final d = ChurchContextService.currentChurchData ??
                            const {};
                        final slug = (d['slug'] ?? d['publicSlug'] ?? '')
                            .toString()
                            .trim();
                        final name = (d['nome'] ??
                                d['name'] ??
                                d['nomeIgreja'] ??
                                '')
                            .toString()
                            .trim();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GestureDetector(
                            onTap: () {},
                            behavior: HitTestBehavior.opaque,
                            child: YahwehSocialPostBar(
                              tenantId: widget.tenantId,
                              postId: widget.item.id,
                              isEvento: false,
                              churchSlug: slug,
                              churchName: name,
                              postsParentCollection:
                                  ChurchTenantPostsCollections.avisos,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTag({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoViewerSheet extends StatefulWidget {
  const _AvisoViewerSheet({
    required this.item,
    required this.tenantId,
    required this.dateLabel,
  });

  final ChurchAvisoItem item;
  final String tenantId;
  final String dateLabel;

  @override
  State<_AvisoViewerSheet> createState() => _AvisoViewerSheetState();
}

class _AvisoViewerSheetState extends State<_AvisoViewerSheet> {
  final PageController _pageCtrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tone = _resolveAvisoTone(item);
    final pad = MediaQuery.of(context).padding;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tone.soft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Aviso completo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: tone.primary,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 16 + pad.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? 'Aviso' : item.title,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _viewerTag(Icons.calendar_today_rounded, widget.dateLabel,
                          tone.primary),
                      _viewerTag(
                        item.permanent
                            ? Icons.all_inclusive_rounded
                            : Icons.timer_rounded,
                        item.permanent
                            ? 'Permanente'
                            : 'Com vencimento',
                        tone.primary,
                      ),
                      _viewerTag(Icons.photo_library_rounded,
                          '${item.imageUrls.length} foto(s)', tone.secondary),
                    ],
                  ),
                  if (item.authorName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Publicado por ${item.authorName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (item.imageUrls.isNotEmpty)
                    Column(
                      children: [
                        // Foto inteira (sem corte) + toque para ampliar em ecrã cheio.
                        SizedBox(
                          height: (MediaQuery.sizeOf(context).height * 0.72)
                              .clamp(430.0, 900.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: PageView.builder(
                              controller: _pageCtrl,
                              itemCount: item.imageUrls.length,
                              onPageChanged: (i) => setState(() => _index = i),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => showYahwehOriginalImageZoom(
                                  context,
                                  imageUrl: item.imageUrls[i],
                                ),
                                child: Container(
                                  color: const Color(0xFF0F172A),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      SafeNetworkImage(
                                        imageUrl: item.imageUrls[i],
                                        fit: BoxFit.contain,
                                      ),
                                      Positioned(
                                        right: 10,
                                        bottom: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.zoom_out_map_rounded,
                                                  color: Colors.white,
                                                  size: 15),
                                              SizedBox(width: 5),
                                              Text(
                                                'Ampliar',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
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
                          ),
                        ),
                        if (item.imageUrls.length > 1) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: List.generate(
                              item.imageUrls.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: i == _index ? 20 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: i == _index
                                      ? tone.primary
                                      : Colors.grey.shade300,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        item.body,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  Builder(
                    builder: (context) {
                      final d =
                          ChurchContextService.currentChurchData ?? const {};
                      final slug = (d['slug'] ?? d['publicSlug'] ?? '')
                          .toString()
                          .trim();
                      final name = (d['nome'] ??
                              d['name'] ??
                              d['nomeIgreja'] ??
                              '')
                          .toString()
                          .trim();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: YahwehSocialPostBar(
                          tenantId: widget.tenantId,
                          postId: item.id,
                          isEvento: false,
                          churchSlug: slug,
                          churchName: name,
                          postsParentCollection:
                              ChurchTenantPostsCollections.avisos,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewerTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChurchAvisoEditorSheet extends StatefulWidget {
  const _ChurchAvisoEditorSheet({
    required this.tenantId,
    required this.role,
    required this.permissions,
    this.initialItem,
  });

  final String tenantId;
  final String role;
  final List<String> permissions;
  final ChurchAvisoItem? initialItem;

  @override
  State<_ChurchAvisoEditorSheet> createState() =>
      _ChurchAvisoEditorSheetState();
}

class _ChurchAvisoEditorSheetState extends State<_ChurchAvisoEditorSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _permanent = true;
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 7));
  final List<String> _existingImageUrls = [];
  final List<Uint8List> _photos = [];
  bool _publishing = false;

  bool get _isEdit => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    if (item == null) return;
    _titleCtrl.text = item.title;
    _bodyCtrl.text = item.body;
    _permanent = item.permanent;
    _expiresAt = item.expiresAt ?? DateTime.now().add(const Duration(days: 7));
    _existingImageUrls.addAll(item.imageUrls);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining =
        ChurchAvisosService.kMaxPhotos - (_photos.length + _existingImageUrls.length);
    if (remaining <= 0) return;

    final files = await MediaHandlerService.instance.pickAndProcessMultipleImages(
      module: YahwehMediaModule.avisos,
      context: context,
    );
    if (!mounted || files.isEmpty) return;

    Uint8List? lastBytes;
    String lastName = 'foto.webp';
    for (final f in files.take(remaining)) {
      final b = await f.readAsBytes();
      if (b.isEmpty) continue;
      final prepared = await ChurchInstantUploadPipeline.prepareImageBytes(
        b,
        postType: kChurchPostTypeAviso,
      );
      final bytes = prepared.isNotEmpty ? prepared : b;
      _photos.add(bytes);
      lastBytes = bytes;
      lastName = f.name.trim().isNotEmpty ? f.name.trim() : 'foto.webp';
    }
    setState(() {});
    if (lastBytes != null && mounted) {
      final resolution =
          await ImmediateMediaAttachFeedback.readResolution(lastBytes);
      if (!mounted) return;
      ImmediateMediaAttachFeedback.showFotoAdicionadaSucesso(
        context,
        fileName: lastName,
        sizeBytes: lastBytes.length,
        resolution: resolution,
      );
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  String _formatDateBr(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  void _openAvisoPhotoZoom({String? url, Uint8List? bytes}) {
    if (!mounted) return;
    final Widget? image = bytes != null
        ? Image.memory(
            bytes,
            fit: BoxFit.contain,
            cacheWidth: 1280,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          )
        : url != null
            ? SafeNetworkImage(imageUrl: url, fit: BoxFit.contain)
            : null;
    if (image == null) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: image,
            ),
          ),
        ),
      ),
    );
  }

  Widget _avisoRemoveButton({required VoidCallback onRemove}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: () {
          if (!mounted) return;
          unawaited(
            showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remover foto'),
                content: const Text('Quer mesmo remover esta foto do aviso?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Remover'),
                  ),
                ],
              ),
            ).then((ok) {
              if (ok == true) onRemove();
            }),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Icon(Icons.close_rounded, size: 26, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final titulo = _titleCtrl.text.trim();
    if (titulo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o título do aviso.')),
        );
      }
      return;
    }

    if (_photos.isNotEmpty) {
      try {
        await DirectStorageUrlPublish.ensureReady(requireAuth: true);
      } catch (e) {
        if (!EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.errorSnackBarWithRetry(
                formatUploadErrorForUser(e),
                onRetry: _publish,
              ),
            );
          }
          return;
        }
      }
      if (!mounted) return;
    }

    final isEdit = _isEdit;
    final photos = List<Uint8List>.from(_photos);
    final existing = List<String>.from(_existingImageUrls);
    final permanent = _permanent;
    final expires = _expiresAt;
    final titleText = _titleCtrl.text;
    final bodyText = _bodyCtrl.text;
    final docId = widget.initialItem?.id;

    try {
      setState(() => _publishing = true);
      final publishDone = Completer<bool>();
      await EcofirePublishProgressUi.runSilentControleTotal<void>(
        context: context,
        successMessage: isEdit
            ? 'Aviso atualizado com sucesso.'
            : 'Aviso publicado com sucesso.',
        closeEditor: () {
          if (mounted) {
            Navigator.pop(context, <String, dynamic>{
              'ok': true,
              'awaitPublish': publishDone.future,
            });
          }
        },
        formatError: formatUploadErrorForUser,
        onPublishSucceeded: () {
          if (!publishDone.isCompleted) publishDone.complete(true);
        },
        action: (reportProgress) async {
          if (isEdit) {
            await ChurchAvisosService.update(
              churchIdHint: widget.tenantId,
              docId: docId!,
              title: titleText,
              body: bodyText,
              permanent: permanent,
              expiresAtEndOfDay: permanent ? null : expires,
              existingImageUrls: existing,
              newPhotoBytes: photos,
              role: widget.role,
              permissions: widget.permissions,
              onUploadProgress: reportProgress,
            );
          } else {
            await ChurchAvisosService.publish(
              churchIdHint: widget.tenantId,
              title: titleText,
              body: bodyText,
              permanent: permanent,
              expiresAtEndOfDay: permanent ? null : expires,
              photoBytes: photos,
              role: widget.role,
              permissions: widget.permissions,
              onUploadProgress: reportProgress,
            );
          }
        },
      );
      if (!publishDone.isCompleted) publishDone.complete(true);
    } catch (e, st) {
      if (EcoFireResilientPublish.isQueuedSuccess(e)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(kFeedPublishQueuedUserMessage),
          );
          Navigator.pop(context, true);
        }
        return;
      }
      debugPrint('ChurchAvisoEditorSheet._publish: $e\n$st');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFDB2777)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? 'Editar aviso' : 'Novo aviso',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Mensagem (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                        prefixIcon: Icon(Icons.article_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2563EB).withValues(alpha: 0.08),
                            const Color(0xFFDB2777).withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                        ),
                      ),
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Aviso permanente',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          _permanent
                              ? 'Fica ativo sem data de vencimento.'
                              : 'Usa a data abaixo para vencimento do aviso.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        value: _permanent,
                        onChanged: (v) => setState(() => _permanent = v),
                        secondary: const Icon(Icons.all_inclusive_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(
                        _permanent
                            ? 'Data do aviso: ${_formatDateBr(_expiresAt)} (informativo)'
                            : 'Data de vencimento: ${_formatDateBr(_expiresAt)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fotos (${_existingImageUrls.length + _photos.length}/${ChurchAvisosService.kMaxPhotos})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _existingImageUrls.length; i++)
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () => _openAvisoPhotoZoom(
                                    url: _existingImageUrls[i]),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SafeNetworkImage(
                                    imageUrl: _existingImageUrls[i],
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: _avisoRemoveButton(
                                  onRemove: () => setState(
                                      () => _existingImageUrls.removeAt(i)),
                                ),
                              ),
                            ],
                          ),
                        for (var i = 0; i < _photos.length; i++)
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    _openAvisoPhotoZoom(bytes: _photos[i]),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    _photos[i],
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.contain,
                                    cacheWidth: 400,
                                    cacheHeight: 400,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.low,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ImmediateMediaAttachFeedback.formatBytes(
                                        _photos[i].length),
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: _avisoRemoveButton(
                                  onRemove: () =>
                                      setState(() => _photos.removeAt(i)),
                                ),
                              ),
                            ],
                          ),
                        if ((_existingImageUrls.length + _photos.length) <
                            ChurchAvisosService.kMaxPhotos)
                          InkWell(
                            onTap: _publishing ? null : _pickPhotos,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                                color: Colors.grey.shade50,
                              ),
                              child: const Icon(Icons.add_a_photo_outlined,
                                  size: 34),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _publishing ? null : _publish,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: YahwehWisdomVisualKit.navyMid,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _publishing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEdit ? 'Salvar alterações' : 'Publicar aviso',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
