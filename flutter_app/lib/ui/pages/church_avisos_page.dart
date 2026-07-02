import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
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

class _ChurchAvisosPageState extends State<ChurchAvisosPage> {
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _loading = false;
  List<ChurchAvisoItem> _items = const [];
  String? _loadError;
  bool _showingStaleCache = false;
  _AvisoGridFilter _filtro = _AvisoGridFilter.todos;
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
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = visible[index];
                      return _AvisoGridCard(
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
                        onDelete: () => _confirmDeleteOne(item),
                      );
                    },
                    childCount: visible.length,
                  ),
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

class _AvisoGridCard extends StatelessWidget {
  const _AvisoGridCard({
    required this.item,
    required this.dateLabel,
    required this.canManage,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onDelete,
  });

  final ChurchAvisoItem item;
  final String dateLabel;
  final bool canManage;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode ? onToggleSelect : null,
        onLongPress: canManage && !selectionMode ? onDelete : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0EA5E9)
                  : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.hasImages)
                      SafeNetworkImage(
                        imageUrl: item.imageUrls.first,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(
                        color: const Color(0xFFEFF6FF),
                        child: Icon(
                          Icons.campaign_outlined,
                          size: 40,
                          color: Colors.blue.shade300,
                        ),
                      ),
                    if (selectionMode)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: Checkbox(
                            value: selected,
                            onChanged: (_) => onToggleSelect(),
                          ),
                        ),
                      ),
                    if (canManage && !selectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.92),
                          ),
                          tooltip: 'Excluir',
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red.shade400,
                            size: 20,
                          ),
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
                        item.title.isEmpty ? 'Aviso' : item.title,
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
                        item.permanent
                            ? 'Permanente'
                            : 'Vence ${_formatExpiry(item.expiresAt)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: item.permanent
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Publicado $dateLabel',
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
    );
  }

  static String _formatExpiry(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

class _ChurchAvisoEditorSheet extends StatefulWidget {
  const _ChurchAvisoEditorSheet({
    required this.tenantId,
    required this.role,
    required this.permissions,
  });

  final String tenantId;
  final String role;
  final List<String> permissions;

  @override
  State<_ChurchAvisoEditorSheet> createState() =>
      _ChurchAvisoEditorSheetState();
}

class _ChurchAvisoEditorSheetState extends State<_ChurchAvisoEditorSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _permanent = true;
  DateTime? _expiresAt;
  final List<Uint8List> _photos = [];
  bool _publishing = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = ChurchAvisosService.kMaxPhotos - _photos.length;
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
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
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
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(e.toString()),
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
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Novo aviso',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Mensagem (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aviso permanente'),
                value: _permanent,
                onChanged: (v) => setState(() => _permanent = v),
              ),
              if (!_permanent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data de vencimento'),
                  subtitle: Text(
                    _expiresAt == null
                        ? 'Toque para escolher'
                        : '${_expiresAt!.day.toString().padLeft(2, '0')}/${_expiresAt!.month.toString().padLeft(2, '0')}/${_expiresAt!.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_rounded),
                  onTap: _pickExpiry,
                ),
              const SizedBox(height: 8),
              Text(
                'Fotos (${_photos.length}/${ChurchAvisosService.kMaxPhotos})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
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
                  if (_photos.length < ChurchAvisosService.kMaxPhotos)
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
                    : const Text('Publicar aviso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
