import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart'
    show showYahwehOriginalImageZoom;

/// Galeria estilo Instagram — PageView 4:5, dots, tap para zoom.
class ChurchInstagramPhotoGallery extends StatefulWidget {
  const ChurchInstagramPhotoGallery({
    super.key,
    required this.imageUrls,
    this.accent = const Color(0xFFE1306C),
    this.borderRadius = 16,
    this.aspectRatio = 4 / 5,
    this.maxHeight,
  });

  final List<String> imageUrls;
  final Color accent;
  final double borderRadius;
  final double aspectRatio;
  final double? maxHeight;

  @override
  State<ChurchInstagramPhotoGallery> createState() =>
      _ChurchInstagramPhotoGalleryState();
}

class _ChurchInstagramPhotoGalleryState
    extends State<ChurchInstagramPhotoGallery> {
  final _pageCtrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    final gallery = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageCtrl,
                  itemCount: urls.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => showYahwehOriginalImageZoom(
                      context,
                      imageUrl: urls[i],
                    ),
                    child: ColoredBox(
                      color: const Color(0xFF0F172A),
                      child: SafeNetworkImage(
                        imageUrl: urls[i],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                if (urls.length > 1)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_index + 1}/${urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_out_map_rounded,
                            color: Colors.white, size: 15),
                        SizedBox(width: 5),
                        Text(
                          'Ampliar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              urls.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: i == _index
                      ? widget.accent
                      : Colors.grey.shade300,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final maxH = widget.maxHeight;
    if (maxH == null) return gallery;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: gallery,
    );
  }
}
