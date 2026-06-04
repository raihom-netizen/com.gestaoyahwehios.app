import 'package:flutter/material.dart';

/// Placeholder elegante quando mídia falha (404, cache, rede).
class UnavailableMediaWidget extends StatelessWidget {
  const UnavailableMediaWidget({
    super.key,
    this.message = 'Imagem indisponível',
    this.onRetry,
    this.width,
    this.height,
    this.icon = Icons.broken_image_rounded,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final double? width;
  final double? height;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final iconSize = compact
        ? 28.0
        : (w != null ? (w * 0.35).clamp(32.0, 64.0) : 48.0);
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: Colors.grey.shade500),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
          if (onRetry != null) ...[
            SizedBox(height: compact ? 6 : 10),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: compact ? 16 : 18),
              label: Text(compact ? 'Tentar' : 'Tentar novamente'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF0A3D91),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Imagem de rede com retry local — evita tela branca em falhas extremas.
class RetryableNetworkImage extends StatefulWidget {
  const RetryableNetworkImage({
    super.key,
    required this.imageBuilder,
    this.width,
    this.height,
    this.message = 'Imagem indisponível',
  });

  final Widget Function(VoidCallback retry) imageBuilder;
  final double? width;
  final double? height;
  final String message;

  @override
  State<RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<RetryableNetworkImage> {
  int _generation = 0;

  void _retry() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<int>(_generation),
      child: widget.imageBuilder(_retry),
    );
  }
}
