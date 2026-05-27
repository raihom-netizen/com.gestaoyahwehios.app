import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Pré-visualização antes de enviar foto/vídeo (estilo WhatsApp).
Future<bool> showChurchChatMediaPreviewSheet(
  BuildContext context, {
  Uint8List? previewBytes,
  String? localPath,
  required String title,
  required bool isVideo,
}) async {
  assert(
    previewBytes != null ||
        (localPath != null && localPath.isNotEmpty) ||
        isVideo,
    'previewBytes, localPath ou isVideo',
  );
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      Widget preview;
      if (!kIsWeb &&
          localPath != null &&
          localPath.isNotEmpty &&
          File(localPath).existsSync() &&
          !isVideo) {
        preview = Image.file(
          File(localPath),
          height: 260,
          width: double.infinity,
          fit: BoxFit.cover,
        );
      } else if (previewBytes != null && previewBytes.isNotEmpty) {
        preview = Image.memory(
          previewBytes,
          height: isVideo ? 220 : 260,
          width: double.infinity,
          fit: BoxFit.contain,
        );
      } else {
        preview = Container(
          height: isVideo ? 220 : 260,
          width: double.infinity,
          color: Colors.grey.shade200,
          child: Icon(
            isVideo ? Icons.videocam_rounded : Icons.image_rounded,
            size: 64,
            color: Colors.grey.shade500,
          ),
        );
      }
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
                        preview,
                        Icon(
                          Icons.play_circle_fill_rounded,
                          size: 56,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ],
                    )
                  : preview,
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
