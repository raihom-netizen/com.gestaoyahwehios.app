import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/services/utilitarios_photo_service.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_photo_edit_flow.dart';

/// Painel de colagem — prévia instantânea na UI; exportação em alta qualidade.
class UtilitariosPhotoCollagePanel extends StatefulWidget {
  const UtilitariosPhotoCollagePanel({
    super.key,
    required this.onBusyChanged,
    this.busy = false,
    this.onExitCollage,
  });

  final ValueChanged<({bool busy, String? label})> onBusyChanged;
  final bool busy;
  final VoidCallback? onExitCollage;

  @override
  State<UtilitariosPhotoCollagePanel> createState() =>
      _UtilitariosPhotoCollagePanelState();
}

class _UtilitariosPhotoCollagePanelState
    extends State<UtilitariosPhotoCollagePanel> {
  static const _gradients = <List<Color>>[
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
    [Color(0xFF059669), Color(0xFF34D399)],
    [Color(0xFFDB2777), Color(0xFFF472B6)],
    [Color(0xFFEA580C), Color(0xFFFBBF24)],
    [Color(0xFF2563EB), Color(0xFF60A5FA)],
    [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    [Color(0xFFBE123C), Color(0xFFF43F5E)],
    [Color(0xFF0F766E), Color(0xFF2DD4BF)],
    [Color(0xFF4F46E5), Color(0xFF818CF8)],
  ];

  final _picker = ImagePicker();
  UtilPhotoCollageTemplate _template =
      UtilitariosPhotoService.collageTemplates.first;
  final List<Uint8List> _photos = [];
  bool _darkBg = false;
  int _gap = 12;

  List<Color> _gradientFor(int index) =>
      _gradients[index % _gradients.length];

  Future<void> _withBusy(String label, Future<void> Function() fn) async {
    widget.onBusyChanged((busy: true, label: label));
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('StateError: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) widget.onBusyChanged((busy: false, label: null));
    }
  }

  Future<void> _pickPhotos({bool multi = true}) async {
    await _withBusy('Carregando fotos…', () async {
      if (multi) {
        final files = await utilitariosPickPlatformFiles(
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          allowMultiple: true,
        );
        if (files.isEmpty) return;
        for (final f in files) {
          if (_photos.length >= _template.slots) break;
          var bytes = await utilitariosReadPlatformFileBytes(f);
          if (bytes.isEmpty) continue;
          bytes = await UtilitariosPhotoService.preparePhotoForEditor(bytes);
          _photos.add(bytes);
        }
      } else if (!kIsWeb) {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
          maxWidth: 1920,
        );
        if (x == null) return;
        var bytes = await x.readAsBytes();
        if (bytes.isEmpty) return;
        bytes = await UtilitariosPhotoService.preparePhotoForEditor(bytes);
        if (_photos.length >= _template.slots) {
          _photos.removeLast();
        }
        _photos.add(bytes);
      }
      if (_photos.isEmpty) throw StateError('Nenhuma foto válida.');
      setState(() {});
    });
  }

  void _selectTemplate(UtilPhotoCollageTemplate t) {
    setState(() {
      _template = t;
      while (_photos.length > t.slots) {
        _photos.removeLast();
      }
    });
  }

  bool get _hasWork => _photos.isNotEmpty;

  void _clearPhotos() {
    _photos.clear();
    _template = UtilitariosPhotoService.collageTemplates.first;
    _darkBg = false;
    _gap = 12;
  }

  Future<bool> _confirmDiscard(String message) async {
    if (!_hasWork) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Descartar colagem?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onCancelCollage() async {
    if (widget.busy) return;
    if (!_hasWork) {
      widget.onExitCollage?.call();
      return;
    }
    if (!await _confirmDiscard(
      'Cancelar a colagem e limpar as fotos selecionadas?',
    )) {
      return;
    }
    if (!mounted) return;
    setState(_clearPhotos);
    widget.onExitCollage?.call();
  }

  Future<void> _onTrocarFotos() async {
    if (widget.busy) return;
    if (!await _confirmDiscard(
      'Trocar as fotos? A colagem atual será descartada.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(_clearPhotos);
    await _pickPhotos();
  }

  ButtonStyle _sessionOutlinedStyle() => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: const Color(0xFF7C3AED),
        side: BorderSide(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.38),
          width: 1.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _exportGradientButton({required bool ready}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.busy || !ready ? null : _export,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: ready
                  ? const [
                      Color(0xFF6366F1),
                      Color(0xFF8B5CF6),
                      Color(0xFFDB2777),
                    ]
                  : [Colors.grey.shade400, Colors.grey.shade500],
            ),
            boxShadow: ready
                ? [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: const SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Exportar colagem',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
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

  Future<void> _export() async {
    await _withBusy('Exportando colagem…', () async {
      if (_photos.length < _template.slots) {
        throw StateError(
          'Adicione ${_template.slots} foto(s) para este formato.',
        );
      }
      final bytes = await UtilitariosPhotoService.buildCollage(
        photos: _photos.take(_template.slots).toList(),
        template: _template,
        gap: _gap,
        darkBackground: _darkBg,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        UtilitariosPhotoEditResult(
          bytes: bytes,
          fileName: 'colagem_${_template.id}.jpg',
          message:
              'Colagem «${_template.label}» criada localmente no GestÃ£o Yahweh.',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = _photos.length >= _template.slots;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: ModernModuleUI.infoBanner(
            context: context,
            icon: Icons.grid_view_rounded,
            iconGradient: const [Color(0xFF6366F1), Color(0xFF06B6D4)],
            text: 'Formato · prévia instantânea · exporte quando pronto.',
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: UtilitariosPhotoService.collageTemplates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final t = UtilitariosPhotoService.collageTemplates[i];
              final sel = t.id == _template.id;
              final g = _gradientFor(i);
              return _layoutChip(
                template: t,
                gradient: g,
                selected: sel,
                dark: dark,
                onTap: widget.busy ? null : () => _selectTemplate(t),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: _optionChip(
                  icon: _darkBg ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  label: _darkBg ? 'Fundo escuro' : 'Fundo claro',
                  active: _darkBg,
                  colors: const [Color(0xFF1E293B), Color(0xFF475569)],
                  onTap: widget.busy
                      ? null
                      : () => setState(() => _darkBg = !_darkBg),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _optionChip(
                  icon: Icons.space_bar_rounded,
                  label: 'Espaço $_gap',
                  active: _gap > 8,
                  colors: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                  onTap: widget.busy
                      ? null
                      : () => setState(
                            () => _gap = _gap >= 20 ? 6 : _gap + 4,
                          ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InteractiveViewer(
              minScale: 0.75,
              maxScale: 3,
              child: Center(child: _liveCollagePreview(context, dark)),
            ),
          ),
        ),
        _photoSlotsRow(dark),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final stacked = c.maxWidth < 400;
                final cancelBtn = SizedBox(
                  width: stacked ? double.infinity : null,
                  child: OutlinedButton(
                    onPressed: widget.busy ? null : _onCancelCollage,
                    style: _sessionOutlinedStyle(),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
                final trocarBtn = SizedBox(
                  width: stacked ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: widget.busy || !_hasWork ? null : _onTrocarFotos,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text(
                      'Trocar fotos',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: _sessionOutlinedStyle(),
                  ),
                );
                final fotosBtn = SizedBox(
                  width: stacked ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: widget.busy ? null : () => _pickPhotos(),
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: Text('Fotos (${_photos.length}/${_template.slots})'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                );
                final exportBtn = _exportGradientButton(ready: ready);
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      exportBtn,
                      const SizedBox(height: 8),
                      fotosBtn,
                      const SizedBox(height: 8),
                      trocarBtn,
                      const SizedBox(height: 8),
                      cancelBtn,
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: cancelBtn),
                        const SizedBox(width: 8),
                        Expanded(child: trocarBtn),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: fotosBtn),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: exportBtn),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Prévia nativa Flutter — atualiza instantaneamente ao mudar formato/fundo/espaço.
  Widget _liveCollagePreview(BuildContext context, bool dark) {
    final bg = _darkBg ? const Color(0xFF121216) : Colors.white;
    final gapPx = _gap.toDouble();
    final accent = _gradientFor(
      UtilitariosPhotoService.collageTemplates
          .indexWhere((t) => t.id == _template.id)
          .clamp(0, 9),
    ).first;

    return AspectRatio(
      aspectRatio: _template.aspect.clamp(0.45, 2.2),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: dark ? 0.45 : 0.22),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            final half = gapPx / 2;
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < _template.cells.length; i++)
                  Positioned(
                    left: _template.cells[i].x * w + half,
                    top: _template.cells[i].y * h + half,
                    width: _template.cells[i].w * w - gapPx,
                    height: _template.cells[i].h * h - gapPx,
                    child: _collageCell(i, dark),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _collageCell(int index, bool dark) {
    final has = index < _photos.length;
    if (has) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _photos[index],
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 720,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: dark ? Colors.white38 : Colors.grey.shade400,
          size: 28,
        ),
      ),
    );
  }

  Widget _photoSlotsRow(bool dark) {
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _template.slots,
        itemBuilder: (context, i) {
          final has = i < _photos.length;
          final g = _gradientFor(i);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.busy
                    ? null
                    : () async {
                        if (has) {
                          setState(() => _photos.removeAt(i));
                        } else {
                          await _pickPhotos(multi: true);
                        }
                      },
                child: Container(
                  width: 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: has
                          ? g.first
                          : (dark
                              ? Colors.white24
                              : Colors.grey.shade300),
                      width: has ? 2.2 : 1,
                    ),
                    boxShadow: has
                        ? [
                            BoxShadow(
                              color: g.first.withValues(alpha: 0.28),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: has
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              _photos[i],
                              fit: BoxFit.cover,
                              cacheWidth: 140,
                            ),
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: dark
                                ? Colors.white38
                                : Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _layoutChip({
    required UtilPhotoCollageTemplate template,
    required List<Color> gradient,
    required bool selected,
    required bool dark,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 112,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected
                ? null
                : (dark
                    ? context.appDarkModuleSurface
                    : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.5)
                  : (dark
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFFE2E8F0)),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: gradient.last.withValues(alpha: 0.38),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _miniLayoutPreview(template, gradient, selected, dark),
              const SizedBox(height: 8),
              Text(
                template.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: selected
                      ? Colors.white
                      : context.appTextPrimary,
                ),
              ),
              Text(
                '${template.slots} fotos',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.92)
                      : context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniLayoutPreview(
    UtilPhotoCollageTemplate t,
    List<Color> gradient,
    bool selected,
    bool dark,
  ) {
    return AspectRatio(
      aspectRatio: t.aspect.clamp(0.45, 2.2),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.18)
              : (dark ? Colors.black26 : Colors.white),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            return Stack(
              children: [
                for (var i = 0; i < t.cells.length; i++)
                  Positioned(
                    left: t.cells[i].x * w + 1,
                    top: t.cells[i].y * h + 1,
                    width: t.cells[i].w * w - 2,
                    height: t.cells[i].h * h - 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradient),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _optionChip({
    required IconData icon,
    required String label,
    required bool active,
    required List<Color> colors,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            gradient: active ? LinearGradient(colors: colors) : null,
            color: active ? null : context.appInputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? Colors.transparent
                  : colors.first.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : colors.first,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : context.appTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
