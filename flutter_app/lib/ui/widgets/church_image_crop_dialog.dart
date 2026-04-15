import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Cortar logo (quadrado) ou foto do gestor (círculo) antes do upload.
///
/// Usa [Dialog] com barra de ações **dentro** do corpo (não só [AlertDialog.actions]),
/// para que **Cancelar / Aplicar** permaneçam visíveis na web (viewport e barra de endereço).
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
      final mq = MediaQuery.sizeOf(ctx);
      final maxH = (mq.height * 0.88).clamp(360.0, 720.0);
      final maxW = (mq.width - 32).clamp(280.0, 440.0);

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        // Altura explícita: [Expanded] no recorte + barra fixa (web não esconde botões).
        child: SizedBox(
          width: maxW,
          height: maxH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  circleUi
                      ? 'Arraste e ajuste o zoom. Use Aplicar para confirmar o recorte.'
                      : 'Ajuste a área. Use Aplicar para confirmar o recorte.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            ThemeCleanPremium.feedbackSnackBar(
                              'Não foi possível cortar a imagem.',
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
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
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
