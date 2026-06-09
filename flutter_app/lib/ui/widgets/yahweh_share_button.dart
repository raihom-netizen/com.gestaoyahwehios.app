import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/yahweh_share_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';

/// Botão «Compartilhar» — abre folha nativa (WhatsApp, etc.) via [share_plus].
class YahwehShareButton extends StatelessWidget {
  const YahwehShareButton({
    super.key,
    required this.onShare,
    this.label = 'Compartilhar',
    this.compact = false,
  });

  final Future<void> Function() onShare;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: () => onShare(),
        icon: const Icon(Icons.share_rounded),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => onShare(),
      icon: const Icon(Icons.share_rounded, size: 20),
      label: Text(label),
    );
  }
}

/// Envia aviso no WhatsApp em 1 toque (sem folha nativa).
Future<void> shareAvisoWhatsApp({
  required String title,
  required String body,
}) =>
    YahwehWhatsAppService.openNoticiaBroadcast(
      '${title.trim()}\n\n${body.trim()}',
    );
