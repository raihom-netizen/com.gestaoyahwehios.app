import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';

/// Botão compacto — 1 toque abre WhatsApp com [message] ou convite de publicação.
class YahwehWhatsAppOneTapIconButton extends StatelessWidget {
  const YahwehWhatsAppOneTapIconButton({
    super.key,
    required this.onSend,
    this.tooltip = 'Enviar no WhatsApp',
    this.size = 22,
    this.minTouch = ThemeCleanPremium.minTouchTarget,
  });

  final Future<void> Function() onSend;
  final String tooltip;
  final double size;
  final double minTouch;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () => onSend(),
      icon: WhatsappBrandIcon(size: size),
      style: IconButton.styleFrom(minimumSize: Size(minTouch, minTouch)),
    );
  }
}

/// Convite aviso/evento — monta mensagem e abre WhatsApp em 1 toque.
class YahwehNoticiaWhatsAppOneTapButton extends StatelessWidget {
  const YahwehNoticiaWhatsAppOneTapButton({
    super.key,
    required this.churchName,
    required this.churchSlug,
    required this.tenantId,
    required this.noticiaId,
    required this.postData,
    this.noticiaKindOverride,
    this.compact = true,
  });

  final String churchName;
  final String churchSlug;
  final String tenantId;
  final String noticiaId;
  final Map<String, dynamic> postData;
  final String? noticiaKindOverride;
  final bool compact;

  Future<void> _send(BuildContext context) async {
    final ok = await YahwehWhatsAppService.sendNoticiaOneTap(
      churchName: churchName,
      churchSlug: churchSlug,
      tenantId: tenantId,
      noticiaId: noticiaId,
      postData: postData,
      noticiaKindOverride: noticiaKindOverride,
    );
    if (!ok && context.mounted) {
      YahwehWhatsAppService.showOpenFailedSnack(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return YahwehWhatsAppOneTapIconButton(onSend: () => _send(context));
    }
    return FilledButton.icon(
      onPressed: () => _send(context),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF16A34A),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        ),
      ),
      icon: const WhatsappBrandIcon(size: 20, color: Colors.white),
      label: const Text(
        'Enviar no WhatsApp',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
