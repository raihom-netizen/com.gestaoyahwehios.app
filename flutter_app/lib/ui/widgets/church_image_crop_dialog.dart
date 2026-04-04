import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Cortar logo (quadrado) ou foto do gestor (círculo) antes do upload.
Future<Uint8List?> showChurchPhotoCropDialog(
  BuildContext context, {
  required Uint8List imageBytes,
  required String title,
  bool circleUi = false,
  double? aspectRatio,
}) {
  final cropController = CropController();
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 320,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                circleUi
                    ? 'Arraste e ajuste o zoom. Toque em Aplicar para centralizar o rosto.'
                    : 'Ajuste a área da logo. Toque em Aplicar quando estiver satisfeito.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Crop(
                    image: imageBytes,
                    controller: cropController,
                    withCircleUi: circleUi,
                    aspectRatio: circleUi ? 1 : aspectRatio,
                    interactive: true,
                    baseColor: Colors.grey.shade900,
                    maskColor: Colors.black.withValues(alpha: 0.45),
                    radius: circleUi ? 999 : 8,
                    onCropped: (result) {
                      if (result is CropSuccess) {
                        Navigator.of(ctx).pop(result.croppedImage);
                      } else if (result is CropFailure) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          ThemeCleanPremium.feedbackSnackBar('Não foi possível cortar a imagem.'),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (circleUi) {
                cropController.cropCircle();
              } else {
                cropController.crop();
              }
            },
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('Aplicar'),
          ),
        ],
      );
    },
  );
}
