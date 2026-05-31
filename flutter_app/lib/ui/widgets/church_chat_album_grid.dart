import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_save_media.dart'
    show churchChatOpenImageZoom;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Item de célula na grelha (URL remota, ficheiro local ou bytes de pré-visualização).
class ChurchChatAlbumCell {
  const ChurchChatAlbumCell({
    this.url,
    this.localPath,
    this.previewBytes,
    required this.type,
    this.onTap,
  });

  final String? url;
  final String? localPath;
  final Uint8List? previewBytes;
  final String type;
  final VoidCallback? onTap;

  bool get isVideo => type == 'video';
}

/// Grelha 2 colunas estilo WhatsApp (+N no último tile quando há mais de 4 visíveis).
class ChurchChatAlbumGrid extends StatelessWidget {
  const ChurchChatAlbumGrid({
    super.key,
    required this.items,
    this.maxWidth = 280,
    this.gap = 2,
    this.maxVisible = 4,
  });

  final List<ChurchChatAlbumCell> items;
  final double maxWidth;
  final double gap;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      return _SingleTile(cell: items.first, maxWidth: maxWidth);
    }

    final visible = items.length > maxVisible ? maxVisible : items.length;
    final extra = items.length - visible;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cellW = (maxWidth - gap) / 2;
    final thumbCache = (dpr * cellW).round().clamp(96, 360);

    Widget cellAt(int displayIndex, ChurchChatAlbumCell cell, double height) {
      final showOverlay = extra > 0 && displayIndex == visible - 1;
      return _AlbumTile(
        cell: cell,
        width: cellW,
        height: height,
        memCache: thumbCache,
        overlayText: showOverlay ? '+$extra' : null,
      );
    }

    if (visible == 2) {
      return SizedBox(
        width: maxWidth,
        child: Row(
          children: [
            cellAt(0, items[0], cellW * 1.1),
            SizedBox(width: gap),
            cellAt(1, items[1], cellW * 1.1),
          ],
        ),
      );
    }

    if (visible == 3) {
      return SizedBox(
        width: maxWidth,
        height: cellW * 1.35 + gap + cellW * 0.65,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cellAt(0, items[0], cellW * 1.35 + gap + cellW * 0.65),
            SizedBox(width: gap),
            Column(
              children: [
                cellAt(1, items[1], cellW * 0.65),
                SizedBox(height: gap),
                cellAt(2, items[2], cellW * 0.65),
              ],
            ),
          ],
        ),
      );
    }

    // 4+ visíveis (4 tiles; o 4.º pode mostrar +N)
    return SizedBox(
      width: maxWidth,
      child: Column(
        children: [
          Row(
            children: [
              cellAt(0, items[0], cellW * 0.72),
              SizedBox(width: gap),
              cellAt(1, items[1], cellW * 0.72),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              cellAt(2, items[2], cellW * 0.72),
              SizedBox(width: gap),
              cellAt(3, items[3], cellW * 0.72),
            ],
          ),
        ],
      ),
    );
  }
}

class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.cell, required this.maxWidth});

  final ChurchChatAlbumCell cell;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final w = maxWidth.clamp(140.0, 280.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: w,
        child: _AlbumTile(
          cell: cell,
          width: w,
          height: w * 0.75,
          memCache: (MediaQuery.devicePixelRatioOf(context) * w).round().clamp(96, 360),
        ),
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.cell,
    required this.width,
    required this.height,
    required this.memCache,
    this.overlayText,
  });

  final ChurchChatAlbumCell cell;
  final double width;
  final double height;
  final int memCache;
  final String? overlayText;

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (cell.previewBytes != null && cell.previewBytes!.isNotEmpty) {
      img = Image.memory(
        cell.previewBytes!,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else if (cell.localPath != null && cell.localPath!.trim().isNotEmpty) {
      img = Image.file(
        File(cell.localPath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(height),
      );
    } else if ((cell.url ?? '').trim().isNotEmpty) {
      img = SafeNetworkImage(
        imageUrl: cell.url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        skipFreshDisplayUrl: true,
        memCacheWidth: memCache,
        memCacheHeight: memCache,
      );
    } else {
      img = _placeholder(height);
    }

    return GestureDetector(
      onTap: cell.onTap ??
          () {
            final u = (cell.url ?? '').trim();
            if (u.isNotEmpty) churchChatOpenImageZoom(context, u);
          },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              img,
              if (cell.isVideo)
                Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: width > 120 ? 44 : 32,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              if (overlayText != null)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: Text(
                    overlayText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(double h) {
    return ColoredBox(
      color: const Color(0xFFE2E8F0),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}
