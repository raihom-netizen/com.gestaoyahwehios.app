import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Pré-visualização antes de enviar foto/vídeo (estilo WhatsApp).
Future<bool> showChurchChatMediaPreviewSheet(
  BuildContext context, {
  required Uint8List previewBytes,
  required String title,
  required bool isVideo,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Container(
        decoration: BoxDecoration(
          color: ThemeCleanPremium.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: isVideo
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          previewBytes,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        Icon(
                          Icons.play_circle_fill_rounded,
                          size: 56,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ],
                    )
                  : Image.memory(
                      previewBytes,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Enviar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return ok == true;
}
