import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/feed_photo_bottom_actions.dart';

/// iOS avisos/eventos — confirmação **sem** [ImageCropper] nativo (crash TestFlight).
/// **Cancelar / Confirmar** sempre na barra inferior (igual web/Android Flutter).
class IosFeedPhotoConfirmScreen extends StatelessWidget {
  const IosFeedPhotoConfirmScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    final previewW = (kEventoAvisoFeedMemCacheMaxPx * 2).clamp(640, 1200);

    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad + 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Confirmar foto',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: file.existsSync()
                    ? ClipRRect(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          cacheWidth: previewW,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                      )
                    : const Text(
                        'Não foi possível abrir a imagem.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
          FeedPhotoBottomActions(
            onCancel: () => Navigator.of(context).pop<String?>(null),
            onConfirm: () => Navigator.of(context).pop(imagePath),
          ),
        ],
      ),
    );
  }
}
