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
  manualBlur,
  faces,
  crop,
  caption,
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
  bool _captionSheetOpen = false;
  bool _previewPanelOpen = false;
  bool _previewOpenForSave = false;
  _CropAspectPreset _cropAspect = _CropAspectPreset.free;
  Rect? _cropRect;
  double _aspect = 1.0;
  Offset? _dragStart;
  Offset? _dragCurrent;
  double _blurIntensity = 0.45;
  UtilPhotoBlurMode _blurMode = UtilPhotoBlurMode.gaussian;
  final List<UtilPhotoCaptionOverlay> _captions = [];
  String? _selectedCaptionId;
  final TextEditingController _captionInputCtrl = TextEditingController();
  UtilPhotoCaptionStyle _captionStyle = UtilPhotoCaptionStyle.bold;
  int _captionColor = 0xFF0F172A;
  int _captionBoxBg = 0xFFFFFFFF;
  int _captionBorder = 0xFFFBBF24;
  bool _captionUseBox = true;
  bool _captionUseBorder = false;
  double _captionScale = 1.45;
  bool _captionBold = true;
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
    if (_blurWorkspaceOpen || _captionSheetOpen) return;
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
    _captionInputCtrl.dispose();
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
      _captionSheetOpen = false;
    });
  }

  Future<void> _applyColorEnhance() async {
    final raw = _image;
    if (raw == null) return;
    await _withBusy('Realçando cores…', () async {
      final out = await UtilitariosPhotoService.enhanceColorsFast(raw);
      await _setImage(out);
      if (mounted) _flashStatus('Cores realçadas');
      _hapticLight();
    });
  }

  void _openCaptionTool() {
    setState(() {
      _captionSheetOpen = true;
      _chromeVisible = true;
      _tool = _PhotoTool.caption;
      _blurWorkspaceOpen = false;
    });
  }

  void _addCaptionFromInput([String? preset]) {
    final text = (preset ?? _captionInputCtrl.text).trim();
    if (text.isEmpty) return;
    final id = _uuid.v4();
    setState(() {
      _captions.add(
        UtilPhotoCaptionOverlay(
          id: id,
          text: text,
          nx: 0.5,
          ny: 0.82,
          style: _captionStyle,
          scale: _captionScale,
          colorArgb: _captionColor,
          boxBgArgb: _captionUseBox ? _captionBoxBg : 0,
          borderArgb: _captionUseBorder ? _captionBorder : 0,
          bold: _captionBold,
        ),
      );
      _selectedCaptionId = id;
      if (preset == null) _captionInputCtrl.clear();
    });
    _hapticLight();
  }

  void _applyCaptionStyle(UtilPhotoCaptionStyle style) {
    setState(() {
      _captionStyle = style;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(style: style);
    });
  }

  void _applyCaptionColor(int colorArgb) {
    setState(() {
      _captionColor = colorArgb;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(colorArgb: colorArgb);
    });
  }

  void _applyCaptionBoxBg(int colorArgb) {
    setState(() {
      _captionBoxBg = colorArgb;
      _captionUseBox = true;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(boxBgArgb: colorArgb);
    });
  }

  void _applyCaptionBorder(int colorArgb) {
    setState(() {
      _captionBorder = colorArgb;
      _captionUseBorder = true;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(borderArgb: colorArgb);
    });
  }

  void _toggleCaptionBox(bool on) {
    setState(() {
      _captionUseBox = on;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(
        boxBgArgb: on ? _captionBoxBg : 0,
      );
    });
  }

  void _toggleCaptionBorder(bool on) {
    setState(() {
      _captionUseBorder = on;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(
        borderArgb: on ? _captionBorder : 0,
      );
    });
  }

  void _applyCaptionScale(double scale) {
    setState(() {
      _captionScale = scale;
      final id = _selectedCaptionId;
      if (id == null) return;
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx < 0) return;
      _captions[idx] = _captions[idx].copyWith(scale: scale);
    });
  }

  Future<void> _burnCaptionsToImage() async {
    final raw = _image;
    if (raw == null || _captions.isEmpty) {
      throw StateError('Adicione texto ou emoji antes de fixar.');
    }
    await _withBusy('Fixando legenda…', () async {
      final out = await UtilitariosPhotoService.burnCaptionOverlays(
        raw,
        List<UtilPhotoCaptionOverlay>.from(_captions),
      );
      await _setImage(out);
      if (!mounted) return;
      setState(() {
        _captions.clear();
        _selectedCaptionId = null;
        _captionSheetOpen = false;
        _tool = _PhotoTool.none;
      });
      _flashStatus('Legenda aplicada');
      _hapticLight();
    });
  }

  /// Salva/compartilha: grava overlays de texto na imagem se ainda não fixados.
  Future<void> _ensureCaptionsCommitted() async {
    if (_image == null || _captions.isEmpty) return;
    await _burnCaptionsToImage();
  }

  void _removeSelectedCaption() {
    final id = _selectedCaptionId;
    if (id == null) return;
    setState(() {
      _captions.removeWhere((c) => c.id == id);
      _selectedCaptionId = null;
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

  bool get _hasUnsavedWork =>
      _historyIndex > 0 || _regions.isNotEmpty || _captions.isNotEmpty;

  void _clearPhotoState() {
    _image = null;
    _fileName = null;
    _historyStack.clear();
    _historyIndex = -1;
    _regions.clear();
    _selectedId = null;
    _captions.clear();
    _selectedCaptionId = null;
    _tool = _PhotoTool.none;
    _blurWorkspaceOpen = false;
    _chromeVisible = true;
    _showingOriginal = false;
    _captionSheetOpen = false;
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
      if (camera) {
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
        _captionSheetOpen = false;
        _chromeVisible = true;
        _pageMode = _PhotoPageMode.editor;
      });
      await _setImage(bytes, pushHistory: false);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nenhum rosto automático — marque a área com o dedo em Borrar.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _openBlurWorkspace(mode: _PhotoTool.manualBlur);
        return;
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
    await _ensureCaptionsCommitted();
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
    await _ensureCaptionsCommitted();
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
    await _ensureCaptionsCommitted();
    final bytes = _image;
    if (bytes == null) return;
    setState(() {
      _previewPanelOpen = true;
      _previewOpenForSave = openForSave;
      _captionSheetOpen = false;
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
    await _ensureCaptionsCommitted();
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
        if (_captionSheetOpen) _buildCaptionSheet(),
        if (_chromeVisible && !_captionSheetOpen && _tool != _PhotoTool.crop)
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

  /// Atualiza a legenda selecionada (ou cria) com o rascunho atual — estilo Lens/WhatsApp.
  void _syncLiveCaptionFromDraft({bool createIfNeeded = true}) {
    final text = _captionInputCtrl.text.trim();
    if (text.isEmpty) return;
    final id = _selectedCaptionId;
    if (id != null) {
      final idx = _captions.indexWhere((x) => x.id == id);
      if (idx >= 0) {
        _captions[idx] = _captions[idx].copyWith(
          text: text,
          style: _captionStyle,
          scale: _captionScale,
          colorArgb: _captionColor,
          boxBgArgb: _captionUseBox ? _captionBoxBg : 0,
          borderArgb: _captionUseBorder ? _captionBorder : 0,
          bold: _captionBold,
        );
        return;
      }
    }
    if (!createIfNeeded) return;
    final newId = _uuid.v4();
    _captions.add(
      UtilPhotoCaptionOverlay(
        id: newId,
        text: text,
        nx: 0.5,
        ny: 0.78,
        style: _captionStyle,
        scale: _captionScale,
        colorArgb: _captionColor,
        boxBgArgb: _captionUseBox ? _captionBoxBg : 0,
        borderArgb: _captionUseBorder ? _captionBorder : 0,
        bold: _captionBold,
      ),
    );
    _selectedCaptionId = newId;
  }

  void _cancelCaptionSheet() {
    setState(() {
      _captionSheetOpen = false;
      if (_captions.isEmpty) {
        _tool = _PhotoTool.none;
      }
    });
  }

  void _confirmCaptionSheet() {
    final text = _captionInputCtrl.text.trim();
    setState(() {
      if (text.isNotEmpty) {
        _syncLiveCaptionFromDraft(createIfNeeded: true);
      }
      _captionSheetOpen = false;
      if (_captions.isEmpty) {
        _tool = _PhotoTool.none;
      }
    });
    _hapticLight();
  }

  Widget _buildCaptionSheet() {
    const emojis = [
      '😀', '😁', '😂', '🤣', '😊', '😍', '🥰', '😘',
      '😎', '🤩', '😇', '🙂', '😉', '😭', '😤', '🔥',
      '❤️', '💕', '💯', '✨', '⭐', '🌟', '✅', '✔️',
      '📌', '📍', '🎉', '🎊', '💪', '👍', '👏', '🙏',
      '📸', '🎯', '🚀', '💎', '🏆', '⚡', '🌈', '🌸',
    ];
    const textColors = [
      0xFFFFFFFF,
      0xFF0F172A,
      0xFFFBBF24,
      0xFF38BDF8,
      0xFFF472B6,
      0xFF34D399,
      0xFFA78BFA,
      0xFFF87171,
    ];
    const boxColors = [
      0xFF0F172A,
      0xFFE2E8F0,
      0xFFF97316,
      0xFFDB2777,
      0xFF2563EB,
      0xFF0D9488,
      0xFF7C3AED,
    ];
    const borderColors = [
      0xFF0F172A,
      0xFFFFFFFF,
      0xFFA78BFA,
      0xFF14B8A6,
      0xFFF97316,
      0xFFEF4444,
    ];
    const sizePresets = <(String, double)>[
      ('Pequena', 0.75),
      ('Média', 1.0),
      ('Grande', 1.45),
    ];
    // Ordem visual do print moderno.
    const styleOrder = <UtilPhotoCaptionStyle>[
      UtilPhotoCaptionStyle.clean,
      UtilPhotoCaptionStyle.classic,
      UtilPhotoCaptionStyle.bold,
      UtilPhotoCaptionStyle.neon,
    ];
    final maxH = MediaQuery.sizeOf(context).height * 0.82;
    final draft = _captionInputCtrl.text.trim();
    final previewText = draft.isEmpty ? 'Digite a legenda…' : draft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _cancelCaptionSheet,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFBBF24),
                            side: const BorderSide(
                              color: Color(0xFFFBBF24),
                              width: 1.6,
                            ),
                            minimumSize: const Size(0, 48),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _confirmCaptionSheet,
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Confirmar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Preview ao vivo (como no print moderno).
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 110),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _captionPreviewStyledText(previewText, isHint: draft.isEmpty),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _captionInputCtrl,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Digite legenda…',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      setState(() {
                        _syncLiveCaptionFromDraft(createIfNeeded: true);
                      });
                    },
                    onSubmitted: (_) => _confirmCaptionSheet(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in sizePresets)
                        _modernPill(
                          label: s.$1,
                          selected: (_captionScale - s.$2).abs() < 0.05,
                          onTap: () => setState(() {
                            _captionScale = s.$2;
                            _syncLiveCaptionFromDraft(createIfNeeded: true);
                          }),
                        ),
                      _modernPill(
                        label: 'Negrito',
                        selected: _captionBold,
                        onTap: () => setState(() {
                          _captionBold = !_captionBold;
                          _syncLiveCaptionFromDraft(createIfNeeded: true);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Estilo / formato',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final style in styleOrder)
                        _modernPill(
                          label: style.label,
                          selected: _captionStyle == style,
                          onTap: () => setState(() {
                            _captionStyle = style;
                            if (style == UtilPhotoCaptionStyle.bold) {
                              _captionUseBox = true;
                              if (_captionBoxBg == 0) {
                                _captionBoxBg = 0xFFFFFFFF;
                              }
                            }
                            _syncLiveCaptionFromDraft(createIfNeeded: true);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cor da letra',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _colorDotsRow(textColors, _captionColor, (c) {
                    setState(() {
                      _captionColor = c;
                      _syncLiveCaptionFromDraft(createIfNeeded: true);
                    });
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'Fundo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _colorDotsRowWithNone(
                    colors: boxColors,
                    selected: _captionUseBox ? _captionBoxBg : 0,
                    noneSelected: !_captionUseBox,
                    onNone: () => setState(() {
                      _captionUseBox = false;
                      _syncLiveCaptionFromDraft(createIfNeeded: true);
                    }),
                    onPick: (c) => setState(() {
                      _captionBoxBg = c;
                      _captionUseBox = true;
                      _syncLiveCaptionFromDraft(createIfNeeded: true);
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Borda',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _colorDotsRowWithNone(
                    colors: borderColors,
                    selected: _captionUseBorder ? _captionBorder : 0,
                    noneSelected: !_captionUseBorder,
                    onNone: () => setState(() {
                      _captionUseBorder = false;
                      _syncLiveCaptionFromDraft(createIfNeeded: true);
                    }),
                    onPick: (c) => setState(() {
                      _captionBorder = c;
                      _captionUseBorder = true;
                      _syncLiveCaptionFromDraft(createIfNeeded: true);
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Emojis',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in emojis)
                        ActionChip(
                          label: Text(e, style: const TextStyle(fontSize: 20)),
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          onPressed: _busy
                              ? null
                              : () {
                                  final cur = _captionInputCtrl.text;
                                  _captionInputCtrl.text = '$cur$e';
                                  _captionInputCtrl.selection =
                                      TextSelection.collapsed(
                                    offset: _captionInputCtrl.text.length,
                                  );
                                  setState(() {
                                    _syncLiveCaptionFromDraft(
                                      createIfNeeded: true,
                                    );
                                  });
                                },
                        ),
                    ],
                  ),
                  if (_selectedCaptionId != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: _busy ? null : _removeSelectedCaption,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFF87171),
                      ),
                      label: const Text(
                        'Remover selecionado',
                        style: TextStyle(color: Color(0xFFF87171)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _captionPreviewStyledText(String text, {required bool isHint}) {
    final fontSize = (22.0 * _captionScale).clamp(14.0, 36.0);
    final weight = _captionBold ? FontWeight.w900 : FontWeight.w600;
    Color color = Color(_captionColor);
    if (isHint) color = color.withValues(alpha: 0.35);
    List<Shadow>? shadows;
    switch (_captionStyle) {
      case UtilPhotoCaptionStyle.clean:
        shadows = const [
          Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ];
      case UtilPhotoCaptionStyle.classic:
        shadows = const [
          Shadow(color: Colors.black, blurRadius: 0, offset: Offset(-1, -1)),
          Shadow(color: Colors.black, blurRadius: 0, offset: Offset(1, 1)),
        ];
      case UtilPhotoCaptionStyle.neon:
        shadows = [
          Shadow(color: color.withValues(alpha: 0.7), blurRadius: 10),
        ];
      case UtilPhotoCaptionStyle.bold:
        shadows = null;
    }
    final showBox = _captionUseBox || _captionStyle == UtilPhotoCaptionStyle.bold;
    return Container(
      padding: showBox || _captionUseBorder
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: _captionUseBox
            ? Color(_captionBoxBg)
            : (_captionStyle == UtilPhotoCaptionStyle.bold
                ? const Color(0xCC0F172A)
                : null),
        borderRadius: BorderRadius.circular(12),
        border: _captionUseBorder
            ? Border.all(color: Color(_captionBorder), width: 2.5)
            : null,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: _captionUseBox &&
                  _captionBoxBg == 0xFFFFFFFF &&
                  color.value == 0xFFFFFFFF
              ? const Color(0xFF0F172A)
              : color,
          shadows: shadows,
        ),
      ),
    );
  }

  Widget _modernPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? const Color(0xFF7C3AED)
          : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
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

  Widget _colorDotsRowWithNone({
    required List<int> colors,
    required int selected,
    required bool noneSelected,
    required VoidCallback onNone,
    required void Function(int) onPick,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: _busy ? null : onNone,
            child: Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: noneSelected
                      ? Colors.white
                      : Colors.white24,
                  width: noneSelected ? 3 : 1,
                ),
              ),
              child: const Icon(
                Icons.block,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
          for (final c in colors) ...[
            GestureDetector(
              onTap: _busy ? null : () => onPick(c),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: !noneSelected && selected == c
                        ? Colors.white
                        : Colors.white24,
                    width: !noneSelected && selected == c ? 3 : 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _colorDotsRow(
    List<int> colors,
    int selected,
    void Function(int) onPick,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in colors) ...[
            GestureDetector(
              onTap: _busy ? null : () => onPick(c),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected == c
                        ? const Color(0xFF22C55E)
                        : Colors.white24,
                    width: selected == c ? 3 : 1,
                  ),
                ),
              ),
            ),
          ],
        ],
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
                    icon: Icons.palette_rounded,
                    label: 'Cores',
                    accent: const Color(0xFF34D399),
                    onTap: _busy ? null : _applyColorEnhance,
                    expanded: !narrow,
                  ),
                  _dockTool(
                    icon: Icons.text_fields_rounded,
                    label: 'Texto',
                    accent: const Color(0xFFF59E0B),
                    selected: _tool == _PhotoTool.caption,
                    onTap: _busy ? null : _openCaptionTool,
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
    final canApply = !_busy && _regions.isNotEmpty;
    return Material(
      color: _immersiveBg,
      child: SafeArea(
        child: Column(
          children: [
            // Header compacto — mais espaço para a foto.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : _closeBlurWorkspace,
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    tooltip: 'Fechar',
                  ),
                  Expanded(
                    child: Text(
                      _tool == _PhotoTool.faces ? 'Borrar rostos' : 'Borrar áreas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: canApply ? _applyBlur : null,
                    child: Text(
                      'Confirmar',
                      style: TextStyle(
                        color: canApply
                            ? const Color(0xFF4ADE80)
                            : Colors.white38,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _tool == _PhotoTool.faces
                    ? 'Rostos destacados — confira e confirme.'
                    : 'Arraste na foto para marcar a área.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Foto o maior possível (painel baixo e discreto).
            Expanded(child: _buildPhotoCanvas(blurMode: true)),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220).withValues(alpha: 0.97),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Intensidade $radiusLabel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                          ),
                          child: Slider(
                            value: _blurIntensity,
                            min: 0.05,
                            max: 1.0,
                            activeColor: const Color(0xFFA78BFA),
                            inactiveColor: Colors.white.withValues(alpha: 0.12),
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _blurIntensity = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Pills discretas (estilo moderno).
                  Row(
                    children: [
                      for (final mode in UtilPhotoBlurMode.values) ...[
                        Expanded(
                          child: _blurModePill(
                            label: mode.label,
                            selected: _blurMode == mode,
                            onTap: _busy
                                ? null
                                : () => setState(() => _blurMode = mode),
                          ),
                        ),
                        if (mode != UtilPhotoBlurMode.values.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy || _selectedId == null
                              ? null
                              : () => setState(() {
                                    _regions.removeWhere(
                                      (r) => r.id == _selectedId,
                                    );
                                    _selectedId = null;
                                  }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white60,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Remover',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: canApply ? _applyBlur : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Ink(
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: canApply
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF16A34A),
                                          Color(0xFF22C55E),
                                        ],
                                      )
                                    : null,
                                color: canApply
                                    ? null
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: canApply
                                        ? Colors.white
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _regions.isEmpty
                                        ? 'Confirmar'
                                        : 'Confirmar (${_regions.length})',
                                    style: TextStyle(
                                      color: canApply
                                          ? Colors.white
                                          : Colors.white38,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blurModePill({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? const Color(0xFF7C3AED).withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA78BFA)
                  : Colors.white.withValues(alpha: 0.14),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
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
                'Realce cores, texto com caixa/borda/cor, corte, borre rostos ou monte colagens.',
                textAlign: TextAlign.center,
                style: ModernModuleUI.moduleSubtitleStyle(context),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _pickImage(),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text(
                    'Galeria',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _pickImage(camera: true),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text(
                    'Câmera',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _onCloseEditor,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: const Text(
                    'Cancelar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
        padding: EdgeInsets.all(blurMode ? 0 : 2),
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
            final canDragRegion = blurMode || _tool == _PhotoTool.crop;
            final captionMode =
                _tool == _PhotoTool.caption || _captions.isNotEmpty;
            return Center(
              child: InteractiveViewer(
                transformationController: _viewerCtrl,
                minScale: 0.7,
                maxScale: 5,
                // No modo texto o pan/zoom do viewer compete com o arraste da legenda.
                panEnabled: !captionMode && !canDragRegion,
                scaleEnabled: !captionMode && !canDragRegion,
                child: GestureDetector(
                  onPanStart: canDragRegion
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
                  onPanUpdate: canDragRegion
                      ? (d) {
                          final box = _canvasKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          setState(() {
                            _dragCurrent = box.globalToLocal(d.globalPosition);
                          });
                        }
                      : null,
                  onPanEnd: canDragRegion
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
                        if (_tool != _PhotoTool.crop && _captions.isNotEmpty)
                          ..._captions.map((c) => _captionOverlay(c, w, h)),
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

  Widget _captionOverlay(UtilPhotoCaptionOverlay c, double w, double h) {
    final selected = c.id == _selectedCaptionId;
    final fontSize = (w * 0.045 * c.scale).clamp(16.0, 42.0);
    final weight = c.bold ? FontWeight.w900 : FontWeight.w600;
    final color = Color(c.colorArgb);
    TextStyle style;
    switch (c.style) {
      case UtilPhotoCaptionStyle.clean:
        style = TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
          ],
        );
      case UtilPhotoCaptionStyle.bold:
        style = TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
        );
      case UtilPhotoCaptionStyle.neon:
        style = TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.85), blurRadius: 12),
          ],
        );
      case UtilPhotoCaptionStyle.classic:
        style = TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(-1, -1)),
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(1, 1)),
          ],
        );
    }
  final textPainter = TextPainter(
      text: TextSpan(text: c.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w * 0.9);
    final tw = textPainter.width;
    final th = textPainter.height;
    final left = (c.nx * w - tw / 2).clamp(0.0, w - tw);
    final top = (c.ny * h - th / 2).clamp(0.0, h - th);
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedCaptionId = c.id;
          _captionStyle = c.style;
          _captionColor = c.colorArgb;
          _captionScale = c.scale;
          _captionBold = c.bold;
          _captionUseBox = c.boxBgArgb != 0;
          _captionUseBorder = c.borderArgb != 0;
          if (c.boxBgArgb != 0) _captionBoxBg = c.boxBgArgb;
          if (c.borderArgb != 0) _captionBorder = c.borderArgb;
          _captionInputCtrl.text = c.text;
          _tool = _PhotoTool.caption;
          _captionSheetOpen = true;
        }),
        onPanUpdate: (d) {
          setState(() {
            final idx = _captions.indexWhere((x) => x.id == c.id);
            if (idx < 0) return;
            final nx = ((c.nx * w + d.delta.dx) / w).clamp(0.05, 0.95);
            final ny = ((c.ny * h + d.delta.dy) / h).clamp(0.05, 0.95);
            _captions[idx] = c.copyWith(nx: nx, ny: ny);
            _selectedCaptionId = c.id;
            _tool = _PhotoTool.caption;
          });
        },
        child: Container(
          padding: (c.boxBgArgb != 0 ||
                  c.borderArgb != 0 ||
                  c.style == UtilPhotoCaptionStyle.bold)
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: c.boxBgArgb != 0
                ? Color(c.boxBgArgb)
                : (c.style == UtilPhotoCaptionStyle.bold
                    ? Colors.black.withValues(alpha: 0.55)
                    : null),
            borderRadius: BorderRadius.circular(10),
            border: c.borderArgb != 0
                ? Border.all(color: Color(c.borderArgb), width: 2.5)
                : (selected
                    ? Border.all(color: const Color(0xFFF59E0B), width: 2)
                    : null),
          ),
          child: Text(c.text, style: style, textAlign: TextAlign.center),
        ),
      ),
    );
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

  Widget _gradientAction({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
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
            'Foto pronta',
            style: ModernModuleUI.moduleTitleStyle(context, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            editSteps > 0
                ? '$editSteps alteração(ões). Salve ou compartilhe.'
                : 'Salve no aparelho ou compartilhe agora.',
            textAlign: TextAlign.center,
            style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _gradientAction(
            icon: Icons.download_rounded,
            label: 'Salvar no aparelho',
            colors: const [Color(0xFF1D4ED8), Color(0xFF38BDF8)],
            onTap: onSave,
          ),
          const SizedBox(height: 10),
          _gradientAction(
            icon: Icons.share_rounded,
            label: 'Compartilhar',
            colors: const [Color(0xFF16A34A), Color(0xFF22C55E)],
            onTap: onShare,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_rounded, size: 18),
            label: const Text(
              'Pré-visualizar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: dark ? Colors.white70 : const Color(0xFF334155),
              side: BorderSide(
                color: dark
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFCBD5E1),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onFinish,
            child: const Text(
              'Concluir e voltar',
              style: TextStyle(fontWeight: FontWeight.w800),
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
