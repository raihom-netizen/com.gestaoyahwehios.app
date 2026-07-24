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
    /// Rótulo moderno (ex.: «Compartilhar») quando [compact] é false.
    this.label = 'Compartilhar',
  });

  final String churchName;
  final String churchSlug;
  final String tenantId;
  final String noticiaId;
  final Map<String, dynamic> postData;
  final String? noticiaKindOverride;
  final bool compact;
  final String label;

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
      // Chip WISDOM — mesma linha que Participar/Comentar; texto completo via FittedBox.
      const accent = Color(0xFF16A34A);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _send(context),
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.white, 0.88)!,
                  Color.lerp(accent, Colors.white, 0.78)!,
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const WhatsappBrandIcon(size: 13, color: accent),
                      const SizedBox(width: 3),
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => _send(context),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF16A34A),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const WhatsappBrandIcon(size: 16, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
