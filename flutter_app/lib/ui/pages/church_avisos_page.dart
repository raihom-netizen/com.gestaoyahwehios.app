import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_avisos_carousel.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

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

/// Filtro rápido da grelha de avisos.
enum _AvisoGridFilter { todos, permanentes, comVencimento, comFoto }

enum _AvisoLayoutMode { grid, lista }

class _ChurchAvisosPageState extends State<ChurchAvisosPage> {
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _loading = false;
  List<ChurchAvisoItem> _items = const [];
  String? _loadError;
  bool _showingStaleCache = false;
  _AvisoGridFilter _filtro = _AvisoGridFilter.todos;
  _AvisoLayoutMode _layoutMode = _AvisoLayoutMode.grid;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _sortDateAsc = true;

  bool get _canManage =>
      ChurchAvisosService.canManage(widget.role, permissions: widget.permissions);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
    switch (_filtro) {
      case _AvisoGridFilter.permanentes:
        list = list.where((a) => a.permanent).toList();
      case _AvisoGridFilter.comVencimento:
        list = list.where((a) => !a.permanent && a.expiresAt != null).toList();
      case _AvisoGridFilter.comFoto:
        list = list.where((a) => a.hasImages).toList();
      case _AvisoGridFilter.todos:
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

  Future<void> _reload() async {
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
      final list = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchAvisosLoadService.loadActive(
          churchIdHint: widget.tenantId,
          limit: ChurchAvisosLoadService.kModuleListLimit,
        ),
        maxAttempts: 4,
      ).timeout(PanelResilientLoad.queryCap);
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

  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChurchAvisoEditorSheet(
        tenantId: widget.tenantId,
        role: widget.role,
        permissions: widget.permissions,
      ),
    );
    if (created == true) await _reload();
  }

  Future<void> _openEditSheet(ChurchAvisoItem item) async {
    final updated = await showModalBottomSheet<bool>(
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
    if (updated == true) await _reload();
  }

  Future<void> _confirmDeleteOne(ChurchAvisoItem item) async {
    final ok = await _showDeleteConfirmDialog(count: 1);
    if (ok != true) return;
    _removeLocalIds({item.id});
    try {
      await ChurchAvisosService.deleteOne(
        churchIdHint: widget.tenantId,
        docId: item.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Aviso excluído.'),
        );
        unawaited(_reload());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatFirebaseErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
        unawaited(_reload());
      }
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _showDeleteConfirmDialog(count: count);
    if (ok != true) return;
    final ids = Set<String>.from(_selected);
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
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('$n aviso(s) excluído(s).'),
        );
        unawaited(_reload());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatFirebaseErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
        unawaited(_reload());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar aviso…',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Todos', _AvisoGridFilter.todos),
              const SizedBox(width: 8),
              _filterChip('Permanentes', _AvisoGridFilter.permanentes),
              const SizedBox(width: 8),
              _filterChip('Com vencimento', _AvisoGridFilter.comVencimento),
              const SizedBox(width: 8),
              _filterChip('Com foto', _AvisoGridFilter.comFoto),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_sortDateAsc ? 'Data ↑ antigos' : 'Data ↓ recentes'),
                selected: true,
                onSelected: (_) => setState(() => _sortDateAsc = !_sortDateAsc),
                avatar: Icon(
                  _sortDateAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _AvisoGridFilter value) {
    final sel = _filtro == value;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filtro = value),
      selectedColor: const Color(0xFF0EA5E9).withValues(alpha: 0.18),
      checkmarkColor: const Color(0xFF0EA5E9),
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
        dateLabel: _formatDate(item.createdAt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final visible = _visibleItems;
    final crossAxisCount = MediaQuery.sizeOf(context).width >= 720 ? 3 : 2;

    final body = SafeArea(
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
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    _AvisosHeroHeader(
                      total: visible.length,
                      fetching: _loading,
                      onRefresh: _reload,
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                            const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                            const Color(0xFF22C55E).withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.blue.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Visual moderno de Avisos: escolha lista ou grid.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SegmentedButton<_AvisoLayoutMode>(
                            showSelectedIcon: false,
                            selected: {_layoutMode},
                            onSelectionChanged: (v) {
                              if (v.isEmpty) return;
                              setState(() => _layoutMode = v.first);
                            },
                            segments: const [
                              ButtonSegment<_AvisoLayoutMode>(
                                value: _AvisoLayoutMode.lista,
                                label: Text('Lista'),
                                icon: Icon(Icons.view_list_rounded, size: 18),
                              ),
                              ButtonSegment<_AvisoLayoutMode>(
                                value: _AvisoLayoutMode.grid,
                                label: Text('Grid'),
                                icon: Icon(Icons.grid_view_rounded, size: 18),
                              ),
                            ],
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
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip:
                                _selectionMode ? 'Cancelar seleção' : 'Selecionar',
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
                                        if (_selected.length == visible.length) {
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
                sliver: _layoutMode == _AvisoLayoutMode.grid
                    ? SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.74,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = visible[index];
                            final card = _AvisoGridCard(
                                item: item,
                                dateLabel: _formatDate(item.createdAt),
                                canManage: _canManage,
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
                              key: ValueKey('grid_${item.id}'),
                              index: index,
                              child: card,
                            );
                          },
                          childCount: visible.length,
                        ),
                      )
                    : SliverList.separated(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final card = _AvisoListCard(
                            item: item,
                            dateLabel: _formatDate(item.createdAt),
                            canManage: _canManage,
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
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                      ),
              ),
          ],
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
            Color(0xFF0EA5E9),
            Color(0xFF3B82F6),
            Color(0xFF8B5CF6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
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
                  '$total aviso(s) ativo(s)',
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
                          SafeNetworkImage(
                            imageUrl: widget.item.imageUrls.first,
                            fit: BoxFit.cover,
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
                                '${widget.item.imageUrls.length} foto(s)',
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
            borderRadius: BorderRadius.circular(16),
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
            borderRadius: BorderRadius.circular(16),
            onTap: widget.selectionMode ? widget.onToggleSelect : widget.onView,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: widget.item.hasImages
                      ? SafeNetworkImage(
                          imageUrl: widget.item.imageUrls.first,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: tone.soft,
                          child: Icon(
                            Icons.campaign_rounded,
                            color: tone.primary,
                            size: 32,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title.isEmpty ? 'Aviso' : widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.item.body.isEmpty
                          ? 'Sem descrição.'
                        : widget.item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
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
                          text: '${widget.item.imageUrls.length} foto(s)',
                          color: tone.secondary,
                        ),
                        _miniTag(
                          icon: widget.item.permanent
                              ? Icons.all_inclusive_rounded
                              : Icons.timer_outlined,
                          text: widget.item.permanent ? 'Permanente' : 'Com validade',
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
                      ),
                      onPressed: widget.onView,
                      icon: Icon(Icons.visibility_rounded, color: tone.primary),
                    ),
                    if (widget.canManage)
                      IconButton.filledTonal(
                        tooltip: 'Editar',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              tone.secondary.withValues(alpha: 0.18),
                        ),
                        onPressed: widget.onEdit,
                        icon: Icon(
                          Icons.edit_rounded,
                          color: tone.secondary,
                        ),
                      ),
                    if (widget.canManage)
                      IconButton.filledTonal(
                        tooltip: 'Excluir',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
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
    required this.dateLabel,
  });

  final ChurchAvisoItem item;
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
                        AspectRatio(
                          aspectRatio: 16 / 10,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: PageView.builder(
                              controller: _pageCtrl,
                              itemCount: item.imageUrls.length,
                              onPageChanged: (i) => setState(() => _index = i),
                              itemBuilder: (_, i) => SafeNetworkImage(
                                imageUrl: item.imageUrls[i],
                                fit: BoxFit.cover,
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

    for (final f in files.take(remaining)) {
      final b = await f.readAsBytes();
      if (b.isNotEmpty) _photos.add(b);
    }
    setState(() {});
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

  Future<void> _publish() async {
    final titulo = _titleCtrl.text.trim();
    if (titulo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o título do aviso.')),
        );
      }
      return;
    }

    if (!await YahwehModuleMediaGate.prepareForPublishUpload(
      context: context,
      module: YahwehMediaModule.avisos,
      logLabel: 'avisos_editor_publish',
      withPhotos: _photos.isNotEmpty,
    )) {
      return;
    }

    setState(() => _publishing = true);
    try {
      if (_isEdit) {
        await ChurchAvisosService.update(
          churchIdHint: widget.tenantId,
          docId: widget.initialItem!.id,
          title: _titleCtrl.text,
          body: _bodyCtrl.text,
          permanent: _permanent,
          expiresAtEndOfDay: _permanent ? null : _expiresAt,
          existingImageUrls: _existingImageUrls,
          newPhotoBytes: _photos,
          role: widget.role,
          permissions: widget.permissions,
        );
      } else {
        await ChurchAvisosService.publish(
          churchIdHint: widget.tenantId,
          title: _titleCtrl.text,
          body: _bodyCtrl.text,
          permanent: _permanent,
          expiresAtEndOfDay: _permanent ? null : _expiresAt,
          photoBytes: _photos,
          role: widget.role,
          permissions: widget.permissions,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('ChurchAvisoEditorSheet._publish: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(formatUploadErrorForUser(e)),
        );
      }
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
                      onPressed: _publishing ? null : _pickExpiry,
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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SafeNetworkImage(
                                  imageUrl: _existingImageUrls[i],
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(32, 32),
                                  ),
                                  iconSize: 18,
                                  onPressed: () =>
                                      setState(() => _existingImageUrls.removeAt(i)),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        for (var i = 0; i < _photos.length; i++)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _photos[i],
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(32, 32),
                                  ),
                                  iconSize: 18,
                                  onPressed: () => setState(() => _photos.removeAt(i)),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        if ((_existingImageUrls.length + _photos.length) <
                            ChurchAvisosService.kMaxPhotos)
                          InkWell(
                            onTap: _publishing ? null : _pickPhotos,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                                color: Colors.grey.shade50,
                              ),
                              child: const Icon(Icons.add_a_photo_outlined),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _publishing ? null : _publish,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _publishing
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEdit ? 'Salvar alterações' : 'Publicar aviso'),
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
