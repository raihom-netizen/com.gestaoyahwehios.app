import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_avisos_carousel.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

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

class _ChurchAvisosPageState extends State<ChurchAvisosPage> {
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _loading = false;
  List<ChurchAvisoItem> _items = const [];
  Map<String, Map<String, dynamic>> _rawById = {};

  bool get _canManage =>
      ChurchAvisosService.canManage(widget.role, permissions: widget.permissions);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _loading = _items.isEmpty);
    try {
      final list = await ChurchAvisosLoadService.loadActive(
        churchIdHint: widget.tenantId,
        limit: ChurchAvisosLoadService.kModuleListLimit,
      );
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Falha ao carregar avisos: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
    await ChurchAvisosService.deleteOne(
      churchIdHint: widget.tenantId,
      docId: item.id,
      data: _rawById[item.id],
    );
    if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Aviso excluído.'),
        );
      await _reload();
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _showDeleteConfirmDialog(count: count);
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await ChurchAvisosService.deleteMany(
        churchIdHint: widget.tenantId,
        docIds: _selected,
        dataById: _rawById,
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('$count aviso(s) excluído(s).'),
        );
        await _reload();
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

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            ChurchAvisosCarousel(churchIdHint: widget.tenantId, compact: true),
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
                    tooltip: _selectionMode ? 'Cancelar seleção' : 'Selecionar',
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
                      onPressed: _items.isEmpty
                          ? null
                          : () => setState(() {
                                if (_selected.length == _items.length) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(_items.map((e) => e.id));
                                }
                              }),
                      child: Text(
                        _selected.length == _items.length
                            ? 'Desmarcar todos'
                            : 'Selecionar todos',
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed:
                          _selected.isEmpty ? null : _confirmDeleteSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text('Excluir (${_selected.length})'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: ThemeCleanPremium.spaceMd),
            ],
            if (_loading && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _canManage
                      ? 'Nenhum aviso publicado. Toque em «Novo aviso» para começar.'
                      : 'Nenhum aviso no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ..._items.map((item) => _AvisoListCard(
                    item: item,
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
                  )),
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

class _AvisoListCard extends StatelessWidget {
  const _AvisoListCard({
    required this.item,
    required this.canManage,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelect,
    required this.onDelete,
  });

  final ChurchAvisoItem item;
  final bool canManage;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode)
              Checkbox(value: selected, onChanged: (_) => onToggleSelect()),
            if (item.hasImages)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SafeNetworkImage(
                  imageUrl: item.imageUrls.first,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    item.permanent
                        ? 'Permanente'
                        : 'Vence em ${item.expiresAt?.day.toString().padLeft(2, '0')}/${item.expiresAt?.month.toString().padLeft(2, '0')}/${item.expiresAt?.year}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: item.permanent
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
            ),
            if (canManage && !selectionMode)
              IconButton(
                tooltip: 'Excluir aviso',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400),
              ),
          ],
        ),
      ),
    );
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
