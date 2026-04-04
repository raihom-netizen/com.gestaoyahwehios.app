import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/marketing_gallery_cms.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/institutional_media_period.dart';
import 'package:gestao_yahweh/ui/widgets/marketing_gestao_yahweh_gallery.dart';

/// Evita maps read-only do snapshot e falhas de interop na web ao gravar `items`.
List<Map<String, dynamic>> _cloneGalleryItemMaps(List<Map<String, dynamic>> items) {
  return items.map((e) => Map<String, dynamic>.from(e)).toList();
}

String _firestoreWriteErrorMessage(Object e) {
  if (e is FirebaseException) {
    final m = e.message;
    if (m != null && m.isNotEmpty) return '${e.code}: $m';
    return e.code;
  }
  return e.toString();
}

class AdminDivulgacaoMediaPage extends StatefulWidget {
  const AdminDivulgacaoMediaPage({super.key});

  @override
  State<AdminDivulgacaoMediaPage> createState() => _AdminDivulgacaoMediaPageState();
}

class _VisibleRow {
  final int originalIndex;
  final Map<String, dynamic> item;
  _VisibleRow({required this.originalIndex, required this.item});
}

class _CmsMaterialFormValues {
  final String title;
  final String description;
  final String category;
  final bool featured;

  const _CmsMaterialFormValues({
    required this.title,
    required this.description,
    required this.category,
    required this.featured,
  });
}

class _AdminDivulgacaoMediaPageState extends State<AdminDivulgacaoMediaPage> {
  bool _uploading = false;
  /// 0–1 durante envio ao Storage; null quando inativo.
  double? _uploadProgress;
  bool _bulkWorking = false;

  InstitutionalMediaPeriod _period = InstitutionalMediaPeriod.all;
  DateTime? _customStart;
  DateTime? _customEnd;

  bool _selectionMode = false;
  final Set<String> _selectedPaths = <String>{};
  /// Paths normalizados atualmente visíveis na grelha (callback da galeria).
  List<String> _visibleGalleryPaths = const [];

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore.instance
      .collection(MarketingStorageLayout.firestoreCollection)
      .doc(MarketingStorageLayout.firestoreGalleryDocId);

  String _itemPath(Map<String, dynamic> item) =>
      MarketingStorageLayout.normalizeObjectPath(
        (item['path'] ?? item['storagePath'] ?? '').toString(),
      );

  List<Map<String, dynamic>> _parseItems(Map<String, dynamic>? data) {
    final raw = data?['items'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => _itemPath(e).isNotEmpty)
        .toList();
  }

  List<_VisibleRow> _visibleRows(List<Map<String, dynamic>> items) {
    final out = <_VisibleRow>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final path = _itemPath(it);
      final d = institutionalMediaDateFromItem(it, storagePath: path);
      if (!institutionalMediaMatchesPeriod(d, _period, _customStart, _customEnd)) {
        continue;
      }
      out.add(_VisibleRow(originalIndex: i, item: it));
    }
    return out;
  }

  InstitutionalMediaAdminConfig get _adminGalleryConfig => InstitutionalMediaAdminConfig(
        period: _period,
        customStart: _customStart,
        customEnd: _customEnd,
        selectionMode: _selectionMode,
        selectedPaths: _selectedPaths,
        onPathToggle: (path) {
          final p = MarketingStorageLayout.normalizeObjectPath(path);
          setState(() {
            if (_selectedPaths.contains(p)) {
              _selectedPaths.remove(p);
            } else {
              _selectedPaths.add(p);
            }
          });
        },
        onVisiblePathsUpdated: (paths) {
          if (!mounted) return;
          setState(() => _visibleGalleryPaths = List<String>.from(paths));
        },
      );

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _customStart ?? now.subtract(const Duration(days: 30));
    final initialEnd = _customEnd ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: ThemeCleanPremium.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || range == null) return;
    setState(() {
      _period = InstitutionalMediaPeriod.custom;
      _customStart = range.start;
      _customEnd = range.end;
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedPaths.clear();
    });
  }

  static const Color _selectionGreen = Color(0xFF16A34A);
  static const Color _selectionGreenLight = Color(0xFFDCFCE7);

  /// Lista ordenada + grelha (mesmo período): útil quando só há ficheiros na grelha (Storage).
  void _selectAllFromListAndGrid(List<_VisibleRow> visible) {
    setState(() {
      for (final r in visible) {
        _selectedPaths.add(_itemPath(r.item));
      }
      for (final p in _visibleGalleryPaths) {
        _selectedPaths.add(MarketingStorageLayout.normalizeObjectPath(p));
      }
    });
  }

  Future<_CmsMaterialFormValues?> _showCmsMaterialFormDialog({
    required String suggestedTitle,
    required String kind,
    String initialDescription = '',
    String initialCategory = MarketingGalleryCms.categoryInstitucional,
    bool initialFeatured = false,
    bool isEdit = false,
  }) async {
    final titleCtrl = TextEditingController(text: suggestedTitle);
    final descCtrl = TextEditingController(text: initialDescription);
    var category = MarketingGalleryCms.normalizeCategory(initialCategory);
    var featured = initialFeatured;
    final kindLabel =
        kind == 'video' ? 'Vídeo' : kind == 'pdf' ? 'PDF' : 'Imagem';
    return showDialog<_CmsMaterialFormValues>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isEdit ? 'Editar material' : 'Novo material na galeria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tipo: $kindLabel',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título (site e painel)',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição curta (opcional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(category),
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  items: MarketingGalleryCms.categoryKeys
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(MarketingGalleryCms.categoryLabel(k)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    category = MarketingGalleryCms.normalizeCategory(v);
                  }),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Destaque no topo do site'),
                  value: featured,
                  onChanged: (v) => setLocal(() => featured = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final t = titleCtrl.text.trim();
                Navigator.pop(
                  context,
                  _CmsMaterialFormValues(
                    title: t.isEmpty ? suggestedTitle : t,
                    description: descCtrl.text.trim(),
                    category: category,
                    featured: featured,
                  ),
                );
              },
              child: Text(isEdit ? 'Salvar' : 'Continuar envio'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
        'm4v',
        'pdf',
      ],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Não foi possível ler o arquivo selecionado.')),
      );
      return;
    }

    final ext = _extOf(picked.name);
    final kind = _kindFromExt(ext);
    final suggestedTitle = _baseNameNoExt(picked.name);
    final form = await _showCmsMaterialFormDialog(
      suggestedTitle: suggestedTitle,
      kind: kind,
    );
    if (!mounted || form == null) return;

    final folder = switch (kind) {
      'video' => 'videos',
      'pdf' => 'pdf',
      _ => 'fotos',
    };
    final safeName = _slugifyFileName(picked.name);
    final storagePath =
        '${MarketingStorageLayout.storageRoot}/$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    StreamSubscription<TaskSnapshot>? sub;
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task = ref.putData(
        bytes,
        SettableMetadata(
          contentType: _contentTypeForExt(ext, kind),
          cacheControl: 'public, max-age=31536000',
        ),
      );
      sub = task.snapshotEvents.listen((snap) {
        if (!mounted) return;
        final total = snap.totalBytes;
        final p = total > 0 ? snap.bytesTransferred / total : 0.0;
        setState(() => _uploadProgress = p);
      });
      await task;

      String? downloadUrl;
      try {
        downloadUrl = await ref.getDownloadURL();
      } catch (_) {}

      final current = await _docRef.get();
      final items = _parseItems(current.data());
      items.add({
        'title': form.title,
        'description': form.description,
        'category': form.category,
        'featured': form.featured,
        'path': MarketingStorageLayout.normalizeObjectPath(storagePath),
        'kind': kind,
        if (downloadUrl != null && downloadUrl.isNotEmpty)
          'downloadUrl': downloadUrl,
        // Firestore não permite FieldValue.serverTimestamp() dentro de arrays.
        'uploadedAt': Timestamp.now(),
      });
      await _docRef.set({
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Mídia adicionada na divulgação.'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar mídia: $e')),
      );
    } finally {
      await sub?.cancel();
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _editItem(List<Map<String, dynamic>> items, int index) async {
    final it = Map<String, dynamic>.from(items[index]);
    final path = _itemPath(it);
    final kind = (it['kind'] ?? 'image').toString();
    final form = await _showCmsMaterialFormDialog(
      suggestedTitle: (it['title'] ?? _baseNameNoExt(path)).toString(),
      kind: kind,
      initialDescription: (it['description'] ?? '').toString(),
      initialCategory: (it['category'] ?? MarketingGalleryCms.categoryInstitucional)
          .toString(),
      initialFeatured: MarketingGalleryCms.truthy(it['featured']),
      isEdit: true,
    );
    if (!mounted || form == null) return;
    final copy = List<Map<String, dynamic>>.from(items);
    copy[index] = {
      ...it,
      'title': form.title,
      'description': form.description,
      'category': form.category,
      'featured': form.featured,
    };
    await _docRef.set({
      'items': copy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Material atualizado.'),
    );
  }

  Future<void> _toggleFeatured(List<Map<String, dynamic>> items, int index) async {
    final copy = items.map((e) => Map<String, dynamic>.from(e)).toList();
    final it = copy[index];
    final next = !MarketingGalleryCms.truthy(it['featured']);
    copy[index] = {...it, 'featured': next};
    await _docRef.set({
      'items': copy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _moveItem(List<Map<String, dynamic>> items, int from, int to) async {
    if (to < 0 || to >= items.length || from == to) return;
    final copy = List<Map<String, dynamic>>.from(items);
    final it = copy.removeAt(from);
    copy.insert(to, it);
    await _docRef.set({
      'items': copy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _removeItem(List<Map<String, dynamic>> items, int index) async {
    final item = items[index];
    final path = _itemPath(item);
    var deleteFile = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Excluir mídia'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O item deixa de aparecer na galeria do site e do painel. '
                'O ficheiro no Storage continua guardado, salvo se marcar a opção abaixo.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFile,
                onChanged: (v) => setLocal(() => deleteFile = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Apagar também o ficheiro no Storage (recomendado; irreversível)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    var firestoreRemoved = false;
    try {
      if (kIsWeb) {
        final snap = await _docRef.get();
        if (!snap.exists) throw StateError('GALLERY_DOC_MISSING');
        final fresh = _parseItems(snap.data());
        final remaining =
            fresh.where((e) => _itemPath(e) != path).toList();
        if (remaining.length == fresh.length) {
          throw StateError('GALLERY_ITEM_NOT_FOUND');
        }
        await _docRef.set({
          'items': _cloneGalleryItemMaps(remaining),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await FirebaseFirestore.instance.runTransaction((txn) async {
          final snap = await txn.get(_docRef);
          if (!snap.exists) throw StateError('GALLERY_DOC_MISSING');
          final fresh = _parseItems(snap.data());
          final remaining =
              fresh.where((e) => _itemPath(e) != path).toList();
          if (remaining.length == fresh.length) {
            throw StateError('GALLERY_ITEM_NOT_FOUND');
          }
          txn.set(
            _docRef,
            {
              'items': _cloneGalleryItemMaps(remaining),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });
      }
      firestoreRemoved = true;
    } catch (e, st) {
      debugPrint('AdminDivulgacao _removeItem: $e\n$st');
      if (!mounted) return;
      final es = e.toString();
      if (es.contains('GALLERY_DOC_MISSING')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deleteFile && path.isNotEmpty
                  ? 'Documento da galeria ausente no Firestore. Tentando só apagar o ficheiro no Storage…'
                  : 'Documento da galeria não existe no Firestore.',
            ),
          ),
        );
        if (!deleteFile || path.isEmpty) return;
      } else if (es.contains('GALLERY_ITEM_NOT_FOUND')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este item já não estava na lista do Firestore. Tentativa de apagar o ficheiro no Storage abaixo, se marcado.',
            ),
          ),
        );
        if (!deleteFile || path.isEmpty) return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar Firestore: ${_firestoreWriteErrorMessage(e)}',
            ),
          ),
        );
        return;
      }
    }

    if (deleteFile && path.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _selectedPaths.remove(path));
    if (firestoreRemoved) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Item removido da galeria (Firestore)${deleteFile ? ' e do Storage.' : '.'}',
        ),
      );
    } else if (deleteFile && path.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Exclusão no Storage tentada (Firestore não foi alterado).',
        ),
      );
    }
  }

  Future<void> _bulkRemove() async {
    if (_selectedPaths.isEmpty) return;
    var deleteFile = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Excluir ${_selectedPaths.length} mídia(s)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Serão removidos da galeria (Firestore) todos os itens selecionados na lista e/ou na grelha.',
                  style: TextStyle(color: Colors.grey.shade800, height: 1.35),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: deleteFile,
                  onChanged: (v) => setLocal(() => deleteFile = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Apagar também os ficheiros no Storage (recomendado; irreversível)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir selecionados'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkWorking = true);
    final removeNorm = _selectedPaths
        .map(MarketingStorageLayout.normalizeObjectPath)
        .where((s) => s.isNotEmpty)
        .toSet();

    var firestoreUpdated = false;
    var fsNoMatch = false;
    var docMissing = false;

    try {
      final snap = await _docRef.get();
      if (!snap.exists) {
        docMissing = true;
      } else {
        final items = _parseItems(snap.data());
        final remaining = items
            .where((e) => !removeNorm.contains(_itemPath(e)))
            .toList();
        final removedCount = items.length - remaining.length;
        if (removedCount > 0) {
          await _docRef.set({
            'items': _cloneGalleryItemMaps(remaining),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          firestoreUpdated = true;
        } else if (removeNorm.isNotEmpty) {
          fsNoMatch = true;
        }
      }
    } catch (e, st) {
      debugPrint('AdminDivulgacao _bulkRemove Firestore: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar Firestore: ${_firestoreWriteErrorMessage(e)}',
            ),
          ),
        );
      }
      if (mounted) setState(() => _bulkWorking = false);
      return;
    }

    if (!deleteFile && fsNoMatch && removeNorm.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhum item selecionado coincide com a lista no Firestore. '
              'Marque «apagar Storage» para remover só os ficheiros, ou use itens da lista CMS.',
            ),
          ),
        );
      }
      if (mounted) setState(() => _bulkWorking = false);
      return;
    }

    var storageOk = 0;
    var storageFail = 0;
    if (deleteFile) {
      for (final p in removeNorm) {
        try {
          await FirebaseStorage.instance.ref(p).delete();
          storageOk++;
        } catch (e) {
          storageFail++;
          debugPrint('AdminDivulgacao Storage delete failed ($p): $e');
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedPaths.clear();
      _selectionMode = false;
      _bulkWorking = false;
    });

    final parts = <String>[];
    if (firestoreUpdated) {
      parts.add('Galeria atualizada no Firestore.');
    } else if (docMissing && removeNorm.isNotEmpty) {
      parts.add('Sem documento ou lista vazia no Firestore (app_public/institutional_gallery).');
    } else if (fsNoMatch && removeNorm.isNotEmpty) {
      parts.add('Sem correspondência na lista Firestore (itens só no Storage).');
    }
    if (deleteFile) {
      if (storageOk > 0) {
        parts.add('$storageOk ficheiro(s) apagado(s) no Storage.');
      }
      if (storageFail > 0) {
        parts.add(
          '$storageFail falha(s) no Storage (regras ou caminho). Publique as regras atualizadas de /public/ se for master.',
        );
      }
    }
    if (parts.isEmpty) {
      parts.add('Operação concluída.');
    }
    if (mounted) {
      final isError = deleteFile && storageFail > 0 && storageOk == 0 && !firestoreUpdated;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts.join(' '), style: const TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: isError ? const Color(0xFF1E293B) : ThemeCleanPremium.success,
        ),
      );
    }
  }

  Widget _buildPeriodAndActionsToolbar(List<_VisibleRow> visible) {
    final isMobile = MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointTablet;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE5EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Período e seleção',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: isMobile ? 15 : 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(institutionalMediaPeriodLabel(InstitutionalMediaPeriod.all)),
                selected: _period == InstitutionalMediaPeriod.all,
                onSelected: (_) => setState(() {
                  _period = InstitutionalMediaPeriod.all;
                }),
              ),
              FilterChip(
                label: Text(institutionalMediaPeriodLabel(InstitutionalMediaPeriod.last7)),
                selected: _period == InstitutionalMediaPeriod.last7,
                onSelected: (_) => setState(() => _period = InstitutionalMediaPeriod.last7),
              ),
              FilterChip(
                label: Text(institutionalMediaPeriodLabel(InstitutionalMediaPeriod.last30)),
                selected: _period == InstitutionalMediaPeriod.last30,
                onSelected: (_) => setState(() => _period = InstitutionalMediaPeriod.last30),
              ),
              FilterChip(
                label: Text(institutionalMediaPeriodLabel(InstitutionalMediaPeriod.last90)),
                selected: _period == InstitutionalMediaPeriod.last90,
                onSelected: (_) => setState(() => _period = InstitutionalMediaPeriod.last90),
              ),
              ActionChip(
                avatar: Icon(
                  Icons.date_range_rounded,
                  size: 18,
                  color: _period == InstitutionalMediaPeriod.custom
                      ? ThemeCleanPremium.primary
                      : Colors.grey.shade700,
                ),
                label: Text(
                  _period == InstitutionalMediaPeriod.custom &&
                          _customStart != null &&
                          _customEnd != null
                      ? '${_customStart!.day}/${_customStart!.month}/${_customStart!.year} — '
                          '${_customEnd!.day}/${_customEnd!.month}/${_customEnd!.year}'
                      : institutionalMediaPeriodLabel(InstitutionalMediaPeriod.custom),
                ),
                onPressed: _pickCustomRange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Itens antigos sem data no Firestore usam a data no nome do ficheiro (timestamp). Fora do período ficam ocultos.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                avatar: Icon(
                  _selectionMode ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: _selectionMode ? _selectionGreen : Colors.grey.shade700,
                ),
                label: Text(_selectionMode ? 'Modo seleção ativo' : 'Selecionar várias'),
                selected: _selectionMode,
                selectedColor: _selectionGreenLight,
                checkmarkColor: _selectionGreen,
                labelStyle: TextStyle(
                  fontWeight: _selectionMode ? FontWeight.w800 : FontWeight.w600,
                  color: _selectionMode ? const Color(0xFF14532D) : const Color(0xFF475569),
                ),
                side: BorderSide(
                  color: _selectionMode ? _selectionGreen.withOpacity(0.5) : const Color(0xFFE2E8F0),
                ),
                onSelected: (_) => _toggleSelectionMode(),
              ),
              if (_selectionMode &&
                  (visible.isNotEmpty || _visibleGalleryPaths.isNotEmpty))
                OutlinedButton.icon(
                  onPressed: _bulkWorking
                      ? null
                      : () => _selectAllFromListAndGrid(visible),
                  icon: const Icon(Icons.select_all_rounded, size: 20),
                  label: const Text('Selecionar todas'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _selectionGreen,
                    side: const BorderSide(color: _selectionGreen),
                  ),
                ),
              if (_selectionMode && _selectedPaths.isNotEmpty)
                FilledButton.icon(
                  onPressed: _bulkWorking ? null : _bulkRemove,
                  icon: _bulkWorking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text('Excluir ${_selectedPaths.length} selecionada(s)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canReorder =
        _period == InstitutionalMediaPeriod.all && !_selectionMode;

    return SafeArea(
      child: SingleChildScrollView(
        padding: ThemeCleanPremium.pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFE5EAF3)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.perm_media_rounded, color: Color(0xFF2563EB)),
                  const Text(
                    'Mídias da página de divulgação',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded),
                    label: const Text('Adicionar foto/vídeo/PDF'),
                  ),
                  Text(
                    'Galeria em ${MarketingStorageLayout.storageRoot} — '
                    'CMS: título, descrição, categoria e destaque. Exclua da lista e, se quiser, apague o ficheiro no Storage.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_uploading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _uploadProgress != null && _uploadProgress! > 0
                      ? _uploadProgress
                      : null,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE8ECF4),
                  color: const Color(0xFF1E5AA8),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _uploadProgress != null && _uploadProgress! > 0
                    ? 'Enviando… ${(_uploadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%'
                    : 'Preparando envio…',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 16),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _docRef.snapshots(),
              builder: (context, snap) {
                final items = _parseItems(snap.data?.data());
                final visible = _visibleRows(items);

                if (items.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPeriodAndActionsToolbar(visible),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFE5EAF3)),
                        ),
                        child: const Text(
                          'Nenhum item ordenado ainda. Faça upload para começar.',
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPeriodAndActionsToolbar(visible),
                    const SizedBox(height: 16),
                    if (visible.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFE5EAF3)),
                        ),
                        child: Text(
                          'Nenhum item neste período. Ajuste o filtro ou use «Todo o período».',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFE5EAF3)),
                        ),
                        child: Column(
                          children: List.generate(visible.length, (vi) {
                            final row = visible[vi];
                            final it = row.item;
                            final i = row.originalIndex;
                            final title = (it['title'] ?? '').toString();
                            final kind = (it['kind'] ?? '').toString().toLowerCase();
                            final path = _itemPath(it);
                            final selected = _selectedPaths.contains(path);
                            final desc = (it['description'] ?? '').toString().trim();
                            final catKey = (it['category'] ?? '').toString();
                            final feat = MarketingGalleryCms.truthy(it['featured']);
                            final downloadUrl =
                                (it['downloadUrl'] ?? '').toString().trim();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFF0FDF4)
                                    : const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? _selectionGreen
                                      : const Color(0xFFDDE5F3),
                                  width: selected ? 2.5 : 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selectionMode)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8, top: 4),
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () => setState(() {
                                              if (selected) {
                                                _selectedPaths.remove(path);
                                              } else {
                                                _selectedPaths.add(path);
                                              }
                                            }),
                                            borderRadius: BorderRadius.circular(12),
                                            child: Icon(
                                              selected
                                                  ? Icons.check_box_rounded
                                                  : Icons.check_box_outline_blank_rounded,
                                              color: selected
                                                  ? _selectionGreen
                                                  : Colors.grey.shade700,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  _GalleryRowThumb(
                                    kind: kind,
                                    path: path,
                                    imageUrl:
                                        downloadUrl.isEmpty ? null : downloadUrl,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            if (feat)
                                              Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: const Text('Destaque'),
                                                avatar: Icon(Icons.star_rounded,
                                                    size: 16,
                                                    color: Colors.amber.shade800),
                                                backgroundColor:
                                                    Colors.amber.shade50,
                                                side: BorderSide.none,
                                                labelStyle: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            if (catKey.isNotEmpty)
                                              Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: Text(
                                                  MarketingGalleryCms
                                                      .categoryLabel(catKey),
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600),
                                                ),
                                                backgroundColor:
                                                    const Color(0xFFEFF6FF),
                                                side: const BorderSide(
                                                    color: Color(0xFFBFDBFE)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          title.isEmpty ? _baseNameNoExt(path) : title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15),
                                        ),
                                        if (desc.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            desc,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.3,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          path,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!_selectionMode) ...[
                                    IconButton(
                                      tooltip: feat
                                          ? 'Remover destaque'
                                          : 'Destacar no site',
                                      onPressed: () => _toggleFeatured(items, i),
                                      icon: Icon(
                                        feat
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        color: feat
                                            ? Colors.amber.shade800
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Editar CMS',
                                      onPressed: () => _editItem(items, i),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: 'Subir',
                                    onPressed: !canReorder || vi == 0
                                        ? null
                                        : () => _moveItem(
                                            items, i, visible[vi - 1].originalIndex),
                                    icon: const Icon(Icons.arrow_upward_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Descer',
                                    onPressed: !canReorder || vi >= visible.length - 1
                                        ? null
                                        : () => _moveItem(
                                            items, i, visible[vi + 1].originalIndex),
                                    icon: const Icon(Icons.arrow_downward_rounded),
                                  ),
                                  if (!_selectionMode) ...[
                                    OutlinedButton.icon(
                                      onPressed: () => _removeItem(items, i),
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          size: 18, color: Color(0xFFDC2626)),
                                      label: const Text('Excluir'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFDC2626),
                                        side: const BorderSide(color: Color(0xFFFECACA)),
                                        minimumSize: const Size(48, 48),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            MarketingGestaoYahwehGallerySection(
              adminConfig: _adminGalleryConfig,
              maxStorageFiles: 200,
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura real para fotos (Storage resiliente); ícone para vídeo/PDF.
class _GalleryRowThumb extends StatelessWidget {
  final String kind;
  final String path;
  final String? imageUrl;

  const _GalleryRowThumb({
    required this.kind,
    required this.path,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final k = kind.toLowerCase();
    if (k == 'video') {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FE),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_fill_rounded,
            color: Color(0xFF7C3AED), size: 30),
      );
    }
    if (k == 'pdf') {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.picture_as_pdf_rounded,
            color: Colors.red.shade700, size: 28),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (52 * dpr).round().clamp(64, 200);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
        child: StableStorageImage(
          storagePath: path,
          imageUrl: imageUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          memCacheWidth: px,
          memCacheHeight: px,
          placeholder: Container(
            color: const Color(0xFFF1F5F9),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: Icon(Icons.image_rounded,
              color: Colors.blue.shade300, size: 28),
        ),
      ),
    );
  }
}

String _extOf(String name) {
  final low = name.toLowerCase().trim();
  final dot = low.lastIndexOf('.');
  if (dot < 0 || dot == low.length - 1) return '';
  return low.substring(dot + 1);
}

String _baseNameNoExt(String name) {
  final clean = name.replaceAll('\\', '/');
  final base = clean.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return base;
  return base.substring(0, dot);
}

String _kindFromExt(String ext) {
  if (ext == 'mp4' || ext == 'mov' || ext == 'webm' || ext == 'm4v') return 'video';
  if (ext == 'pdf') return 'pdf';
  return 'image';
}

String _contentTypeForExt(String ext, String kind) {
  if (kind == 'video') {
    if (ext == 'webm') return 'video/webm';
    if (ext == 'mov') return 'video/quicktime';
    return 'video/mp4';
  }
  if (kind == 'pdf') return 'application/pdf';
  if (ext == 'png') return 'image/png';
  if (ext == 'webp') return 'image/webp';
  if (ext == 'gif') return 'image/gif';
  return 'image/jpeg';
}

String _slugifyFileName(String input) {
  final noSpaces = input.trim().replaceAll(RegExp(r'\s+'), '_').toLowerCase();
  final safe = noSpaces.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
  if (safe.isEmpty) return 'arquivo.bin';
  return safe;
}
