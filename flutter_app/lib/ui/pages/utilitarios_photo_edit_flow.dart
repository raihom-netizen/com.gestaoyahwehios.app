import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:gestao_yahweh/constants/utilitarios_module_icons.dart';
import 'package:gestao_yahweh/services/utilitarios_photo_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_photo_collage_flow.dart';

class UtilitariosPhotoEditResult {
  const UtilitariosPhotoEditResult({
    required this.bytes,
    required this.fileName,
    required this.message,
  });

  final Uint8List bytes;
  final String fileName;
  final String message;
}

enum _PhotoPageMode { editor, collage }

enum _PhotoTool {
  none,
  enhance,
  manualBlur,
  faces,
  crop,
}

enum _CropAspectPreset {
  free(null, 'Livre'),
  square(1, '1:1'),
  portrait45(4 / 5, '4:5'),
  landscape43(4 / 3, '4:3'),
  landscape169(16 / 9, '16:9'),
  story916(9 / 16, '9:16');

  const _CropAspectPreset(this.ratio, this.label);
  final double? ratio;
  final String label;
}

Future<UtilitariosPhotoEditResult?> openUtilitariosPhotoEditFlow(
  BuildContext context,
) {
  return Navigator.of(context).push<UtilitariosPhotoEditResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _UtilitariosPhotoEditPage(),
    ),
  );
}

class _UtilitariosPhotoEditPage extends StatefulWidget {
  const _UtilitariosPhotoEditPage();

  @override
  State<_UtilitariosPhotoEditPage> createState() =>
      _UtilitariosPhotoEditPageState();
}

class _UtilitariosPhotoEditPageState extends State<_UtilitariosPhotoEditPage> {
  static const _gradient = [
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
  ];

  final _uuid = const Uuid();
  final GlobalKey _canvasKey = GlobalKey();
  final _picker = ImagePicker();
  final _viewerCtrl = TransformationController();

  _PhotoPageMode _pageMode = _PhotoPageMode.editor;
  bool _busy = false;
  String? _busyLabel;
  Uint8List? _image;
  String? _fileName;
  final List<Uint8List> _historyStack = [];
  int _historyIndex = -1;
  final List<UtilPhotoEditRegion> _regions = [];
  String? _selectedId;
  _PhotoTool _tool = _PhotoTool.none;
  bool _blurWorkspaceOpen = false;
  bool _chromeVisible = true;
  bool _showingOriginal = false;
  bool _enhanceSheetOpen = false;
  bool _previewPanelOpen = false;
  bool _previewOpenForSave = false;
  _CropAspectPreset _cropAspect = _CropAspectPreset.free;
  Rect? _cropRect;
  double _aspect = 1.0;
  Offset? _dragStart;
  Offset? _dragCurrent;
  double _blurIntensity = 0.45;
  UtilPhotoBlurMode _blurMode = UtilPhotoBlurMode.gaussian;
  String? _statusBadge;
  Timer? _statusBadgeTimer;

  static const _immersiveBg = Color(0xFF0B1220);

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
          content: Text(
            e.toString().replaceFirst('StateError: ', '').replaceFirst('Bad state: ', ''),
          ),
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

  void _pushHistory() {
    // Mantido para compatibilidade — histórico usa _commitNewImage.
  }

  void _commitNewImage(Uint8List bytes, {required bool asNewStep}) {
    if (asNewStep && _historyIndex >= 0) {
      _historyStack.removeRange(_historyIndex + 1, _historyStack.length);
      _historyStack.add(Uint8List.fromList(bytes));
      _historyIndex = _historyStack.length - 1;
    } else if (_historyStack.isEmpty) {
      _historyStack.add(Uint8List.fromList(bytes));
      _historyIndex = 0;
    } else if (!asNewStep) {
      _historyStack[_historyIndex] = Uint8List.fromList(bytes);
    }
    while (_historyStack.length > 8) {
      _historyStack.removeAt(0);
      _historyIndex--;
    }
    _image = bytes;
  }

  void _resetHistory(Uint8List bytes) {
    _historyStack
      ..clear()
      ..add(Uint8List.fromList(bytes));
    _historyIndex = 0;
    _image = bytes;
  }

  Uint8List? get _originalImage =>
      _historyStack.isNotEmpty ? _historyStack.first : _image;

  int get _editStepCount => math.max(0, _historyIndex);

  void _flashStatus(String message) {
    _statusBadgeTimer?.cancel();
    setState(() => _statusBadge = message);
    _statusBadgeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusBadge = null);
    });
  }

  void _hapticLight() {
    if (!kIsWeb) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  void _toggleChrome() {
    if (_blurWorkspaceOpen || _enhanceSheetOpen) return;
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _toggleViewerZoom() {
    final m = _viewerCtrl.value;
    final scale = m.getMaxScaleOnAxis();
    if (scale > 1.05) {
      _viewerCtrl.value = Matrix4.identity();
    } else {
      _viewerCtrl.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _statusBadgeTimer?.cancel();
    _viewerCtrl.dispose();
    super.dispose();
  }

  Future<void> _setImage(Uint8List bytes, {bool pushHistory = true}) async {
    if (pushHistory && _image != null) _pushHistory();
    final prepared = await UtilitariosPhotoService.preparePhotoForEditor(bytes);
    final aspect = await UtilitariosPhotoService.photoAspectRatio(prepared);
    if (!mounted) return;
    setState(() {
      if (pushHistory) {
        _commitNewImage(prepared, asNewStep: true);
      } else {
        _resetHistory(prepared);
      }
      _aspect = aspect;
      _regions.clear();
      _selectedId = null;
      _cropRect = null;
      _enhanceSheetOpen = false;
    });
  }

  void _undo() {
    if (_historyIndex <= 0) return;
    _hapticLight();
    setState(() {
      _historyIndex--;
      _image = Uint8List.fromList(_historyStack[_historyIndex]);
      _regions.clear();
      _selectedId = null;
      _cropRect = null;
      _tool = _PhotoTool.none;
    });
    unawaited(
      UtilitariosPhotoService.photoAspectRatio(_image!).then((a) {
        if (mounted) setState(() => _aspect = a);
      }),
    );
    _flashStatus('Desfeito');
  }

  void _jumpToHistory(int index) {
    if (index < 0 || index >= _historyStack.length) return;
    _hapticLight();
    setState(() {
      _historyIndex = index;
      _image = Uint8List.fromList(_historyStack[index]);
      _regions.clear();
      _selectedId = null;
      _cropRect = null;
      _tool = _PhotoTool.none;
    });
    unawaited(
      UtilitariosPhotoService.photoAspectRatio(_image!).then((a) {
        if (mounted) setState(() => _aspect = a);
      }),
    );
  }

  bool get _hasUnsavedWork => _historyIndex > 0 || _regions.isNotEmpty;

  void _clearPhotoState() {
    _image = null;
    _fileName = null;
    _historyStack.clear();
    _historyIndex = -1;
    _regions.clear();
    _selectedId = null;
    _tool = _PhotoTool.none;
    _blurWorkspaceOpen = false;
    _chromeVisible = true;
    _showingOriginal = false;
    _enhanceSheetOpen = false;
    _cropAspect = _CropAspectPreset.free;
    _cropRect = null;
    _aspect = 1.0;
    _dragStart = null;
    _dragCurrent = null;
    _statusBadge = null;
    _viewerCtrl.value = Matrix4.identity();
  }

  void _openBlurWorkspace({_PhotoTool mode = _PhotoTool.manualBlur}) {
    setState(() {
      _blurWorkspaceOpen = true;
      _tool = mode;
      _cropRect = null;
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  void _closeBlurWorkspace() {
    setState(() {
      _blurWorkspaceOpen = false;
      _tool = _PhotoTool.none;
      _dragStart = null;
      _dragCurrent = null;
    });
  }

  Future<bool> _confirmDiscardEdits(String message) async {
    if (!_hasUnsavedWork) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Descartar alterações?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDB2777),
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onCloseEditor() async {
    if (_busy) return;
    if (_image == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!await _confirmDiscardEdits(
      'As alterações desta foto serão perdidas ao sair do editor.',
    )) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onTrocarFoto() async {
    if (_busy || _image == null) return;
    if (!await _confirmDiscardEdits(
      'Trocar de foto? As alterações atuais serão descartadas.',
    )) {
      return;
    }
    if (!mounted) return;
    if (kIsWeb) {
      await _pickImage();
      return;
    }
    final escolha = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoPickSourceSheet(
        onGaleria: () => Navigator.pop(ctx, 'galeria'),
        onCamera: () => Navigator.pop(ctx, 'camera'),
      ),
    );
    if (!mounted || escolha == null) return;
    await _pickImage(camera: escolha == 'camera');
  }

  ButtonStyle _photoOutlinedActionStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: const Color(0xFF7C3AED),
        side: BorderSide(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.38),
          width: 1.4,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Future<void> _pickImage({bool camera = false}) async {
    await _withBusy('Carregando foto…', () async {
      Uint8List? bytes;
      String name = 'foto.jpg';
      if (camera && !kIsWeb) {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
          maxWidth: 3200,
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      } else {
        final files = await utilitariosPickPlatformFiles(
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          preferBytes: true,
        );
        if (files.isEmpty) return;
        final f = files.first;
        bytes = await utilitariosReadPlatformFileBytes(f);
        name = f.name;
      }
      if (bytes.isEmpty) throw StateError('Imagem vazia.');
      setState(() {
        _historyStack.clear();
        _historyIndex = -1;
        _fileName = name;
        _tool = _PhotoTool.none;
        _blurWorkspaceOpen = false;
        _enhanceSheetOpen = false;
        _chromeVisible = true;
        _pageMode = _PhotoPageMode.editor;
      });
      await _setImage(bytes, pushHistory: false);
    });
  }

  Future<void> _runEnhance() async {
    setState(() {
      _enhanceSheetOpen = true;
      _chromeVisible = true;
      _tool = _PhotoTool.enhance;
    });
  }

  Future<void> _applyEnhance(UtilPhotoEnhanceTarget target) async {
    final raw = _image;
    if (raw == null) return;
    setState(() => _enhanceSheetOpen = false);
    await _withBusy('Melhorando para ${target.label}…', () async {
      final out = await UtilitariosPhotoService.enhanceQuality(
        raw,
        target: target,
      );
      await _setImage(out);
      if (mounted) _flashStatus('${target.label} aplicado');
      _hapticLight();
    });
  }

  Future<void> _runRotate() async {
    final raw = _image;
    if (raw == null) return;
    await _withBusy('Girando…', () async {
      final out = await UtilitariosPhotoService.rotateClockwise(raw);
      await _setImage(out);
    });
  }

  Future<void> _runFlip() async {
    final raw = _image;
    if (raw == null) return;
    await _withBusy('Espelhando…', () async {
      final out = await UtilitariosPhotoService.flipHorizontal(raw);
      await _setImage(out);
    });
  }

  Future<void> _applyCrop() async {
    final raw = _image;
    final rect = _cropRect;
    if (raw == null || rect == null) {
      throw StateError('Desenhe a área de corte na foto.');
    }
    await _withBusy('Cortando…', () async {
      final out = await UtilitariosPhotoService.cropImage(
        raw,
        nx: rect.left,
        ny: rect.top,
        nw: rect.width,
        nh: rect.height,
      );
      await _setImage(out);
      if (mounted) {
        _flashStatus('Corte aplicado');
        _hapticLight();
      }
      setState(() => _tool = _PhotoTool.none);
    });
  }

  Future<void> _detectFaces() async {
    final raw = _image;
    if (raw == null) return;
    if (!UtilitariosPhotoService.mlKitFaceSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Detecção de rostos no app Android e iPhone.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _withBusy('Detectando rostos…', () async {
      final found = await UtilitariosPhotoService.detectFaces(raw);
      if (found.isEmpty) {
        throw StateError('Nenhum rosto encontrado. Marque manualmente.');
      }
      setState(() {
        _regions
          ..removeWhere((r) => r.kind == 'face')
          ..addAll(found);
      });
      _openBlurWorkspace(mode: _PhotoTool.faces);
    });
  }

  Future<void> _applyBlur() async {
    final raw = _image;
    if (raw == null) return;
    final radius = (6 + _blurIntensity * 34).round();
    await _withBusy('Aplicando ${_blurMode.label.toLowerCase()}…', () async {
      if (_regions.isEmpty) {
        throw StateError('Marque ou detecte áreas para borrar.');
      }
      final out = await UtilitariosPhotoService.applyBlurRegions(
        raw,
        _regions,
        blurRadius: radius,
        mode: _blurMode,
      );
      await _setImage(out);
      if (mounted) {
        _flashStatus('Borrão aplicado');
        _hapticLight();
      }
      if (mounted) _closeBlurWorkspace();
    });
  }

  String get _outputFileName {
    final base = (_fileName ?? 'foto')
        .replaceAll(RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false), '');
    return '${base.isEmpty ? 'foto' : base}_editada.jpg';
  }

  Future<void> _savePhotoLocal() async {
    final bytes = _image;
    if (bytes == null) return;
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: bytes,
      fileName: _outputFileName,
      mimeType: 'image/jpeg',
      preferShare: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Foto salva em Utilitarios_GestaoYahweh no aparelho.'
              : 'Não foi possível salvar a foto.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sharePhoto() async {
    final bytes = _image;
    if (bytes == null) return;
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: bytes,
      fileName: _outputFileName,
      mimeType: 'image/jpeg',
      preferShare: true,
      shareText: 'Foto editada — GestÃ£o Yahweh',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Escolha WhatsApp, e-mail ou outro app.'
              : 'Não foi possível compartilhar.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startCropMode() {
    setState(() {
      _blurWorkspaceOpen = false;
      _tool = _PhotoTool.crop;
      _cropRect ??= const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
      _regions.clear();
      _selectedId = null;
    });
  }

  void _addManualRegion(Rect norm) {
    final id = _uuid.v4();
    setState(() {
      if (_tool == _PhotoTool.crop) {
        _cropRect = norm;
        return;
      }
      _regions.add(
        UtilPhotoEditRegion(
          id: id,
          nx: norm.left,
          ny: norm.top,
          nw: norm.width,
          nh: norm.height,
          label: 'Área',
          kind: 'manual',
        ),
      );
      _selectedId = id;
    });
  }

  Rect? _normRectFromDrag(Offset a, Offset b, Size canvas) {
    if (canvas.width <= 0 || canvas.height <= 0) return null;
    var left = (math.min(a.dx, b.dx) / canvas.width).clamp(0.0, 1.0);
    var top = (math.min(a.dy, b.dy) / canvas.height).clamp(0.0, 1.0);
    var right = (math.max(a.dx, b.dx) / canvas.width).clamp(0.0, 1.0);
    var bottom = (math.max(a.dy, b.dy) / canvas.height).clamp(0.0, 1.0);
    var w = right - left;
    var h = bottom - top;
    if (w < 0.02 || h < 0.02) return null;

    final ratio = _cropAspect.ratio;
    if (_tool == _PhotoTool.crop && ratio != null) {
      final cx = left + w / 2;
      final cy = top + h / 2;
      if (w / h > ratio) {
        w = h * ratio;
      } else {
        h = w / ratio;
      }
      left = (cx - w / 2).clamp(0.0, 1.0 - w);
      top = (cy - h / 2).clamp(0.0, 1.0 - h);
    }
    return Rect.fromLTWH(left, top, w, h);
  }

  Future<void> _openPreview({bool openForSave = false}) async {
    final bytes = _image;
    if (bytes == null) return;
    setState(() {
      _previewPanelOpen = true;
      _previewOpenForSave = openForSave;
      _enhanceSheetOpen = false;
      _tool = _PhotoTool.none;
      _chromeVisible = true;
    });
  }

  void _closePreviewPanel() {
    if (!_previewPanelOpen) return;
    setState(() {
      _previewPanelOpen = false;
      _previewOpenForSave = false;
    });
  }

  Future<void> _handlePreviewAction(_PhotoPreviewAction action) async {
    _closePreviewPanel();
    if (!mounted) return;
    switch (action) {
      case _PhotoPreviewAction.back:
        break;
      case _PhotoPreviewAction.save:
        await _savePhotoLocal();
      case _PhotoPreviewAction.share:
        await _sharePhoto();
      case _PhotoPreviewAction.finish:
        await _confirmSave();
    }
  }

  Future<void> _openFinishSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoFinishSheet(
        editSteps: _editStepCount,
        onPreview: () => Navigator.pop(ctx, 'preview'),
        onSave: () => Navigator.pop(ctx, 'save'),
        onShare: () => Navigator.pop(ctx, 'share'),
        onFinish: () => Navigator.pop(ctx, 'finish'),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'preview':
        await _openPreview();
      case 'save':
      case 'share':
      case 'finish':
        await _openPreview(openForSave: action == 'finish');
    }
  }

  Future<void> _confirmSave() async {
    final bytes = _image;
    if (bytes == null) return;
    final base = (_fileName ?? 'foto')
        .replaceAll(RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false), '');
    if (!mounted) return;
    Navigator.pop(
      context,
      UtilitariosPhotoEditResult(
        bytes: bytes,
        fileName: '${base.isEmpty ? 'foto' : base}_editada.jpg',
        message: 'Foto editada localmente no GestÃ£o Yahweh.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editingPhoto =
        _pageMode == _PhotoPageMode.editor && _image != null && !_blurWorkspaceOpen;

    return Scaffold(
      backgroundColor: editingPhoto ? _immersiveBg : Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: editingPhoto,
      appBar: _buildAppBar(editingPhoto),
      body: Stack(
        children: [
          Column(
            children: [
              if ((!editingPhoto || _chromeVisible) && !_previewPanelOpen)
                _buildModeSwitcher(),
              if (_pageMode == _PhotoPageMode.collage)
                Expanded(
                  child: UtilitariosPhotoCollagePanel(
                    busy: _busy,
                    onExitCollage: () =>
                        setState(() => _pageMode = _PhotoPageMode.editor),
                    onBusyChanged: (s) => setState(() {
                      _busy = s.busy;
                      _busyLabel = s.label;
                    }),
                  ),
                )
              else if (_image == null)
                Expanded(child: _buildBody())
              else if (_blurWorkspaceOpen)
                Expanded(child: _buildBlurWorkspaceBody())
              else
                Expanded(child: _buildImmersiveEditor()),
            ],
          ),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar(bool editingPhoto) {
    if (editingPhoto && !_chromeVisible) {
      return null;
    }
    final showEditorActions = _pageMode == _PhotoPageMode.editor &&
        _image != null &&
        !_blurWorkspaceOpen &&
        !_previewPanelOpen;
    return AppBar(
      backgroundColor: editingPhoto
          ? _immersiveBg.withValues(alpha: 0.92)
          : null,
      foregroundColor: editingPhoto ? Colors.white : null,
      elevation: editingPhoto ? 0 : null,
      title: Text(
        _previewPanelOpen
            ? 'Pré-visualização'
            : (editingPhoto ? 'Editar foto' : 'Editor de Foto'),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: editingPhoto ? Colors.white : null,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: _previewPanelOpen ? 'Voltar ao editor' : 'Fechar editor',
        onPressed: _busy
            ? null
            : () {
                if (_previewPanelOpen) {
                  _closePreviewPanel();
                } else {
                  _onCloseEditor();
                }
              },
      ),
      actions: [
        if (showEditorActions && _historyIndex > 0)
          IconButton(
            onPressed: _busy ? null : _undo,
            icon: const Icon(Icons.undo_rounded),
            tooltip: 'Desfazer',
          ),
        if (showEditorActions) ...[
          IconButton(
            onPressed: _busy ? null : () => _openPreview(),
            icon: const Icon(Icons.visibility_rounded),
            tooltip: 'Pré-visualizar',
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Mais opções',
            color: const Color(0xFF1E293B),
            onSelected: (action) {
              switch (action) {
                case 'rotate':
                  unawaited(_runRotate());
                case 'flip':
                  unawaited(_runFlip());
                case 'swap':
                  unawaited(_onTrocarFoto());
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'rotate',
                child: ListTile(
                  leading: Icon(Icons.rotate_right_rounded),
                  title: Text('Girar 90°'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'flip',
                child: ListTile(
                  leading: Icon(Icons.flip_rounded),
                  title: Text('Espelhar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'swap',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz_rounded),
                  title: Text('Trocar foto'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _busy ? null : _openFinishSheet,
            icon: const Icon(Icons.check_circle_rounded),
            tooltip: 'Concluir',
          ),
        ],
      ],
    );
  }

  Widget _buildImmersiveEditor() {
    if (_previewPanelOpen) {
      return _buildInlinePreviewPanel();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: _toggleChrome,
                onDoubleTap: _toggleViewerZoom,
                onLongPressStart: _historyIndex > 0
                    ? (_) => setState(() => _showingOriginal = true)
                    : null,
                onLongPressEnd: _historyIndex > 0
                    ? (_) => setState(() => _showingOriginal = false)
                    : null,
                onLongPressCancel: () => setState(() => _showingOriginal = false),
                child: _buildBody(),
              ),
              if (_showingOriginal && _originalImage != null)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Original — solte para voltar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_statusBadge != null) _buildStatusBadge(),
            ],
          ),
        ),
        if (_historyStack.length > 1) _buildHistoryStrip(),
        if (_tool == _PhotoTool.crop) _buildCropFloatingBar(),
        if (_enhanceSheetOpen) _buildEnhanceSheet(),
        if (_chromeVisible && !_enhanceSheetOpen && _tool != _PhotoTool.crop)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _buildFloatingDock(),
          ),
      ],
    );
  }

  Widget _buildInlinePreviewPanel() {
    final bytes = _image;
    if (bytes == null) return const SizedBox.shrink();
    final steps = _editStepCount;
    final openForSave = _previewOpenForSave;
    final maxImgH = MediaQuery.sizeOf(context).height * 0.42;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: _gradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            openForSave
                ? 'Revise a foto final antes de exportar.'
                : steps > 0
                    ? '$steps edição(ões) aplicada(s).'
                    : 'Visualização da foto atual.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxImgH),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                if (_historyStack.length > 1) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _historyStack.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final selected = i == _historyIndex;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 44,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFDB2777)
                                    : Colors.white.withValues(alpha: 0.25),
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            child: Image.memory(
                              _historyStack[i],
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _handlePreviewAction(_PhotoPreviewAction.back),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text(
                    'Voltar ao editor',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _previewGradientButton(
                  icon: Icons.download_rounded,
                  label: 'Salvar no aparelho',
                  colors: const [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                  onPressed: _busy
                      ? null
                      : () => _handlePreviewAction(_PhotoPreviewAction.save),
                ),
                const SizedBox(height: 10),
                _previewGradientButton(
                  icon: Icons.share_rounded,
                  label: 'Compartilhar',
                  colors: _gradient,
                  onPressed: _busy
                      ? null
                      : () => _handlePreviewAction(_PhotoPreviewAction.share),
                ),
                if (openForSave) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _handlePreviewAction(_PhotoPreviewAction.finish),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Concluir e voltar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewGradientButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            height: 50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Positioned(
      top: 8,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _statusBadge!,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryStrip() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: _historyStack.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = i == _historyIndex;
            return GestureDetector(
              onTap: _busy ? null : () => _jumpToHistory(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFDB2777)
                        : Colors.white.withValues(alpha: 0.25),
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFDB2777).withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _historyStack[i],
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            );
          },
        ),
    );
  }

  Widget _buildEnhanceSheet() {
    final maxH = MediaQuery.sizeOf(context).height * 0.42;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Melhorar imagem',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _enhanceSheetOpen = false;
                                  _tool = _PhotoTool.none;
                                }),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                  Text(
                    'Escolha a resolução — processamento local e rápido.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, c) {
                      final stacked = c.maxWidth < 360;
                      final cards = UtilPhotoEnhanceTarget.values
                          .map((t) => _enhanceResolutionCard(t))
                          .toList();
                      if (stacked) {
                        return Column(
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              cards[i],
                              if (i < cards.length - 1) const SizedBox(height: 10),
                            ],
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 10),
                          Expanded(child: cards[1]),
                        ],
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

  Widget _enhanceResolutionCard(UtilPhotoEnhanceTarget target) {
    final is4k = target == UtilPhotoEnhanceTarget.fourK;
    final accent = is4k ? const Color(0xFF059669) : const Color(0xFF2563EB);
    return Material(
      color: accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _applyEnhance(target),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  is4k ? Icons.hd_rounded : Icons.high_quality_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${target.longEdge}px · nitidez + luz',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aspectPill(_CropAspectPreset preset) {
    final selected = _cropAspect == preset;
    return Material(
      color: selected
          ? const Color(0xFF8B5CF6)
          : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => setState(() => _cropAspect = preset),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            preset.label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingDock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 380;
                final tools = <Widget>[
                  _dockTool(
                    icon: Icons.auto_fix_high_rounded,
                    label: 'Melhorar',
                    accent: const Color(0xFF34D399),
                    onTap: _busy ? null : _runEnhance,
                    expanded: !narrow,
                  ),
                  _dockTool(
                    icon: Icons.crop_rounded,
                    label: 'Cortar',
                    accent: const Color(0xFFA78BFA),
                    selected: _tool == _PhotoTool.crop,
                    onTap: _busy ? null : _startCropMode,
                    expanded: !narrow,
                  ),
                  _dockTool(
                    icon: Icons.blur_on_rounded,
                    label: 'Borrar',
                    accent: const Color(0xFFF472B6),
                    onTap: _busy
                        ? null
                        : () => _openBlurWorkspace(mode: _PhotoTool.manualBlur),
                    expanded: !narrow,
                  ),
                  _dockTool(
                    icon: Icons.face_retouching_off_rounded,
                    label: 'Rostos',
                    accent: const Color(0xFF818CF8),
                    onTap: _busy ? null : _detectFaces,
                    expanded: !narrow,
                  ),
                  _dockTool(
                    icon: Icons.visibility_rounded,
                    label: 'Ver',
                    accent: const Color(0xFF38BDF8),
                    onTap: _busy ? null : () => _openPreview(),
                    expanded: !narrow,
                  ),
                ];
                if (narrow) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < tools.length; i++) ...[
                          SizedBox(width: 68, child: tools[i]),
                          if (i < tools.length - 1) const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: tools,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropFloatingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in _CropAspectPreset.values) ...[
                        _aspectPill(p),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final stacked = c.maxWidth < 380;
                    final cancelBtn = SizedBox(
                      width: stacked ? double.infinity : null,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _tool = _PhotoTool.none;
                                  _cropRect = null;
                                }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                    final applyBtn = SizedBox(
                      width: stacked ? double.infinity : null,
                      child: FilledButton.icon(
                        onPressed: _busy || _cropRect == null ? null : _applyCrop,
                        icon: const Icon(Icons.crop_rounded, size: 18),
                        label: const Text(
                          'Aplicar corte',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          applyBtn,
                          const SizedBox(height: 8),
                          cancelBtn,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 4, child: cancelBtn),
                        const SizedBox(width: 10),
                        Expanded(flex: 6, child: applyBtn),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(
        children: [
          _modePill(
            icon: Icons.tune_rounded,
            label: 'Editar foto',
            selected: _pageMode == _PhotoPageMode.editor,
            gradient: const [Color(0xFFDB2777), Color(0xFF7C3AED)],
            onTap: _busy ? null : () => setState(() => _pageMode = _PhotoPageMode.editor),
          ),
          const SizedBox(width: 10),
          _modePill(
            icon: Icons.grid_view_rounded,
            label: 'Colagem',
            selected: _pageMode == _PhotoPageMode.collage,
            gradient: const [Color(0xFF6366F1), Color(0xFF06B6D4)],
            onTap: _busy ? null : () => setState(() => _pageMode = _PhotoPageMode.collage),
          ),
        ],
      ),
    );
  }

  Widget _modePill({
    required IconData icon,
    required String label,
    required bool selected,
    required List<Color> gradient,
    required VoidCallback? onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: selected ? LinearGradient(colors: gradient) : null,
              color: selected
                  ? null
                  : (dark
                      ? const Color(0xFF1E293B)
                      : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : (dark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.grey.shade300),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: gradient.first.withValues(alpha: 0.32),
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
                  color: selected ? Colors.white : gradient.first,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? Colors.white
                          : (dark ? Colors.white.withValues(alpha: 0.9) : Colors.black87),
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

  Widget _buildBlurWorkspaceBody() {
    final radiusLabel = (6 + _blurIntensity * 34).round();
    return Material(
      color: _immersiveBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _closeBlurWorkspace,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fechar borrar',
                  ),
                  Expanded(
                    child: Text(
                      _tool == _PhotoTool.faces ? 'Borrar rostos' : 'Borrar áreas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy || _regions.isEmpty ? null : _applyBlur,
                    child: const Text(
                      'Aplicar',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _tool == _PhotoTool.faces
                    ? 'Rostos destacados — confira e toque em Aplicar.'
                    : 'Arraste na foto para marcar o que deseja borrar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildPhotoCanvas(blurMode: true)),
            LayoutBuilder(
              builder: (context, c) {
                final stacked = c.maxWidth < 420;
                final controls = Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Intensidade $radiusLabel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Slider(
                        value: _blurIntensity,
                        min: 0.05,
                        max: 1.0,
                        activeColor: const Color(0xFFDB2777),
                        inactiveColor: Colors.white.withValues(alpha: 0.15),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _blurIntensity = v),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final mode in UtilPhotoBlurMode.values)
                            SizedBox(
                              width: stacked ? double.infinity : null,
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _blurMode = mode),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: _blurMode == mode
                                      ? const Color(0xFFDB2777)
                                      : Colors.white.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  minimumSize: const Size(0, 42),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  mode.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (stacked) ...[
                        FilledButton.icon(
                          onPressed: _busy || _regions.isEmpty ? null : _applyBlur,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text('Aplicar (${_regions.length})'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            backgroundColor: const Color(0xFFDB2777),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy || _selectedId == null
                              ? null
                              : () => setState(() {
                                    _regions.removeWhere(
                                      (r) => r.id == _selectedId,
                                    );
                                    _selectedId = null;
                                  }),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Remover'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy || _selectedId == null
                                    ? null
                                    : () => setState(() {
                                          _regions.removeWhere(
                                            (r) => r.id == _selectedId,
                                          );
                                          _selectedId = null;
                                        }),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Remover'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                  minimumSize: const Size(0, 42),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed:
                                    _busy || _regions.isEmpty ? null : _applyBlur,
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text('Aplicar (${_regions.length})'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  backgroundColor: const Color(0xFFDB2777),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
                return controls;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.28),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 120),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFFDB2777),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _busyLabel ?? 'Processando…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _dockTool({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback? onTap,
    bool selected = false,
    bool expanded = true,
  }) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.45) : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accent.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
    if (expanded) {
      return Expanded(child: child);
    }
    return child;
  }

  Widget _buildBody() {
    if (_image == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ModernModuleUI.iconBadge(
                icon: UtilitariosModuleIcons.photoEdit,
                gradient: _gradient,
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                'Escolha uma foto',
                style: ModernModuleUI.moduleTitleStyle(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Melhore, corte, borre rostos ou monte colagens.',
                textAlign: TextAlign.center,
                style: ModernModuleUI.moduleSubtitleStyle(context),
              ),
              const SizedBox(height: 24),
              ModernModuleUI.centeredPickButton(
                gradient: _gradient,
                icon: Icons.photo_library_rounded,
                label: 'Galeria',
                onPressed: _busy ? null : () => _pickImage(),
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 10),
                ModernModuleUI.centeredPickButton(
                  gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  icon: Icons.photo_camera_rounded,
                  label: 'Câmera',
                  onPressed: _busy ? null : () => _pickImage(camera: true),
                  secondary: true,
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _onCloseEditor,
                icon: const Icon(Icons.close_rounded, size: 20),
                label: const Text(
                  'Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: _photoOutlinedActionStyle().copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _pageMode = _PhotoPageMode.collage),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Ir direto para Colagem'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: _buildPhotoCanvas(blurMode: false),
    );
  }

  Widget _buildPhotoCanvas({required bool blurMode}) {
    final image = _showingOriginal && _originalImage != null
        ? _originalImage!
        : _image;
    if (image == null) return const SizedBox.shrink();

    return ColoredBox(
      color: blurMode ? _immersiveBg : _immersiveBg,
      child: Padding(
        padding: EdgeInsets.all(blurMode ? 6 : 2),
        child: LayoutBuilder(
          builder: (context, c) {
            final maxW = c.maxWidth;
            final maxH = c.maxHeight;
            var w = maxW;
            var h = w / _aspect;
            if (h > maxH) {
              h = maxH;
              w = h * _aspect;
            }
            final canDrag = blurMode || _tool == _PhotoTool.crop;
            return Center(
              child: InteractiveViewer(
                transformationController: _viewerCtrl,
                minScale: 0.7,
                maxScale: 5,
                child: GestureDetector(
                  onPanStart: canDrag
                      ? (d) {
                          final box = _canvasKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(d.globalPosition);
                          setState(() {
                            _dragStart = local;
                            _dragCurrent = local;
                          });
                        }
                      : null,
                  onPanUpdate: canDrag
                      ? (d) {
                          final box = _canvasKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          setState(() {
                            _dragCurrent = box.globalToLocal(d.globalPosition);
                          });
                        }
                      : null,
                  onPanEnd: canDrag
                      ? (_) {
                          final start = _dragStart;
                          final end = _dragCurrent;
                          final box = _canvasKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (start != null && end != null && box != null) {
                            final rect = _normRectFromDrag(
                              start,
                              end,
                              box.size,
                            );
                            if (rect != null) _addManualRegion(rect);
                          }
                          setState(() {
                            _dragStart = null;
                            _dragCurrent = null;
                          });
                        }
                      : null,
                  child: SizedBox(
                    key: _canvasKey,
                    width: w,
                    height: h,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            image,
                            width: w,
                            height: h,
                            fit: BoxFit.fill,
                          ),
                        ),
                        if (_tool == _PhotoTool.crop && _cropRect != null)
                          ..._cropOverlay(_cropRect!, w, h),
                        if (_tool != _PhotoTool.crop)
                          ..._regions.map((r) => _regionOverlay(r, w, h)),
                        if (_dragStart != null && _dragCurrent != null)
                          Positioned.fromRect(
                            rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _tool == _PhotoTool.crop
                                      ? const Color(0xFF8B5CF6)
                                      : const Color(0xFFDB2777),
                                  width: 2,
                                ),
                                color: (_tool == _PhotoTool.crop
                                        ? const Color(0xFF8B5CF6)
                                        : const Color(0xFFDB2777))
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _cropOverlay(Rect norm, double w, double h) {
    final crop = Rect.fromLTWH(
      norm.left * w,
      norm.top * h,
      norm.width * w,
      norm.height * h,
    );
    return [
      Positioned.fill(
        child: CustomPaint(
          painter: _CropDimPainter(crop),
        ),
      ),
      Positioned.fromRect(
        rect: crop,
        child: CustomPaint(
          painter: _CropGridPainter(),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
      ..._cropHandlePositions(crop).map(
        (offset) => Positioned(
          left: offset.dx - 12,
          top: offset.dy - 12,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Offset> _cropHandlePositions(Rect crop) {
    return [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
      Offset(crop.center.dx, crop.top),
      Offset(crop.center.dx, crop.bottom),
      Offset(crop.left, crop.center.dy),
      Offset(crop.right, crop.center.dy),
    ];
  }

  Widget _regionOverlay(UtilPhotoEditRegion r, double w, double h) {
    final selected = r.id == _selectedId;
    final isFace = r.kind == 'face';
    final color = isFace ? const Color(0xFF7C3AED) : const Color(0xFFDB2777);
    return Positioned(
      left: r.nx * w,
      top: r.ny * h,
      width: r.nw * w,
      height: r.nh * h,
      child: GestureDetector(
        onTap: () => setState(() => _selectedId = r.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: color,
              width: selected ? 3 : 2,
            ),
            color: color.withValues(alpha: selected ? 0.32 : (isFace ? 0.22 : 0.14)),
            boxShadow: isFace
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: isFace
              ? Center(
                  child: Icon(
                    Icons.face_retouching_off_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: math.min(r.nw * w, r.nh * h) * 0.35,
                  ),
                )
              : (r.label.isEmpty
                  ? null
                  : Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        color: color.withValues(alpha: 0.85),
                        child: Text(
                          r.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )),
        ),
      ),
    );
  }
}

enum _PhotoPreviewAction { back, save, share, finish }

/// Pré-visualização fullscreen da foto editada.
class _PhotoEditPreviewScreen extends StatelessWidget {
  const _PhotoEditPreviewScreen({
    required this.imageBytes,
    required this.fileName,
    required this.editSteps,
    this.openForSave = false,
  });

  final Uint8List imageBytes;
  final String fileName;
  final int editSteps;
  final bool openForSave;

  static const _gradient = [
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDB2777),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, _PhotoPreviewAction.back),
        ),
        title: const Text(
          'Pré-visualização',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                openForSave
                    ? 'Revise a foto final. Salve, compartilhe ou volte para editar.'
                    : editSteps > 0
                        ? '$editSteps edição(ões) aplicada(s).'
                        : 'Visualização da foto atual.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _PhotoPreviewAction.back),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text(
                  'Voltar ao editor',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _PhotoPreviewAction.save),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text(
                  'Salvar no aparelho',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: const Color(0xFF1D4ED8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _PhotoPreviewAction.share),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text(
                  'Compartilhar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: _gradient[0],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (openForSave) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _PhotoPreviewAction.finish),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Concluir e voltar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoFinishSheet extends StatelessWidget {
  const _PhotoFinishSheet({
    required this.editSteps,
    required this.onPreview,
    required this.onSave,
    required this.onShare,
    required this.onFinish,
  });

  final int editSteps;
  final VoidCallback onPreview;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Concluir edição',
            style: ModernModuleUI.moduleTitleStyle(context, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            editSteps > 0
                ? '$editSteps alteração(ões). Pré-visualize antes de exportar.'
                : 'Pré-visualize ou exporte a foto.',
            textAlign: TextAlign.center,
            style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 13),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Pré-visualizar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Salvar no aparelho'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Compartilhar'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Concluir e voltar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: const Color(0xFFDB2777),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escolha rápida de origem ao trocar foto no editor.
class _PhotoPickSourceSheet extends StatelessWidget {
  const _PhotoPickSourceSheet({
    required this.onGaleria,
    required this.onCamera,
  });

  final VoidCallback onGaleria;
  final VoidCallback onCamera;

  static const _gradient = [
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Trocar foto',
            style: ModernModuleUI.moduleTitleStyle(context, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Escolha outra imagem da galeria ou da câmera.',
            textAlign: TextAlign.center,
            style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ModernModuleUI.centeredPickButton(
            gradient: _gradient,
            icon: Icons.photo_library_rounded,
            label: 'Galeria',
            onPressed: onGaleria,
          ),
          const SizedBox(height: 10),
          ModernModuleUI.centeredPickButton(
            gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
            icon: Icons.photo_camera_rounded,
            label: 'Câmera',
            onPressed: onCamera,
            secondary: true,
          ),
        ],
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final thirdW = size.width / 3;
    final thirdH = size.height / 3;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(thirdW * i, 0), Offset(thirdW * i, size.height), paint);
      canvas.drawLine(Offset(0, thirdH * i), Offset(size.width, thirdH * i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CropDimPainter extends CustomPainter {
  _CropDimPainter(this.crop);

  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRect(crop),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropDimPainter oldDelegate) =>
      oldDelegate.crop != crop;
}
