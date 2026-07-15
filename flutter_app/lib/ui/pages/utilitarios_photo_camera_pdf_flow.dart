import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/services/utilitarios_local_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';

/// Resultado do fluxo Foto/Câmera para PDF (fotos cruas prontas para montar PDF).
class UtilitariosPhotoCameraPdfResult {
  const UtilitariosPhotoCameraPdfResult({
    required this.pages,
    this.onePdfPerPage = false,
    this.pdfBytes,
  });

  final List<Uint8List> pages;
  final bool onePdfPerPage;
  /// PDF já montado no fluxo (compartilhar sem segunda espera).
  final Uint8List? pdfBytes;
}

/// Máximo de fotos neste fluxo (pedido do usuário).
const int kPhotoCameraPdfMaxPages = 20;

/// Lado máximo ao gravar fotos para o PDF (velocidade de montagem).
const int _kCameraPdfMaxSide = 1600;
const int _kCameraPdfJpegQuality = 82;

/// Foto/Câmera para PDF — câmera do aparelho, fotos leves, PDF no final.
Future<UtilitariosPhotoCameraPdfResult?> openUtilitariosPhotoCameraPdfFlow(
  BuildContext context,
) {
  return Navigator.of(context).push<UtilitariosPhotoCameraPdfResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _PhotoCameraPdfSimplePage(),
    ),
  );
}

const _kBrand = 'Foto/Câmera para PDF';
const _kAccent = Color(0xFF14B8A6);
const _kBg = Color(0xFF0B1220);

class _PhotoCameraPdfSimplePage extends StatefulWidget {
  const _PhotoCameraPdfSimplePage();

  @override
  State<_PhotoCameraPdfSimplePage> createState() =>
      _PhotoCameraPdfSimplePageState();
}

class _PhotoCameraPdfSimplePageState extends State<_PhotoCameraPdfSimplePage> {
  final _picker = ImagePicker();
  final _photos = <Uint8List>[];
  bool _busy = false;
  String? _busyLabel;

  int get _remaining => kPhotoCameraPdfMaxPages - _photos.length;
  bool get _atLimit => _photos.length >= kPhotoCameraPdfMaxPages;

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

  Future<Uint8List> _prepareForPdf(Uint8List raw) {
    return compute(_prepareCameraPdfImageIsolate, raw);
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_atLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Limite de $kPhotoCameraPdfMaxPages fotos alcançado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _withBusy(() async {
      if (source == ImageSource.camera) {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: _kCameraPdfJpegQuality,
          maxWidth: _kCameraPdfMaxSide.toDouble(),
        );
        if (x == null) return;
        final bytes = await x.readAsBytes();
        if (bytes.isEmpty) throw StateError('Foto vazia.');
        final prepared = await _prepareForPdf(bytes);
        if (!mounted) return;
        setState(() => _photos.add(prepared));
        return;
      }

      // Galeria: uma ou várias (até o restante do limite).
      if (kIsWeb) {
        final x = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: _kCameraPdfJpegQuality,
          maxWidth: _kCameraPdfMaxSide.toDouble(),
        );
        if (x == null) return;
        final bytes = await x.readAsBytes();
        if (bytes.isEmpty) throw StateError('Imagem vazia.');
        final prepared = await _prepareForPdf(bytes);
        if (!mounted) return;
        setState(() => _photos.add(prepared));
        return;
      }

      final files = await utilitariosPickPlatformFiles(
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        preferBytes: true,
        allowMultiple: true,
      );
      if (files.isEmpty) return;
      final added = <Uint8List>[];
      for (final f in files) {
        if (_photos.length + added.length >= kPhotoCameraPdfMaxPages) break;
        final bytes = await utilitariosReadPlatformFileBytes(f);
        if (bytes.isEmpty) continue;
        added.add(await _prepareForPdf(bytes));
      }
      if (added.isEmpty) throw StateError('Nenhuma imagem válida.');
      if (!mounted) return;
      setState(() => _photos.addAll(added));
    }, label: 'Preparando foto…');
  }

  void _removeAt(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _finishPdf() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tire ou adicione ao menos uma foto.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _withBusy(() async {
      // PDF montado aqui — tela Utilitários só compartilha (sem segunda espera).
      final pdf = await UtilitariosLocalService.imagesToPdf(
        List<Uint8List>.from(_photos),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        UtilitariosPhotoCameraPdfResult(
          pages: List<Uint8List>.from(_photos),
          pdfBytes: pdf,
        ),
      );
    }, label: 'Gerando PDF…');
  }

  Future<bool> _confirmDiscard() async {
    if (_photos.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar fotos?'),
        content: Text(
          'Você tem ${_photos.length} foto(s). Deseja sair e descartar?',
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
        if (await _confirmDiscard() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: _kBg,
            appBar: AppBar(
              backgroundColor: _kBg,
              foregroundColor: Colors.white,
              title: const Text(_kBrand, style: TextStyle(fontSize: 17)),
              leading: IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  if (await _confirmDiscard() && mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      _photos.isEmpty
                          ? 'Tire fotos com a câmera do aparelho (máx. $kPhotoCameraPdfMaxPages). Depois monte o PDF.'
                          : '${_photos.length}/$kPhotoCameraPdfMaxPages foto(s) · restam $_remaining',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _photos.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.photo_camera_outlined,
                                  size: 64,
                                  color: _kAccent.withValues(alpha: 0.7),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhuma foto ainda',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemCount: _photos.length,
                            itemBuilder: (context, i) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      _photos[i],
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(40, 40),
                                      ),
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed:
                                          _busy ? null : () => _removeAt(i),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: _kAccent,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: (_busy || _atLimit)
                                    ? null
                                    : () => _addPhoto(ImageSource.camera),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kAccent,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(48, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.photo_camera),
                                label: const Text('Tirar foto'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (_busy || _atLimit)
                                    ? null
                                    : () => _addPhoto(ImageSource.gallery),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                  minimumSize: const Size(48, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Galeria'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _busy || _photos.isEmpty ? null : _finishPdf,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white12,
                              minimumSize: const Size(48, 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: Text(
                              _photos.isEmpty
                                  ? 'Montar PDF'
                                  : 'Montar PDF (${_photos.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
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
                              color: Colors.redAccent.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
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
              color: Colors.black54,
              child: Center(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _busyLabel!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aguarde a conclusão — não feche o app.',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.55),
                            fontSize: 12,
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
    );
  }
}

/// Reduz e orienta a foto ao adicionar — montar PDF fica quase instantâneo.
Uint8List _prepareCameraPdfImageIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  var work = img.bakeOrientation(decoded);
  final maxDim = work.width > work.height ? work.width : work.height;
  if (maxDim > _kCameraPdfMaxSide) {
    work = img.copyResize(
      work,
      width: work.width >= work.height ? _kCameraPdfMaxSide : null,
      height: work.height > work.width ? _kCameraPdfMaxSide : null,
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(work, quality: _kCameraPdfJpegQuality),
  );
}
