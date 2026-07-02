import 'dart:async';

import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/feed_photo_bottom_actions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

class _RatioOption {
  const _RatioOption({required this.label, this.ratio});
  final String label;
  final double? ratio;
}

/// Recorte para fotos do feed (eventos / avisos): proporções em faixa tipo iOS e **Cancelar / Confirmar** na base (mobile e web).
class PremiumFeedImageCropScreen extends StatefulWidget {
  const PremiumFeedImageCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<PremiumFeedImageCropScreen> createState() =>
      _PremiumFeedImageCropScreenState();
}

class _PremiumFeedImageCropScreenState extends State<PremiumFeedImageCropScreen> {
  static const _ratios = <_RatioOption>[
    _RatioOption(label: 'Toda imagem', ratio: null),
    _RatioOption(label: '16×9', ratio: 16 / 9),
    _RatioOption(label: '4×3', ratio: 4 / 3),
    _RatioOption(label: '3×2', ratio: 3 / 2),
    _RatioOption(label: 'Quadrada', ratio: 1),
  ];

  late Uint8List _bytes;
  final _cropController = CropController();
  int _selectedRatioIndex = 0;

  @override
  void initState() {
    super.initState();
    _bytes = widget.imageBytes;
    unawaited(_preparePreviewBytes());
  }

  Future<void> _preparePreviewBytes() async {
    if (_bytes.isEmpty) return;
    try {
      final lite = await MediaService.compressImageBytes(
        _bytes,
        profile: MediaImageProfile.feed,
      );
      if (!mounted || lite.isEmpty || lite.length >= _bytes.length) return;
      setState(() {
        _bytes = lite;
        _cropController.image = lite;
      });
    } catch (_) {}
  }

  void _selectRatio(int index) {
    setState(() => _selectedRatioIndex = index);
  }

  void _rotate90() {
    final decoded = img.decodeImage(_bytes);
    if (decoded == null) return;
    final rotated = img.copyRotate(decoded, angle: 90);
    final edge = 1600;
    final resized = img.copyResize(
      rotated,
      width: rotated.width > rotated.height ? edge : null,
      height: rotated.height >= rotated.width ? edge : null,
    );
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    setState(() => _bytes = out);
    _cropController.image = out;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final primary = ThemeCleanPremium.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad + 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Ajustar enquadramento',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.35,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'Por defeito usa a foto inteira — arraste ou escolha outra proporção.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Crop(
                  image: _bytes,
                  controller: _cropController,
                  aspectRatio: _ratios[_selectedRatioIndex].ratio,
                  /// Modo livre: área inicial = imagem completa (antes ficava uma janela ao centro).
                  initialRectBuilder:
                      _ratios[_selectedRatioIndex].ratio == null
                          ? InitialRectBuilder.withBuilder(
                              (viewportRect, imageRect) => imageRect,
                            )
                          : null,
                  interactive: true,
                  baseColor: const Color(0xFF0A0A0A),
                  maskColor: Colors.black.withValues(alpha: 0.52),
                  radius: 4,
                  onCropped: (result) async {
                    if (result is CropSuccess) {
                      var out = result.croppedImage;
                      try {
                        out = await MediaService.compressImageBytes(
                          out,
                          profile: MediaImageProfile.feed,
                        );
                      } catch (_) {}
                      if (!context.mounted) return;
                      Navigator.of(context).pop(out);
                    } else if (result is CropFailure) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        ThemeCleanPremium.feedbackSnackBar(
                          'Não foi possível aplicar o recorte.',
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.97),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: _ratios.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final sel = i == _selectedRatioIndex;
                        return CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          color: sel
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          onPressed: () => _selectRatio(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _ratios[i].label,
                                style: TextStyle(
                                  color: sel
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.55),
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      sel ? primary : Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              FeedPhotoBottomActions(
                onCancel: () => Navigator.of(context).pop(null),
                onConfirm: () => _cropController.crop(),
                center: IconButton(
                  onPressed: _rotate90,
                  tooltip: 'Girar 90°',
                  icon: Icon(
                    Icons.rotate_90_degrees_ccw_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
