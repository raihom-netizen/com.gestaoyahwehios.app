import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Ícones de entrega estilo WhatsApp (relógio / ✓ / ✓✓ cinza / ✓✓ azul).
class ChurchChatDeliveryStatusIcon extends StatelessWidget {
  const ChurchChatDeliveryStatusIcon({
    super.key,
    required this.deliveryStatus,
    required this.mine,
    this.peerRead = false,
    this.size = 15,
  });

  final String deliveryStatus;
  final bool mine;
  /// DM: parceiro viu a conversa (`lastSeenAtByUid`) ou `deliveryStatus: read`.
  final bool peerRead;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!mine) return const SizedBox.shrink();

    final ds = deliveryStatus.trim();
    final read = peerRead || ds == ChurchChatService.deliveryRead;
    final delivered = read ||
        ds == ChurchChatService.deliveryDelivered;

    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);

    if (ds == ChurchChatService.deliveryQueued) {
      return Icon(Icons.cloud_queue_rounded, size: size, color: muted);
    }
    if (ds == 'failed') {
      return Icon(Icons.error_outline_rounded, size: size, color: Theme.of(context).colorScheme.error);
    }
    if (ds == ChurchChatService.deliverySending ||
        ds == ChurchChatService.deliveryUploading) {
      return Icon(Icons.schedule_rounded, size: size, color: muted);
    }
    if (read) {
      return Icon(
        Icons.done_all_rounded,
        size: size,
        color: const Color(0xFF53BDEB),
      );
    }
    if (delivered) {
      return Icon(Icons.done_all_rounded, size: size, color: muted);
    }
    if (ds == ChurchChatService.deliverySent || ds.isEmpty) {
      return Icon(Icons.done_rounded, size: size, color: muted);
    }
    return Icon(
      Icons.error_outline_rounded,
      size: size,
      color: Theme.of(context).colorScheme.error,
    );
  }
}
