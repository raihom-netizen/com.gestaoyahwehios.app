import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/services/utilitarios_local_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';

/// Resultado do fluxo Scanner de Documentos (páginas processadas + PDF montado).
class UtilitariosDocumentScannerResult {
  const UtilitariosDocumentScannerResult({
    required this.pages,
    this.pdfBytes,
  });

  final List<Uint8List> pages;
  final Uint8List? pdfBytes;
}

/// Máximo de páginas por escaneamento.
const int kDocScannerMaxPages = 30;

/// Captura leve — qualidade boa sem travar o isolate de bordas.
const int _kScanCaptureMaxSide = 1600;
const int _kScanCaptureJpegQuality = 88;

/// Scanner de Documentos — cor original, recorte auto/manual, PDF rápido.
Future<UtilitariosDocumentScannerResult?> openUtilitariosDocumentScannerFlow(
  BuildContext context,
) {
  return Navigator.of(context).push<UtilitariosDocumentScannerResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _DocumentScannerPage(),
    ),
  );
}

// Visual moderno: fundo escuro + gradientes vivos.
const _kBrand = 'Scanner de Documentos';
const _kAccent = Color(0xFF2DD4BF);
const _kAccentSoft = Color(0xFF5EEAD4);
const _kAccent2 = Color(0xFF38BDF8);
const _kBg = Color(0xFF070B12);
const _kSurface = Color(0xFF121826);
const _kSurface2 = Color(0xFF1A2333);

const _kGradTeal = [Color(0xFF14B8A6), Color(0xFF0EA5E9)];
const _kGradViolet = [Color(0xFF8B5CF6), Color(0xFFEC4899)];
const _kGradOrange = [Color(0xFFF59E0B), Color(0xFFEF4444)];

/// Única opção: cor original (sem filtros pesados).
enum _ScanMode {
  original('Original', 'Cor natural da foto');

  final String label;
  final String description;
  const _ScanMode(this.label, this.description);

  String get engineKey => UtilitariosLocalService.scanModeOriginal;
}

/// Página escaneada — [original] é a foto de trabalho (borda detectada em nx..nh).
class _ScannedPage {
  final Uint8List original;
  final Uint8List preview;
  final _ScanMode mode;
  final double nx, ny, nw, nh;

  const _ScannedPage({
    required this.original,
    required this.preview,
    required this.mode,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });

  _ScannedPage copyWith({
    Uint8List? original,
    Uint8List? preview,
    _ScanMode? mode,
    double? nx,
    double? ny,
    double? nw,
    double? nh,
  }) {
    return _ScannedPage(
      original: original ?? this.original,
      preview: preview ?? this.preview,
      mode: mode ?? this.mode,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      nw: nw ?? this.nw,
      nh: nh ?? this.nh,
    );
  }
}

class _DocumentScannerPage extends StatefulWidget {
  const _DocumentScannerPage();

  @override
  State<_DocumentScannerPage> createState() => _DocumentScannerPageState();
}

class _DocumentScannerPageState extends State<_DocumentScannerPage> {
  final _picker = ImagePicker();
  final List<_ScannedPage> _pages = [];
  bool _busy = false;
  String? _busyLabel;
  static const _ScanMode _currentMode = _ScanMode.original;

  bool get _atLimit => _pages.length >= kDocScannerMaxPages;

  Future<void> _withBusy(
    Future<void> Function() fn, {
    String label = '',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label.isEmpty ? null : label;
    });
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e
                .toString()
                .replaceFirst('StateError: ', '')
                .replaceFirst('Bad state: ', ''),
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

  Future<void> _capturePage(ImageSource source) async {
    if (_atLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Limite de $kDocScannerMaxPages páginas alcançado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _withBusy(() async {
      Uint8List? rawBytes;
      if (source == ImageSource.camera) {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: _kScanCaptureJpegQuality,
          maxWidth: _kScanCaptureMaxSide.toDouble(),
        );
        if (x == null) return;
        rawBytes = await x.readAsBytes();
      } else if (kIsWeb) {
        final x = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: _kScanCaptureJpegQuality,
          maxWidth: _kScanCaptureMaxSide.toDouble(),
        );
        if (x == null) return;
        rawBytes = await x.readAsBytes();
      } else {
        final files = await utilitariosPickPlatformFiles(
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          preferBytes: true,
          allowMultiple: true,
        );
        if (files.isEmpty) return;
        for (final f in files) {
          if (_pages.length >= kDocScannerMaxPages) break;
          final bytes = await utilitariosReadPlatformFileBytes(f);
          if (bytes.isEmpty) continue;
          await _processAndAddPage(bytes);
          if (!mounted) return;
        }
        return;
      }
      if (rawBytes.isEmpty) {
        throw StateError('Imagem vazia.');
      }
      await _processAndAddPage(rawBytes);
    }, label: 'Preparando página…');
  }

  /// 1 único isolate: prepare + auto-crop + enhance preview.
  Future<void> _processAndAddPage(Uint8List raw) async {
    final result = await UtilitariosLocalService.prepareScanCapture(
      raw,
      mode: _currentMode.engineKey,
    );
    if (!mounted) return;
    setState(() => _pages.add(_ScannedPage(
          original: result.original,
          preview: result.preview,
          mode: _currentMode,
          nx: result.nx,
          ny: result.ny,
          nw: result.nw,
          nh: result.nh,
        )));
  }

  void _removeAt(int index) {
    setState(() => _pages.removeAt(index));
  }

  Future<void> _openEditor(int index) async {
    if (index < 0 || index >= _pages.length || _busy) return;
    final updated = await Navigator.of(context).push<_ScannedPage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScanPageEditor(
          page: _pages[index],
          pageIndex: index,
          pageCount: _pages.length,
          onRetake: () async {
            Navigator.of(context).pop();
            _removeAt(index);
            await _capturePage(ImageSource.camera);
          },
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() => _pages[index] = updated);
  }

  Future<void> _finishPdf() async {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escaneie ao menos uma página.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _withBusy(() async {
      final exportPages = <Uint8List>[];
      for (var i = 0; i < _pages.length; i++) {
        if (mounted) {
          setState(() => _busyLabel = 'Gerando PDF… ${i + 1}/${_pages.length}');
        }
        final page = _pages[i];
        // Aplica o recorte detectado/ajustado (antes era 0,0,1,1 — bug).
        final exported = await UtilitariosLocalService.buildScanExport(
          page.original,
          nx: page.nx,
          ny: page.ny,
          nw: page.nw,
          nh: page.nh,
          mode: UtilitariosLocalService.scanModeOriginal,
        );
        exportPages.add(exported);
        if (!mounted) return;
      }

      final pdf = await UtilitariosLocalService.imagesToPdf(exportPages);
      if (!mounted) return;
      Navigator.of(context).pop(
        UtilitariosDocumentScannerResult(
          pages: exportPages,
          pdfBytes: pdf,
        ),
      );
    }, label: 'Gerando PDF…');
  }

  Future<bool> _confirmDiscard() async {
    if (_pages.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text('Descartar escaneamento?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Você tem ${_pages.length} página(s). Deseja sair e descartar?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          nav.pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: _kBg,
            body: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildBody()),
                  _buildBottomBar(),
                ],
              ),
            ),
          ),
          if (_busy && _busyLabel != null) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Fechar',
            onPressed: () async {
              if (await _confirmDiscard() && mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          const Expanded(
            child: Text(
              _kBrand,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: _kGradTeal),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: _kAccent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Text(
              'Original',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: _kGradTeal,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _kAccent2.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  size: 46,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Digitalizar documento',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cor original · recorte automático ou manual · PDF rápido.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text(
                '${_pages.length}/$kDocScannerMaxPages página(s)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Toque para editar',
                style: TextStyle(
                  color: _kAccentSoft.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
              childAspectRatio: 0.78,
            ),
            itemCount: _pages.length,
            itemBuilder: (context, i) {
              final page = _pages[i];
              return Material(
                color: _kSurface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _busy ? null : () => _openEditor(i),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        page.preview,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: _kGradTeal,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Original',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: _busy ? null : () => _removeAt(i),
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(Icons.delete_outline,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Modificar',
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

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Digitalizar',
            style: TextStyle(
              color: _kAccentSoft.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _roundAction(
                icon: Icons.photo_library_rounded,
                label: 'Galeria',
                colors: _kGradViolet,
                onTap: (_busy || _atLimit)
                    ? null
                    : () => _capturePage(ImageSource.gallery),
              ),
              const Spacer(),
              GestureDetector(
                onTap: (_busy || _atLimit)
                    ? null
                    : () => _capturePage(ImageSource.camera),
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: _kGradTeal),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: (_busy || _atLimit)
                          ? Colors.white24
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: (_busy || _atLimit)
                          ? Colors.white38
                          : const Color(0xFF0F766E),
                      size: 28,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _roundAction(
                icon: Icons.check_rounded,
                label: _pages.isEmpty ? 'Concluir' : 'PDF (${_pages.length})',
                colors: _kGradOrange,
                onTap: _busy || _pages.isEmpty ? null : _finishPdf,
              ),
            ],
          ),
          if (_pages.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirmDiscard() && mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: Text(
                'Descartar',
                style: TextStyle(
                  color: Colors.redAccent.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required List<Color> colors,
  }) {
    final enabled = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: enabled
                    ? LinearGradient(colors: colors)
                    : null,
                color: enabled ? null : Colors.white12,
                borderRadius: BorderRadius.circular(16),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: colors.first.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white70 : Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildBusyOverlay() {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Material(
          color: _kSurface2,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _kAccent,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _busyLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Aguarde — processamento local e rápido.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor de página (filtros + girar + cortar) — estilo CamScanner
// ─────────────────────────────────────────────────────────────────────────────

class _ScanPageEditor extends StatefulWidget {
  const _ScanPageEditor({
    required this.page,
    required this.pageIndex,
    required this.pageCount,
    required this.onRetake,
  });

  final _ScannedPage page;
  final int pageIndex;
  final int pageCount;
  final VoidCallback onRetake;

  @override
  State<_ScanPageEditor> createState() => _ScanPageEditorState();
}

class _ScanPageEditorState extends State<_ScanPageEditor> {
  late _ScannedPage _page;
  bool _busy = false;
  String? _busyLabel;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
  }

  Future<void> _withBusy(String label, Future<void> Function() fn) async {
    if (_busy) return;
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
            e
                .toString()
                .replaceFirst('StateError: ', '')
                .replaceFirst('Bad state: ', ''),
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

  Future<void> _rotateLeft() async {
    await _withBusy('Girando…', () async {
      final r = await UtilitariosLocalService.rotateScanCapture(
        _page.original,
        nx: _page.nx,
        ny: _page.ny,
        nw: _page.nw,
        nh: _page.nh,
        mode: UtilitariosLocalService.scanModeOriginal,
        quarterTurns: -1,
      );
      if (!mounted) return;
      setState(() => _page = _ScannedPage(
            original: r.original,
            preview: r.preview,
            mode: _ScanMode.original,
            nx: r.nx,
            ny: r.ny,
            nw: r.nw,
            nh: r.nh,
          ));
    });
  }

  Future<void> _openCrop() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recorte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Escolha automático ou ajuste manual das bordas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                _cropChoiceTile(
                  ctx,
                  value: 'auto',
                  title: 'Automático',
                  subtitle: 'Detecta as bordas do documento na hora',
                  icon: Icons.auto_fix_high_rounded,
                  colors: _kGradTeal,
                ),
                const SizedBox(height: 10),
                _cropChoiceTile(
                  ctx,
                  value: 'manual',
                  title: 'Manual',
                  subtitle: 'Arraste os cantos e ajuste o enquadramento',
                  icon: Icons.crop_free_rounded,
                  colors: _kGradViolet,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;

    if (choice == 'auto') {
      await _withBusy('Recorte automático…', () async {
        final r = await UtilitariosLocalService.detectScanCropRect(
          _page.original,
        );
        final preview = await UtilitariosLocalService.rebuildScanPreview(
          _page.original,
          nx: r.nx,
          ny: r.ny,
          nw: r.nw,
          nh: r.nh,
          mode: UtilitariosLocalService.scanModeOriginal,
        );
        if (!mounted) return;
        setState(() => _page = _page.copyWith(
              preview: preview,
              mode: _ScanMode.original,
              nx: r.nx,
              ny: r.ny,
              nw: r.nw,
              nh: r.nh,
            ));
      });
      return;
    }

    final cropped = await Navigator.of(context).push<_ScannedPage>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ScanCropEditor(page: _page),
      ),
    );
    if (!mounted || cropped == null) return;
    setState(() => _page = cropped.copyWith(mode: _ScanMode.original));
  }

  Widget _cropChoiceTile(
    BuildContext ctx, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(ctx, value),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
            gradient: LinearGradient(
              colors: [
                colors.first.withValues(alpha: 0.22),
                colors.last.withValues(alpha: 0.10),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _kBg,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          'Página ${widget.pageIndex + 1}/${widget.pageCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(context, _page),
                        child: const Text(
                          'OK',
                          style: TextStyle(
                            color: _kAccentSoft,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ColoredBox(
                        color: _kSurface,
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Center(
                            child: Image.memory(
                              _page.preview,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _kAccent.withValues(alpha: 0.18),
                          _kAccent2.withValues(alpha: 0.12),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.palette_outlined,
                            color: _kAccentSoft, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cor original — sem filtros (mais rápido)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(22)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _toolBtn(
                        Icons.camera_alt_rounded,
                        'Retomar',
                        _busy ? null : widget.onRetake,
                        colors: _kGradOrange,
                      ),
                      _toolBtn(
                        Icons.rotate_left_rounded,
                        'Girar',
                        _busy ? null : _rotateLeft,
                        colors: _kGradViolet,
                      ),
                      _toolBtn(
                        Icons.crop_rounded,
                        'Cortar',
                        _busy ? null : _openCrop,
                        colors: _kGradTeal,
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _busy
                              ? null
                              : () => Navigator.pop(context, _page),
                          child: Ink(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient:
                                  const LinearGradient(colors: _kGradTeal),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: _kAccent.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.check, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_busy && _busyLabel != null)
          ColoredBox(
            color: Colors.black45,
            child: Center(
              child: Material(
                color: _kSurface2,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _kAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _busyLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolBtn(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    required List<Color> colors,
  }) {
    final enabled = onTap != null;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: enabled
                      ? LinearGradient(colors: colors)
                      : null,
                  color: enabled ? null : Colors.white12,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: colors.first.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Icon(icon,
                    color: enabled ? Colors.white : Colors.white30, size: 22),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white30,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor de recorte com alças nos cantos + auto-borda
// ─────────────────────────────────────────────────────────────────────────────

class _ScanCropEditor extends StatefulWidget {
  const _ScanCropEditor({required this.page});
  final _ScannedPage page;

  @override
  State<_ScanCropEditor> createState() => _ScanCropEditorState();
}

class _ScanCropEditorState extends State<_ScanCropEditor> {
  late double _nx, _ny, _nw, _nh;
  bool _busy = false;
  double _aspect = 3 / 4;

  @override
  void initState() {
    super.initState();
    _nx = widget.page.nx;
    _ny = widget.page.ny;
    _nw = widget.page.nw;
    _nh = widget.page.nh;
    _loadAspect();
  }

  Future<void> _loadAspect() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.page.original);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      if (!mounted || w <= 0 || h <= 0) return;
      setState(() => _aspect = w / h);
    } catch (_) {
      // Mantém aspect padrão.
    }
  }

  Future<void> _autoDetect() async {
    setState(() => _busy = true);
    try {
      final r = await UtilitariosLocalService.detectScanCropRect(
        widget.page.original,
      );
      if (!mounted) return;
      setState(() {
        _nx = r.nx;
        _ny = r.ny;
        _nw = r.nw;
        _nh = r.nh;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final preview = await UtilitariosLocalService.rebuildScanPreview(
        widget.page.original,
        nx: _nx,
        ny: _ny,
        nw: _nw,
        nh: _nh,
        mode: UtilitariosLocalService.scanModeOriginal,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        widget.page.copyWith(
          preview: preview,
          mode: _ScanMode.original,
          nx: _nx,
          ny: _ny,
          nw: _nw,
          nh: _nh,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _onCornerDragNorm(int corner, double dx, double dy) {
    var l = _nx;
    var t = _ny;
    var r = _nx + _nw;
    var b = _ny + _nh;
    const minSize = 0.12;
    switch (corner) {
      case 0: // TL
        l = (l + dx).clamp(0.0, r - minSize);
        t = (t + dy).clamp(0.0, b - minSize);
        break;
      case 1: // TR
        r = (r + dx).clamp(l + minSize, 1.0);
        t = (t + dy).clamp(0.0, b - minSize);
        break;
      case 2: // BR
        r = (r + dx).clamp(l + minSize, 1.0);
        b = (b + dy).clamp(t + minSize, 1.0);
        break;
      case 3: // BL
        l = (l + dx).clamp(0.0, r - minSize);
        b = (b + dy).clamp(t + minSize, 1.0);
        break;
    }
    setState(() {
      _nx = l;
      _ny = t;
      _nw = r - l;
      _nh = b - t;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Recorte manual',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _busy ? null : _autoDetect,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient:
                              const LinearGradient(colors: _kGradTeal),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_fix_high_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Auto',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Arraste os cantos coloridos · toque em Auto para detectar de novo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _aspect,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final view = Size(c.maxWidth, c.maxHeight);
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    widget.page.original,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                  ),
                                  CustomPaint(
                                    painter: _CropOverlayPainter(
                                      nx: _nx,
                                      ny: _ny,
                                      nw: _nw,
                                      nh: _nh,
                                    ),
                                  ),
                                  ...List.generate(4, (corner) {
                                    final left = corner == 0 || corner == 3;
                                    final top = corner == 0 || corner == 1;
                                    final handleColors = switch (corner) {
                                      0 => _kGradTeal,
                                      1 => _kGradViolet,
                                      2 => _kGradOrange,
                                      _ => const [
                                          Color(0xFF38BDF8),
                                          Color(0xFF22D3EE),
                                        ],
                                    };
                                    return Positioned(
                                      left: left
                                          ? _nx * view.width - 20
                                          : (_nx + _nw) * view.width - 20,
                                      top: top
                                          ? _ny * view.height - 20
                                          : (_ny + _nh) * view.height - 20,
                                      child: GestureDetector(
                                        onPanUpdate: (d) {
                                          final dx = d.delta.dx / view.width;
                                          final dy = d.delta.dy / view.height;
                                          _onCornerDragNorm(corner, dx, dy);
                                        },
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: handleColors,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: handleColors.first
                                                    .withValues(alpha: 0.55),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _busy ? null : _apply,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: _kGradTeal),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _kAccent.withValues(alpha: 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded,
                                      color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Aplicar recorte',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });

  final double nx, ny, nw, nh;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      nx * size.width,
      ny * size.height,
      nw * size.width,
      nh * size.height,
    );
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);

    final border = Paint()
      ..color = _kAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(rect, border);

    // Grade 3x3
    final grid = Paint()
      ..color = _kAccent.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) =>
      old.nx != nx || old.ny != ny || old.nw != nw || old.nh != nh;
}
