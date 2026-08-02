import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/constants/utilitarios_module_icons.dart';
import 'package:gestao_yahweh/services/utilitarios_local_service.dart';
import 'package:gestao_yahweh/services/utilitarios_pdf_preserve_export.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';

/// Resultado das ferramentas PDF (merge / split / editor).
class UtilitariosPdfToolResult {
  const UtilitariosPdfToolResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.message,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String message;
}

enum UtilitariosPdfToolMode { merge, split, edit }

/// Formato de exportacao do editor PDF.
enum _ExportFormat { pdf, word, png, jpg }

/// Card de formato de exportacao no hub moderno.
class _ExportFormatCard extends StatelessWidget {
  const _ExportFormatCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: gradient.map((c) => c.withValues(alpha: 0.12)).toList(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: gradient.first.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<UtilitariosPdfToolResult?> openUtilitariosPdfToolFlow(
  BuildContext context,
  UtilitariosPdfToolMode mode,
) {
  return Navigator.of(context).push<UtilitariosPdfToolResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _UtilitariosPdfToolPage(mode: mode),
    ),
  );
}

class _PdfSource {
  _PdfSource(
      {required this.name, required this.bytes, required this.pageCount});
  final String name;
  final Uint8List bytes;
  final int pageCount;
}

class _MergePageItem {
  _MergePageItem({
    required this.sourceIndex,
    required this.pageIndex,
  }) : thumb = null;
  final int sourceIndex;
  final int pageIndex;
  Uint8List? thumb;
}

class _UtilitariosPdfToolPage extends StatefulWidget {
  const _UtilitariosPdfToolPage({required this.mode});
  final UtilitariosPdfToolMode mode;

  @override
  State<_UtilitariosPdfToolPage> createState() =>
      _UtilitariosPdfToolPageState();
}

enum _PdfEditorTool {
  pickField,
  select,
  text,
  highlight,
  whiteout,
  check,
  erase
}

/// Modo de visualização do editor: documento ou grade de páginas.
enum _EditViewMode { document, grid }

class _UtilitariosPdfToolPageState extends State<_UtilitariosPdfToolPage> {
  static final Uint8List _kThumbPending = Uint8List(0);

  bool _busy = false;
  String? _busyLabel;

  // Merge
  final _sources = <_PdfSource>[];
  final _mergeOrder = <_MergePageItem>[];

  // Split / Edit
  Uint8List? _singlePdf;
  String? _singleName;
  List<Uint8List> _thumbs = const [];
  final Set<int> _splitSelected = {};
  List<int> _splitPageOrder = const [];
  int _splitRangeFrom = 1;
  int _splitRangeTo = 1;
  final TextEditingController _splitRangeFromCtrl =
      TextEditingController(text: '1');
  final TextEditingController _splitRangeToCtrl =
      TextEditingController(text: '1');
  bool _splitThumbsLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _splitRangeFromCtrl.dispose();
    _splitRangeToCtrl.dispose();
    super.dispose();
  }

  bool _thumbReady(Uint8List thumb) => thumb.isNotEmpty;

  int get _singlePdfPageCount => _thumbs.length;

  void _syncSplitRangeCtrls() {
    final from =
        _splitRangeFrom.clamp(1, math.max(1, _singlePdfPageCount)).toInt();
    final to = _splitRangeTo.clamp(1, math.max(1, _singlePdfPageCount)).toInt();
    _splitRangeFrom = from;
    _splitRangeTo = to;
    if (_splitRangeFromCtrl.text != '$from') {
      _splitRangeFromCtrl.text = '$from';
    }
    if (_splitRangeToCtrl.text != '$to') {
      _splitRangeToCtrl.text = '$to';
    }
  }

  /// Lê De/Até digitados nos campos antes de gerar (mesmo sem «Aplicar intervalo»).
  void _readSplitRangeFromControllers() {
    final total = math.max(1, _singlePdfPageCount);
    final fromN = int.tryParse(_splitRangeFromCtrl.text.trim());
    final toN = int.tryParse(_splitRangeToCtrl.text.trim());
    if (fromN != null) {
      _splitRangeFrom = fromN.clamp(1, total).toInt();
    }
    if (toN != null) {
      _splitRangeTo = toN.clamp(1, total).toInt();
    }
  }

  void _commitSplitRangeFromField() {
    final n = int.tryParse(_splitRangeFromCtrl.text.trim());
    if (n == null) {
      _syncSplitRangeCtrls();
      return;
    }
    setState(() {
      _splitRangeFrom = n.clamp(1, math.max(1, _singlePdfPageCount)).toInt();
      _applySplitRangeSync();
    });
  }

  void _commitSplitRangeToField() {
    final n = int.tryParse(_splitRangeToCtrl.text.trim());
    if (n == null) {
      _syncSplitRangeCtrls();
      return;
    }
    setState(() {
      _splitRangeTo = n.clamp(1, math.max(1, _singlePdfPageCount)).toInt();
      _applySplitRangeSync();
    });
  }

  Future<void> _loadSinglePdfThumbsProgressive() async {
    final pdf = _singlePdf;
    if (pdf == null || _thumbs.isEmpty) return;
    if (_splitThumbsLoading) return;
    _splitThumbsLoading = true;
    final thumbWidth =
        widget.mode == UtilitariosPdfToolMode.split ? 240.0 : 360.0;
    final thumbQuality = widget.mode == UtilitariosPdfToolMode.split ? 74 : 82;
    final baseOrder = widget.mode == UtilitariosPdfToolMode.edit
        ? <int>[0, ...List.generate(_thumbs.length - 1, (i) => i + 1)]
        : List<int>.generate(_thumbs.length, (i) => i);
    final pending = baseOrder.where((i) => !_thumbReady(_thumbs[i])).toList();
    const chunkSize = 15;
    try {
      for (var start = 0; start < pending.length; start += chunkSize) {
        if (!mounted) return;
        final batch = pending.sublist(
          start,
          math.min(start + chunkSize, pending.length),
        );
        final rendered = await UtilitariosLocalService.renderPdfPagesAt(
          pdf,
          batch,
          fullWidth: thumbWidth,
          jpegQuality: thumbQuality,
        );
        for (final e in rendered.entries) {
          _thumbs[e.key] = e.value;
        }
        if (mounted) setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _splitThumbsLoading = false);
      } else {
        _splitThumbsLoading = false;
      }
    }
  }

  // Editor
  int _editPage = 0;
  final List<Uint8List?> _editPageImages = [];
  final List<double> _editPageAspects = [];

  /// Tamanho físico original (pontos PDF) — preservado no export/compartilhar.
  final List<({double widthPts, double heightPts})> _editPageSizesPts = [];
  final List<List<UtilPdfTextField>> _docFields = [];
  final Set<String> _editedFieldIds = {};
  String? _selectedFieldId;
  bool _detectingFields = false;
  final List<List<UtilPdfPageAnnotation>> _annotations = [];
  _PdfEditorTool _editTool = _PdfEditorTool.select;
  _EditViewMode _editViewMode = _EditViewMode.document;
  /// Chrome mínimo no documento — página quase tela cheia (toque nos campos).
  bool _editToolsExpanded = false;
  bool _editThumbsExpanded = false;
  String? _selectedAnnId;
  final List<List<List<UtilPdfPageAnnotation>>> _undo = [];
  final GlobalKey _pageCanvasKey = GlobalKey();
  double _textFontScale = 1.0;
  int _highlightColor = 0xFFFFF59D;
  int _textColor = 0xFF1E293B;

  List<Color> get _gradient => switch (widget.mode) {
        UtilitariosPdfToolMode.merge => const [
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
            Color(0xFF06B6D4)
          ],
        UtilitariosPdfToolMode.split => const [
            Color(0xFFEA580C),
            Color(0xFFF97316),
            Color(0xFFFBBF24)
          ],
        UtilitariosPdfToolMode.edit => const [
            Color(0xFF059669),
            Color(0xFF10B981),
            Color(0xFF34D399)
          ],
      };

  String get _title => switch (widget.mode) {
        UtilitariosPdfToolMode.merge => 'Juntar PDF',
        UtilitariosPdfToolMode.split => 'Dividir PDF',
        UtilitariosPdfToolMode.edit => 'Editor PDF',
      };

  Future<void> _withBusy(String label, Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(utilitariosFormatPickError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  bool get _hasWork => switch (widget.mode) {
        UtilitariosPdfToolMode.merge => _mergeOrder.isNotEmpty,
        UtilitariosPdfToolMode.split => _singlePdf != null,
        UtilitariosPdfToolMode.edit => _singlePdf != null,
      };

  bool get _hasUnsavedEditWork {
    if (widget.mode != UtilitariosPdfToolMode.edit) return false;
    if (_editedFieldIds.isNotEmpty) return true;
    for (final page in _annotations) {
      if (page.isNotEmpty) return true;
    }
    return false;
  }

  void _clearAllWork() {
    _sources.clear();
    _mergeOrder.clear();
    _singlePdf = null;
    _singleName = null;
    _thumbs = const [];
    _splitSelected.clear();
    _splitPageOrder = const [];
    _splitRangeFrom = 1;
    _splitRangeTo = 1;
    _splitThumbsLoading = false;
    _syncSplitRangeCtrls();
    _editPage = 0;
    _editPageImages.clear();
    _editPageAspects.clear();
    _editPageSizesPts.clear();
    _docFields.clear();
    _editedFieldIds.clear();
    _selectedFieldId = null;
    _detectingFields = false;
    _annotations.clear();
    _editTool = _PdfEditorTool.select;
    _editViewMode = _EditViewMode.document;
    _editToolsExpanded = false;
    _editThumbsExpanded = false;
    _selectedAnnId = null;
    _undo.clear();
    _textFontScale = 1.0;
  }

  Future<bool> _confirmDiscard(String message) async {
    final dirty = _hasUnsavedEditWork ||
        (widget.mode == UtilitariosPdfToolMode.merge &&
            _mergeOrder.isNotEmpty) ||
        (widget.mode != UtilitariosPdfToolMode.merge && _singlePdf != null);
    if (!dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Descartar operação?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _gradient.first),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onCloseFlow() async {
    if (_busy) return;
    if (!await _confirmDiscard(
      'Sair e descartar o que foi feito nesta ferramenta?',
    )) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onCancelOperation() async {
    if (_busy) return;
    if (!_hasWork) {
      await _onCloseFlow();
      return;
    }
    if (!await _confirmDiscard(
      'Cancelar e voltar para escolher outro arquivo?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(_clearAllWork);
  }

  Future<void> _onTrocarArquivo() async {
    if (_busy || !_hasWork) return;
    if (!await _confirmDiscard(
      'Trocar de arquivo? O progresso atual será descartado.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(_clearAllWork);
    await _pickPdfs(
      multiple: widget.mode == UtilitariosPdfToolMode.merge,
    );
  }

  ButtonStyle _sessionOutlinedStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        foregroundColor: _gradient.first,
        side: BorderSide(
            color: _gradient.first.withValues(alpha: 0.38), width: 1.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  String get _trocarArquivoLabel => switch (widget.mode) {
        UtilitariosPdfToolMode.merge => 'Outros PDFs',
        _ => 'Trocar PDF',
      };

  Future<void> _pickPdfs({required bool multiple}) async {
    await _withBusy('Lendo PDF…', () async {
      if (widget.mode == UtilitariosPdfToolMode.merge) {
        final picked = await utilitariosPickMultipleFileBytes(
          allowedExtensions: const ['pdf'],
        );
        var added = 0;
        for (final f in picked) {
          if (!_isPdfFileName(f.name)) continue;
          if (f.bytes.isEmpty) continue;
          UtilitariosLocalService.ensureWithinSize(f.bytes, label: 'PDF');
          final n = await UtilitariosLocalService.pdfPageCount(f.bytes);
          _sources.add(
            _PdfSource(
              name: f.name,
              bytes: f.bytes,
              pageCount: n,
            ),
          );
          for (var p = 0; p < n; p++) {
            if (_mergeOrder.length >=
                UtilitariosLocalService.kMaxPdfPagesTools) {
              throw StateError(
                'Máximo de ${UtilitariosLocalService.kMaxPdfPagesTools} páginas por união. '
                'Remova páginas ou use um PDF menor.',
              );
            }
            _mergeOrder.add(
              _MergePageItem(sourceIndex: _sources.length - 1, pageIndex: p),
            );
          }
          added++;
        }
        if (added == 0) {
          throw StateError(
            'Não foi possível ler os PDFs. Salve no aparelho e tente outro arquivo.',
          );
        }
        if (mounted) setState(() {});
        await _loadMergeThumbs();
      } else {
        final picked = await utilitariosPickSingleFileBytes(
          allowedExtensions: const ['pdf'],
        );
        if (picked == null) return;
        if (!_isPdfFileName(picked.name)) {
          throw StateError('Escolha um arquivo PDF (.pdf).');
        }
        if (picked.bytes.isEmpty) throw StateError('Arquivo vazio.');
        UtilitariosLocalService.ensureWithinSize(picked.bytes, label: 'PDF');
        late final int pageCount;
        try {
          // O pdfrx tenta automaticamente senha vazia. Isso abre PDFs com
          // restrições/owner password sem perguntar nada ao usuário.
          pageCount = await UtilitariosLocalService.pdfPageCount(picked.bytes);
        } catch (e) {
          final message = e.toString().toLowerCase();
          if (message.contains('password') ||
              message.contains('senha') ||
              message.contains('encrypted')) {
            throw StateError(
              'Este PDF exige uma senha secreta para ser aberto. '
              'Sem a chave não é tecnicamente possível descriptografar o conteúdo. '
              'PDFs que apenas bloqueiam edição, cópia ou impressão são limpos '
              'automaticamente, sem pedir senha.',
            );
          }
          rethrow;
        }
        _singlePdf = picked.bytes;
        _singleName = picked.name;
        if (pageCount > UtilitariosLocalService.kMaxPdfPagesTools) {
          throw StateError(
            'Máximo de ${UtilitariosLocalService.kMaxPdfPagesTools} páginas por PDF.',
          );
        }
        if (pageCount < 1) throw StateError('PDF sem páginas.');
        _thumbs = List<Uint8List>.filled(pageCount, _kThumbPending);
        _splitPageOrder = List.generate(pageCount, (i) => i);
        _splitSelected
          ..clear()
          ..addAll(_splitPageOrder);
        _splitRangeFrom = 1;
        _splitRangeTo = pageCount;
        _syncSplitRangeCtrls();
        if (widget.mode == UtilitariosPdfToolMode.edit) {
          _annotations
            ..clear()
            ..addAll(
                List.generate(pageCount, (_) => <UtilPdfPageAnnotation>[]));
          _editPageImages
            ..clear()
            ..addAll(List<Uint8List?>.filled(pageCount, null));
          _editPageAspects
            ..clear()
            ..addAll(List<double>.filled(pageCount, 1.0));
          _editPageSizesPts
            ..clear()
            ..addAll(
              List.generate(
                pageCount,
                (_) => (widthPts: 595.27, heightPts: 841.89),
              ),
            );
          _docFields
            ..clear()
            ..addAll(List.generate(pageCount, (_) => <UtilPdfTextField>[]));
          _editedFieldIds.clear();
          _editPage = 0;
          _selectedAnnId = null;
          _selectedFieldId = null;
          _editTool = _PdfEditorTool.pickField;
          _editViewMode = _EditViewMode.document;
          _editToolsExpanded = false;
          _editThumbsExpanded = false;
          _undo.clear();
          unawaited(_loadEditPageSizes(picked.bytes).then((_) {
            if (mounted) unawaited(_ensureEditPageReady(0));
          }));
          // Não dispara ensure em paralelo — espera tamanhos reais do PDF.
        }
        if (mounted) setState(() {});
        unawaited(_loadSinglePdfThumbsProgressive());
      }
    });
  }

  bool _isPdfFileName(String name) {
    return name.toLowerCase().trim().endsWith('.pdf');
  }

  Future<void> _loadMergeThumbs() async {
    const batchSize = 5;
    final pending = _mergeOrder.where((item) => item.thumb == null).toList();
    for (var start = 0; start < pending.length; start += batchSize) {
      if (!mounted) return;
      final batch = pending.sublist(
        start,
        math.min(start + batchSize, pending.length),
      );
      final futures = batch.map((item) async {
        final src = _sources[item.sourceIndex];
        item.thumb = await UtilitariosLocalService.renderPdfPageAt(
          src.bytes,
          item.pageIndex,
          fullWidth: 200,
        );
      });
      await Future.wait(futures);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmMerge() async {
    if (_mergeOrder.isEmpty) {
      throw StateError('Adicione ao menos um PDF.');
    }
    await _withBusy('Unindo páginas…', () async {
      final order = _mergeOrder
          .map(
            (e) => (
              pdf: _sources[e.sourceIndex].bytes,
              pageIndex: e.pageIndex,
            ),
          )
          .toList();
      final pdf = await UtilitariosLocalService.mergeOrderedPdfPages(order);
      if (!mounted) return;
      Navigator.pop(
        context,
        UtilitariosPdfToolResult(
          bytes: pdf,
          fileName: 'pdf_unido_gestao_yahweh.pdf',
          mimeType: 'application/pdf',
          message:
              'PDF unido com ${_mergeOrder.length} página(s) na ordem escolhida.',
        ),
      );
    });
  }

  List<int> get _splitExportOrder => _splitPageOrder
      .where((p) => _splitSelected.contains(p))
      .toList(growable: false);

  /// Páginas efetivas para exportar — respeita intervalo De/Até mesmo sem «Aplicar».
  List<int> _resolveSplitExportOrder() {
    if (_thumbs.isEmpty) return const [];

    var from = _splitRangeFrom;
    var to = _splitRangeTo;
    final fromCtrl = int.tryParse(_splitRangeFromCtrl.text.trim());
    final toCtrl = int.tryParse(_splitRangeToCtrl.text.trim());
    if (fromCtrl != null) {
      from = fromCtrl.clamp(1, math.max(1, _thumbs.length)).toInt();
    }
    if (toCtrl != null) {
      to = toCtrl.clamp(1, math.max(1, _thumbs.length)).toInt();
    }

    final rangeFrom = math.min(from, to);
    final rangeTo = math.max(from, to);
    final start = (rangeFrom - 1).clamp(0, _thumbs.length - 1);
    final end = (rangeTo - 1).clamp(0, _thumbs.length - 1);
    final rangePages = List.generate(end - start + 1, (i) => start + i);
    final rangeSet = rangePages.toSet();

    final current = _splitExportOrder;
    final allPagesStillSelected = _splitSelected.length >= _thumbs.length;
    final rangeIsNarrower = rangePages.length < _thumbs.length;

    // Usuário restringiu De/Até mas a seleção ainda está em «todas».
    if (allPagesStillSelected && rangeIsNarrower) {
      return _splitPageOrder.where(rangeSet.contains).toList(growable: false);
    }

    return current;
  }

  void _applySplitRangeSync() {
    if (_thumbs.isEmpty) return;
    final from = math.min(_splitRangeFrom, _splitRangeTo);
    final to = math.max(_splitRangeFrom, _splitRangeTo);
    final start = (from - 1).clamp(0, _thumbs.length - 1);
    final end = (to - 1).clamp(0, _thumbs.length - 1);
    _splitRangeFrom = from;
    _splitRangeTo = to;
    _splitSelected
      ..clear()
      ..addAll(List.generate(end - start + 1, (i) => start + i));
    _syncSplitRangeCtrls();
  }

  Future<void> _confirmSplit() async {
    final pdf = _singlePdf;
    if (pdf == null) throw StateError('Selecione um PDF.');
    _readSplitRangeFromControllers();
    final exportOrder = _resolveSplitExportOrder();
    if (exportOrder.isEmpty) {
      throw StateError(
          'Marque ao menos uma página ou defina um intervalo válido.');
    }
    await _withBusy('Gerando PDF…', () async {
      final out = await UtilitariosLocalService.splitPdfPages(
        pdf,
        exportOrder,
        onePdfPerPage: false,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        UtilitariosPdfToolResult(
          bytes: out.bytes,
          fileName: out.fileName,
          mimeType: out.mime,
          message:
              'PDF gerado com ${exportOrder.length} página(s) na ordem escolhida.',
        ),
      );
    });
  }

  void _applySplitRange() {
    if (_thumbs.isEmpty) return;
    setState(_applySplitRangeSync);
  }

  void _selectAllSplitPages() {
    if (_thumbs.isEmpty) return;
    setState(() {
      _splitRangeFrom = 1;
      _splitRangeTo = _thumbs.length;
      _splitSelected
        ..clear()
        ..addAll(_splitPageOrder);
    });
  }

  void _clearSplitSelection() {
    setState(() => _splitSelected.clear());
  }

  void _quickSelectPages(bool Function(int pageIndex) predicate) {
    setState(() {
      _splitSelected.clear();
      for (var i = 0; i < _thumbs.length; i++) {
        if (predicate(i)) _splitSelected.add(i);
      }
    });
  }

  Widget _splitQuickBtn(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _gradient.first.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _gradient.first.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _gradient.first,
            ),
          ),
        ),
      ),
    );
  }

  void _moveSplitPage(int fromIndex, int toIndex) {
    if (fromIndex == toIndex || _splitPageOrder.isEmpty) return;
    setState(() {
      final item = _splitPageOrder.removeAt(fromIndex);
      var insertAt = toIndex;
      if (insertAt > fromIndex) insertAt--;
      insertAt = insertAt.clamp(0, _splitPageOrder.length);
      _splitPageOrder.insert(insertAt, item);
    });
  }

  String _splitOrderSummary(List<int> exportOrder) {
    if (exportOrder.isEmpty) return '';
    if (exportOrder.length == 1) {
      return 'Selecionada: página ${exportOrder.first + 1}';
    }
    if (exportOrder.length <= 6) {
      return 'Ordem: ${exportOrder.map((p) => p + 1).join(' → ')}';
    }
    final head = exportOrder.take(3).map((p) => p + 1).join(' → ');
    return 'Ordem: $head … → ${exportOrder.last + 1}';
  }

  Widget _buildSplitIntervalPanel({
    required int total,
    required int selectedCount,
    required List<int> exportOrder,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ModernModuleUI.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gradient.first.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _gradient.first.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: _gradient.first),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Intervalo de páginas',
                  style: ModernModuleUI.moduleTitleStyle(context, fontSize: 14),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _gradient.first.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$selectedCount de $total',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: _gradient.first,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _splitRangeField(
                  label: 'De',
                  controller: _splitRangeFromCtrl,
                  onMinus: () => _bumpSplitRange(fromField: true, delta: -1),
                  onPlus: () => _bumpSplitRange(fromField: true, delta: 1),
                  onCommit: _commitSplitRangeFromField,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: _gradient.first.withValues(alpha: 0.7),
                ),
              ),
              Expanded(
                child: _splitRangeField(
                  label: 'Até',
                  controller: _splitRangeToCtrl,
                  onMinus: () => _bumpSplitRange(fromField: false, delta: -1),
                  onPlus: () => _bumpSplitRange(fromField: false, delta: 1),
                  onCommit: _commitSplitRangeToField,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _splitActionChip(
                icon: Icons.checklist_rounded,
                label: 'Aplicar intervalo',
                primary: true,
                onTap: _busy ? null : _applySplitRange,
              ),
              _splitActionChip(
                icon: Icons.select_all_rounded,
                label: 'Todas',
                onTap: _busy ? null : _selectAllSplitPages,
              ),
              _splitActionChip(
                icon: Icons.deselect_rounded,
                label: 'Limpar',
                onTap: _busy ? null : _clearSplitSelection,
              ),
            ],
          ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              _splitOrderSummary(exportOrder),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitPageGridTile({
    required int listIndex,
    required int pageIdx,
    required bool selected,
  }) {
    Widget card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _toggleSplitPage(pageIdx),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _gradient.first : Colors.grey.shade300,
              width: selected ? 2.5 : 1,
            ),
            color: selected
                ? _gradient.first.withValues(alpha: 0.08)
                : ModernModuleUI.cardBg(context),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _gradient.first.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _thumbReady(_thumbs[pageIdx])
                            ? Image.memory(
                                _thumbs[pageIdx],
                                fit: BoxFit.contain,
                                width: double.infinity,
                                gaplessPlayback: true,
                              )
                            : Center(
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: _gradient.first,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pág. ${pageIdx + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: selected ? _gradient.first : null,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: _gradient.first.withValues(alpha: 0.75),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _gradient.first,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (_busy) return card;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != listIndex,
      onAcceptWithDetails: (d) => _moveSplitPage(d.data, listIndex),
      builder: (context, candidates, rejected) {
        final highlight = candidates.isNotEmpty;
        return LongPressDraggable<int>(
          data: listIndex,
          delay: const Duration(milliseconds: 140),
          feedback: Material(
            color: Colors.transparent,
            elevation: 10,
            shadowColor: _gradient.first.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(width: 132, height: 168, child: card),
          ),
          childWhenDragging: Opacity(opacity: 0.32, child: card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: highlight
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _gradient.first, width: 2),
                  )
                : null,
            child: card,
          ),
        );
      },
    );
  }

  void _toggleSplitPage(int pageIndex) {
    setState(() {
      if (_splitSelected.contains(pageIndex)) {
        _splitSelected.remove(pageIndex);
      } else {
        _splitSelected.add(pageIndex);
      }
      final exportOrder = _splitExportOrder;
      if (exportOrder.isNotEmpty) {
        _splitRangeFrom = exportOrder.first + 1;
        _splitRangeTo = exportOrder.last + 1;
      }
    });
  }

  void _bumpSplitRange({required bool fromField, required int delta}) {
    if (_thumbs.isEmpty) return;
    setState(() {
      if (fromField) {
        _splitRangeFrom =
            (_splitRangeFrom + delta).clamp(1, _singlePdfPageCount).toInt();
      } else {
        _splitRangeTo =
            (_splitRangeTo + delta).clamp(1, _singlePdfPageCount).toInt();
      }
      _applySplitRangeSync();
    });
  }

  String _editedFileName() {
    final raw = _singleName ?? 'documento.pdf';
    final base = raw.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return '${base}_editado.pdf';
  }

  String _passwordFreeFileName() {
    final raw = _singleName ?? 'documento.pdf';
    final base = raw.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return '${base}_sem_senha.pdf';
  }

  Future<void> _removePdfPassword() async {
    final pdf = _singlePdf;
    if (pdf == null || _thumbs.isEmpty || _busy) return;

    // Sem diálogo: um toque limpa a proteção e já entrega a cópia aberta.
    // Cada página é re-renderizada pelo PDFium (que abre PDFs com senha de
    // dono/restrições) e um PDF totalmente novo é montado — sem qualquer
    // senha, sem bloqueio de cópia/impressão/edição.
    await _withBusy('Limpando senha e gerando PDF aberto…', () async {
      final pages = <Uint8List>[];
      for (var i = 0; i < _thumbs.length; i++) {
        final base = await UtilitariosLocalService.renderPdfPageAt(
          pdf,
          i,
          fullWidth: 1600,
        );
        final flat =
            await UtilitariosLocalService.flattenPdfPageWithAnnotations(
          base,
          i < _annotations.length ? _annotations[i] : const [],
        );
        pages.add(flat);
      }
      final sizes = _editPageSizesPts.length == pages.length
          ? List<({double widthPts, double heightPts})>.from(_editPageSizesPts)
          : await UtilitariosLocalService.pdfAllPagePointSizes(pdf);
      final out = await UtilitariosLocalService.exportEditedPdfPages(
        pages,
        pageSizesPts: sizes,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        UtilitariosPdfToolResult(
          bytes: out,
          fileName: _passwordFreeFileName(),
          mimeType: 'application/pdf',
          message:
              'Novo PDF aberto (sem senha) criado com ${_thumbs.length} página(s). Salve ou compartilhe.',
        ),
      );
    });
  }

  Future<void> _loadEditPageSizes(Uint8List pdfBytes) async {
    try {
      final sizes =
          await UtilitariosLocalService.pdfAllPagePointSizes(pdfBytes);
      if (!mounted || sizes.isEmpty) return;
      setState(() {
        _editPageSizesPts
          ..clear()
          ..addAll(sizes);
        // Proporção do papel original (A4 etc.) — alinhada à visualização.
        for (var i = 0; i < sizes.length && i < _editPageAspects.length; i++) {
          final w = sizes[i].widthPts;
          final h = sizes[i].heightPts;
          if (w > 0 && h > 0) {
            _editPageAspects[i] = w / h;
          }
        }
      });
    } catch (_) {
      // Mantém fallback A4 já preenchido.
    }
  }

  Future<void> _ensureEditPageReady(int page) async {
    final pdf = _singlePdf;
    if (pdf == null || page < 0 || page >= _thumbs.length) return;
    if (_editPageImages[page] != null && _docFields[page].isNotEmpty) return;

    if (!mounted) return;
    setState(() => _detectingFields = true);
    try {
      if (_editPageImages[page] == null) {
        final size = await UtilitariosLocalService.pdfPageRenderPixelSize(
          pdf,
          page,
        );
        _editPageAspects[page] =
            size.width > 0 ? size.width / size.height : 1.0;
        final mq = MediaQuery.sizeOf(context);
        final renderWidth = kIsWeb
            ? math.max(
                UtilitariosLocalService.kPdfEditRenderWidth,
                mq.width * 1.35,
              )
            : UtilitariosLocalService.kPdfEditRenderWidth;
        _editPageImages[page] = await UtilitariosLocalService.renderPdfPageAt(
          pdf,
          page,
          fullWidth: renderWidth,
        );
      }
      if (_docFields[page].isEmpty) {
        _docFields[page] =
            await UtilitariosLocalService.detectPdfPageTextFields(
          pdf,
          page,
          pageJpeg: _editPageImages[page],
        );
      }
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      if (mounted) setState(() => _detectingFields = false);
    }
  }

  Rect _imageRectInCanvas(Size canvas, double aspect) {
    if (aspect <= 0) aspect = 1;
    final canvasAspect = canvas.width / canvas.height;
    if (aspect > canvasAspect) {
      final w = canvas.width;
      final h = w / aspect;
      return Rect.fromLTWH(0, (canvas.height - h) / 2, w, h);
    }
    final h = canvas.height;
    final w = h * aspect;
    return Rect.fromLTWH((canvas.width - w) / 2, 0, w, h);
  }

  Offset? _canvasToNormalized(Offset local, Size canvas, double aspect) {
    final r = _imageRectInCanvas(canvas, aspect);
    if (!r.contains(local)) return null;
    return Offset(
      ((local.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((local.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  List<UtilPdfTextField> get _currentFields =>
      _docFields.isEmpty ? const [] : _docFields[_editPage];

  UtilPdfTextField? get _selectedField {
    final id = _selectedFieldId;
    if (id == null) return null;
    for (final f in _currentFields) {
      if (f.id == id) return f;
    }
    return null;
  }

  UtilPdfTextField? _fieldAt(double nx, double ny) {
    for (final f in _currentFields.reversed) {
      if (nx >= f.nx && nx <= f.nx + f.nw && ny >= f.ny && ny <= f.ny + f.nh) {
        return f;
      }
    }
    return null;
  }

  String _effectiveFieldText(UtilPdfTextField field, int pageIndex) {
    for (final a in _annotations[pageIndex]) {
      if (a.id == 'ann_${field.id}') return a.text;
    }
    return field.text;
  }

  double _fontScaleForField(UtilPdfTextField field) {
    // O tamanho da fonte agora deriva da altura real do campo detectado
    // (render vetorial). Escala 1.0 = manter exatamente o tamanho original.
    return 1.0;
  }

  ({int textArgb, bool fontBold, double fontScale}) _styleForField(
    UtilPdfTextField field,
    int pageIndex,
  ) {
    for (final a in _annotations[pageIndex]) {
      if (a.id == 'ann_${field.id}') {
        return (
          textArgb: a.textArgb,
          fontBold: a.fontBold,
          fontScale: a.fontScale,
        );
      }
    }
    return (
      textArgb: field.textArgb,
      fontBold: field.fontBold,
      fontScale: _fontScaleForField(field),
    );
  }

  void _applyFieldsFromDrafts(
    Map<int, Map<String, String>> drafts, {
    Set<String> excludedKeys = const {},
  }) {
    _pushUndo();
    setState(() {
      for (var p = 0; p < _docFields.length; p++) {
        final pageDraft = drafts[p] ?? {};
        final list = _annotations[p];
        for (final field in _docFields[p]) {
          final fieldKey = '${p}_${field.id}';
          final textId = 'ann_${field.id}';
          final whiteoutId = 'wo_${field.id}';
          final existingIdx = list.indexWhere((a) => a.id == textId);
          final whiteoutIdx = list.indexWhere((a) => a.id == whiteoutId);

          if (excludedKeys.contains(fieldKey)) {
            list.removeWhere((a) => a.id == textId);
            _editedFieldIds.remove(field.id);
            final wo = UtilPdfPageAnnotation(
              id: whiteoutId,
              type: 'whiteout',
              nx: field.nx,
              ny: field.ny,
              nw: field.nw.clamp(0.006, 0.98),
              nh: field.nh.clamp(0.008, 0.98),
              backgroundArgb: field.backgroundArgb ?? 0xFFFFFFFF,
              seamless: true,
              replaceSourceText: field.text.trim(),
            );
            if (whiteoutIdx >= 0) {
              list[whiteoutIdx] = wo;
            } else {
              list.add(wo);
            }
            continue;
          }

          list.removeWhere((a) => a.id == whiteoutId);
          final newText = (pageDraft[field.id] ?? field.text).trim();

          if (newText == field.text.trim()) {
            if (existingIdx >= 0) {
              list.removeAt(existingIdx);
              _editedFieldIds.remove(field.id);
            }
            continue;
          }

          final style = _styleForField(field, p);
          final ann = UtilPdfPageAnnotation(
            id: textId,
            type: 'text',
            nx: field.nx,
            ny: field.ny,
            nw: field.nw.clamp(0.006, 0.98),
            nh: field.nh.clamp(0.008, 0.98),
            text: newText,
            textArgb: style.textArgb,
            backgroundArgb: field.backgroundArgb ?? 0xFFFFFFFF,
            fontScale: style.fontScale,
            fontBold: style.fontBold,
            fontItalic: field.fontItalic,
            fontFamily: field.fontFamily,
            seamless: true,
            // Localiza o trecho antigo no PDF para cobrir só ele (sem mancha).
            replaceSourceText: field.text.trim(),
          );
          if (existingIdx >= 0) {
            list[existingIdx] = ann;
          } else {
            list.add(ann);
          }
          _editedFieldIds.add(field.id);
        }
      }
      _selectedFieldId = null;
      _selectedAnnId = null;
      _editTool = _PdfEditorTool.select;
    });
  }

  void _cancelEditor() {
    unawaited(_onCancelOperation());
  }

  Future<void> _openFieldsEditorFullscreen({String? focusFieldKey}) async {
    if (_docFields.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum campo de texto detectado neste documento.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final drafts = <int, Map<String, String>>{};
    for (var p = 0; p < _docFields.length; p++) {
      drafts[p] = {};
      for (final f in _docFields[p]) {
        drafts[p]![f.id] = _effectiveFieldText(f, p);
      }
    }

    final result = await Navigator.of(context).push<_PdfFieldsEditorResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PdfFieldsEditorScreen(
          gradient: _gradient,
          docFields: _docFields,
          thumbs: _thumbs,
          initialDrafts: drafts,
          focusFieldKey: focusFieldKey,
        ),
      ),
    );

    if (result != null && mounted) {
      _applyFieldsFromDrafts(
        result.drafts,
        excludedKeys: result.excludedKeys,
      );
    }
  }

  Future<void> _onDocFieldTap(UtilPdfTextField field) async {
    // Edição no próprio documento (um campo por vez — estilo Word).
    final current = _effectiveFieldText(field, _editPage);
    final edited = await _editFieldWordStyle(field, current);
    if (edited == null || !mounted) return;
    _applySingleFieldEdit(field, edited);
  }

  /// Digitação ampla no campo — sem lista comprimida no meio da página.
  Future<String?> _editFieldWordStyle(
    UtilPdfTextField field,
    String initial,
  ) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: _gradient.first),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editar no documento',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O texto substitui o trecho no PDF original — layout preservado.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 6,
                    minLines: 2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      height: 1.35,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Digite como no Word…',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: _gradient.first, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                          style: FilledButton.styleFrom(
                            backgroundColor: _gradient.first,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Aplicar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  void _applySingleFieldEdit(UtilPdfTextField field, String newText) {
    _pushUndo();
    setState(() {
      final p = _editPage;
      final list = _annotations[p];
      final textId = 'ann_${field.id}';
      final whiteoutId = 'wo_${field.id}';
      list.removeWhere((a) => a.id == whiteoutId);
      final existingIdx = list.indexWhere((a) => a.id == textId);

      if (newText.trim() == field.text.trim()) {
        if (existingIdx >= 0) {
          list.removeAt(existingIdx);
          _editedFieldIds.remove(field.id);
        }
        _selectedFieldId = null;
        _selectedAnnId = null;
        return;
      }

      final style = _styleForField(field, p);
      final ann = UtilPdfPageAnnotation(
        id: textId,
        type: 'text',
        nx: field.nx,
        ny: field.ny,
        nw: field.nw.clamp(0.006, 0.98),
        nh: field.nh.clamp(0.008, 0.98),
        text: newText,
        textArgb: style.textArgb,
        backgroundArgb: field.backgroundArgb ?? 0xFFFFFFFF,
        fontScale: style.fontScale,
        fontBold: style.fontBold,
        fontItalic: field.fontItalic,
        fontFamily: field.fontFamily,
        seamless: true,
        replaceSourceText: field.text.trim(),
      );
      if (existingIdx >= 0) {
        list[existingIdx] = ann;
      } else {
        list.add(ann);
      }
      _editedFieldIds.add(field.id);
      _selectedFieldId = null;
      _selectedAnnId = textId;
      _editTool = _PdfEditorTool.select;
    });
  }

  Future<String?> _editFieldTextDialog(String initial) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar campo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          minLines: 2,
          decoration: const InputDecoration(
            hintText:
                'Altere só o que precisar — o PDF original fica visível atrás.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  bool _fieldHasAnnotation(String fieldId) =>
      _currentAnn.any((a) => a.id == 'ann_$fieldId');

  Future<void> _openEditPreview({bool preferShare = false}) async {
    final pdf = _singlePdf;
    if (pdf == null || _thumbs.isEmpty) return;
    if (!mounted) return;

    List<Uint8List>? previewPages;
    await _withBusy('Montando pré-visualização…', () async {
      previewPages = await _buildPreviewPages();
    });
    if (!mounted || previewPages == null || previewPages!.isEmpty) return;

    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PdfEditPreviewScreen(
          gradient: _gradient,
          pages: previewPages!,
          fileName: _editedFileName(),
          pageAspects: List<double>.from(_editPageAspects),
          pageSizesPts: List.of(_editPageSizesPts),
          preferShare: preferShare,
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'share') {
      await _openShareFormats();
    } else if (action == 'save_folder') {
      await _exportEditedPdf(action: 'save_folder');
    }
  }

  /// Monta imagens com edições aplicadas (prévia fullscreen fiel ao resultado).
  Future<List<Uint8List>> _buildPreviewPages() async {
    final out = <Uint8List>[];
    for (var i = 0; i < _thumbs.length; i++) {
      await _ensureEditPageReady(i);
      final base = _editPageImages.length > i ? _editPageImages[i] : null;
      final ann =
          i < _annotations.length ? _annotations[i] : <UtilPdfPageAnnotation>[];
      if (base == null || base.isEmpty) {
        final thumb = _thumbs[i];
        if (thumb.isNotEmpty) out.add(thumb);
        continue;
      }
      late final Uint8List pageBytes;
      if (ann.isEmpty) {
        pageBytes = base;
      } else {
        pageBytes = await UtilitariosLocalService.flattenPdfPageWithAnnotations(
          base,
          ann,
        );
      }
      out.add(pageBytes);
      // Aspecto real da imagem (evita preview achatado em landscape).
      try {
        final codec = await ui.instantiateImageCodec(pageBytes);
        final frame = await codec.getNextFrame();
        final w = frame.image.width;
        final h = frame.image.height;
        frame.image.dispose();
        if (w > 0 && h > 0 && i < _editPageAspects.length) {
          _editPageAspects[i] = w / h;
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> _openShareFormats() async {
    if (!mounted) return;
    final result = await showModalBottomSheet<_ExportFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Compartilhar como',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha o formato — Word, PDF, JPEG ou PNG',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _ExportFormatCard(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF',
                    description: 'Documento editado',
                    gradient: const [Color(0xFFE53935), Color(0xFFD32F2F)],
                    onTap: () => Navigator.pop(ctx, _ExportFormat.pdf),
                  ),
                  _ExportFormatCard(
                    icon: Icons.description_rounded,
                    label: 'WORD',
                    description: 'Visual fiel (.docx)',
                    gradient: const [Color(0xFF1976D2), Color(0xFF1565C0)],
                    onTap: () => Navigator.pop(ctx, _ExportFormat.word),
                  ),
                  _ExportFormatCard(
                    icon: Icons.image_rounded,
                    label: 'PNG',
                    description: 'Alta qualidade',
                    gradient: const [Color(0xFF43A047), Color(0xFF388E3C)],
                    onTap: () => Navigator.pop(ctx, _ExportFormat.png),
                  ),
                  _ExportFormatCard(
                    icon: Icons.photo_rounded,
                    label: 'JPEG',
                    description: 'Imagem leve',
                    gradient: const [Color(0xFFFB8C00), Color(0xFFEF6C00)],
                    onTap: () => Navigator.pop(ctx, _ExportFormat.jpg),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Retornar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _ExportFormat.pdf:
        await _exportEditedPdf(action: 'share');
      case _ExportFormat.word:
        await _exportAsWord();
      case _ExportFormat.png:
        await _exportAsImages(format: 'png');
      case _ExportFormat.jpg:
        await _exportAsImages(format: 'jpg');
    }
  }

  Future<void> _exportEditedPdf({required String action}) async {
    final pdf = _singlePdf;
    if (pdf == null) return;
    await _withBusy('Gerando PDF editado…', () async {
      late final Uint8List out;
      try {
        out = await UtilitariosPdfPreserveExport.export(
          originalPdf: pdf,
          annotationsByPage: _annotations,
        );
      } catch (e, st) {
        debugPrint('Export PDF nativo falhou: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Não foi possível salvar a edição no PDF. Tente de novo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (!mounted) return;
      final fileName = _editedFileName();
      final ok = await utilitariosSaveOrShareBytes(
        context: context,
        bytes: out,
        fileName: fileName,
        mimeType: 'application/pdf',
        preferShare: action == 'share',
        chooseSaveLocation: action == 'save_folder',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (action == 'share'
                    ? 'PDF editado pronto para compartilhar.'
                    : 'PDF editado salvo (formato original).')
                : 'Não foi possível exportar o PDF.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok && mounted) {
        Navigator.pop(
          context,
          UtilitariosPdfToolResult(
            bytes: out,
            fileName: fileName,
            mimeType: 'application/pdf',
            message: 'PDF editado com sucesso.',
          ),
        );
      }
    });
  }

  Future<void> _exportAsWord() async {
    final pdf = _singlePdf;
    if (pdf == null) return;
    await _withBusy('Gerando Word (.docx)…', () async {
      try {
        final pdfBytes = await UtilitariosPdfPreserveExport.export(
          originalPdf: pdf,
          annotationsByPage: _annotations,
        );
        final docx = await UtilitariosLocalService.pdfToVisualDocx(pdfBytes);
        final fileName = _editedFileName().replaceAll('.pdf', '.docx');
        final ok = await utilitariosSaveOrShareBytes(
          context: context,
          bytes: docx,
          fileName: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          preferShare: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Word (.docx) visual pronto — formato original preservado.'
                : 'Não foi possível exportar o Word.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (ok && mounted) {
          Navigator.pop(
            context,
            UtilitariosPdfToolResult(
              bytes: docx,
              fileName: fileName,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              message: 'Word visual (.docx) com páginas no formato original.',
            ),
          );
        }
      } catch (e, st) {
        debugPrint('Export Word falhou: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível exportar como Word.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Future<void> _exportAsImages({required String format}) async {
    final pdf = _singlePdf;
    if (pdf == null || _thumbs.isEmpty) return;
    final asPng = format == 'png';
    await _withBusy(asPng ? 'Gerando PNG…' : 'Gerando JPEG…', () async {
      try {
        final pdfBytes = await UtilitariosPdfPreserveExport.export(
          originalPdf: pdf,
          annotationsByPage: _annotations,
        );
        final pages = asPng
            ? await UtilitariosLocalService.pdfToPngs(pdfBytes)
            : await UtilitariosLocalService.pdfToJpegs(pdfBytes);
        if (pages.isEmpty) {
          throw StateError('Nenhuma página gerada.');
        }
        final ext = asPng ? 'png' : 'jpg';
        final mime = asPng ? 'image/png' : 'image/jpeg';
        late final Uint8List out;
        late final String fileName;
        late final String outMime;
        if (pages.length == 1) {
          out = pages.first;
          fileName = _editedFileName().replaceAll('.pdf', '.$ext');
          outMime = mime;
        } else {
          final stem = _editedFileName().replaceAll('.pdf', '');
          out = await UtilitariosLocalService.zipImages(
            pages,
            stem,
            extension: ext,
          );
          fileName = '${stem}_paginas.zip';
          outMime = 'application/zip';
        }
        final ok = await utilitariosSaveOrShareBytes(
          context: context,
          bytes: out,
          fileName: fileName,
          mimeType: outMime,
          preferShare: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? '${asPng ? 'PNG' : 'JPEG'} pronto para compartilhar.'
                : 'Não foi possível exportar.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (ok && mounted) {
          Navigator.pop(
            context,
            UtilitariosPdfToolResult(
              bytes: out,
              fileName: fileName,
              mimeType: outMime,
              message:
                  '${pages.length} página(s) em ${asPng ? 'PNG' : 'JPEG'}.',
            ),
          );
        }
      } catch (e, st) {
        debugPrint('Export images falhou: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível exportar como imagem.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Future<void> _confirmEdit() async {
    await _openEditPreview(preferShare: false);
  }

  String _newAnnId() => 'a${DateTime.now().microsecondsSinceEpoch}';

  void _pushUndo() {
    _undo.add(
      _annotations
          .map((page) => page.map((a) => a.copyWith()).toList())
          .toList(),
    );
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    setState(() {
      for (var i = 0; i < _annotations.length && i < prev.length; i++) {
        _annotations[i] = List<UtilPdfPageAnnotation>.from(prev[i]);
      }
      _selectedAnnId = null;
    });
  }

  List<UtilPdfPageAnnotation> get _currentAnn =>
      _annotations.isEmpty ? const [] : _annotations[_editPage];

  UtilPdfPageAnnotation? get _selectedAnn {
    final id = _selectedAnnId;
    if (id == null) return null;
    for (final a in _currentAnn) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _selectAnn(String? id) => setState(() => _selectedAnnId = id);

  Future<void> _editAnnText(UtilPdfPageAnnotation ann) async {
    final result = await _editFieldTextDialog(ann.text);
    if (result == null || !mounted) return;
    _pushUndo();
    final list = _annotations[_editPage];
    final i = list.indexWhere((a) => a.id == ann.id);
    if (i < 0) return;
    setState(() {
      final isFieldAnn = ann.id.startsWith('ann_');
      list[i] = list[i].copyWith(
        text: result,
        // Campo do documento mantém a caixa original (formatação idêntica);
        // texto avulso cresce para acomodar novas linhas.
        nh: isFieldAnn
            ? list[i].nh
            : math.max(list[i].nh, 0.06 + result.split('\n').length * 0.035),
      );
    });
  }

  void _deleteAnn(String id) {
    _pushUndo();
    setState(() {
      _annotations[_editPage].removeWhere((a) => a.id == id);
      if (_selectedAnnId == id) _selectedAnnId = null;
    });
  }

  void _addAnnotationAt(double nx, double ny, String type) {
    _pushUndo();
    final id = _newAnnId();
    final list = _annotations[_editPage];
    final ann = UtilPdfPageAnnotation(
      id: id,
      type: type,
      nx: nx.clamp(0.02, 0.88),
      ny: ny.clamp(0.02, 0.88),
      nw: type == 'check' ? 0.07 : (type == 'whiteout' ? 0.35 : 0.72),
      nh: type == 'check'
          ? 0.07
          : (type == 'highlight' ? 0.09 : (type == 'whiteout' ? 0.06 : 0.1)),
      text: type == 'text' ? 'Novo texto' : '',
      argb: _highlightColor,
      textArgb: _textColor,
      fontScale: _textFontScale,
      seamless: type == 'text' || type == 'whiteout',
    );
    setState(() {
      list.add(ann);
      _selectedAnnId = id;
    });
    if (type == 'text') {
      unawaited(_editAnnText(ann));
    }
  }

  void _onCanvasTap(TapDownDetails d, Size size, double aspect) {
    if (size.width <= 0 || size.height <= 0) return;
    final norm = _canvasToNormalized(d.localPosition, size, aspect);
    if (norm == null) return;
    final nx = norm.dx;
    final ny = norm.dy;

    if (_editTool == _PdfEditorTool.select) {
      final field = _fieldAt(nx, ny);
      if (field != null) {
        unawaited(_onDocFieldTap(field));
        return;
      }
      for (final a in _currentAnn.reversed) {
        if (nx >= a.nx &&
            nx <= a.nx + a.nw &&
            ny >= a.ny &&
            ny <= a.ny + a.nh) {
          _selectAnn(a.id);
          if (a.type == 'text') unawaited(_editAnnText(a));
          return;
        }
      }
      setState(() {
        _selectedFieldId = null;
        _selectedAnnId = null;
      });
      return;
    }

    if (_editTool == _PdfEditorTool.erase) {
      for (final a in _currentAnn.reversed) {
        if (nx >= a.nx &&
            nx <= a.nx + a.nw &&
            ny >= a.ny &&
            ny <= a.ny + a.nh) {
          _deleteAnn(a.id);
          return;
        }
      }
      return;
    }

    if (_editTool == _PdfEditorTool.select) {
      for (final a in _currentAnn.reversed) {
        if (nx >= a.nx &&
            nx <= a.nx + a.nw &&
            ny >= a.ny &&
            ny <= a.ny + a.nh) {
          _selectAnn(a.id);
          return;
        }
      }
      _selectAnn(null);
      return;
    }

    final type = switch (_editTool) {
      _PdfEditorTool.text => 'text',
      _PdfEditorTool.highlight => 'highlight',
      _PdfEditorTool.whiteout => 'whiteout',
      _PdfEditorTool.check => 'check',
      _ => 'text',
    };
    _addAnnotationAt(nx, ny, type);
  }

  void _moveAnn(String id, Offset delta, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final list = _annotations[_editPage];
    final i = list.indexWhere((a) => a.id == id);
    if (i < 0) return;
    setState(() {
      list[i] = list[i].copyWith(
        nx: (list[i].nx + delta.dx / size.width).clamp(0.0, 0.95),
        ny: (list[i].ny + delta.dy / size.height).clamp(0.0, 0.95),
      );
    });
  }

  void _resizeAnn(String id, Offset delta, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final list = _annotations[_editPage];
    final i = list.indexWhere((a) => a.id == id);
    if (i < 0) return;
    setState(() {
      list[i] = list[i].copyWith(
        nw: (list[i].nw + delta.dx / size.width).clamp(0.05, 0.98),
        nh: (list[i].nh + delta.dy / size.height).clamp(0.04, 0.98),
      );
    });
  }

  Future<void> _pickColor({required bool forText}) async {
    const palette = <int>[
      0xFF1E293B,
      0xFFDC2626,
      0xFF2563EB,
      0xFF059669,
      0xFF7C3AED,
      0xFFEA580C,
      0xFFFFF59D,
      0xFF86EFAC,
      0xFF93C5FD,
      0xFFFDA4AF,
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: palette
                .map(
                  (c) => GestureDetector(
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (forText) {
        _textColor = picked;
      } else {
        _highlightColor = picked;
      }
      final sel = _selectedAnn;
      if (sel != null) {
        _pushUndo();
        final list = _annotations[_editPage];
        final i = list.indexWhere((a) => a.id == sel.id);
        if (i >= 0) {
          list[i] = list[i].copyWith(
            argb: forText ? list[i].argb : picked,
            textArgb: forText ? picked : list[i].textArgb,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == UtilitariosPdfToolMode.edit) {
      return _buildEditFullscreenScaffold();
    }
    return Scaffold(
      backgroundColor: ModernModuleUI.scaffoldBgOf(context),
      appBar: AppBar(
        title:
            Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _gradient.first,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Fechar',
          onPressed: _busy ? null : _onCloseFlow,
        ),
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ModernModuleUI.gradientActionCard(
                  gradient: _gradient,
                  icon: switch (widget.mode) {
                    UtilitariosPdfToolMode.merge =>
                      UtilitariosModuleIcons.mergePdf,
                    UtilitariosPdfToolMode.split =>
                      UtilitariosModuleIcons.splitPdf,
                    UtilitariosPdfToolMode.edit =>
                      UtilitariosModuleIcons.editPdf,
                  },
                  title: _title,
                  subtitle: switch (widget.mode) {
                    UtilitariosPdfToolMode.merge =>
                      'PDFs · reordene · confirme.',
                    UtilitariosPdfToolMode.split =>
                      'Páginas ou intervalo · gere o PDF.',
                    UtilitariosPdfToolMode.edit =>
                      'Campos · anotações · pinça para zoom.',
                  },
                  compact: true,
                  onTap: () {},
                ),
              ),
              Expanded(child: _buildBody()),
              _buildBottomBar(),
            ],
          ),
          if (_busy) _busyOverlay(),
        ],
      ),
    );
  }

  /// Editor PDF imersivo fullscreen (padrão moderno tipo Files Editor).
  Widget _buildEditFullscreenScaffold() {
    final hasDoc = _singlePdf != null && _thumbs.isNotEmpty;
    final shortName = (_singleName ?? 'Editor PDF');
    final title = shortName.length > 28
        ? '${shortName.substring(0, 26)}…'
        : shortName;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: [
          // Edge-to-edge: só SafeArea no topo/base mínimo — documento usa a tela toda.
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _onCloseFlow,
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (hasDoc) ...[
                        IconButton(
                          tooltip: _editViewMode == _EditViewMode.grid
                              ? 'Documento tela cheia'
                              : 'Grade de páginas',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _editViewMode =
                                        _editViewMode == _EditViewMode.grid
                                            ? _EditViewMode.document
                                            : _EditViewMode.grid;
                                    if (_editViewMode ==
                                        _EditViewMode.document) {
                                      _editToolsExpanded = false;
                                      _editThumbsExpanded = false;
                                    }
                                  }),
                          icon: Icon(
                            _editViewMode == _EditViewMode.grid
                                ? Icons.fullscreen_rounded
                                : Icons.grid_view_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ] else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              Expanded(child: _buildEditBody()),
              _buildEditActionBar(hasDoc),
            ],
          ),
          if (_busy) _busyOverlay(),
        ],
      ),
    );
  }

  Widget _viewModeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _gradient.first : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.7),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditActionBar(bool hasDoc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: hasDoc
            ? Row(
                children: [
                  _compactBarBtn(
                    label: 'Descartar',
                    icon: Icons.delete_outline_rounded,
                    filled: false,
                    color: const Color(0xFFF87171),
                    onTap: _busy ? null : _onDiscardToPickAnother,
                  ),
                  const SizedBox(width: 6),
                  _compactBarBtn(
                    label: 'Salvar',
                    icon: Icons.save_rounded,
                    filled: true,
                    color: const Color(0xFF2563EB),
                    onTap: _busy
                        ? null
                        : () => unawaited(
                              _openEditPreview(preferShare: false),
                            ),
                  ),
                  const SizedBox(width: 6),
                  _compactBarBtn(
                    label: 'Enviar',
                    icon: Icons.ios_share_rounded,
                    filled: true,
                    color: _gradient.first,
                    onTap: _busy
                        ? null
                        : () => unawaited(_openShareFormats()),
                  ),
                ],
              )
            : OutlinedButton(
                onPressed: _busy ? null : _onCloseFlow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
    );
  }

  /// Descarta edições e volta a escolher outro PDF (antes de Salvar).
  Future<void> _onDiscardToPickAnother() async {
    if (_busy) return;
    if (!await _confirmDiscard(
      'Descartar as edições e escolher outro arquivo?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(_clearAllWork);
    unawaited(_pickPdfs(multiple: false));
  }

  /// Botão de ação compacto — texto nunca quebra/corta (FittedBox).
  Widget _compactBarBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return Expanded(
      child: SizedBox(
        height: 48,
        child: Material(
          color: filled
              ? (onTap == null ? color.withValues(alpha: 0.4) : color)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: filled
                  ? null
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: filled ? Colors.white : color,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: filled ? Colors.white : color,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
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
    );
  }

  Widget _busyOverlay() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(_busyLabel ?? 'Processando…',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (widget.mode) {
      UtilitariosPdfToolMode.merge => _buildMergeBody(),
      UtilitariosPdfToolMode.split => _buildSplitBody(),
      UtilitariosPdfToolMode.edit => _buildEditBody(),
    };
  }

  Widget _buildMergeBody() {
    if (_mergeOrder.isEmpty) {
      return ModernModuleUI.emptyPickState(
        context: context,
        gradient: _gradient,
        icon: UtilitariosModuleIcons.mergePdf,
        title: 'Adicione PDFs para juntar',
        subtitle:
            'Selecione um ou vários arquivos.\nDepois arraste para reordenar as páginas.',
        buttonLabel: 'Escolher PDFs',
        buttonIcon: Icons.create_new_folder_rounded,
        onPressed: _busy ? null : () => _pickPdfs(multiple: true),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Center(
            child: ModernModuleUI.centeredPickButton(
              gradient: _gradient,
              icon: Icons.add_rounded,
              label: 'Adicionar mais PDFs',
              onPressed: _busy ? null : () => _pickPdfs(multiple: true),
              secondary: true,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            itemCount: _mergeOrder.length,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _mergeOrder.removeAt(oldIndex);
                _mergeOrder.insert(newIndex, item);
              });
            },
            itemBuilder: (context, i) {
              final item = _mergeOrder[i];
              final src = _sources[item.sourceIndex];
              return Card(
                key: ValueKey('m$i-${item.sourceIndex}-${item.pageIndex}'),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.thumb != null
                        ? Image.memory(
                            item.thumb!,
                            width: 48,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : const SizedBox(
                            width: 48,
                            height: 64,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                  title: Text(
                    '${src.name} · pág. ${item.pageIndex + 1}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _gradient.first.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${src.pageCount} pág.',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _gradient.first,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Arraste ≡ para mudar',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSplitBody() {
    if (_singlePdf == null) {
      return ModernModuleUI.emptyPickState(
        context: context,
        gradient: _gradient,
        icon: UtilitariosModuleIcons.splitPdf,
        title: 'Escolha um PDF para dividir',
        subtitle: 'Selecione páginas individuais ou um intervalo contínuo.',
        buttonLabel: 'Escolher PDF',
        buttonIcon: Icons.picture_as_pdf_rounded,
        onPressed: _busy ? null : () => _pickPdfs(multiple: false),
      );
    }

    final total = _thumbs.length;
    final exportOrder = _resolveSplitExportOrder();
    final selectedCount = exportOrder.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossAxisCount = w >= 720 ? 3 : 2;
        final aspectRatio = w >= 720 ? 0.68 : 0.72;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _buildSplitIntervalPanel(
                  total: total,
                  selectedCount: selectedCount,
                  exportOrder: exportOrder,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selected count + toggle
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _gradient.first.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$selectedCount de $total selecionadas',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _gradient.first,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : (_splitSelected.length == total
                                  ? _clearSplitSelection
                                  : _selectAllSplitPages),
                          icon: Icon(
                            _splitSelected.length == total
                                ? Icons.clear_all_rounded
                                : Icons.select_all_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _splitSelected.length == total
                                ? 'Desmarcar'
                                : 'Todas',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Quick-select buttons
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _splitQuickBtn(
                          'Primeiras 5',
                          () =>
                              _quickSelectPages((i) => i < math.min(5, total)),
                        ),
                        _splitQuickBtn(
                          'Últimas 5',
                          () => _quickSelectPages(
                              (i) => i >= math.max(0, total - 5)),
                        ),
                        _splitQuickBtn(
                          'Pares',
                          () => _quickSelectPages((i) => (i + 1).isEven),
                        ),
                        _splitQuickBtn(
                          'Ímpares',
                          () => _quickSelectPages((i) => (i + 1).isOdd),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toque para selecionar · segure e arraste para reordenar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: aspectRatio,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, listIndex) {
                    final pageIdx = _splitPageOrder[listIndex];
                    return _buildSplitPageGridTile(
                      listIndex: listIndex,
                      pageIdx: pageIdx,
                      selected: _splitSelected.contains(pageIdx),
                    );
                  },
                  childCount: _splitPageOrder.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _splitRangeField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required VoidCallback onCommit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: ModernModuleUI.scaffoldBgOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              _splitStepButton(icon: Icons.remove_rounded, onTap: onMinus),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => onCommit(),
                  onEditingComplete: onCommit,
                  onTapOutside: (_) => onCommit(),
                ),
              ),
              _splitStepButton(icon: Icons.add_rounded, onTap: onPlus),
            ],
          ),
        ),
      ],
    );
  }

  Widget _splitStepButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: _gradient.first, size: 22),
        ),
      ),
    );
  }

  Widget _splitActionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary ? _gradient.first : ModernModuleUI.scaffoldBgOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary ? _gradient.first : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: primary ? Colors.white : _gradient.first,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: primary ? Colors.white : _gradient.first,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditBody() {
    if (_singlePdf == null || _thumbs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: _gradient.first.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  UtilitariosModuleIcons.editPdf,
                  size: 42,
                  color: _gradient.first,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Editor PDF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Edite no documento ou na grade.\nPré-visualize antes de salvar ou compartilhar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _busy ? null : () => _pickPdfs(multiple: false),
                style: FilledButton.styleFrom(
                  backgroundColor: _gradient.first,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(220, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text(
                  'Carregar PDF',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_editViewMode == _EditViewMode.grid) {
      return _buildEditGridView();
    }
    return _buildEditDocumentView();
  }

  /// Grade de páginas — toque abre a página no documento; botão edita campos.
  Widget _buildEditGridView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_thumbs.length} página(s) · toque para editar no documento',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(_openFieldsEditorFullscreen()),
                icon: Icon(Icons.edit_note_rounded,
                    color: _gradient.first, size: 20),
                label: Text(
                  'Campos',
                  style: TextStyle(
                    color: _gradient.first,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: _thumbs.length,
            itemBuilder: (context, i) {
              final sel = i == _editPage;
              final edits = i < _annotations.length ? _annotations[i].length : 0;
              final thumb = _thumbs[i];
              return Material(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _busy
                      ? null
                      : () {
                          setState(() {
                            _editPage = i;
                            _editViewMode = _EditViewMode.document;
                            _editToolsExpanded = false;
                            _editThumbsExpanded = false;
                          });
                          unawaited(_ensureEditPageReady(i));
                        },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb.isNotEmpty)
                        Image.memory(
                          thumb,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        const Center(child: CircularProgressIndicator()),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel
                                ? _gradient.first
                                : Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      if (edits > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$edits',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Editar tela cheia',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditDocumentView() {
    final ann = _currentAnn;
    final sel = _selectedAnn;
    final fields = _currentFields;
    final pageImage = _editPageImages[_editPage];
    final aspect =
        _editPageAspects.length > _editPage ? _editPageAspects[_editPage] : 1.0;
    return Column(
      children: [
        // Barra fina de ferramentas (expansível) — não rouba a página.
        _buildEditChromeStrip(fields.length),
        if (_editToolsExpanded) _buildEditToolbar(fields.length),
        if (_detectingFields) _buildDetectingBanner(),
        if (sel != null) _buildSelectionBar(sel),
        Expanded(
          child: Container(
            key: _pageCanvasKey,
            color: const Color(0xFF0B1220),
            child: pageImage == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white70),
                        const SizedBox(height: 12),
                        Text(
                          'Preparando documento…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      final size = Size(c.maxWidth, c.maxHeight);
                      final imgRect = _imageRectInCanvas(size, aspect);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          InteractiveViewer(
                            minScale: kIsWeb ? 0.55 : 0.4,
                            maxScale: 10,
                            boundaryMargin: const EdgeInsets.all(80),
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapDown: (d) =>
                                    _onCanvasTap(d, size, aspect),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: imgRect.left,
                                      top: imgRect.top,
                                      width: imgRect.width,
                                      height: imgRect.height,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.45),
                                              blurRadius: 24,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: Image.memory(
                                          pageImage,
                                          width: imgRect.width,
                                          height: imgRect.height,
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                    ),
                                    ...fields
                                        .where(
                                            (f) => !_fieldHasAnnotation(f.id))
                                        .map(
                                          (f) => _buildDocFieldOverlay(
                                            f,
                                            imgRect,
                                            selected:
                                                f.id == _selectedFieldId,
                                            edited: false,
                                          ),
                                        ),
                                    ...ann.map(
                                      (a) => _buildAnnOverlay(a, imgRect),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Status flutuante — não reduz altura do PDF.
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                '${_editPage + 1}/${_thumbs.length}'
                                ' · ${ann.length} edit.'
                                ' · ${fields.length} campos'
                                ' · pinça p/ zoom',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Material(
                              color: _gradient.first,
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy
                                    ? null
                                    : () => setState(() {
                                          _editThumbsExpanded =
                                              !_editThumbsExpanded;
                                        }),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    _editThumbsExpanded
                                        ? Icons.expand_more_rounded
                                        : Icons.view_carousel_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        if (_editThumbsExpanded) _buildEditPageThumbsStrip(),
      ],
    );
  }

  /// Faixa compacta: ferramentas / campos / páginas — página fica em tela cheia.
  Widget _buildEditChromeStrip(int fieldCount) {
    final g0 = _gradient.first;
    return Material(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            _chromeChip(
              icon: _editToolsExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.handyman_rounded,
              label: _editToolsExpanded ? 'Ocultar' : 'Ferramentas',
              selected: _editToolsExpanded,
              onTap: () => setState(
                () => _editToolsExpanded = !_editToolsExpanded,
              ),
            ),
            const SizedBox(width: 6),
            if (fieldCount > 0)
              _chromeChip(
                icon: Icons.grid_view_rounded,
                label: '$fieldCount campos',
                selected: false,
                color: g0,
                onTap: () => unawaited(_openFieldsEditorFullscreen()),
              ),
            const Spacer(),
            _chromeChip(
              icon: Icons.view_carousel_rounded,
              label: 'Pág. ${_editPage + 1}',
              selected: _editThumbsExpanded,
              onTap: () => setState(
                () => _editThumbsExpanded = !_editThumbsExpanded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chromeChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? (selected ? _gradient.first : Colors.white70);
    return Material(
      color: selected
          ? _gradient.first.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditPageThumbsStrip() {
    return SizedBox(
      height: kIsWeb ? 64 : 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: _thumbs.length,
        itemBuilder: (context, i) {
          final selPage = i == _editPage;
          final count = _annotations[i].length;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _busy
                  ? null
                  : () {
                      setState(() => _editPage = i);
                      unawaited(_ensureEditPageReady(i));
                    },
              child: Container(
                width: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selPage
                        ? _gradient.first
                        : Colors.white.withValues(alpha: 0.15),
                    width: selPage ? 2.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _thumbs[i],
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    if (count > 0)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _gradient.first,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildDetectingBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _gradient.first.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _gradient.first,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Detectando campos no documento…',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _gradient.first,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldSelectionBar(UtilPdfTextField field) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        elevation: 0,
        color: _gradient.first.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 20, color: _gradient.first),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Campo selecionado',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      field.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _onDocFieldTap(field),
                style: FilledButton.styleFrom(
                  backgroundColor: _gradient.first.withValues(alpha: 0.18),
                  foregroundColor: _gradient.first,
                ),
                child: const Text('Editar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocFieldOverlay(
    UtilPdfTextField field,
    Rect imgRect, {
    required bool selected,
    required bool edited,
  }) {
    final left = imgRect.left + field.nx * imgRect.width;
    final top = imgRect.top + field.ny * imgRect.height;
    final w = field.nw * imgRect.width;
    final h = field.nh * imgRect.height;
    final color = edited
        ? const Color(0xFF22C55E)
        : (selected ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8));

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.28),
                      color.withValues(alpha: 0.12),
                    ],
                  )
                : null,
            color: selected ? null : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: selected ? 1 : 0.5),
              width: selected ? 2.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.75)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        size: 12, color: Colors.white),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildEditToolbar(int fieldCount) {
    final g0 = _gradient.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? Colors.white70 : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: surfaceColor,
        border: Border.all(color: g0.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with title and fields button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [g0, g0.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: g0.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editor PDF',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: textColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      'Toque no texto e digite',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: subtextColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (fieldCount > 0)
                Material(
                  color: g0.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy
                        ? null
                        : () => unawaited(_openFieldsEditorFullscreen()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.grid_view_rounded, size: 16, color: g0),
                          const SizedBox(width: 6),
                          Text(
                            '$fieldCount',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              color: g0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Tool buttons — scroll horizontal, sem cortar rótulos
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                _modernToolButton(
                    _PdfEditorTool.select, Icons.touch_app_rounded, 'Mover'),
                const SizedBox(width: 6),
                _modernToolButton(
                    _PdfEditorTool.text, Icons.text_fields_rounded, 'Texto'),
                const SizedBox(width: 6),
                _modernToolButton(_PdfEditorTool.highlight,
                    Icons.highlight_rounded, 'Destaque'),
                const SizedBox(width: 6),
                _modernToolButton(_PdfEditorTool.whiteout,
                    Icons.format_color_reset_rounded, 'Corrigir'),
                const SizedBox(width: 6),
                _modernToolButton(
                    _PdfEditorTool.check, Icons.check_box_rounded, 'Check'),
                const SizedBox(width: 6),
                _modernToolButton(
                    _PdfEditorTool.erase, Icons.auto_fix_off_rounded, 'Apagar'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Undo button
                _contextIconButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Desfazer',
                  color: _undo.isEmpty ? Colors.grey.shade400 : g0,
                  onPressed: _undo.isEmpty || _busy ? null : _undoLast,
                ),
                // Text tool options
                if (_editTool == _PdfEditorTool.text) ...[
                  const SizedBox(width: 4),
                  _modernFontChip('P', 0.85),
                  _modernFontChip('M', 1.0),
                  _modernFontChip('G', 1.35),
                  const SizedBox(width: 4),
                  _contextIconButton(
                    icon: Icons.format_color_text_rounded,
                    tooltip: 'Cor do texto',
                    color: Color(_textColor),
                    onPressed: _busy ? null : () => _pickColor(forText: true),
                  ),
                ],
                // Highlight tool options
                if (_editTool == _PdfEditorTool.highlight) ...[
                  const SizedBox(width: 4),
                  _contextIconButton(
                    icon: Icons.palette_rounded,
                    tooltip: 'Cor do destaque',
                    color: Color(_highlightColor),
                    onPressed: _busy ? null : () => _pickColor(forText: false),
                  ),
                ],
                const Spacer(),
                // Hint text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _editToolHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: subtextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernToolButton(_PdfEditorTool tool, IconData icon, String label) {
    final g0 = _gradient.first;
    final sel = _editTool == tool;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy
            ? null
            : () => setState(() {
                  _editTool = tool;
                  _selectedFieldId = null;
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 58),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: sel
                ? LinearGradient(
                    colors: [g0, g0.withValues(alpha: 0.8)],
                  )
                : null,
            color: sel
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel
                  ? Colors.transparent
                  : (isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: g0.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: sel
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.grey.shade700),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  color: sel
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contextIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _modernFontChip(String label, double scale) {
    final g0 = _gradient.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = (_textFontScale - scale).abs() < 0.05;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _busy
            ? null
            : () => setState(() {
                  _textFontScale = scale;
                  final s = _selectedAnn;
                  if (s != null && s.type == 'text') {
                    _pushUndo();
                    final list = _annotations[_editPage];
                    final i = list.indexWhere((a) => a.id == s.id);
                    if (i >= 0) list[i] = list[i].copyWith(fontScale: scale);
                  }
                }),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isSelected
                ? g0.withValues(alpha: 0.15)
                : (isDark ? Colors.white10 : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? g0 : Colors.transparent,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w900,
              color: isSelected
                  ? g0
                  : (isDark ? Colors.white70 : Colors.grey.shade700),
            ),
          ),
        ),
      ),
    );
  }

  String get _editToolHint => switch (_editTool) {
        _PdfEditorTool.pickField => 'Toque em Campos para abrir a lista',
        _PdfEditorTool.select =>
          'Arraste para mover · toque no campo para editar',
        _PdfEditorTool.text => 'Toque na página para novo texto',
        _PdfEditorTool.highlight => 'Toque para destacar trecho',
        _PdfEditorTool.whiteout => 'Toque para cobrir texto antigo',
        _PdfEditorTool.check => 'Toque para marcar check',
        _PdfEditorTool.erase => 'Toque no campo para apagar',
      };

  Widget _toolChip(
    double width,
    _PdfEditorTool tool,
    IconData icon,
    String label, {
    bool primary = false,
  }) {
    final sel = _editTool == tool;
    final chipColor = primary ? _gradient.first : _gradient.first;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy
              ? null
              : () => setState(() {
                    _editTool = tool;
                    _selectedFieldId = null;
                  }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel
                  ? chipColor.withValues(alpha: 0.14)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel ? chipColor : Colors.grey.shade300,
                width: sel ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 22, color: sel ? chipColor : Colors.grey.shade600),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: sel ? chipColor : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fontChip(String label, double scale) {
    final sel = (_textFontScale - scale).abs() < 0.05;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        selected: sel,
        onSelected: _busy
            ? null
            : (_) => setState(() {
                  _textFontScale = scale;
                  final s = _selectedAnn;
                  if (s != null && s.type == 'text') {
                    _pushUndo();
                    final list = _annotations[_editPage];
                    final i = list.indexWhere((a) => a.id == s.id);
                    if (i >= 0) list[i] = list[i].copyWith(fontScale: scale);
                  }
                }),
      ),
    );
  }

  Widget _buildSelectionBar(UtilPdfPageAnnotation sel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: _gradient.first.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sel.type == 'text'
                      ? (sel.text.isEmpty ? 'Texto selecionado' : sel.text)
                      : 'Campo ${sel.type}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              if (sel.type == 'text')
                IconButton(
                  tooltip: 'Editar texto',
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: _busy ? null : () => _editAnnText(sel),
                ),
              IconButton(
                tooltip: 'Excluir',
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: Colors.red.shade600),
                onPressed: _busy ? null : () => _deleteAnn(sel.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnnOverlay(UtilPdfPageAnnotation a, Rect imgRect) {
    final left = imgRect.left + a.nx * imgRect.width;
    final top = imgRect.top + a.ny * imgRect.height;
    final w = a.nw * imgRect.width;
    final h = a.nh * imgRect.height;
    final selected = a.id == _selectedAnnId;
    final border = selected
        ? Border.all(color: _gradient.first, width: 2)
        : Border.all(color: Colors.blue.withValues(alpha: 0.35), width: 1);

    Widget child;
    if (a.type == 'highlight') {
      child = Container(
        decoration: BoxDecoration(
          color: Color(a.argb).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: border,
        ),
      );
    } else if (a.type == 'whiteout') {
      child = Container(
        decoration: BoxDecoration(
          color: a.seamless
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? border
              : (a.seamless
                  ? Border.all(
                      color: _gradient.first.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : border),
        ),
        child: selected && !a.seamless
            ? null
            : (a.seamless
                ? null
                : Center(
                    child: Icon(Icons.format_color_reset_rounded,
                        size: 16, color: Colors.grey.shade500),
                  )),
      );
    } else if (a.type == 'check') {
      child = Container(
        width: h.clamp(22, 40),
        height: h.clamp(22, 40),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green.shade600, width: 2.5),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white.withValues(alpha: 0.9),
        ),
        child:
            Icon(Icons.check_rounded, color: Colors.green.shade700, size: 18),
      );
    } else if (a.type == 'text' && a.seamless) {
      // Mostra o texto novo sobre o PDF (estilo Word) — o que se vê é o que sai.
      final text = a.text.isEmpty ? ' ' : a.text;
      final lineCount = math.max(1, '\n'.allMatches(text).length + 1);
      final scale = a.fontScale <= 0 ? 1.0 : a.fontScale;
      var fs = ((h / lineCount) * 0.78 * scale).clamp(8.0, 42.0);
      final probe = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs,
            height: 1.12,
            fontWeight: a.fontBold ? FontWeight.w700 : FontWeight.w500,
            color: Color(a.textArgb),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 6,
      )..layout(maxWidth: math.max(8, w));
      if (probe.width > w && probe.width > 0 && w > 8) {
        // Não comprime no centro: reduz só o necessário para caber na linha.
        fs = math.max(8.0, fs * (w / probe.width) * 0.98);
      }
      child = Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          // Cobre o texto antigo por baixo para parecer digitação no documento.
          color: Color(a.backgroundArgb ?? 0xFFFFFFFF).withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(2),
          border: selected
              ? Border.all(color: _gradient.first, width: 1.5)
              : Border.all(
                  color: _gradient.first.withValues(alpha: 0.25), width: 1),
        ),
        child: Text(
          text,
          maxLines: 6,
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.left,
          style: TextStyle(
            fontWeight: a.fontBold ? FontWeight.w700 : FontWeight.w500,
            fontSize: fs,
            color: Color(a.textArgb),
            height: 1.12,
          ),
        ),
      );
    } else {
      // Mesma fórmula do render final (fonte vetorial): tamanho derivado da
      // altura do campo + auto-fit na largura. O que se vê na grid é o que
      // sai no PDF — sem desconfigurar.
      final text = a.text.isEmpty ? 'Toque em editar' : a.text;
      final lineCount = math.max(1, '\n'.allMatches(text).length + 1);
      final scale = a.fontScale <= 0 ? 1.0 : a.fontScale;
      var fs = ((h / lineCount) * 0.74 * scale).clamp(4.0, 200.0);
      final probe = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fs,
            height: 1.18,
            fontWeight: a.fontBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: lineCount + 4,
      )..layout();
      if (probe.width > w && probe.width > 0) {
        fs = math.max(4.0, fs * w / probe.width * 0.985);
      }
      child = Container(
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: a.seamless
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(a.seamless ? 2 : 6),
          border: border,
          boxShadow: a.seamless
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                  ),
                ],
        ),
        child: Text(
          text,
          maxLines: lineCount + 4,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontWeight: a.fontBold ? FontWeight.w700 : FontWeight.w400,
            fontSize: fs,
            color: Color(a.textArgb),
            height: 1.18,
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: a.type == 'check' ? null : w,
      height: a.type == 'check' ? null : h,
      child: GestureDetector(
        onPanStart: (_) {
          if (_editTool != _PdfEditorTool.select) return;
          _pushUndo();
          _selectAnn(a.id);
        },
        onPanUpdate: (d) {
          if (_editTool == _PdfEditorTool.select) {
            _moveAnn(a.id, d.delta, imgRect.size);
          }
        },
        onDoubleTap: a.type == 'text' ? () => _editAnnText(a) : null,
        onTap: () {
          if (_editTool == _PdfEditorTool.erase) {
            _deleteAnn(a.id);
          } else if (_editTool == _PdfEditorTool.select) {
            _selectAnn(a.id);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(width: w, height: h, child: child),
            if (selected && a.type != 'check')
              Positioned(
                right: -6,
                bottom: -6,
                child: GestureDetector(
                  onPanUpdate: (d) => _resizeAnn(a.id, d.delta, imgRect.size),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _gradient.first,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final canConfirm = switch (widget.mode) {
      UtilitariosPdfToolMode.merge => _mergeOrder.isNotEmpty,
      UtilitariosPdfToolMode.split =>
        _singlePdf != null && _resolveSplitExportOrder().isNotEmpty,
      UtilitariosPdfToolMode.edit => _singlePdf != null && _thumbs.isNotEmpty,
    };
    final onConfirm = switch (widget.mode) {
      UtilitariosPdfToolMode.merge => _confirmMerge,
      UtilitariosPdfToolMode.split => _confirmSplit,
      UtilitariosPdfToolMode.edit => _confirmEdit,
    };
    final confirmLabel = switch (widget.mode) {
      UtilitariosPdfToolMode.edit => 'Salvar PDF',
      UtilitariosPdfToolMode.split => _resolveSplitExportOrder().isEmpty
          ? 'Gerar PDF'
          : 'Gerar (${_resolveSplitExportOrder().length} pág.)',
      _ => 'Confirmar',
    };
    final isEdit = widget.mode == UtilitariosPdfToolMode.edit;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasWork) ...[
              // Cancelar + Trocar side by side
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _onCancelOperation,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: _sessionOutlinedStyle(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _onTrocarArquivo,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                      label: Text(
                        _trocarArquivoLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: _sessionOutlinedStyle(),
                    ),
                  ),
                ],
              ),
              if (isEdit) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (!_busy && canConfirm)
                            ? () => _openEditPreview()
                            : null,
                        icon: const Icon(Icons.visibility_rounded, size: 18),
                        label: const Text(
                          'Pré-visualizar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: _gradient.first,
                          side: BorderSide(
                            color: _gradient.first.withValues(alpha: 0.45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: _gradient),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _gradient.first.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: (!_busy && canConfirm) ? onConfirm : null,
                          icon: const Icon(Icons.ios_share_rounded, size: 20),
                          label: Text(
                            confirmLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor:
                                Colors.grey.withValues(alpha: 0.35),
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: (!_busy && canConfirm) ? _removePdfPassword : null,
                  icon: Icon(
                    Icons.lock_open_rounded,
                    size: 18,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.9),
                  ),
                  label: const Text(
                    'Limpar senha e compartilhar',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    minimumSize: const Size(48, 40),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: (!_busy && canConfirm) ? onConfirm : null,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(confirmLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: _gradient.first,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _onCloseFlow,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text(
                    'Cancelar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: _sessionOutlinedStyle(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Resultado do editor de campos em lista.
class _PdfFieldsEditorResult {
  const _PdfFieldsEditorResult({
    required this.drafts,
    required this.excludedKeys,
  });

  final Map<int, Map<String, String>> drafts;
  final Set<String> excludedKeys;
}

/// Editor fullscreen — todos os campos do PDF em lista moderna.
class _PdfFieldsEditorScreen extends StatefulWidget {
  const _PdfFieldsEditorScreen({
    required this.gradient,
    required this.docFields,
    required this.thumbs,
    required this.initialDrafts,
    this.focusFieldKey,
  });

  final List<Color> gradient;
  final List<List<UtilPdfTextField>> docFields;
  final List<Uint8List> thumbs;
  final Map<int, Map<String, String>> initialDrafts;
  final String? focusFieldKey;

  @override
  State<_PdfFieldsEditorScreen> createState() => _PdfFieldsEditorScreenState();
}

class _PdfFieldsEditorScreenState extends State<_PdfFieldsEditorScreen> {
  static const _cardAccents = <Color>[
    Color(0xFF059669),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
    Color(0xFF9333EA),
  ];

  late final Map<int, Map<String, String>> _drafts;
  final Set<String> _excluded = {};
  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _drafts = widget.initialDrafts.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v)),
    );
    for (var p = 0; p < widget.docFields.length; p++) {
      for (final f in widget.docFields[p]) {
        _cardKeys[_key(p, f.id)] = GlobalKey();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _key(int page, String fieldId) => '${page}_$fieldId';

  int get _totalFields =>
      widget.docFields.fold<int>(0, (n, page) => n + page.length);

  int get _activeFields => _totalFields - _excluded.length;

  void _scrollToFocus() {
    final focus = widget.focusFieldKey;
    if (focus == null) return;
    final ctx = _cardKeys[focus]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  String _fieldText(int page, UtilPdfTextField field) {
    if (_excluded.contains(_key(page, field.id))) return '';
    return (_drafts[page]?[field.id] ?? field.text).trim();
  }

  void _confirm() {
    Navigator.pop(
      context,
      _PdfFieldsEditorResult(
          drafts: _drafts, excludedKeys: Set.from(_excluded)),
    );
  }

  void _cancel() => Navigator.pop(context);

  Future<void> _editField(int page, UtilPdfTextField field) async {
    if (_excluded.contains(_key(page, field.id))) return;
    final ctrl = TextEditingController(text: _fieldText(page, field));
    final accent = _cardAccents[page % _cardAccents.length];
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Editar campo',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 8,
                    minLines: 3,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Digite o novo texto…',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: accent, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (ctx, constraints) {
                      final narrow = constraints.maxWidth < 360;
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, ctrl.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: const Text('Aplicar'),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, ctrl.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: const Text('Aplicar'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _drafts[page] ??= {};
      _drafts[page]![field.id] = result;
    });
  }

  Future<void> _deleteField(int page, UtilPdfTextField field) async {
    final fieldKey = _key(page, field.id);
    if (_excluded.contains(fieldKey)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir campo?'),
        content: const Text(
          'Este campo será removido da lista e coberto no PDF ao confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _excluded.add(fieldKey));
  }

  void _restoreField(int page, UtilPdfTextField field) {
    setState(() => _excluded.remove(_key(page, field.id)));
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gradient;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 118,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TextButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            label: const Text(
              'Retornar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
        title: const Text(
          'Campos editáveis',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: g.first,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: g,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Text(
              '$_activeFields de $_totalFields campo(s) · edição em grade · toque para editar · cor do texto preservada',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                // Flatten all fields into a list for the grid.
                final items = <({int page, UtilPdfTextField field, int idx})>[];
                for (var p = 0; p < widget.docFields.length; p++) {
                  for (var i = 0; i < widget.docFields[p].length; i++) {
                    items.add((page: p, field: widget.docFields[p][i], idx: i));
                  }
                }
                return CustomScrollView(
                  controller: _scrollCtrl,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = items[index];
                            final field = item.field;
                            final p = item.page;
                            final i = item.idx;
                            final fieldKey = _key(p, field.id);
                            final accent =
                                _cardAccents[index % _cardAccents.length];
                            final excluded = _excluded.contains(fieldKey);
                            final text = _fieldText(p, field);
                            final original = field.text.trim();
                            final edited = !excluded && text != original;
                            final textColor = Color(field.textArgb);

                            return Opacity(
                              key: _cardKeys[fieldKey],
                              opacity: excluded ? 0.5 : 1,
                              child: GestureDetector(
                                onTap: excluded
                                    ? () => _restoreField(p, field)
                                    : () => _editField(p, field),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: excluded
                                          ? Colors.grey.shade300
                                          : accent.withValues(alpha: 0.45),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 8, 6, 7),
                                        decoration: BoxDecoration(
                                          color: excluded
                                              ? Colors.grey.shade100
                                              : accent.withValues(alpha: 0.08),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(13),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 3,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: excluded
                                                    ? Colors.grey.shade400
                                                    : accent,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Pg ${p + 1} · C ${i + 1}${edited ? ' ✎' : ''}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 11,
                                                  color: excluded
                                                      ? Colors.grey.shade500
                                                      : accent,
                                                ),
                                              ),
                                            ),
                                            if (!excluded)
                                              SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  tooltip: 'Excluir',
                                                  onPressed: () =>
                                                      _deleteField(p, field),
                                                  icon: Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 16,
                                                    color: Colors.red.shade600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              10, 7, 10, 8),
                                          child: Text(
                                            excluded
                                                ? (original.isEmpty
                                                    ? '(excluído)'
                                                    : original)
                                                : (text.isEmpty
                                                    ? 'Toque para editar'
                                                    : text),
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: field.fontBold
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              fontSize: 12.5,
                                              height: 1.3,
                                              color: excluded
                                                  ? Colors.grey.shade500
                                                  : textColor,
                                              decoration: excluded
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: items.length,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.88,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: Colors.grey.shade800,
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      'Confirmar',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: g.first,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pré-visualização fullscreen do PDF editado antes de salvar/compartilhar.
/// Usa a proporção **real da imagem** (nunca força A4) — evita documento achatado.
class _PdfEditPreviewScreen extends StatefulWidget {
  const _PdfEditPreviewScreen({
    required this.gradient,
    required this.pages,
    required this.fileName,
    this.pageAspects = const [],
    this.pageSizesPts = const [],
    this.preferShare = false,
  });

  final List<Color> gradient;
  final List<Uint8List> pages;
  final String fileName;
  final List<double> pageAspects;
  final List<({double widthPts, double heightPts})> pageSizesPts;
  final bool preferShare;

  @override
  State<_PdfEditPreviewScreen> createState() => _PdfEditPreviewScreenState();
}

class _PdfEditPreviewScreenState extends State<_PdfEditPreviewScreen> {
  late List<double> _aspects;

  @override
  void initState() {
    super.initState();
    _aspects = List<double>.from(widget.pageAspects);
    while (_aspects.length < widget.pages.length) {
      _aspects.add(0);
    }
    unawaited(_measureAspects());
  }

  Future<void> _measureAspects() async {
    for (var i = 0; i < widget.pages.length; i++) {
      try {
        final codec = await ui.instantiateImageCodec(widget.pages[i]);
        final frame = await codec.getNextFrame();
        final w = frame.image.width.toDouble();
        final h = frame.image.height.toDouble();
        frame.image.dispose();
        if (w > 0 && h > 0 && mounted) {
          setState(() => _aspects[i] = w / h);
        }
      } catch (_) {}
    }
  }

  double _aspectFor(int index) {
    if (index < _aspects.length && _aspects[index] > 0.05) {
      return _aspects[index];
    }
    if (index < widget.pageSizesPts.length) {
      final s = widget.pageSizesPts[index];
      if (s.widthPts > 0 && s.heightPts > 0) {
        return s.widthPts / s.heightPts;
      }
    }
    return 1.0;
  }

  void _openZoom(BuildContext context, int index) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PdfPageZoomScreen(
          page: widget.pages[index],
          pageNumber: index + 1,
          pageCount: widget.pages.length,
          gradient: widget.gradient,
          aspect: _aspectFor(index),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: SizedBox(
        height: 48,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gradient;
    final preferShare = widget.preferShare;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        leading: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text(
            'Voltar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
        title: const Text(
          'Pré-visualizar',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Sair',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Toque para ampliar · proporção original · Salvar ou Enviar',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: widget.pages.length,
              itemBuilder: (context, index) {
                final aspect = _aspectFor(index);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxW = math.min(constraints.maxWidth, 640.0);
                        final h = maxW / aspect;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openZoom(context, index),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: maxW,
                              height: h,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    widget.pages[index],
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.high,
                                    alignment: Alignment.center,
                                  ),
                                  if (widget.pages.length > 1)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              g.first.withValues(alpha: 0.92),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${index + 1}/${widget.pages.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: IconButton(
                                      tooltip: 'Ampliar',
                                      onPressed: () =>
                                          _openZoom(context, index),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F172A)
                                            .withValues(alpha: 0.75),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(44, 44),
                                      ),
                                      icon:
                                          const Icon(Icons.fullscreen_rounded),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Voltar ao editor',
                          maxLines: 1,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: preferShare
                        ? [
                            _actionBtn(
                              label: 'Enviar',
                              icon: Icons.ios_share_rounded,
                              color: g.first,
                              onTap: () => Navigator.pop(context, 'share'),
                            ),
                            const SizedBox(width: 8),
                            _actionBtn(
                              label: 'Salvar',
                              icon: Icons.save_rounded,
                              color: const Color(0xFF2563EB),
                              onTap: () =>
                                  Navigator.pop(context, 'save_folder'),
                            ),
                          ]
                        : [
                            _actionBtn(
                              label: 'Salvar',
                              icon: Icons.save_rounded,
                              color: const Color(0xFF2563EB),
                              onTap: () =>
                                  Navigator.pop(context, 'save_folder'),
                            ),
                            const SizedBox(width: 8),
                            _actionBtn(
                              label: 'Enviar',
                              icon: Icons.ios_share_rounded,
                              color: g.first,
                              onTap: () => Navigator.pop(context, 'share'),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ampliação dedicada da página — zoom/pan sem disputar gestos com a lista da
/// prévia. O botão **Retornar** permanece sempre visível.
class _PdfPageZoomScreen extends StatefulWidget {
  const _PdfPageZoomScreen({
    required this.page,
    required this.pageNumber,
    required this.pageCount,
    required this.gradient,
    this.aspect = 210 / 297,
  });

  final Uint8List page;
  final int pageNumber;
  final int pageCount;
  final List<Color> gradient;
  final double aspect;

  @override
  State<_PdfPageZoomScreen> createState() => _PdfPageZoomScreenState();
}

class _PdfPageZoomScreenState extends State<_PdfPageZoomScreen> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setScale(double target) {
    final scale = target.clamp(1.0, 8.0);
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale);
    _controller.value = matrix;
    setState(() {});
  }

  void _zoomBy(double factor) {
    _setScale(_controller.value.getMaxScaleOnAxis() * factor);
  }

  void _reset() => _setScale(1);

  @override
  Widget build(BuildContext context) {
    final current = _controller.value.getMaxScaleOnAxis();
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 118,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: const Text(
            'Retornar',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
        ),
        title: Text(
          'Página ${widget.pageNumber} de ${widget.pageCount}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: widget.gradient.first,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: current > 1.05 ? _reset : () => _setScale(2.5),
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(80),
                onInteractionEnd: (_) => setState(() {}),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final aspect =
                            widget.aspect > 0.05 ? widget.aspect : 1.0;
                        final maxW = c.maxWidth;
                        final maxH = c.maxHeight;
                        late final double w;
                        late final double h;
                        if (maxW / maxH > aspect) {
                          h = maxH;
                          w = h * aspect;
                        } else {
                          w = maxW;
                          h = w / aspect;
                        }
                        return Container(
                          width: w,
                          height: h,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              widget.page,
                              width: w,
                              height: h,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Center(
                child: Material(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Diminuir',
                          onPressed:
                              current <= 1.01 ? null : () => _zoomBy(1 / 1.4),
                          icon: const Icon(Icons.remove_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                        TextButton(
                          onPressed: _reset,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: Text(
                            '${(current * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ampliar',
                          onPressed:
                              current >= 7.99 ? null : () => _zoomBy(1.4),
                          icon: const Icon(Icons.add_rounded),
                          color: Colors.white,
                          disabledColor: Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
