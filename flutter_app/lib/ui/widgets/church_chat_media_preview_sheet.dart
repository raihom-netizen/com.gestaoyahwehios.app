import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:image_picker/image_picker.dart';

/// Item de pré-visualização (foto/vídeo) antes do envio.
class ChurchChatMediaPreviewItem {
  const ChurchChatMediaPreviewItem({
    this.previewBytes,
    this.localPath,
    this.isVideo = false,
    this.label,
  });

  final Uint8List? previewBytes;
  final String? localPath;
  final bool isVideo;
  final String? label;
}

/// Pré-visualização antes de enviar — estilo galeria (maior, fundo escuro, grelha).
Future<bool> showChurchChatMediaPreviewSheet(
  BuildContext context, {
  Uint8List? previewBytes,
  String? localPath,
  required String title,
  required bool isVideo,
}) {
  return showChurchChatMediaGalleryPreviewSheet(
    context,
    title: title,
    items: [
      ChurchChatMediaPreviewItem(
        previewBytes: previewBytes,
        localPath: localPath,
        isVideo: isVideo,
      ),
    ],
  );
}

/// Galeria moderna: 1 foto em destaque ou grelha (até [kChatMaxImagesPerPick]).
Future<bool> showChurchChatMediaGalleryPreviewSheet(
  BuildContext context, {
  required String title,
  required List<ChurchChatMediaPreviewItem> items,
}) async {
  if (items.isEmpty) return false;
  final capped = items.take(kChatMaxImagesPerPick).toList();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      final heroH = (size.height * 0.52).clamp(280.0, 520.0);
      return Container(
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        decoration: const BoxDecoration(
          color: Color(0xFF0F1115),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(12, 10, 12, 14 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              capped.length > 1
                  ? '$title (${capped.length})'
                  : title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: capped.length == 1
                  ? _GalleryHero(
                      item: capped.first,
                      height: heroH,
                    )
                  : _GalleryGrid(items: capped, maxHeight: heroH),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      capped.length > 1
                          ? 'Enviar ${capped.length}'
                          : 'Enviar',
                    ),
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

/// Pré-visualiza e confirma um lote de [XFile] (galeria multi-foto).
Future<List<XFile>?> confirmChatImageBatchPreview(
  BuildContext context,
  List<XFile> files,
) async {
  if (files.isEmpty) return null;
  final capped = files.take(kChatMaxImagesPerPick).toList();
  final items = <ChurchChatMediaPreviewItem>[];
  for (final x in capped) {
    Uint8List? bytes;
    if (kIsWeb) {
      try {
        bytes = await x.readAsBytes();
      } catch (_) {}
    }
    items.add(
      ChurchChatMediaPreviewItem(
        localPath: !kIsWeb && (x.path).trim().isNotEmpty ? x.path : null,
        previewBytes: bytes,
        label: x.name,
      ),
    );
  }
  final ok = await showChurchChatMediaGalleryPreviewSheet(
    context,
    title: capped.length > 1 ? 'Enviar fotos' : 'Enviar foto',
    items: items,
  );
  if (!ok) return null;
  return capped;
}

class _GalleryHero extends StatelessWidget {
  const _GalleryHero({required this.item, required this.height});

  final ChurchChatMediaPreviewItem item;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _previewImage(item, fit: BoxFit.contain),
            if (item.isVideo)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 72,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({required this.items, required this.maxHeight});

  final List<ChurchChatMediaPreviewItem> items;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final cross = items.length <= 4 ? 2 : 3;
    return SizedBox(
      height: maxHeight,
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _previewImage(item, fit: BoxFit.cover),
                if (item.isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 40,
                      color: Colors.white70,
                    ),
                  ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _previewImage(
  ChurchChatMediaPreviewItem item, {
  required BoxFit fit,
}) {
  if (!kIsWeb &&
      item.localPath != null &&
      item.localPath!.isNotEmpty &&
      File(item.localPath!).existsSync() &&
      !item.isVideo) {
    return Image.file(
      File(item.localPath!),
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(item.isVideo),
    );
  }
  if (item.previewBytes != null && item.previewBytes!.isNotEmpty) {
    return Image.memory(
      item.previewBytes!,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(item.isVideo),
    );
  }
  return _placeholder(item.isVideo);
}

Widget _placeholder(bool isVideo) {
  return ColoredBox(
    color: const Color(0xFF1C1F26),
    child: Icon(
      isVideo ? Icons.videocam_rounded : Icons.image_rounded,
      size: 56,
      color: Colors.white38,
    ),
  );
}
